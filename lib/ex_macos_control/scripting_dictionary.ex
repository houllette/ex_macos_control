defmodule ExMacOSControl.ScriptingDictionary do
  @moduledoc false

  alias ExMacOSControl.Automation

  @limit 2_097_152
  @include_uri "http://www.w3.org/2003/XInclude"

  def read(path) do
    path = Path.expand(path)

    with {:ok, root, sources} <- load(path, [], Path.dirname(path)) do
      suites = Enum.filter(root.children, &(&1.tag == "suite"))

      {:ok,
       %{
         status: :declared,
         qualification: :unverified,
         path: path,
         sources: sources,
         fingerprint: fingerprint(sources),
         suites: Enum.map(suites, &suite/1)
       }}
    end
  end

  def parse(xml) when is_binary(xml) and byte_size(xml) <= @limit do
    opts = [event_fun: &event/3, event_state: %{stack: [], roots: []}, external_entities: :none]

    case :xmerl_sax_parser.stream(xml, [:skip_external_dtd, :disallow_entities | opts]) do
      {:ok, %{roots: [%{tag: "dictionary"} = root]}, rest} ->
        if String.trim(rest) == "", do: {:ok, root}, else: Automation.invalid("Trailing dictionary data")

      _ ->
        Automation.invalid("Invalid scripting dictionary")
    end
  catch
    _, _ -> Automation.invalid("Invalid scripting dictionary")
  end

  def parse(_xml), do: Automation.invalid("Scripting dictionary exceeds the size limit")

  def fingerprint(sources) do
    sources
    |> Enum.sort()
    |> Enum.map(fn {_path, hash} -> hash end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def fresh?(sources) do
    Enum.all?(sources, fn {path, hash} ->
      case File.read(path) do
        {:ok, raw} -> :crypto.hash(:sha256, raw) == hash
        _ -> false
      end
    end)
  end

  defp event({:startElement, uri, name, _qualified, attrs}, _location, state) do
    if length(state.stack) >= 64, do: throw({:dictionary_depth, ~c"Dictionary nesting limit"})
    attrs = Map.new(attrs, fn {_uri, _prefix, key, value} -> {to_string(key), to_string(value)} end)
    node = %{tag: to_string(name), uri: to_string(uri), attrs: attrs, children: []}
    %{state | stack: [node | state.stack]}
  end

  defp event({:endElement, _, _, _}, _location, %{stack: [node | rest]} = state) do
    node = %{node | children: Enum.reverse(node.children)}

    case rest do
      [parent | ancestors] -> %{state | stack: [%{parent | children: [node | parent.children]} | ancestors]}
      [] -> %{state | stack: [], roots: [node | state.roots]}
    end
  end

  defp event(_event, _location, state), do: state

  defp load(path, seen, base) do
    with true <- length(seen) < 8 and path not in seen,
         {:ok, %{type: :regular, size: size}} when size <= @limit <- File.lstat(path),
         {:ok, raw} <- File.read(path),
         {:ok, root} <- parse(raw),
         {:ok, root, sources} <- expand(root, path, [path | seen], base) do
      {:ok, root, Map.put(sources, path, :crypto.hash(:sha256, raw))}
    else
      _ -> Automation.invalid("Unable to read scripting dictionary or its local includes")
    end
  end

  defp expand(node, origin, seen, base) do
    Enum.reduce_while(node.children, {:ok, [], %{}}, fn child, {:ok, children, sources} ->
      case expand_child(child, origin, seen, base) do
        {:ok, nodes, included} -> {:cont, {:ok, children ++ nodes, Map.merge(sources, included)}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, children, sources} -> {:ok, %{node | children: children}, sources}
      error -> error
    end
  end

  defp expand_child(%{tag: "include", uri: @include_uri} = node, origin, seen, base) do
    uri = URI.parse(node.attrs["href"] || "")
    target = Path.expand(URI.decode(uri.path || ""), Path.dirname(origin))

    allowed =
      String.starts_with?(target, base <> "/") or String.starts_with?(target, "/System/Library/ScriptingDefinitions/")

    with true <- uri.scheme in [nil, "file"] and uri.host in [nil, "", "localhost"] and allowed,
         {:ok, root, sources} <- load(target, seen, base),
         {:ok, nodes} <- select_include(root, node.attrs["xpointer"]) do
      {:ok, nodes, sources}
    else
      _ -> Automation.invalid("Unsupported scripting dictionary include")
    end
  end

  defp expand_child(node, origin, seen, base) do
    with {:ok, expanded, sources} <- expand(node, origin, seen, base), do: {:ok, [expanded], sources}
  end

  defp select_include(root, "xpointer(/dictionary/suite)") do
    {:ok, Enum.filter(root.children, &(&1.tag == "suite"))}
  end

  defp select_include(root, "xpointer(/dictionary/suite/node()[not(self::command and " <> _ = pointer) do
    excluded = Regex.scan(~r/@name = '([^']+)'/, pointer, capture: :all_but_first) |> List.flatten()
    nodes = root.children |> Enum.filter(&(&1.tag == "suite")) |> Enum.flat_map(& &1.children)
    {:ok, Enum.reject(nodes, &(&1.tag == "command" and &1.attrs["name"] in excluded))}
  end

  defp select_include(root, nil), do: {:ok, [root]}
  defp select_include(_root, _pointer), do: Automation.invalid("Unsupported dictionary selector")

  defp suite(node) do
    %{
      name: node.attrs["name"],
      code: node.attrs["code"],
      description: node.attrs["description"],
      commands: definitions(node, "command"),
      classes: definitions(node, "class"),
      extensions: definitions(node, "class-extension"),
      enumerations: definitions(node, "enumeration")
    }
  end

  defp definitions(node, tag) do
    node.children |> Enum.filter(&(&1.tag == tag)) |> Enum.map(&definition/1)
  end

  defp definition(node) do
    Map.put(node.attrs, "children", Enum.map(node.children, &Map.put(definition(&1), "kind", &1.tag)))
  end
end

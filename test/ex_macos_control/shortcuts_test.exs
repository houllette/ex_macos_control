defmodule ExMacOSControl.ShortcutsTest do
  use ExUnit.Case, async: false
  import Mox
  alias ExMacOSControl.{Error, Shortcuts}

  setup :verify_on_exit!

  setup do
    directory = Path.expand("tmp/shortcuts-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    executable = Path.join(directory, "shortcuts")

    File.write!(executable, """
    #!/bin/sh
    printf '%s\\n' "$@" > "$EXMC_TEST_ARGS"
    if [ "$1" = run ] && [ "$2" = --input-path ]; then
      /bin/cat "$3" > "$EXMC_TEST_INPUT"
    else
      /bin/cat > "$EXMC_TEST_INPUT"
    fi
    if [ -n "$EXMC_TEST_DELAY" ]; then /bin/sleep "$EXMC_TEST_DELAY"; fi
    printf '%s' "$EXMC_TEST_RESPONSE"
    """)

    File.chmod!(executable, 0o700)

    environment = %{
      "PATH" => directory,
      "EXMC_TEST_ARGS" => Path.join(directory, "args"),
      "EXMC_TEST_INPUT" => Path.join(directory, "input"),
      "EXMC_TEST_RESPONSE" => "result",
      "EXMC_TEST_DELAY" => ""
    }

    original = Map.new(environment, fn {k, _} -> {k, System.get_env(k)} end)
    System.put_env(environment)

    on_exit(fn ->
      Enum.each(original, fn {k, v} -> if v, do: System.put_env(k, v), else: System.delete_env(k) end)
      File.rm_rf!(directory)
    end)

    %{directory: directory}
  end

  test "preserves structured input as text and keeps option-like identifiers separate", %{directory: directory} do
    for input <- [%{"text" => "quotes\" 雪\n"}, ["one", "two"]] do
      assert {:ok, "result"} = Shortcuts.run("-e", input: input)

      assert ["run", "--input-path", path, "--", "-e"] =
               File.read!(Path.join(directory, "args")) |> String.split("\n", trim: true)

      assert Path.extname(path) == ".txt"
      assert Jason.decode!(File.read!(Path.join(directory, "input"))) == input
      refute File.exists?(Path.dirname(path))
    end
  end

  test "passes file input and output types separately without a shell", %{directory: directory} do
    path = Path.join(directory, "input file.txt")
    File.write!(path, "data")
    output = Path.join(directory, "output file.png")
    assert {:ok, "result"} = Shortcuts.run("id", input_paths: [path], output_path: output, output_type: "public.png")

    assert File.read!(Path.join(directory, "args")) ==
             "run\n--input-path\n#{path}\n--output-path\n#{output}\n--output-type\npublic.png\n--\nid\n"

    assert {:error, %Error{}} = Shortcuts.run("id", input: "text", input_paths: [path])
  end

  test "workflow protocol rejects unversioned and malformed results", %{directory: directory} do
    System.put_env("EXMC_TEST_RESPONSE", ~s({"exmc":1,"result":[{"id":"message"}]}))
    assert {:ok, [%{"id" => "message"}]} = Shortcuts.workflow("id", "messages.search", %{sender: "synthetic"})

    assert %{"exmc" => 1, "operation" => "messages.search", "input" => %{"sender" => "synthetic"}} =
             Path.join(directory, "input") |> File.read!() |> Jason.decode!()

    System.put_env("EXMC_TEST_RESPONSE", ~s({"result":[]}))
    assert {:error, %Error{}} = Shortcuts.workflow("id", "messages.search", %{})
    System.put_env("EXMC_TEST_RESPONSE", "private invalid text")

    assert {:error, %Error{message: "Shortcut did not return valid JSON"}} =
             Shortcuts.workflow("id", "messages.search", %{})
  end

  test "typed binary output preserves bytes that text trimming would remove" do
    output = "\n\tsynthetic binary\r\n"
    System.put_env("EXMC_TEST_RESPONSE", output)
    assert {:ok, ^output} = Shortcuts.run("id", output_type: "public.png")
    assert {:ok, ^output} = Shortcuts.run("id", output: :binary)
  end

  test "CLI helpers honor scoped execution defaults and explicit overrides", %{directory: directory} do
    System.put_env("EXMC_TEST_DELAY", "0.1")

    for command <- ["automator", "plutil", "osadecompile"] do
      File.cp!(Path.join(directory, "shortcuts"), Path.join(directory, command))
      File.chmod!(Path.join(directory, command), 0o700)
    end

    file = Path.join(directory, "synthetic.workflow")
    File.write!(file, "synthetic")

    ExMacOSControl.with_options([timeout: 0], fn ->
      assert {:error, %Error{type: :timeout}} = Shortcuts.run("id")
      assert {:error, %Error{type: :timeout}} = ExMacOSControl.Automator.run(file)
      assert {:error, %Error{type: :timeout}} = ExMacOSControl.PropertyList.read(file)
      assert {:error, %Error{type: :timeout}} = ExMacOSControl.Script.decompile(file)
      assert {:ok, "result"} = Shortcuts.run("id", timeout: 1000)
    end)
  end

  test "pipelines pass output to the next Shortcut without changing its text", %{directory: directory} do
    System.put_env("EXMC_TEST_RESPONSE", " transformed 雪 ")
    assert {:ok, " transformed 雪 "} = Shortcuts.pipeline(["first", "second"], "original", trim: false)
    assert File.read!(Path.join(directory, "input")) == " transformed 雪 "
    assert File.read!(Path.join(directory, "args")) =~ "--\nsecond\n"
  end

  test "JSON pipelines preserve structured values as JSON text at each boundary", %{directory: directory} do
    System.put_env("EXMC_TEST_RESPONSE", ~s({"text":"雪","items":[1,2]}))

    assert {:ok, %{"text" => "雪", "items" => [1, 2]}} =
             Shortcuts.pipeline(["one", "two"], %{"initial" => true}, output: :json)

    assert Jason.decode!(File.read!(Path.join(directory, "input"))) == %{"text" => "雪", "items" => [1, 2]}
  end

  test "JSON pipeline boundaries preserve scalar booleans, null and quoted strings", %{directory: directory} do
    for value <- [true, false, nil, "quoted\" 雪"] do
      System.put_env("EXMC_TEST_RESPONSE", Jason.encode!(value))
      assert {:ok, ^value} = Shortcuts.pipeline(["one", "two"], "initial", output: :json)
      assert Jason.decode!(File.read!(Path.join(directory, "input"))) == value
    end
  end

  test "pipeline deadline covers all commands and retains acknowledged earlier results", %{directory: directory} do
    File.write!(Path.join(directory, "shortcuts"), """
    #!/bin/sh
    for argument do identifier="$argument"; done
    if [ "$identifier" = two ]; then /bin/sleep 2; fi
    printf result
    """)

    assert {:error, error} = Shortcuts.pipeline(["one", "two", "three"], "initial", timeout: 1000)
    assert error.type == :timeout
    assert error.details.outcome == :unknown
    assert error.details.composition.completed == [%{step: {:shortcut, "one"}, result: "result"}]
  end

  test "selection handoff uses the captured files as native Shortcut file input", %{directory: directory} do
    file = Path.join(directory, "selected 雪.txt")
    File.write!(file, "selected")

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ ->
      {:ok, ExMacOSControl.TestHelpers.script_output([[file]])}
    end)

    assert {:ok, "result"} = ExMacOSControl.Workflows.selection_to_shortcut("Process Files")
    assert File.read!(Path.join(directory, "args")) == "run\n--input-path\n#{file}\n--\nProcess Files\n"
  end

  test "Shortcut output replaces the text clipboard only after successful execution" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert %{"text" => "result"} = opts[:args] |> hd() |> Jason.decode!()
      {:ok, ~s({"exmc":1,"result":true})}
    end)

    assert {:ok, "result"} = ExMacOSControl.Workflows.shortcut_to_clipboard("Transform", "input")
  end

  test "invalid pipelines cannot launch a Shortcut", %{directory: directory} do
    assert {:error, %Error{}} = Shortcuts.pipeline(["one", ""], "input")
    assert {:error, %Error{}} = Shortcuts.pipeline(["one"], "input", output: :binary)
    refute File.exists?(Path.join(directory, "args"))
  end
end

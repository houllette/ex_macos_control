defmodule ExMacOSControl.ShortcutsTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{Error, Shortcuts}

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
end

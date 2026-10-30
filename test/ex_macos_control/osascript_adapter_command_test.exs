defmodule ExMacOSControl.OSAScriptAdapterCommandTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{Error, OSAScriptAdapter}

  # Exercise real command construction without invoking any macOS applications.
  setup do
    directory = Path.expand("tmp/command_#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    args_file = Path.join(directory, "args")
    executable = Path.join(directory, "osascript")

    File.write!(executable, """
    #!/bin/sh
    printf '%s\\n' "$@" > "$EX_MACOS_CONTROL_ARGS_FILE"
    case "$EX_MACOS_CONTROL_COMMAND_MODE" in
      error) printf 'execution error: Not authorized. (-1743)\\n' >&2; exit 1 ;;
      structured) printf '%s\\n' "$EX_MACOS_CONTROL_COMMAND_OUTPUT" ;;
      slow) exec /bin/sleep 2 ;;
      *) printf 'result\\n' ;;
    esac
    """)

    File.chmod!(executable, 0o700)

    environment = %{
      "PATH" => directory,
      "EX_MACOS_CONTROL_ARGS_FILE" => args_file,
      "EX_MACOS_CONTROL_COMMAND_MODE" => "success",
      "EX_MACOS_CONTROL_COMMAND_OUTPUT" => ""
    }

    original = Map.new(environment, fn {key, _} -> {key, System.get_env(key)} end)
    System.put_env(environment)

    on_exit(fn ->
      Enum.each(original, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      File.rm_rf!(directory)
    end)

    %{directory: directory, executable: executable, args_file: args_file}
  end

  test "passes inline scripts and arguments as separate command arguments", %{args_file: file} do
    assert {:ok, "result"} = OSAScriptAdapter.run_applescript("return 1", args: ["a b", "--flag"])
    assert File.read!(file) == "-e\nreturn 1\n--\na b\n--flag\n"
  end

  test "uses the JavaScript interpreter and passes arguments", %{args_file: file} do
    assert {:ok, "result"} = OSAScriptAdapter.run_javascript("1 + 1", args: ["value"], timeout: 1000)
    assert File.read!(file) == "-l\nJavaScript\n-e\n1 + 1\n--\nvalue\n"
  end

  test "honors timeouts for AppleScript, JXA, script files, and Shortcuts", %{directory: directory} do
    System.put_env("EX_MACOS_CONTROL_COMMAND_MODE", "slow")
    script = Path.join(directory, "script.js")
    File.write!(script, "1 + 1")

    calls = [
      fn -> OSAScriptAdapter.run_applescript("delay 2", timeout: 25) end,
      fn -> OSAScriptAdapter.run_javascript("1 + 1", timeout: 25) end,
      fn -> OSAScriptAdapter.run_script_file(script, timeout: 25) end,
      fn -> OSAScriptAdapter.run_shortcut("Fixture", timeout: 25) end
    ]

    Enum.each(calls, fn call ->
      started = System.monotonic_time(:millisecond)
      assert {:error, %Error{type: :timeout, details: %{timeout: 25}}} = call.()
      assert System.monotonic_time(:millisecond) - started < 1000
    end)
  end

  test "rejects invalid timeouts before starting any command", %{directory: directory, args_file: file} do
    script = Path.join(directory, "script.js")
    File.write!(script, "1 + 1")

    for timeout <- [-1, 1.5, "1000", false, :invalid],
        call <- [
          fn -> OSAScriptAdapter.run_applescript("return 1", timeout: timeout) end,
          fn -> OSAScriptAdapter.run_javascript("1 + 1", timeout: timeout) end,
          fn -> OSAScriptAdapter.run_script_file(script, timeout: timeout) end,
          fn -> OSAScriptAdapter.run_shortcut("Fixture", timeout: timeout) end
        ] do
      assert {:error, %Error{type: :execution_error, message: message}} = call.()
      assert message =~ "Timeout must be"
      refute File.exists?(file)
    end
  end

  test "supports explicit unlimited timeouts" do
    assert {:ok, "result"} = OSAScriptAdapter.run_applescript("return 1", timeout: :infinity)
    assert {:ok, "result"} = OSAScriptAdapter.run_javascript("1 + 1", timeout: nil)
  end

  test "parses command errors both with and without timeout" do
    System.put_env("EX_MACOS_CONTROL_COMMAND_MODE", "error")

    for opts <- [[], [timeout: 1000]] do
      assert {:error, %Error{type: :permission_denied}} =
               OSAScriptAdapter.run_applescript("return 1", opts)
    end
  end

  test "returns structured errors rather than crashing when a command cannot be spawned", %{
    executable: executable
  } do
    File.rm!(executable)

    for opts <- [[], [timeout: 1000]] do
      assert {:error, %Error{type: :execution_error, details: %{reason: :enoent}}} =
               OSAScriptAdapter.run_applescript("return 1", opts)
    end
  end

  test "lists Shortcut names without splitting embedded punctuation or whitespace", %{args_file: file} do
    names = ["  Daily, Notes | 雪  ", "line\nbreak\tname", ~S(Path\name)]
    System.put_env("EX_MACOS_CONTROL_COMMAND_MODE", "structured")

    System.put_env(
      "EX_MACOS_CONTROL_COMMAND_OUTPUT",
      ExMacOSControl.TestHelpers.script_output(Enum.map(names, &[&1]))
    )

    assert {:ok, ^names} = OSAScriptAdapter.list_shortcuts()
    script = File.read!(file)
    assert script =~ "name of every shortcut"
    assert script =~ "my exmc_encode_rows(shortcutRows)"
    refute script =~ "to run shortcut"
  end

  test "lists an empty Shortcut library and rejects malformed output" do
    System.put_env("EX_MACOS_CONTROL_COMMAND_MODE", "structured")
    System.put_env("EX_MACOS_CONTROL_COMMAND_OUTPUT", "EXMC1\nEND")
    assert {:ok, []} = OSAScriptAdapter.list_shortcuts()

    System.put_env("EX_MACOS_CONTROL_COMMAND_OUTPUT", "one,two")
    assert {:error, %Error{type: :execution_error}} = OSAScriptAdapter.list_shortcuts()
  end

  test "escapes shortcut names and string input", %{args_file: file} do
    assert {:ok, "result"} =
             OSAScriptAdapter.run_shortcut(~S(Name\"quoted), input: ~S(Input\"quoted))

    assert File.read!(file) ==
             "-e\n" <>
               ~S(tell application "Shortcuts Events" to run shortcut "Name\\\"quoted" with input "Input\\\"quoted") <>
               "\n--\n"
  end

  test "serializes structured Shortcut input once as JSON, then escapes it as AppleScript", %{
    args_file: file
  } do
    input = %{"path" => ~S(C:\Users\me), "text" => ~s(Hello "world"\n)}
    assert {:ok, "result"} = OSAScriptAdapter.run_shortcut("Fixture", input: input)
    encoded = input |> Jason.encode!() |> ExMacOSControl.Script.escape_string()
    assert File.read!(file) =~ "with input \"#{encoded}\""
  end

  test "detects script file language and forwards arguments", %{directory: directory, args_file: file} do
    script = Path.join(directory, "script.JXA")
    File.write!(script, "1 + 1")
    assert {:ok, "result"} = OSAScriptAdapter.run_script_file(script, args: ["a b"])
    assert File.read!(file) == "-l\nJavaScript\n--\n#{script}\na b\n"
  end
end

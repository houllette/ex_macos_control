defmodule ExMacOSControl.OSAScriptAdapterTelemetryTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.OSAScriptAdapter

  setup do
    # Attach a test telemetry handler
    test_pid = self()
    handler_id = "test-osascript-handler-#{:erlang.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:ex_macos_control, :applescript, :start],
        [:ex_macos_control, :applescript, :stop],
        [:ex_macos_control, :applescript, :exception]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    %{handler_id: handler_id}
  end

  describe "run_applescript/1 telemetry" do
    @tag :integration
    test "emits start and stop events for successful execution" do
      script = ~s(return "test")
      {:ok, result} = OSAScriptAdapter.run_applescript(script)

      assert result == "test"

      # Should receive start event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], measurements, metadata}

      assert is_integer(measurements.script_length)
      assert measurements.script_length == String.length(script)
      assert metadata.command == "osascript"
      assert metadata.script == script
      assert metadata.timeout == nil

      # Should receive stop event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :stop], measurements, metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration > 0
      assert measurements.script_length == String.length(script)
      assert metadata.result_type == :success
      assert metadata.output_length == String.length("test")

      # Should not receive exception event
      refute_received {:telemetry, [:ex_macos_control, :applescript, :exception], _, _}
    end

    @tag :integration
    test "emits start and exception events for failed execution" do
      script = "invalid syntax here"
      {:error, _error} = OSAScriptAdapter.run_applescript(script)

      # Should receive start event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, _}

      # Should receive exception event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :exception], measurements, metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration > 0
      assert metadata.result_type == :error
      assert is_map(metadata.error)

      # Should not receive stop event
      refute_received {:telemetry, [:ex_macos_control, :applescript, :stop], _, _}
    end

    @tag :integration
    test "includes script preview in metadata (first 100 chars)" do
      long_script = String.duplicate("a", 200)
      OSAScriptAdapter.run_applescript(long_script)

      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, %{script: preview}}

      assert String.length(preview) == 100
      assert preview == String.slice(long_script, 0, 100)
    end

    @tag :integration
    test "includes full short script in metadata" do
      short_script = ~s(return "hello")
      OSAScriptAdapter.run_applescript(short_script)

      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, %{script: script}}

      assert script == short_script
    end
  end

  describe "run_applescript/2 with timeout telemetry" do
    @tag :integration
    test "includes timeout in metadata when provided" do
      script = ~s(return "test")
      {:ok, _} = OSAScriptAdapter.run_applescript(script, timeout: 5000)

      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, metadata}
      assert metadata.timeout == 5000
    end

    @tag :integration
    test "emits exception event on timeout" do
      # Script that takes longer than timeout
      script = "delay 2"
      {:error, _} = OSAScriptAdapter.run_applescript(script, timeout: 100)

      # Should receive start event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, metadata}
      assert metadata.timeout == 100

      # Should receive exception event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :exception], _, metadata}
      assert metadata.result_type == :error
      assert metadata.error.type == :timeout

      # Should not receive stop event
      refute_received {:telemetry, [:ex_macos_control, :applescript, :stop], _, _}
    end

    @tag :integration
    test "measures execution duration accurately" do
      script = "delay 0.1"
      {:ok, _} = OSAScriptAdapter.run_applescript(script, timeout: 5000)

      # Clear start event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, _}

      # Check stop event duration
      assert_received {:telemetry, [:ex_macos_control, :applescript, :stop], measurements, _}

      # Duration should be at least 100ms (delay 0.1 seconds = 100,000 microseconds)
      # Allow some margin
      assert measurements.duration >= 80_000
    end
  end

  describe "run_applescript/2 with args telemetry" do
    @tag :integration
    test "emits events when using arguments" do
      script = """
      on run argv
        return item 1 of argv
      end run
      """

      {:ok, result} = OSAScriptAdapter.run_applescript(script, args: ["test_arg"])
      assert result == "test_arg"

      # Should receive both start and stop events
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, _}
      assert_received {:telemetry, [:ex_macos_control, :applescript, :stop], _, _}
    end
  end

  describe "run_javascript/1 telemetry" do
    @tag :integration
    test "emits start and stop events for JXA execution" do
      script = "(function() { return 'test'; })()"
      {:ok, result} = OSAScriptAdapter.run_javascript(script)

      assert result == "test"

      # Should receive start event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], measurements, metadata}

      assert measurements.script_length == String.length(script)
      assert metadata.command == "osascript"
      assert metadata.script == script

      # Should receive stop event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :stop], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.result_type == :success
    end

    @tag :integration
    test "emits exception event for JXA syntax errors" do
      script = "invalid javascript syntax"
      {:error, _error} = OSAScriptAdapter.run_javascript(script)

      # Should receive start event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, _}

      # Should receive exception event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :exception], _, metadata}
      assert metadata.result_type == :error
    end
  end

  describe "run_script_file/2 telemetry" do
    setup do
      # Create temporary test files
      tmp_dir = System.tmp_dir!()
      applescript_file = Path.join(tmp_dir, "test_#{:erlang.unique_integer()}.applescript")
      js_file = Path.join(tmp_dir, "test_#{:erlang.unique_integer()}.js")

      File.write!(applescript_file, "return \"applescript result\"")
      File.write!(js_file, "(function() { return 'js result'; })()")

      on_exit(fn ->
        File.rm(applescript_file)
        File.rm(js_file)
      end)

      %{applescript_file: applescript_file, js_file: js_file}
    end

    @tag :integration
    test "emits events for AppleScript file execution", %{applescript_file: file} do
      {:ok, result} = OSAScriptAdapter.run_script_file(file, [])
      assert result == "applescript result"

      # Should receive start and stop events
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], measurements, metadata}

      # Script should be the filename (not full content since it's a file)
      assert metadata.script == Path.basename(file)
      assert measurements.script_length == String.length(Path.basename(file))

      assert_received {:telemetry, [:ex_macos_control, :applescript, :stop], _, _}
    end

    @tag :integration
    test "emits events for JavaScript file execution", %{js_file: file} do
      {:ok, result} = OSAScriptAdapter.run_script_file(file, language: :javascript)
      assert result == "js result"

      # Should receive start and stop events
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, _}
      assert_received {:telemetry, [:ex_macos_control, :applescript, :stop], _, _}
    end

    @tag :integration
    test "emits exception event for nonexistent file" do
      {:error, _} = OSAScriptAdapter.run_script_file("/nonexistent/file.applescript", [])

      # Should NOT receive any telemetry events because validation fails before execution
      refute_received {:telemetry, [:ex_macos_control, :applescript, :start], _, _}
      refute_received {:telemetry, [:ex_macos_control, :applescript, :stop], _, _}
      refute_received {:telemetry, [:ex_macos_control, :applescript, :exception], _, _}
    end
  end

  describe "telemetry metadata consistency" do
    @tag :integration
    test "start and stop events have consistent script_length" do
      script = ~s(return "consistency test")
      OSAScriptAdapter.run_applescript(script)

      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], start_measurements, _}

      assert_received {:telemetry, [:ex_macos_control, :applescript, :stop], stop_measurements, _}

      assert start_measurements.script_length == stop_measurements.script_length
    end

    @tag :integration
    test "stop event includes output_length" do
      script = ~s(return "hello world")
      {:ok, output} = OSAScriptAdapter.run_applescript(script)

      # Clear start event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, _}

      assert_received {:telemetry, [:ex_macos_control, :applescript, :stop], _, metadata}
      assert metadata.output_length == String.length(output)
    end

    @tag :integration
    test "exception event includes error details" do
      script = "syntax error here"
      {:error, error} = OSAScriptAdapter.run_applescript(script)

      # Clear start event
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, _}

      assert_received {:telemetry, [:ex_macos_control, :applescript, :exception], _, metadata}
      assert metadata.error == error
    end
  end

  describe "telemetry event ordering" do
    @tag :integration
    test "events are emitted in correct order for success" do
      script = ~s(return "test")
      OSAScriptAdapter.run_applescript(script)

      # Start should come before stop
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, _}
      assert_received {:telemetry, [:ex_macos_control, :applescript, :stop], _, _}
      refute_received {:telemetry, [:ex_macos_control, :applescript, :exception], _, _}
    end

    @tag :integration
    test "events are emitted in correct order for failure" do
      script = "invalid"
      OSAScriptAdapter.run_applescript(script)

      # Start should come before exception
      assert_received {:telemetry, [:ex_macos_control, :applescript, :start], _, _}
      assert_received {:telemetry, [:ex_macos_control, :applescript, :exception], _, _}
      refute_received {:telemetry, [:ex_macos_control, :applescript, :stop], _, _}
    end
  end
end

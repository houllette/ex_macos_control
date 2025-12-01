defmodule ExMacOSControl.SystemEventsTest do
  use ExUnit.Case, async: true
  import Mox

  alias ExMacOSControl.Error
  alias ExMacOSControl.SystemEvents

  setup :verify_on_exit!

  describe "list_processes/0" do
    test "returns parsed list of processes" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Events"
        assert script =~ "name of every application process"
        {:ok, "Safari, Finder, Terminal"}
      end)

      assert {:ok, processes} = SystemEvents.list_processes()
      assert processes == ["Safari", "Finder", "Terminal"]
    end

    test "trims whitespace from process names" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, " Safari , Finder ,  Terminal  "}
      end)

      assert {:ok, processes} = SystemEvents.list_processes()
      assert processes == ["Safari", "Finder", "Terminal"]
    end

    test "handles empty process list" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, ""}
      end)

      assert {:ok, processes} = SystemEvents.list_processes()
      assert processes == []
    end

    test "handles single process" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "Finder"}
      end)

      assert {:ok, processes} = SystemEvents.list_processes()
      assert processes == ["Finder"]
    end

    test "returns error when System Events unavailable" do
      error = Error.execution_error("System Events not available")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.list_processes()
    end
  end

  describe "process_exists?/1" do
    test "returns true when process exists" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Events"
        assert script =~ ~s(exists process "Safari")
        {:ok, "true"}
      end)

      assert {:ok, true} = SystemEvents.process_exists?("Safari")
    end

    test "returns false when process doesn't exist" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(exists process "NonexistentApp")
        {:ok, "false"}
      end)

      assert {:ok, false} = SystemEvents.process_exists?("NonexistentApp")
    end

    test "handles execution errors" do
      error = Error.execution_error("System Events error")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.process_exists?("Safari")
    end

    test "handles mixed case boolean values" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "True"}
      end)

      assert {:ok, true} = SystemEvents.process_exists?("Safari")
    end
  end

  describe "quit_application/1" do
    test "returns :ok on successful quit" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(application "Calculator")
        assert script =~ "quit"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.quit_application("Calculator")
    end

    test "returns error when application not found" do
      error = Error.not_found("Application not found", app: "NonexistentApp")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.quit_application("NonexistentApp")
    end

    test "handles permission errors" do
      error = Error.permission_denied("Automation permission required")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.quit_application("Safari")
    end

    test "handles execution errors" do
      error = Error.execution_error("Failed to quit application")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.quit_application("Safari")
    end
  end

  describe "launch_application/1" do
    test "returns :ok on successful launch" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(application "Calculator")
        assert script =~ "activate"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.launch_application("Calculator")
    end

    test "returns error when application not found" do
      error = Error.not_found("Application not found", app: "NonexistentApp")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.launch_application("NonexistentApp")
    end

    test "handles execution errors" do
      error = Error.execution_error("Failed to launch application")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.launch_application("Calculator")
    end
  end

  describe "activate_application/1" do
    test "delegates to launch_application/1" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(application "Calculator")
        assert script =~ "activate"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.activate_application("Calculator")
    end

    test "returns error when application not found" do
      error = Error.not_found("Application not found", app: "NonexistentApp")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.activate_application("NonexistentApp")
    end
  end
end

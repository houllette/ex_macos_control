defmodule ExMacOSControl.AdapterFactoryTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExMacOSControl.AdapterFactory

  # Set up verification for Mox
  setup :verify_on_exit!

  describe "mock_applescript_success/1" do
    test "sets up successful mock" do
      AdapterFactory.mock_applescript_success("test result")

      result = ExMacOSControl.AdapterMock.run_applescript("any script")
      assert result == {:ok, "test result"}
    end
  end

  describe "mock_applescript_error/1" do
    test "sets up error mock with atom reason" do
      AdapterFactory.mock_applescript_error(:syntax_error)

      result = ExMacOSControl.AdapterMock.run_applescript("any script")
      assert result == {:error, :syntax_error}
    end

    test "sets up error mock with string reason" do
      AdapterFactory.mock_applescript_error("custom error message")

      result = ExMacOSControl.AdapterMock.run_applescript("any script")
      assert result == {:error, "custom error message"}
    end
  end

  describe "mock_shortcut_success/0" do
    test "sets up successful shortcut mock" do
      AdapterFactory.mock_shortcut_success()

      result = ExMacOSControl.AdapterMock.run_shortcut("any shortcut")
      assert result == :ok
    end
  end

  describe "mock_shortcut_error/1" do
    test "sets up error shortcut mock" do
      AdapterFactory.mock_shortcut_error(:not_found)

      result = ExMacOSControl.AdapterMock.run_shortcut("any shortcut")
      assert result == {:error, :not_found}
    end
  end

  describe "setup_mock/1" do
    test "sets up custom mock behavior" do
      AdapterFactory.setup_mock(fn
        "script1" -> {:ok, "result1"}
        "script2" -> {:ok, "result2"}
        _ -> {:error, :unknown}
      end)

      assert {:ok, "result1"} = ExMacOSControl.AdapterMock.run_applescript("script1")
    end
  end

  describe "stub_applescript_success/1" do
    test "allows multiple calls with same result" do
      AdapterFactory.stub_applescript_success("result")

      assert {:ok, "result"} = ExMacOSControl.AdapterMock.run_applescript("script1")
      assert {:ok, "result"} = ExMacOSControl.AdapterMock.run_applescript("script2")
      assert {:ok, "result"} = ExMacOSControl.AdapterMock.run_applescript("script3")
    end
  end

  describe "stub_applescript_error/1" do
    test "allows multiple calls with same error" do
      AdapterFactory.stub_applescript_error(:error)

      assert {:error, :error} = ExMacOSControl.AdapterMock.run_applescript("script1")
      assert {:error, :error} = ExMacOSControl.AdapterMock.run_applescript("script2")
    end
  end
end

defmodule ExMacOSControlScriptFileTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExMacOSControl
  alias ExMacOSControl.Error
  alias ExMacOSControl.TestHelpers

  setup :verify_on_exit!

  describe "run_script_file/1" do
    test "delegates to adapter with empty options" do
      file_path = TestHelpers.fixture_path("applescript/hello_world.applescript")

      ExMacOSControl.AdapterMock
      |> expect(:run_script_file, fn ^file_path, [] ->
        {:ok, "Hello, World!"}
      end)

      assert {:ok, "Hello, World!"} = ExMacOSControl.run_script_file(file_path)
    end

    test "returns error from adapter" do
      file_path = "/nonexistent.applescript"

      ExMacOSControl.AdapterMock
      |> expect(:run_script_file, fn ^file_path, [] ->
        {:error, Error.not_found("Script file not found", file: file_path)}
      end)

      assert {:error, %Error{type: :not_found}} = ExMacOSControl.run_script_file(file_path)
    end
  end

  describe "run_script_file/2" do
    test "delegates to adapter with options" do
      file_path = TestHelpers.fixture_path("applescript/with_arguments.applescript")
      opts = [args: ["test"], timeout: 5000]

      ExMacOSControl.AdapterMock
      |> expect(:run_script_file, fn ^file_path, ^opts ->
        {:ok, "test"}
      end)

      assert {:ok, "test"} = ExMacOSControl.run_script_file(file_path, opts)
    end

    test "supports language override option" do
      file_path = "/path/to/script.txt"
      opts = [language: :applescript]

      ExMacOSControl.AdapterMock
      |> expect(:run_script_file, fn ^file_path, ^opts ->
        {:ok, "result"}
      end)

      assert {:ok, "result"} = ExMacOSControl.run_script_file(file_path, opts)
    end

    test "supports all options combined" do
      file_path = "/path/to/script.scpt"
      opts = [language: :applescript, args: ["arg1"], timeout: 10_000]

      ExMacOSControl.AdapterMock
      |> expect(:run_script_file, fn ^file_path, ^opts ->
        {:ok, "result"}
      end)

      assert {:ok, "result"} = ExMacOSControl.run_script_file(file_path, opts)
    end
  end
end

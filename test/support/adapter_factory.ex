defmodule ExMacOSControl.AdapterFactory do
  @moduledoc """
  Factory functions for creating and configuring mock adapters in tests.

  This module provides helpers for setting up Mox expectations for the
  ExMacOSControl.Adapter behaviour, making it easier to write unit tests.
  """

  import Mox

  @doc """
  Sets up a mock adapter to return a successful result for run_applescript/1.

  ## Examples

      test "successful script execution" do
        AdapterFactory.mock_applescript_success("Hello, World!")
        {:ok, result} = ExMacOSControl.run_applescript("return 'test'")
        assert result == "Hello, World!"
      end
  """
  @spec mock_applescript_success(String.t()) :: Mox.t()
  def mock_applescript_success(result) do
    ExMacOSControl.AdapterMock
    |> expect(:run_applescript, fn _script -> {:ok, result} end)
  end

  @doc """
  Sets up a mock adapter to return a successful result for run_applescript/2.

  ## Examples

      test "successful script execution with options" do
        AdapterFactory.mock_applescript_success_with_opts("Hello, World!")
        {:ok, result} = ExMacOSControl.run_applescript("return 'test'", timeout: 5000)
        assert result == "Hello, World!"
      end
  """
  @spec mock_applescript_success_with_opts(String.t()) :: Mox.t()
  def mock_applescript_success_with_opts(result) do
    ExMacOSControl.AdapterMock
    |> expect(:run_applescript, fn _script, _opts -> {:ok, result} end)
  end

  @doc """
  Sets up a mock adapter to return an error for run_applescript/1.

  ## Examples

      test "script execution error" do
        AdapterFactory.mock_applescript_error(:syntax_error)
        {:error, reason} = ExMacOSControl.run_applescript("invalid script")
        assert reason == :syntax_error
      end
  """
  @spec mock_applescript_error(atom() | String.t()) :: Mox.t()
  def mock_applescript_error(reason) do
    ExMacOSControl.AdapterMock
    |> expect(:run_applescript, fn _script -> {:error, reason} end)
  end

  @doc """
  Sets up a mock adapter to return a successful result for run_shortcut/1.

  ## Examples

      test "successful shortcut execution" do
        AdapterFactory.mock_shortcut_success()
        :ok = ExMacOSControl.run_shortcut("My Shortcut")
      end
  """
  @spec mock_shortcut_success() :: Mox.t()
  def mock_shortcut_success do
    ExMacOSControl.AdapterMock
    |> expect(:run_shortcut, fn _name -> :ok end)
  end

  @doc """
  Sets up a mock adapter to return an error for run_shortcut/1.

  ## Examples

      test "shortcut not found" do
        AdapterFactory.mock_shortcut_error(:not_found)
        {:error, reason} = ExMacOSControl.run_shortcut("Nonexistent Shortcut")
        assert reason == :not_found
      end
  """
  @spec mock_shortcut_error(atom() | String.t()) :: Mox.t()
  def mock_shortcut_error(reason) do
    ExMacOSControl.AdapterMock
    |> expect(:run_shortcut, fn _name -> {:error, reason} end)
  end

  @doc """
  Sets up a mock adapter with custom expectations.

  Use this when you need fine-grained control over mock behavior.

  ## Examples

      test "custom mock behavior" do
        AdapterFactory.setup_mock(fn
          "return 'hello'" -> {:ok, "hello"}
          "return 'world'" -> {:ok, "world"}
          _ -> {:error, :unknown_script}
        end)

        assert {:ok, "hello"} = ExMacOSControl.run_applescript("return 'hello'")
        assert {:ok, "world"} = ExMacOSControl.run_applescript("return 'world'")
      end
  """
  @spec setup_mock((String.t() -> {:ok, String.t()} | {:error, any()})) :: Mox.t()
  def setup_mock(fun) when is_function(fun, 1) do
    ExMacOSControl.AdapterMock
    |> expect(:run_applescript, fun)
  end

  @doc """
  Sets up a mock adapter that allows multiple calls with the same expectation.

  ## Examples

      test "multiple script executions" do
        AdapterFactory.stub_applescript_success("result")

        assert {:ok, "result"} = ExMacOSControl.run_applescript("script 1")
        assert {:ok, "result"} = ExMacOSControl.run_applescript("script 2")
        assert {:ok, "result"} = ExMacOSControl.run_applescript("script 3")
      end
  """
  @spec stub_applescript_success(String.t()) :: Mox.t()
  def stub_applescript_success(result) do
    ExMacOSControl.AdapterMock
    |> stub(:run_applescript, fn _script -> {:ok, result} end)
  end

  @doc """
  Sets up a mock adapter that allows multiple calls returning errors.

  ## Examples

      test "multiple script errors" do
        AdapterFactory.stub_applescript_error(:execution_error)

        assert {:error, :execution_error} = ExMacOSControl.run_applescript("script 1")
        assert {:error, :execution_error} = ExMacOSControl.run_applescript("script 2")
      end
  """
  @spec stub_applescript_error(atom() | String.t()) :: Mox.t()
  def stub_applescript_error(reason) do
    ExMacOSControl.AdapterMock
    |> stub(:run_applescript, fn _script -> {:error, reason} end)
  end

  @doc """
  Verifies that all mock expectations have been met.

  This is typically called automatically by ExUnit, but can be called
  explicitly if needed.

  ## Examples

      test "verify expectations" do
        AdapterFactory.mock_applescript_success("result")
        ExMacOSControl.run_applescript("test")
        AdapterFactory.verify_mocks()
      end
  """
  @spec verify_mocks() :: :ok
  def verify_mocks do
    verify!()
  end
end

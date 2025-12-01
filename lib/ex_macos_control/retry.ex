defmodule ExMacOSControl.Retry do
  @moduledoc """
  Retry logic for transient failures in macOS automation.

  This module provides automatic retry functionality with configurable backoff
  strategies to handle transient failures like timeouts. It's particularly useful
  when automating macOS operations that may temporarily fail due to system state
  or application responsiveness.

  ## Supported Backoff Strategies

  - `:exponential` - Doubles the wait time between each retry (default)
  - `:linear` - Uses a constant wait time between retries

  ## When to Use Retry Logic

  Retry logic is appropriate for:

  - Timeout errors that may succeed on subsequent attempts
  - Operations that depend on application state that may change
  - Network-dependent operations within scripts
  - UI automation that may be affected by system responsiveness

  Do NOT use retry logic for:

  - Syntax errors (these won't be fixed by retrying)
  - Permission errors (user intervention required)
  - Not found errors (resources won't appear by retrying)

  ## Examples

      # Basic retry with exponential backoff (default)
      Retry.with_retry(fn ->
        ExMacOSControl.run_applescript(script)
      end)

      # Custom max attempts with linear backoff
      Retry.with_retry(fn ->
        ExMacOSControl.run_applescript(script, timeout: 5000)
      end, max_attempts: 5, backoff: :linear)

      # Using with application modules
      Retry.with_retry(fn ->
        ExMacOSControl.Finder.list_windows()
      end, max_attempts: 3)

  ## Telemetry

  This module emits telemetry events for retry operations:

  - `[:ex_macos_control, :retry, :start]` - When retry logic begins
  - `[:ex_macos_control, :retry, :attempt]` - On each retry attempt
  - `[:ex_macos_control, :retry, :stop]` - When retry logic completes
  - `[:ex_macos_control, :retry, :error]` - When all retries are exhausted

  ### Event Metadata

  - `attempt` - Current attempt number (1-indexed)
  - `max_attempts` - Maximum number of attempts configured
  - `backoff` - Backoff strategy in use
  - `sleep_time` - Time slept before retry (in milliseconds)
  - `error` - Error that triggered retry or final error
  """

  @doc """
  Executes a function with automatic retry on timeout errors.

  ## Parameters

  - `fun` - A zero-arity function that returns `{:ok, result}` or `{:error, error}`
  - `opts` - Keyword list of options:
    - `:max_attempts` - Maximum number of attempts (default: 3)
    - `:backoff` - Backoff strategy, `:exponential` or `:linear` (default: `:exponential`)

  ## Returns

  - `{:ok, result}` - If the function succeeds within max attempts
  - `{:error, error}` - If all attempts fail or a non-retryable error occurs

  ## Retry Behavior

  Only timeout errors (errors with `type: :timeout`) are retried. All other errors
  are returned immediately without retrying.

  ## Examples

      # With default options (3 attempts, exponential backoff)
      iex> Retry.with_retry(fn -> {:ok, "success"} end)
      {:ok, "success"}

      # With timeout error that succeeds on retry
      iex> state = :ets.new(:test, [:public])
      iex> :ets.insert(state, {:attempts, 0})
      iex> fun = fn ->
      ...>   [{:attempts, count}] = :ets.lookup(state, :attempts)
      ...>   :ets.insert(state, {:attempts, count + 1})
      ...>   if count < 2 do
      ...>     {:error, %{type: :timeout, message: "timeout"}}
      ...>   else
      ...>     {:ok, "success"}
      ...>   end
      ...> end
      iex> Retry.with_retry(fun)
      {:ok, "success"}

      # With non-timeout error (no retry)
      iex> Retry.with_retry(fn -> {:error, %{type: :syntax_error}} end)
      {:error, %{type: :syntax_error}}

      # With custom options
      iex> Retry.with_retry(fn -> {:ok, "done"} end, max_attempts: 5, backoff: :linear)
      {:ok, "done"}
  """
  @spec with_retry(fun :: (-> {:ok, any()} | {:error, any()}), opts :: keyword()) ::
          {:ok, any()} | {:error, any()}
  def with_retry(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    backoff = Keyword.get(opts, :backoff, :exponential)

    metadata = %{max_attempts: max_attempts, backoff: backoff}
    :telemetry.execute([:ex_macos_control, :retry, :start], %{}, metadata)

    result = do_retry(fun, 1, max_attempts, backoff)

    case result do
      {:ok, _} ->
        :telemetry.execute([:ex_macos_control, :retry, :stop], %{}, metadata)

      {:error, error} ->
        :telemetry.execute([:ex_macos_control, :retry, :error], %{}, Map.put(metadata, :error, error))
    end

    result
  end

  # Recursively attempts to execute the function with retry logic
  defp do_retry(fun, attempt, max_attempts, backoff) do
    metadata = %{attempt: attempt, max_attempts: max_attempts, backoff: backoff}
    :telemetry.execute([:ex_macos_control, :retry, :attempt], %{attempt: attempt}, metadata)

    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, %{type: :timeout} = error} when attempt < max_attempts ->
        sleep_time = calculate_backoff(attempt, backoff)
        metadata_with_sleep = Map.merge(metadata, %{sleep_time: sleep_time, error: error})
        :telemetry.execute([:ex_macos_control, :retry, :sleep], %{sleep_time: sleep_time}, metadata_with_sleep)

        Process.sleep(sleep_time)
        do_retry(fun, attempt + 1, max_attempts, backoff)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Calculates the sleep time based on backoff strategy
  @doc false
  @spec calculate_backoff(attempt :: pos_integer(), strategy :: :exponential | :linear) :: pos_integer()
  def calculate_backoff(attempt, :exponential) when is_integer(attempt) and attempt > 0 do
    # Exponential: 2^attempt * 100ms
    # Attempt 1: 200ms, Attempt 2: 400ms, Attempt 3: 800ms, etc.
    round(:math.pow(2, attempt) * 100)
  end

  def calculate_backoff(_attempt, :linear) do
    # Linear: constant 1000ms (1 second)
    1000
  end
end

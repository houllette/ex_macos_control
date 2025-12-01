defmodule ExMacOSControl.RetryTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.Retry

  # Telemetry handler module to avoid performance warnings
  def handle_telemetry_event(event, measurements, metadata, config) do
    send(config.test_pid, {:telemetry, event, measurements, metadata})
  end

  describe "with_retry/2" do
    test "returns success immediately on first attempt" do
      result =
        Retry.with_retry(fn ->
          {:ok, "success"}
        end)

      assert result == {:ok, "success"}
    end

    test "returns error immediately for non-timeout errors" do
      result =
        Retry.with_retry(fn ->
          {:error, %{type: :syntax_error, message: "syntax error"}}
        end)

      assert result == {:error, %{type: :syntax_error, message: "syntax error"}}
    end

    test "does not retry non-timeout errors" do
      # Track attempts using send to self
      result =
        Retry.with_retry(fn ->
          send(self(), :attempt)
          {:error, %{type: :permission_error}}
        end)

      # Should only receive one attempt message
      assert_received :attempt
      refute_received :attempt
      assert result == {:error, %{type: :permission_error}}
    end

    test "retries on timeout error up to max_attempts" do
      # This will fail all 3 attempts
      result =
        Retry.with_retry(
          fn ->
            send(self(), :attempt)
            {:error, %{type: :timeout, message: "timeout"}}
          end,
          max_attempts: 3
        )

      # Should receive 3 attempt messages
      assert_received :attempt
      assert_received :attempt
      assert_received :attempt
      refute_received :attempt

      assert result == {:error, %{type: :timeout, message: "timeout"}}
    end

    test "succeeds after retrying timeout error" do
      # Create a counter using Agent
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_retry(
          fn ->
            count = Agent.get_and_update(counter, fn c -> {c, c + 1} end)

            if count < 2 do
              {:error, %{type: :timeout}}
            else
              {:ok, "success"}
            end
          end,
          max_attempts: 3
        )

      assert result == {:ok, "success"}
      assert Agent.get(counter, & &1) == 3

      Agent.stop(counter)
    end

    test "respects custom max_attempts" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_retry(
          fn ->
            count = Agent.get_and_update(counter, fn c -> {c, c + 1} end)
            send(self(), {:attempt, count})
            {:error, %{type: :timeout}}
          end,
          max_attempts: 5
        )

      # Should attempt 5 times
      assert Agent.get(counter, & &1) == 5
      assert result == {:error, %{type: :timeout}}

      Agent.stop(counter)
    end

    test "succeeds on last attempt" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_retry(
          fn ->
            count = Agent.get_and_update(counter, fn c -> {c, c + 1} end)

            # Succeed on attempt 3 (last attempt with max_attempts: 3)
            if count < 2 do
              {:error, %{type: :timeout}}
            else
              {:ok, "success on last attempt"}
            end
          end,
          max_attempts: 3
        )

      assert result == {:ok, "success on last attempt"}
      assert Agent.get(counter, & &1) == 3

      Agent.stop(counter)
    end

    test "handles various error structures with timeout type" do
      # Error as map with type
      result1 = Retry.with_retry(fn -> {:error, %{type: :timeout}} end, max_attempts: 1)
      assert result1 == {:error, %{type: :timeout}}

      # Error with additional fields
      result2 =
        Retry.with_retry(
          fn -> {:error, %{type: :timeout, message: "timed out", details: %{}}} end,
          max_attempts: 1
        )

      assert result2 == {:error, %{type: :timeout, message: "timed out", details: %{}}}
    end

    test "preserves success value through retry logic" do
      values = ["result1", 42, %{key: "value"}, ["list", "items"]]

      for value <- values do
        result = Retry.with_retry(fn -> {:ok, value} end)
        assert result == {:ok, value}
      end
    end
  end

  describe "with_retry/2 with exponential backoff" do
    test "uses exponential backoff timing" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      start_time = System.monotonic_time(:millisecond)

      Retry.with_retry(
        fn ->
          Agent.update(counter, &(&1 + 1))
          {:error, %{type: :timeout}}
        end,
        max_attempts: 3,
        backoff: :exponential
      )

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # Exponential backoff: attempt 1 (0ms) + sleep 200ms + attempt 2 + sleep 400ms + attempt 3
      # Should take at least 600ms (200 + 400)
      # Allow some margin for test execution time
      assert elapsed >= 550
      assert Agent.get(counter, & &1) == 3

      Agent.stop(counter)
    end

    test "calculates correct backoff times for exponential" do
      assert Retry.calculate_backoff(1, :exponential) == 200
      assert Retry.calculate_backoff(2, :exponential) == 400
      assert Retry.calculate_backoff(3, :exponential) == 800
      assert Retry.calculate_backoff(4, :exponential) == 1600
      assert Retry.calculate_backoff(5, :exponential) == 3200
    end
  end

  describe "with_retry/2 with linear backoff" do
    test "uses linear backoff timing" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      start_time = System.monotonic_time(:millisecond)

      Retry.with_retry(
        fn ->
          Agent.update(counter, &(&1 + 1))
          {:error, %{type: :timeout}}
        end,
        max_attempts: 3,
        backoff: :linear
      )

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # Linear backoff: attempt 1 (0ms) + sleep 1000ms + attempt 2 + sleep 1000ms + attempt 3
      # Should take at least 2000ms (1000 + 1000)
      # Allow some margin for test execution time
      assert elapsed >= 1950
      assert Agent.get(counter, & &1) == 3

      Agent.stop(counter)
    end

    test "calculates correct backoff times for linear" do
      assert Retry.calculate_backoff(1, :linear) == 1000
      assert Retry.calculate_backoff(2, :linear) == 1000
      assert Retry.calculate_backoff(3, :linear) == 1000
      assert Retry.calculate_backoff(100, :linear) == 1000
    end
  end

  describe "with_retry/2 telemetry" do
    setup do
      # Attach a test telemetry handler
      test_pid = self()

      handler_id = "test-retry-handler-#{:erlang.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:ex_macos_control, :retry, :start],
          [:ex_macos_control, :retry, :attempt],
          [:ex_macos_control, :retry, :sleep],
          [:ex_macos_control, :retry, :stop],
          [:ex_macos_control, :retry, :error]
        ],
        &__MODULE__.handle_telemetry_event/4,
        %{test_pid: test_pid}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      %{handler_id: handler_id}
    end

    test "emits start event" do
      Retry.with_retry(fn -> {:ok, "success"} end, max_attempts: 3, backoff: :exponential)

      assert_received {:telemetry, [:ex_macos_control, :retry, :start], %{}, %{max_attempts: 3, backoff: :exponential}}
    end

    test "emits attempt events for each retry" do
      Retry.with_retry(fn -> {:error, %{type: :timeout}} end, max_attempts: 3)

      # Should receive 3 attempt events
      assert_received {:telemetry, [:ex_macos_control, :retry, :attempt], %{attempt: 1}, _}
      assert_received {:telemetry, [:ex_macos_control, :retry, :attempt], %{attempt: 2}, _}
      assert_received {:telemetry, [:ex_macos_control, :retry, :attempt], %{attempt: 3}, _}
    end

    test "emits stop event on success" do
      Retry.with_retry(fn -> {:ok, "success"} end)

      # Clear start and attempt events
      assert_received {:telemetry, [:ex_macos_control, :retry, :start], _, _}
      assert_received {:telemetry, [:ex_macos_control, :retry, :attempt], _, _}

      # Should receive stop event
      assert_received {:telemetry, [:ex_macos_control, :retry, :stop], %{}, _}
      refute_received {:telemetry, [:ex_macos_control, :retry, :error], _, _}
    end

    test "emits error event on failure" do
      error = %{type: :timeout, message: "test timeout"}
      Retry.with_retry(fn -> {:error, error} end, max_attempts: 1)

      # Clear start and attempt events
      assert_received {:telemetry, [:ex_macos_control, :retry, :start], _, _}
      assert_received {:telemetry, [:ex_macos_control, :retry, :attempt], _, _}

      # Should receive error event with error metadata
      assert_received {:telemetry, [:ex_macos_control, :retry, :error], %{},
                       %{error: ^error, max_attempts: 1, backoff: :exponential}}

      refute_received {:telemetry, [:ex_macos_control, :retry, :stop], _, _}
    end

    test "emits sleep events with correct metadata" do
      Retry.with_retry(fn -> {:error, %{type: :timeout}} end, max_attempts: 2, backoff: :exponential)

      # Clear start and first attempt
      assert_received {:telemetry, [:ex_macos_control, :retry, :start], _, _}
      assert_received {:telemetry, [:ex_macos_control, :retry, :attempt], %{attempt: 1}, _}

      # Should receive sleep event before second attempt
      assert_received {:telemetry, [:ex_macos_control, :retry, :sleep], %{sleep_time: 200}, metadata}

      assert metadata.attempt == 1
      assert metadata.sleep_time == 200
      assert metadata.error.type == :timeout
    end

    test "emits complete telemetry flow for successful retry" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Retry.with_retry(
        fn ->
          count = Agent.get_and_update(counter, fn c -> {c, c + 1} end)

          if count < 1 do
            {:error, %{type: :timeout}}
          else
            {:ok, "success"}
          end
        end,
        max_attempts: 3,
        backoff: :linear
      )

      # Start event
      assert_received {:telemetry, [:ex_macos_control, :retry, :start], %{}, %{max_attempts: 3, backoff: :linear}}

      # First attempt (fails)
      assert_received {:telemetry, [:ex_macos_control, :retry, :attempt], %{attempt: 1}, _}
      assert_received {:telemetry, [:ex_macos_control, :retry, :sleep], %{sleep_time: 1000}, _}

      # Second attempt (succeeds)
      assert_received {:telemetry, [:ex_macos_control, :retry, :attempt], %{attempt: 2}, _}

      # Stop event
      assert_received {:telemetry, [:ex_macos_control, :retry, :stop], %{}, _}

      # No error event
      refute_received {:telemetry, [:ex_macos_control, :retry, :error], _, _}

      # No third attempt
      refute_received {:telemetry, [:ex_macos_control, :retry, :attempt], %{attempt: 3}, _}

      Agent.stop(counter)
    end
  end

  describe "with_retry/2 edge cases" do
    test "handles max_attempts of 1 (no retry)" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_retry(
          fn ->
            Agent.update(counter, &(&1 + 1))
            {:error, %{type: :timeout}}
          end,
          max_attempts: 1
        )

      assert result == {:error, %{type: :timeout}}
      assert Agent.get(counter, & &1) == 1

      Agent.stop(counter)
    end

    test "handles very high max_attempts" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_retry(
          fn ->
            count = Agent.get_and_update(counter, fn c -> {c, c + 1} end)

            if count < 2 do
              {:error, %{type: :timeout}}
            else
              {:ok, "success"}
            end
          end,
          max_attempts: 100
        )

      assert result == {:ok, "success"}
      assert Agent.get(counter, & &1) == 3

      Agent.stop(counter)
    end

    test "works with empty options list" do
      result = Retry.with_retry(fn -> {:ok, "success"} end, [])
      assert result == {:ok, "success"}
    end
  end
end

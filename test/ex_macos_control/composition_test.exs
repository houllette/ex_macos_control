defmodule ExMacOSControl.CompositionTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Composition, Error, Notes, Retry}
  setup :verify_on_exit!

  test "all native calls consume the same deadline, including explicit longer timeouts" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert opts[:timeout] in 1..500
      Process.sleep(30)
      {:ok, ~s({"exmc":1,"result":[]})}
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert opts[:timeout] in 1..470
      assert opts[:max_output_bytes] == 200
      {:ok, ~s({"exmc":1,"result":[]})}
    end)

    assert {:ok, []} =
             Composition.run(
               fn ->
                 Notes.list_accounts()
                 Notes.list_accounts(timeout: 10_000)
               end,
               timeout: 500,
               max_output_bytes: 200
             )

    assert Composition.remaining() == :infinity
    assert ExMacOSControl.execution_options() == []
  end

  test "expired scopes never dispatch new effects and do not leak options" do
    assert {:error, %Error{type: :timeout, details: %{outcome: :not_started}}} =
             Composition.run(fn -> Notes.create_note(title: "never") end, timeout: 0)

    assert ExMacOSControl.execution_options() == []
  end

  test "nested scopes cannot extend the parent deadline and restore it on exceptions" do
    assert_raise RuntimeError, "failed", fn ->
      Composition.run(
        fn ->
          parent = Composition.remaining()

          Composition.run(
            fn ->
              assert Composition.remaining() <= parent
              raise "failed"
            end,
            timeout: 10_000
          )
        end,
        timeout: 500
      )
    end

    assert Composition.remaining() == :infinity
  end

  test "failure keeps completed results, unknown outcome and original error type without retry" do
    error = Error.timeout("send", outcome: :unknown)

    assert {:error, result} =
             Composition.run(fn ->
               with {:ok, _} <- Composition.step(:create_draft, fn -> {:ok, "draft-id"} end) do
                 Composition.step(:send_draft, fn -> {:error, error} end)
               end
             end)

    assert result.type == :timeout
    assert result.details.outcome == :unknown
    assert result.details.composition == %{step: :send_draft, completed: [%{step: :create_draft, result: "draft-id"}]}
  end

  test "batch stops at first failure and retains results in input order" do
    assert {:error, error} =
             Composition.run(fn ->
               Composition.map([1, 2, 3], :item, fn
                 1 -> {:ok, "one"}
                 2 -> {:error, Error.permission_denied("denied")}
                 3 -> flunk("must not continue")
               end)
             end)

    assert error.details.composition.completed == [%{step: {:item, 0}, result: "one"}]
    assert error.type == :permission_denied
  end

  test "resource cleanup has its own budget after work expires" do
    assert {:error, %Error{type: :timeout}} =
             Composition.run(
               fn ->
                 Composition.resource(
                   "owned",
                   fn _ ->
                     Process.sleep(30)
                     Composition.step(:late, fn -> flunk("must not run") end)
                   end,
                   fn "owned" ->
                     assert Composition.remaining() in 1..5000
                     send(self(), :cleaned)
                     :ok
                   end
                 )
               end,
               timeout: 20
             )

    assert_received :cleaned
  end

  test "cleanup runs for exceptions and throws, and preserves the original failure" do
    for kind <- [:error, :throw] do
      operation = fn ->
        Composition.run(fn ->
          Composition.resource(
            :owned,
            fn _ ->
              if kind == :error, do: raise("callback"), else: throw(:callback)
            end,
            fn _ ->
              send(self(), :cleaned)
              :ok
            end
          )
        end)
      end

      if kind == :error,
        do: assert_raise(RuntimeError, "callback", operation),
        else: assert(catch_throw(operation.()) == :callback)

      assert_received :cleaned
    end

    assert Composition.remaining() == :infinity
  end

  test "cleanup failure preserves both the work failure and the resource identity" do
    assert {:error, error} =
             Composition.run(fn ->
               Composition.resource("window-id", fn _ -> {:error, Error.permission_denied("work")} end, fn _ ->
                 {:error, Error.execution_error("cleanup")}
               end)
             end)

    assert error.type == :permission_denied
    assert error.details.resource == "window-id"
    assert error.details.cleanup_error.message == "cleanup"
  end

  test "invalid options never invoke the callback" do
    for opts <- [[timeout: :infinity], [timeout: nil], [timeout: -1], [unknown: true], [max_output_bytes: 0]] do
      assert {:error, %Error{}} = Composition.run(fn -> flunk("must not run") end, opts)
    end
  end

  test "generic retry does not repeat acknowledged writes when a later step times out" do
    reference = make_ref()

    assert {:error, %Error{type: :timeout}} =
             Retry.with_retry(fn ->
               Composition.run(fn ->
                 Composition.step(:write, fn ->
                   Process.put(reference, Process.get(reference, 0) + 1)
                   {:ok, "created-id"}
                 end)

                 Composition.step(:later, fn -> {:error, Error.timeout("waiting", outcome: :not_started)} end)
               end)
             end)

    assert Process.get(reference) == 1
  end

  test "a cleanup exception cannot mask a callback exception" do
    assert_raise RuntimeError, "work", fn ->
      Composition.run(fn ->
        Composition.resource(:owned, fn _ -> raise "work" end, fn _ -> raise "cleanup" end)
      end)
    end

    assert Composition.remaining() == :infinity
  end

  test "standalone batches retain their completed results without a surrounding run" do
    assert {:error, error} =
             Composition.map([:one, :two], :item, fn
               :one -> {:ok, "created"}
               :two -> {:error, Error.execution_error("failed")}
             end)

    assert error.details.composition.completed == [%{step: {:item, 0}, result: "created"}]
    assert Composition.remaining() == :infinity
  end
end

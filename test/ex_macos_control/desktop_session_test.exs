defmodule ExMacOSControl.DesktopSessionTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{Composition, Error}
  alias ExMacOSControl.Desktop.Session

  defmodule Backend do
    @behaviour Session
    @impl true
    def snapshot(ids), do: {:ok, %{ids: ids, existing: [99]}}

    @impl true
    def prepare(id, before) do
      send(self(), {:prepared, id, before.existing})
      if id == "failed", do: {:error, Error.execution_error("startup")}, else: {:ok, [%{id: id}]}
    end

    @impl true
    def close(ref) do
      send(self(), {:closed, ref.id, Composition.remaining()})
      if ref.id == "raised", do: raise("cleanup")
      if ref.id == "blocked", do: {:error, Error.execution_error("modified")}, else: :ok
    end

    @impl true
    def restore(_) do
      send(self(), :restored)
      :ok
    end
  end

  setup do
    previous = Application.get_env(:ex_macos_control, :desktop_session_backend)
    Application.put_env(:ex_macos_control, :desktop_session_backend, Backend)
    on_exit(fn -> Application.put_env(:ex_macos_control, :desktop_session_backend, previous) end)
  end

  test "default cleanup releases owned windows in reverse order and preserves the callback result" do
    assert {:ok, :result} = Session.with_apps(["one", "two"], fn -> {:ok, :result} end)
    assert_received {:prepared, "one", [99]}
    assert_received {:prepared, "two", [99]}
    assert_receive {:closed, "two", budget} when budget > 0
    assert_receive {:closed, "one", budget} when budget > 0
    assert_received :restored
    refute_received {:closed, 99, _}
  end

  test "later startup failures still clean earlier acquisitions" do
    assert {:error, _} = Session.with_apps(["one", "failed"], fn -> flunk("must not execute") end)
    assert_received {:closed, "one", _}
    assert_received :restored
  end

  test "callback exceptions and throws release windows before propagating" do
    assert_raise RuntimeError, "callback", fn -> Session.with_apps(["one"], fn -> raise "callback" end) end
    assert_received {:closed, "one", _}
    assert catch_throw(Session.with_apps(["two"], fn -> throw(:callback) end)) == :callback
    assert_received {:closed, "two", _}
  end

  test "expired work still gets a separate cleanup budget and all cleanups are attempted" do
    assert {:error, error} =
             Session.with_apps(
               ["one", "blocked", "two"],
               fn ->
                 Process.sleep(15)
                 {:error, Error.timeout("work")}
               end,
               timeout: 10
             )

    assert error.details.cleanup_error
    assert_received {:closed, "two", budget} when budget > 0
    assert_received {:closed, "blocked", budget} when budget > 0
    assert_received {:closed, "one", budget} when budget > 0
    assert_received :restored
  end

  test "one raising cleanup cannot prevent remaining windows or focus restoration" do
    assert {:error, _} = Session.with_apps(["one", "raised", "two"], fn -> :ok end)
    assert_received {:closed, "two", _}
    assert_received {:closed, "raised", _}
    assert_received {:closed, "one", _}
    assert_received :restored
  end

  test "keeping support windows requires an explicit option" do
    assert :ok = Session.with_apps(["one"], fn -> :ok end, keep_windows: true)
    refute_received {:closed, _, _}
    assert_received :restored
    assert {:error, _} = Session.with_apps(["one"], fn -> :ok end, keep_windows: :invalid)
  end
end

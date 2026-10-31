defmodule ExMacOSControl.SafariGuardLiveTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{CompositionLiveSession, LiveEvidence, Safari}
  @moduletag :personal
  @moduletag safari_guards: true
  @moduletag timeout: 120_000
  @moduletag apps: ["com.apple.Safari"]
  unless System.get_env("EXMC_LIVE_TESTS") == "1" and System.get_env("EXMC_PERSONAL_TESTS") == "1",
    do: @moduletag(skip: "Requires personal opt-in")

  test "bound handles refuse stale app identities and replaced documents", context do
    live = CompositionLiveSession.start(context)
    path = Path.join(live.root, "guard.html")

    File.write!(
      path,
      "<html><body><input id='field' oninput='document.querySelector(\"#display\").textContent=this.value'><p id='display'></p></body></html>"
    )

    url = "file://" <> URI.encode(path)
    intent = LiveEvidence.intent(live, :safari_window)
    assert {:ok, page} = CompositionLiveSession.effect(live, :open_page, fn -> Safari.open_page(url) end)

    CompositionLiveSession.own(live, :safari_window, page.window_id, fn -> Safari.close_page(page) end,
      intent_id: intent,
      verify: fn ->
        CompositionLiveSession.query(
          "com.apple.Safari",
          "return app.windows().every(function(w){if(w.id()!==input.id)return true;var tabs=w.tabs();return !tabs || tabs.length===0;});",
          %{id: page.window_id}
        )
      end
    )

    assert is_integer(page.application_pid) and is_number(page.application_started_at)
    assert :ok = Safari.wait_for_ready(page)
    assert {:ok, pinned} = Safari.pin_document(page)
    assert :ok = Safari.fill(pinned, "#field", "first")
    assert {:ok, "first"} = Safari.text(pinned, "#display")

    for stale <- [
          %{page | application_pid: page.application_pid + 1},
          %{page | application_started_at: page.application_started_at + 1}
        ] do
      assert {:error, _} = Safari.fill(stale, "#field", "must not edit")
      assert {:error, _} = Safari.close_page(stale)
    end

    assert {:ok, "first"} = Safari.text(page, "#display")
    assert {:ok, reloaded} = Safari.navigate_page(pinned, url)
    assert reloaded.document_token != pinned.document_token
    assert {:error, _} = Safari.text(pinned, "#display")
    assert {:error, _} = Safari.close_page(pinned)
    assert {:ok, ""} = Safari.text(reloaded, "#display")
    next_url = url <> "#next"
    assert {:ok, navigated} = Safari.navigate_page(reloaded, next_url)
    assert {:error, _} = Safari.fill(reloaded, "#field", "must not edit")
    assert :ok = Safari.fill(navigated, "#field", "second")
    assert {:ok, "second"} = Safari.text(navigated, "#display")

    CompositionLiveSession.event(live, "verified", %{
      pid_guard: true,
      launch_guard: true,
      document_reload_guard: true,
      navigation_guard: true
    })
  end
end

defmodule ExMacOSControl.SafariCompositionsTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Error, Safari}
  alias ExMacOSControl.Safari.Page
  setup :verify_on_exit!

  test "scoped pages preserve identity, wait before use, and close on success" do
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn source, opts ->
      refute source =~ "https://example.invalid"
      assert opts[:args] == ["https://example.invalid"]
      {:ok, "42"}
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["window_id"] == 42
      assert input(opts)["owned"] == true
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["window_id"] == 42
      assert input(opts)["tab_index"] == 1
      response(" $99 ")
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      assert source =~ "additional tabs"
      assert input(opts)["window_id"] == 42
      assert opts[:timeout] in 1..5000
      response(true)
    end)

    assert {:ok, " $99 "} =
             Safari.with_page("https://example.invalid", fn %Page{window_id: 42} = page ->
               Safari.text(page, ".price")
             end)
  end

  test "a readiness error still closes the owned window without running the callback" do
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, "9"} end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      {:error, Error.permission_denied("JavaScript disabled")}
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["window_id"] == 9
      response(true)
    end)

    assert {:error, %Error{type: :permission_denied}} =
             Safari.with_page("https://example.invalid", fn _ -> flunk("not ready") end)
  end

  test "selector text is passed as data, including quotes, Unicode and script-like text" do
    selector = ~s|[title="雪');throw new Error('bad')"]|

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      refute source =~ selector
      assert input(opts)["code"] =~ Jason.encode!(Jason.encode!(%{selector: selector}), escape: :javascript_safe)
      response("text")
    end)

    assert {:ok, "text"} = Safari.text(%Page{window_id: 3, tab_index: 2}, selector)
  end

  test "navigation dispatches once and polls through stale and loading documents" do
    page = %Page{window_id: 4, tab_index: 1}
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("https://example.invalid/old") end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      assert source =~ "t.url=input.url"
      assert input(opts)["url"] == "https://example.invalid/new"
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(false) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(true) end)
    assert :ok = Safari.navigate_and_wait(page, "https://example.invalid/new", interval: 1)
  end

  test "a failed action with unknown outcome is returned after a single click" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(true) end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      {:error, Error.timeout("click", outcome: :unknown)}
    end)

    assert {:error, %Error{details: %{outcome: :unknown}}} = Safari.click(%Page{window_id: 1, tab_index: 1}, "button")
  end

  test "invalid inputs fail before opening windows" do
    assert {:error, %Error{}} = Safari.with_page("url", [interval: 0], fn _ -> :ok end)
    assert {:error, %Error{}} = Safari.extract_text("url", "")
    assert {:error, %Error{}} = Safari.fill_fields(%Page{window_id: 1, tab_index: 1}, [{"#ok", "x"}, {"#bad", nil}])
  end

  defp input(opts), do: opts[:args] |> hd() |> Jason.decode!()
  defp response(value), do: {:ok, Jason.encode!(%{exmc: 1, result: value})}
end

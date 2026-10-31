defmodule ExMacOSControl.AccessibilityTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Accessibility, Error, Music, Wait}
  setup :verify_on_exit!

  test "selectors stay data, preserve literal punctuation and propagate execution limits" do
    title = "Delete \"all\" & 雪"

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn script, opts ->
      refute script =~ title
      assert %{"path" => [%{"title" => ^title}], "process" => 123} = opts[:args] |> hd() |> Jason.decode!()
      assert opts[:timeout] == 500
      {:ok, ~s({"exmc":1,"result":true})}
    end)

    assert :ok = Accessibility.click(123, [%{title: title}], timeout: 500)
  end

  test "bounds and selectors are checked before any accessibility operation" do
    assert {:error, %Error{}} = Accessibility.tree("App", depth: 11)
    assert {:error, %Error{}} = Accessibility.tree("App", max_nodes: 1001)
    assert {:error, %Error{}} = Accessibility.click("App", [%{index: 0}])
    assert {:error, %Error{}} = Accessibility.click("App", [%{raw_code: "ignored"}])
    assert {:error, %Error{}} = Accessibility.press_key_code("App", 128)
    assert {:error, %Error{}} = Music.set_volume(101)
  end

  test "wait retries observable false, propagates errors and enforces its deadline" do
    ref = make_ref()

    assert :ok =
             Wait.until(
               fn ->
                 count = Process.get(ref, 0)
                 Process.put(ref, count + 1)
                 count > 0
               end,
               timeout: 100,
               interval: 1
             )

    assert {:error, %Error{type: :timeout}} = Wait.until(fn -> false end, timeout: 2, interval: 1)
    error = Error.permission_denied("Denied")
    assert {:error, ^error} = Wait.until(fn -> {:error, error} end)
  end

  test "state waits inherit output limits and stop before dispatch at an expired deadline" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert opts[:timeout] in 1..1000
      assert opts[:max_output_bytes] == 500
      {:ok, ~s({"exmc":1,"result":true})}
    end)

    ExMacOSControl.with_options([timeout: 1000, max_output_bytes: 500], fn ->
      assert :ok = Accessibility.wait_for("Synthetic", [])
    end)

    ExMacOSControl.with_options([timeout: 0, max_output_bytes: 500], fn ->
      assert {:error, %Error{type: :timeout}} = Accessibility.wait_for("Synthetic", [])
    end)
  end
end

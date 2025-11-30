defmodule ExMacosControlTest do
  use ExUnit.Case, async: true
  doctest ExMacOSControl

  test "exposes run_shortcut/1 and run_applescript/1" do
    assert function_exported?(ExMacOSControl, :run_shortcut, 1)
    assert function_exported?(ExMacOSControl, :run_applescript, 1)
  end
end

defmodule ExMacOSControl.Qualification.TaskTest do
  use ExUnit.Case, async: true
  alias Mix.Tasks.ExMacosControl.Qualify

  test "CLI refuses arbitrary scripts, recipients and conflicting profile flags before startup" do
    for arguments <- [
          [],
          ["--script", "send something"],
          ["--manifest", "tmp/file", "--profile", "notes-crud", "--recipient", "anyone@example.com"],
          ["--manifest", "tmp/file", "--profile", "notes-crud", "--profile", "mail-capture"],
          ["--manifest", "tmp/file", "--profile", "notes-crud", "--execute", "--no-execute"]
        ] do
      assert_raise Mix.Error, fn -> Qualify.run(arguments) end
    end
  end
end

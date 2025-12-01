defmodule ExMacOSControl.ScriptTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.Script

  doctest ExMacOSControl.Script

  describe "tell/2" do
    test "generates basic tell block with single command" do
      script = Script.tell("Finder", ["activate"])

      assert script == """
             tell application "Finder"
               activate
             end tell\
             """
    end

    test "generates tell block with multiple commands" do
      script =
        Script.tell("Finder", [
          "activate",
          "open home folder"
        ])

      assert script == """
             tell application "Finder"
               activate
               open home folder
             end tell\
             """
    end

    test "generates tell block with command helper" do
      script =
        Script.tell("Finder", [
          "activate",
          Script.cmd("open", "Macintosh HD")
        ])

      assert script == """
             tell application "Finder"
               activate
               open "Macintosh HD"
             end tell\
             """
    end

    test "generates nested tell blocks" do
      script =
        Script.tell("System Events", [
          Script.tell_obj("process", "Safari", [
            "set frontmost to true"
          ])
        ])

      assert script == """
             tell application "System Events"
               tell process "Safari"
                 set frontmost to true
               end tell
             end tell\
             """
    end

    test "escapes quotes in application name" do
      script = Script.tell("My \"Special\" App", ["activate"])

      assert script == """
             tell application "My \\"Special\\" App"
               activate
             end tell\
             """
    end
  end

  describe "tell_obj/3" do
    test "generates tell block for process" do
      script = Script.tell_obj("process", "Safari", ["set frontmost to true"])

      assert script == """
             tell process "Safari"
               set frontmost to true
             end tell\
             """
    end

    test "generates tell block for window" do
      script = Script.tell_obj("window", "Untitled", ["close"])

      assert script == """
             tell window "Untitled"
               close
             end tell\
             """
    end

    test "escapes quotes in object name" do
      script = Script.tell_obj("process", "My \"App\"", ["activate"])

      assert script == """
             tell process "My \\"App\\""
               activate
             end tell\
             """
    end
  end

  describe "cmd/2 with single argument" do
    test "quotes string arguments" do
      assert Script.cmd("open", "Macintosh HD") == ~s(open "Macintosh HD")
    end

    test "handles numeric arguments" do
      assert Script.cmd("set volume", 50) == "set volume 50"
      assert Script.cmd("delay", 1.5) == "delay 1.5"
    end

    test "handles boolean arguments" do
      assert Script.cmd("set muted", true) == "set muted true"
      assert Script.cmd("set visible", false) == "set visible false"
    end

    test "escapes quotes in string arguments" do
      assert Script.cmd("open", ~s(My "Special" Folder)) ==
               ~s(open "My \\"Special\\" Folder")
    end
  end

  describe "cmd/2 with list arguments" do
    test "formats all-numeric lists as AppleScript lists" do
      assert Script.cmd("set bounds of window 1 to", [0, 0, 800, 600]) ==
               "set bounds of window 1 to {0, 0, 800, 600}"
    end

    test "formats mixed string lists as space-separated quoted values" do
      assert Script.cmd("make", ["new", "window"]) ==
               ~s(make "new" "window")
    end

    test "handles mixed numeric and non-numeric arguments" do
      assert Script.cmd("test", ["foo", 42, true]) ==
               ~s(test "foo" 42 true)
    end

    test "escapes quotes in list arguments" do
      assert Script.cmd("make", ["new", ~s(My "Special" Item)]) ==
               ~s(make "new" "My \\"Special\\" Item")
    end
  end

  describe "quote escaping" do
    test "escapes single quotes in strings" do
      script = Script.tell("Finder", [Script.cmd("open", ~s(Holden's Folder))])

      assert script == """
             tell application "Finder"
               open "Holden's Folder"
             end tell\
             """
    end

    test "escapes double quotes in strings" do
      script =
        Script.tell("Finder", [
          Script.cmd("open", ~s(My "Important" Files))
        ])

      assert script == """
             tell application "Finder"
               open "My \\"Important\\" Files"
             end tell\
             """
    end

    test "handles backslashes in strings" do
      script = Script.tell("Finder", [Script.cmd("open", "Path\\With\\Backslashes")])

      # Note: Single backslashes are preserved, only quotes are escaped
      assert script == """
             tell application "Finder"
               open "Path\\With\\Backslashes"
             end tell\
             """
    end
  end

  describe "indentation" do
    test "properly indents single-level commands" do
      script =
        Script.tell("Finder", [
          "activate",
          "open home folder",
          "close every window"
        ])

      # Each command should be indented by 2 spaces
      assert script =~ "  activate\n"
      assert script =~ "  open home folder\n"
      assert script =~ "  close every window\n"
    end

    test "properly indents nested tell blocks" do
      script =
        Script.tell("System Events", [
          Script.tell_obj("process", "Finder", [
            "set frontmost to true",
            "click menu item 1"
          ])
        ])

      # Outer tell commands indented by 2 spaces
      assert script =~ "  tell process"

      # Inner commands indented by 4 spaces (2 from outer + 2 from inner)
      assert script =~ "    set frontmost to true\n"
      assert script =~ "    click menu item 1\n"
    end
  end

  describe "complex examples" do
    test "generates Finder automation script" do
      script =
        Script.tell("Finder", [
          "activate",
          Script.cmd("open", "/Applications"),
          "set current view of front window to icon view"
        ])

      assert script == """
             tell application "Finder"
               activate
               open "/Applications"
               set current view of front window to icon view
             end tell\
             """
    end

    test "generates System Events UI automation script" do
      script =
        Script.tell("System Events", [
          Script.tell_obj("process", "Safari", [
            "set frontmost to true",
            "click menu bar 1",
            Script.cmd("keystroke", "f"),
            Script.cmd("delay", 0.5)
          ])
        ])

      assert script == """
             tell application "System Events"
               tell process "Safari"
                 set frontmost to true
                 click menu bar 1
                 keystroke "f"
                 delay 0.5
               end tell
             end tell\
             """
    end

    test "generates window bounds script" do
      script =
        Script.tell("Finder", [
          Script.cmd("set bounds of window 1 to", [100, 100, 900, 700])
        ])

      assert script == """
             tell application "Finder"
               set bounds of window 1 to {100, 100, 900, 700}
             end tell\
             """
    end
  end
end

# DSL vs Raw AppleScript: Choosing the Right Approach

ExMacOSControl offers two ways to write AppleScript automation:

1. **The Script DSL** - Elixir functions that generate AppleScript
2. **Raw AppleScript** - Write AppleScript directly as strings

This guide helps you choose the right approach for your use case.

## Quick Decision Tree

```
Need complex control flow (if/while/repeat)?
├─ Yes → Use Raw AppleScript
└─ No → Keep reading...

Need variables or handlers?
├─ Yes → Use Raw AppleScript
└─ No → Keep reading...

Building simple tell blocks with dynamic values?
├─ Yes → Use Script DSL
└─ No → Either works, pick your preference

Porting existing AppleScript?
└─ Use Raw AppleScript (don't rewrite what works)
```

## The Script DSL

### What It Is

The Script DSL provides Elixir functions that generate AppleScript code:

```elixir
alias ExMacOSControl.Script

# Elixir code
script = Script.tell("Finder", [
  "activate",
  Script.cmd("open", "/Applications")
])

# Generates this AppleScript:
# tell application "Finder"
#   activate
#   open "/Applications"
# end tell
```

### When to Use the DSL

✅ **Simple Tell Blocks**

```elixir
# DSL: Clear and concise
Script.tell("Safari", ["activate"])

# vs Raw: More verbose
"""
tell application "Safari"
  activate
end tell
"""
```

✅ **Dynamic App Names or Values**

```elixir
# DSL: Natural Elixir variable interpolation
app_name = get_target_app()
path = get_target_path()

script = Script.tell(app_name, [
  Script.cmd("open", path)
])

# vs Raw: Manual string interpolation
"""
tell application "#{app_name}"
  open "#{escape(path)}"
end tell
"""
```

✅ **Building Scripts Programmatically**

```elixir
# DSL: Use Enum functions naturally
commands =
  files
  |> Enum.map(&"open #{&1}")
  |> Script.tell("Finder", _)

# vs Raw: Awkward string building
commands_str =
  files
  |> Enum.map(&"  open \"#{&1}\"")
  |> Enum.join("\n")

"""
tell application "Finder"
#{commands_str}
end tell
"""
```

✅ **Nested Tell Blocks**

```elixir
# DSL: Structured and readable
Script.tell("System Events", [
  Script.tell_obj("process", "Safari", [
    "set frontmost to true"
  ])
])

# vs Raw: More nesting to track
"""
tell application "System Events"
  tell process "Safari"
    set frontmost to true
  end tell
end tell
"""
```

### DSL Limitations

The DSL is **intentionally minimal**. It does NOT support:

- ❌ Control flow (`if`, `repeat`, `while`)
- ❌ Variables (`set x to ...`)
- ❌ Handlers (`on doSomething()`)
- ❌ Complex AppleScript features
- ❌ Full language coverage

**This is by design.** The DSL covers common patterns only.

## Raw AppleScript

### When to Use Raw AppleScript

✅ **Control Flow**

```applescript
tell application "Finder"
  set fileList to {}
  repeat with f in (get files of desktop)
    if name of f ends with ".pdf" then
      set end of fileList to name of f
    end if
  end repeat
  return fileList
end tell
```

**Why not DSL?** No support for `repeat`, `if`, or `set`.

✅ **Variables and State**

```applescript
tell application "Mail"
  set unreadCount to count of (messages of inbox whose read status is false)
  if unreadCount > 10 then
    return "You have " & unreadCount & " unread messages!"
  else
    return "All caught up"
  end if
end tell
```

**Why not DSL?** Needs `set` and `if`.

✅ **Handlers (Functions)**

```applescript
on processFile(filePath)
  tell application "Finder"
    return name of file filePath
  end tell
end processFile

return processFile("/path/to/file")
```

**Why not DSL?** No handler support.

✅ **Existing AppleScript**

If you already have working AppleScript, just use it:

```elixir
# Don't rewrite this into DSL - it works!
script = """
tell application "iTunes"
  set currentTrack to current track
  return name of currentTrack & " by " & artist of currentTrack
end tell
"""

ExMacOSControl.run_applescript(script)
```

✅ **Complex Application-Specific Logic**

Some apps have rich AppleScript dictionaries with complex object models:

```applescript
tell application "Photos"
  set albumList to albums
  repeat with anAlbum in albumList
    set photoCount to count of media items of anAlbum
    log name of anAlbum & ": " & photoCount & " photos"
  end repeat
end tell
```

**Why not DSL?** Too app-specific and complex.

## Side-by-Side Comparisons

### Example 1: Simple Activation

**DSL Approach:**

```elixir
alias ExMacOSControl.Script

script = Script.tell("Safari", ["activate"])
ExMacOSControl.run_applescript(script)
```

**Raw Approach:**

```elixir
ExMacOSControl.run_applescript("""
tell application "Safari"
  activate
end tell
""")
```

**Winner:** DSL - cleaner, less quotes

---

### Example 2: Dynamic Values

**DSL Approach:**

```elixir
app = "Finder"
folder = "/Applications"

script = Script.tell(app, [
  Script.cmd("open", folder)
])

ExMacOSControl.run_applescript(script)
```

**Raw Approach:**

```elixir
app = "Finder"
folder = "/Applications"

ExMacOSControl.run_applescript("""
tell application "#{app}"
  open "#{escape_applescript(folder)}"
end tell
""")

# Plus you need this helper:
defp escape_applescript(str) do
  String.replace(str, "\"", "\\\"")
end
```

**Winner:** DSL - automatic escaping, cleaner interpolation

---

### Example 3: Conditional Logic

**DSL Approach:**

```elixir
# Can't do it! DSL doesn't support if/else
```

**Raw Approach:**

```elixir
ExMacOSControl.run_applescript("""
tell application "Finder"
  set fileCount to count of files of desktop
  if fileCount > 10 then
    return "Too many files"
  else
    return "Desktop is tidy"
  end if
end tell
""")
```

**Winner:** Raw - DSL can't do this

---

### Example 4: Building Multiple Commands

**DSL Approach:**

```elixir
files = ["/file1.txt", "/file2.txt", "/file3.txt"]

commands =
  files
  |> Enum.map(&Script.cmd("open", &1))

script = Script.tell("TextEdit", commands)
ExMacOSControl.run_applescript(script)
```

**Raw Approach:**

```elixir
files = ["/file1.txt", "/file2.txt", "/file3.txt"]

commands =
  files
  |> Enum.map(&"  open \"#{escape(&1)}\"")
  |> Enum.join("\n")

ExMacOSControl.run_applescript("""
tell application "TextEdit"
#{commands}
end tell
""")
```

**Winner:** DSL - no manual escaping or indentation

---

### Example 5: Nested Tell Blocks

**DSL Approach:**

```elixir
script = Script.tell("System Events", [
  Script.tell_obj("process", "Safari", [
    "set frontmost to true",
    Script.cmd("click menu item", "New Tab", of: "menu 1 of menu bar item 1")
  ])
])
```

**Raw Approach:**

```elixir
script = """
tell application "System Events"
  tell process "Safari"
    set frontmost to true
    click menu item "New Tab" of menu 1 of menu bar item 1
  end tell
end tell
"""
```

**Winner:** Tie - both are readable

---

### Example 6: Complex Iteration

**DSL Approach:**

```elixir
# Can't do it! DSL doesn't support repeat loops
```

**Raw Approach:**

```elixir
ExMacOSControl.run_applescript("""
tell application "Mail"
  set unreadMessages to {}
  repeat with msg in (messages of inbox)
    if read status of msg is false then
      set end of unreadMessages to subject of msg
    end if
  end repeat
  return unreadMessages
end tell
""")
```

**Winner:** Raw - DSL can't do this

## Mixing Both Approaches

You can combine DSL and Raw for the best of both worlds:

### Pattern 1: DSL for Structure, Raw for Logic

```elixir
# Use DSL for the tell block structure
inner_logic = """
set fileCount to count of files
if fileCount > 100 then
  return "Too many files"
else
  return "OK"
end if
"""

script = Script.tell("Finder", [inner_logic])
ExMacOSControl.run_applescript(script)
```

### Pattern 2: Conditional DSL Building

```elixir
# Use Elixir logic to decide what AppleScript to build
commands =
  if should_activate? do
    ["activate"]
  else
    []
  end

commands = commands ++ [
  Script.cmd("open", path)
]

script = Script.tell(app_name, commands)
```

### Pattern 3: Multiple Scripts

```elixir
# Use DSL for simple operations
setup_script = Script.tell("Finder", ["activate"])
ExMacOSControl.run_applescript(setup_script)

# Use Raw for complex operations
complex_script = """
tell application "Finder"
  set results to {}
  repeat with f in files of desktop
    if size of f > 1000000 then
      set end of results to name of f
    end if
  end repeat
  return results
end tell
"""
{:ok, large_files} = ExMacOSControl.run_applescript(complex_script)
```

## Performance Considerations

### DSL Runtime Overhead

The DSL generates AppleScript strings at runtime:

```elixir
# This builds a string
script = Script.tell("Finder", ["activate"])  # ~microseconds

# Then executes it
ExMacOSControl.run_applescript(script)  # ~milliseconds to seconds
```

**The script building overhead is negligible** compared to osascript execution time.

### When Raw is Faster

If you're running the same script repeatedly, pre-build it:

```elixir
# ❌ Rebuilds DSL every time
def activate_finder do
  Script.tell("Finder", ["activate"])
  |> ExMacOSControl.run_applescript()
end

# ✅ Built once at compile time
@activate_script """
tell application "Finder"
  activate
end tell
"""

def activate_finder do
  ExMacOSControl.run_applescript(@activate_script)
end
```

**Difference:** Nanoseconds. Don't optimize prematurely.

## Best Practices

### 1. Start with DSL

Try the DSL first. If it doesn't fit, drop to raw:

```elixir
# Try DSL
script = Script.tell("Finder", [
  # Oops, I need an if statement
  # DSL can't do this
])

# Switch to raw
script = """
tell application "Finder"
  if (count of windows) > 0 then
    close windows
  end if
end tell
"""
```

### 2. Use DSL for Reusable Helpers

```elixir
defmodule AppleScriptHelpers do
  alias ExMacOSControl.Script

  def activate(app_name) do
    Script.tell(app_name, ["activate"])
  end

  def quit(app_name) do
    Script.tell(app_name, ["quit"])
  end

  def open_file(app_name, path) do
    Script.tell(app_name, [
      Script.cmd("open", path)
    ])
  end
end

# Usage
AppleScriptHelpers.activate("Safari")
|> ExMacOSControl.run_applescript()
```

### 3. Validate Raw AppleScript in Script Editor

Before using raw AppleScript in production:

1. Open **Script Editor.app**
2. Paste your AppleScript
3. Click **Compile** (⌘K)
4. Click **Run** (⌘R)
5. Fix any errors
6. Copy working script into Elixir

### 4. Document Why You Chose Raw

```elixir
# Using raw AppleScript because we need repeat loops
# DSL doesn't support control flow
@find_pdf_script """
tell application "Finder"
  set pdfFiles to {}
  repeat with f in (get files of desktop)
    if name of f ends with ".pdf" then
      set end of pdfFiles to name of f
    end if
  end repeat
  return pdfFiles
end tell
"""
```

### 5. Keep DSL Scripts Simple

If your DSL code gets complex, it's a sign to use raw:

```elixir
# 🤔 This is getting complex...
commands =
  data
  |> Enum.map(&transform/1)
  |> Enum.filter(&valid?/1)
  |> Enum.map(&Script.cmd("process", &1))
  |> Enum.chunk_every(10)
  |> Enum.map(fn chunk ->
    Script.tell("App", chunk)
  end)

# ✅ Better: Use raw AppleScript with built-in iteration
script = """
tell application "App"
  repeat with item in #{Enum.join(data, ",")}
    if item is valid then
      process item
    end if
  end repeat
end tell
"""
```

## Summary

### Use the DSL When:

- ✅ Building simple tell blocks
- ✅ Dynamic app names or values
- ✅ Generating scripts programmatically
- ✅ Want automatic quote escaping
- ✅ Prefer Elixir syntax

### Use Raw AppleScript When:

- ✅ Need control flow (if/while/repeat)
- ✅ Need variables
- ✅ Need handlers/functions
- ✅ Porting existing AppleScript
- ✅ Using complex app-specific features
- ✅ Following AppleScript tutorials

### Both Are Valid!

There's no wrong choice. Pick what feels natural for your use case. The DSL is a convenience, not a requirement.

## Examples by Use Case

### Use Case: Quick Prototyping

**Recommendation:** DSL

```elixir
# Fast iteration in IEx
iex> Script.tell("Finder", ["activate"]) |> ExMacOSControl.run_applescript()
```

### Use Case: Production Web Scraping

**Recommendation:** Raw (more complex logic needed)

```applescript
tell application "Safari"
  set results to {}
  repeat with w in windows
    repeat with t in tabs of w
      set end of results to URL of t
    end repeat
  end repeat
  return results
end tell
```

### Use Case: Simple App Launcher

**Recommendation:** DSL

```elixir
def launch(app_name) do
  Script.tell(app_name, ["activate"])
  |> ExMacOSControl.run_applescript()
end
```

### Use Case: Complex Mail Filtering

**Recommendation:** Raw

```applescript
tell application "Mail"
  set urgentMessages to {}
  repeat with msg in messages of inbox
    if subject of msg contains "[URGENT]" and read status of msg is false then
      set end of urgentMessages to {subject:subject of msg, sender:sender of msg}
    end if
  end repeat
  return urgentMessages
end tell
```

## Further Reading

- [Common Patterns](common_patterns.html) - See both approaches in action
- [Advanced Usage](advanced_usage.html) - Custom DSL extensions
- [Script Module Documentation](https://hexdocs.pm/ex_macos_control/ExMacOSControl.Script.html) - Full DSL API reference

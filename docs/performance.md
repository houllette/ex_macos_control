# Performance Guide

This guide provides best practices for optimizing performance and reliability when using ExMacOSControl for macOS automation.

## Overview

ExMacOSControl executes AppleScript, JXA, and Shortcuts via the `osascript` command-line tool. Understanding the performance characteristics of these operations can help you build more reliable and efficient automation.

## Common Bottlenecks

### 1. Script Execution Time

**Issue:** AppleScript and JXA execution can be slow, especially when interacting with applications or the UI.

**Causes:**
- Application responsiveness (apps may be busy)
- UI operations (finding windows, clicking buttons)
- System Events interactions
- Script complexity and loops

**Solutions:**
- Use appropriate timeouts for operations
- Minimize UI interactions where possible
- Prefer direct API calls over UI automation
- Break complex scripts into smaller operations

**Example:**
```elixir
# Instead of one large timeout for complex operations
{:ok, result} = ExMacOSControl.run_applescript(complex_script, timeout: 30_000)

# Break it down into smaller operations with shorter timeouts
{:ok, result1} = ExMacOSControl.run_applescript(script1, timeout: 5_000)
{:ok, result2} = ExMacOSControl.run_applescript(script2, timeout: 5_000)
{:ok, result3} = ExMacOSControl.run_applescript(script3, timeout: 5_000)
```

### 2. Application Launch Time

**Issue:** Scripts that launch or activate applications may take several seconds.

**Solution:** Use longer timeouts when launching applications (5-10 seconds):

```elixir
script = """
tell application "Safari"
  activate
  make new document
end tell
"""

{:ok, _} = ExMacOSControl.run_applescript(script, timeout: 10_000)
```

### 3. File System Operations

**Issue:** File operations (copying, moving, searching) can be slow for large files or directories.

**Solution:**
- Use native Elixir File module when possible
- Only use AppleScript for operations that require Finder integration
- Consider background tasks for large operations

```elixir
# Prefer Elixir's File module
File.cp!(source, destination)

# Only use Finder when you need Finder-specific features
ExMacOSControl.Finder.move_to_trash(file_path)
```

### 4. Repeated osascript Calls

**Issue:** Each call to `osascript` has overhead (process spawn, script compilation).

**Solution:** Combine operations into a single script when possible:

```elixir
# Less efficient - multiple osascript calls
{:ok, name} = ExMacOSControl.Finder.get_frontmost_window()
{:ok, bounds} = ExMacOSControl.Finder.get_window_bounds(name)
{:ok, position} = ExMacOSControl.Finder.get_window_position(name)

# More efficient - single script with multiple operations
script = """
tell application "Finder"
  set frontWindow to front window
  set windowInfo to {name of frontWindow, bounds of frontWindow, position of frontWindow}
  return windowInfo
end tell
"""
{:ok, result} = ExMacOSControl.run_applescript(script)
```

## Timeout Configuration

### Default Behavior

By default, ExMacOSControl operations have NO timeout. This means they will wait indefinitely for completion.

### When to Use Timeouts

**Always use timeouts for:**
- Production applications
- Operations that interact with external applications
- UI automation
- Network-dependent scripts
- Any operation that could hang

**Timeout not needed for:**
- Simple calculations or string operations
- Scripts you've tested extensively
- Operations with guaranteed fast completion

### Recommended Timeout Values

| Operation Type | Recommended Timeout |
|---------------|---------------------|
| Simple script (calculations, strings) | 1,000ms (1s) |
| Application queries (get window name) | 3,000ms (3s) |
| Application launch/activation | 10,000ms (10s) |
| UI automation (clicking, typing) | 5,000ms (5s) |
| File operations | 5,000-15,000ms (5-15s) |
| Complex multi-step operations | 15,000-30,000ms (15-30s) |

### Example Usage

```elixir
# Quick operation
{:ok, result} = ExMacOSControl.run_applescript(
  ~s(return "hello"),
  timeout: 1_000
)

# UI automation
{:ok, _} = ExMacOSControl.SystemEvents.click_button(
  "OK",
  "Safari",
  timeout: 5_000
)

# Complex operation
{:ok, data} = ExMacOSControl.run_applescript(
  complex_workflow_script,
  timeout: 30_000
)
```

## Retry Logic

### When to Use Retry

The `ExMacOSControl.Retry` module provides automatic retry functionality for transient failures.

**Use retry for:**
- Timeout errors that may succeed on subsequent attempts
- Operations that depend on application state
- Network-dependent operations within scripts
- UI automation affected by system responsiveness

**Do NOT use retry for:**
- Syntax errors (won't be fixed by retrying)
- Permission errors (user intervention required)
- Not found errors (resources won't appear)
- Logic errors in your scripts

### Retry Examples

```elixir
alias ExMacOSControl.Retry

# Basic retry with exponential backoff (default)
# Attempts: 1st immediately, 2nd after 200ms, 3rd after 400ms
{:ok, result} = Retry.with_retry(fn ->
  ExMacOSControl.Finder.get_frontmost_window()
end)

# Custom max attempts with linear backoff
# Attempts: 1st immediately, 2nd-5th after 1000ms each
{:ok, result} = Retry.with_retry(fn ->
  ExMacOSControl.SystemEvents.click_button("OK", "MyApp", timeout: 5_000)
end, max_attempts: 5, backoff: :linear)

# Combining timeout and retry
{:ok, windows} = Retry.with_retry(fn ->
  ExMacOSControl.run_applescript(
    list_all_windows_script,
    timeout: 10_000
  )
end, max_attempts: 3, backoff: :exponential)
```

### Backoff Strategies

**Exponential Backoff (default)**
- Doubles wait time between retries
- Formula: `2^attempt * 100ms`
- Best for: Operations that may need increasing time to succeed
- Wait times: 200ms, 400ms, 800ms, 1600ms, etc.

**Linear Backoff**
- Constant wait time between retries
- Wait time: 1000ms (1 second)
- Best for: Operations with consistent retry timing
- Wait times: 1000ms, 1000ms, 1000ms, etc.

```elixir
# Exponential: Good for gradual system recovery
Retry.with_retry(fn ->
  ExMacOSControl.run_applescript(script, timeout: 5_000)
end, backoff: :exponential)

# Linear: Good for operations with known fixed delay
Retry.with_retry(fn ->
  ExMacOSControl.run_applescript(script, timeout: 5_000)
end, backoff: :linear)
```

## Telemetry and Monitoring

ExMacOSControl emits telemetry events for all operations, allowing you to monitor performance and reliability.

### AppleScript Execution Events

**Events:**
- `[:ex_macos_control, :applescript, :start]` - Script execution begins
- `[:ex_macos_control, :applescript, :stop]` - Script execution succeeds
- `[:ex_macos_control, :applescript, :exception]` - Script execution fails

**Measurements:**
- `script_length` - Length of the script in bytes
- `duration` - Execution time in microseconds (stop/exception only)

**Metadata:**
- `command` - Command being executed ("osascript")
- `script` - First 100 characters of the script
- `timeout` - Configured timeout (or nil)
- `result_type` - `:success` or `:error`
- `output_length` - Length of output (success only)
- `error` - Error details (exception only)

### Retry Events

**Events:**
- `[:ex_macos_control, :retry, :start]` - Retry logic begins
- `[:ex_macos_control, :retry, :attempt]` - Each retry attempt
- `[:ex_macos_control, :retry, :sleep]` - Sleeping before retry
- `[:ex_macos_control, :retry, :stop]` - Retry succeeds
- `[:ex_macos_control, :retry, :error]` - All retries exhausted

**Metadata:**
- `attempt` - Current attempt number
- `max_attempts` - Maximum configured attempts
- `backoff` - Backoff strategy (`:exponential` or `:linear`)
- `sleep_time` - Time to sleep before next retry (sleep event only)
- `error` - Error that triggered retry

### Setting Up Telemetry

```elixir
# In your application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    # Attach telemetry handlers
    :telemetry.attach_many(
      "ex-macos-control-handler",
      [
        [:ex_macos_control, :applescript, :start],
        [:ex_macos_control, :applescript, :stop],
        [:ex_macos_control, :applescript, :exception],
        [:ex_macos_control, :retry, :start],
        [:ex_macos_control, :retry, :stop],
        [:ex_macos_control, :retry, :error]
      ],
      &handle_telemetry_event/4,
      nil
    )

    children = [
      # Your app's children
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp handle_telemetry_event(event, measurements, metadata, _config) do
    # Log or send to monitoring service
    Logger.info("Telemetry event: #{inspect(event)}")
    Logger.debug("Measurements: #{inspect(measurements)}")
    Logger.debug("Metadata: #{inspect(metadata)}")
  end
end
```

### Example: Tracking Slow Operations

```elixir
defmodule MyApp.TelemetryHandler do
  require Logger

  def handle_event([:ex_macos_control, :applescript, :stop], measurements, metadata, _) do
    duration_ms = measurements.duration / 1_000

    if duration_ms > 5_000 do
      Logger.warning("""
      Slow AppleScript execution detected:
      Duration: #{duration_ms}ms
      Script: #{metadata.script}
      Timeout: #{metadata.timeout}
      """)
    end
  end

  def handle_event([:ex_macos_control, :retry, :error], _measurements, metadata, _) do
    Logger.error("""
    Retry exhausted after #{metadata.max_attempts} attempts:
    Error: #{inspect(metadata.error)}
    """)
  end

  def handle_event(_, _, _, _), do: :ok
end

# Attach in your application.ex
:telemetry.attach_many(
  "slow-operations-tracker",
  [
    [:ex_macos_control, :applescript, :stop],
    [:ex_macos_control, :retry, :error]
  ],
  &MyApp.TelemetryHandler.handle_event/4,
  nil
)
```

## Benchmarking

### Simple Benchmarking

```elixir
defmodule MyApp.Benchmark do
  def measure(label, fun) do
    {time, result} = :timer.tc(fun)
    IO.puts("#{label}: #{time / 1_000}ms")
    result
  end
end

# Usage
MyApp.Benchmark.measure("Get Finder windows", fn ->
  ExMacOSControl.Finder.list_windows()
end)
# => "Get Finder windows: 234.5ms"
```

### Using Benchee

For more comprehensive benchmarking, use the [Benchee](https://github.com/bencheeorg/benchee) library:

```elixir
# In mix.exs
{:benchee, "~> 1.3", only: :dev}

# In a benchmark file
Benchee.run(%{
  "direct applescript" => fn ->
    ExMacOSControl.run_applescript(~s(tell application "Finder" to return name of every window))
  end,
  "via Finder module" => fn ->
    ExMacOSControl.Finder.list_windows()
  end,
  "with timeout" => fn ->
    ExMacOSControl.run_applescript(
      ~s(tell application "Finder" to return name of every window),
      timeout: 5_000
    )
  end
})
```

## Best Practices Summary

1. **Use timeouts** in production for all operations
2. **Choose appropriate timeout values** based on operation type
3. **Use retry logic** for transient failures (timeouts)
4. **Monitor with telemetry** to identify slow operations
5. **Combine operations** into single scripts when possible
6. **Prefer native Elixir** for non-automation tasks
7. **Break down complex scripts** into smaller operations
8. **Test timeout values** in your specific environment
9. **Use exponential backoff** for gradual recovery scenarios
10. **Use linear backoff** for known fixed delays

## Troubleshooting Performance Issues

### Operation Taking Too Long

1. Check if timeout is appropriate for the operation
2. Verify the application is responsive
3. Simplify the script if possible
4. Consider breaking into smaller operations
5. Check telemetry data for actual execution time

### Frequent Timeouts

1. Increase timeout value
2. Add retry logic with exponential backoff
3. Check system resources (CPU, memory)
4. Verify the application is not hanging
5. Consider if the operation is too complex

### Retry Not Working

1. Verify error type is `:timeout`
2. Check max_attempts is sufficient
3. Consider increasing timeout before retry
4. Review telemetry events for retry attempts
5. Ensure the operation can succeed eventually

## Further Resources

- [AppleScript Language Guide](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/)
- [JXA Documentation](https://developer.apple.com/library/archive/releasenotes/InterapplicationCommunication/RN-JavaScriptForAutomation/)
- [System Events Scripting](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/)
- [Telemetry Documentation](https://hexdocs.pm/telemetry/)

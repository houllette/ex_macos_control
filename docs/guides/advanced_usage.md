# Advanced Usage

This guide covers advanced topics for power users: performance optimization, telemetry integration, retry strategies, custom adapters, and the Objective-C bridge.

## Table of Contents

1. [Performance Optimization](#performance-optimization)
2. [Telemetry Integration](#telemetry-integration)
3. [Retry Strategies](#retry-strategies)
4. [Custom Adapters](#custom-adapters)
5. [Objective-C Bridge (JXA)](#objective-c-bridge-jxa)

---

## Performance Optimization

### Understanding Execution Time

macOS automation has three performance components:

```elixir
# 1. Script Building (~microseconds) - negligible
script = Script.tell("Finder", ["activate"])

# 2. osascript Launch (~50-200ms) - fixed overhead
# 3. Actual Script Execution (varies) - your bottleneck
ExMacOSControl.run_applescript(script)  # Total: component 2 + 3
```

**Key Insight:** The osascript launch overhead is fixed. Optimize script execution, not script building.

### Timeout Tuning

Default timeouts vary by operation. Tune them based on your needs:

```elixir
# Default timeout (usually 30 seconds)
{:ok, result} = ExMacOSControl.run_applescript(script)

# Quick operations - fail fast
{:ok, result} = ExMacOSControl.run_applescript(script, timeout: 5_000)

# Long operations - be patient
{:ok, result} = ExMacOSControl.run_applescript(script, timeout: 120_000)

# Infinite timeout (use with caution!)
{:ok, result} = ExMacOSControl.run_applescript(script, timeout: :infinity)
```

**Recommendations:**

- **UI Automation**: 10-30 seconds (depends on app responsiveness)
- **File Operations**: 5-10 seconds
- **Network Operations**: 30-60 seconds
- **Batch Processing**: 60-300 seconds

### Batch Operations

Group multiple operations into a single AppleScript:

```elixir
# ❌ Slow: Multiple osascript calls
for file <- files do
  script = Script.tell("Finder", [Script.cmd("open", file)])
  ExMacOSControl.run_applescript(script)
  # Each call: ~50-200ms overhead
end

# ✅ Fast: Single osascript call
commands = Enum.map(files, &Script.cmd("open", &1))
script = Script.tell("Finder", commands)
ExMacOSControl.run_applescript(script)
# One call: ~50-200ms overhead total
```

**Performance Gain:** ~10x faster for 10 files

### Caching Compiled Scripts

Pre-compile static scripts at module load time:

```elixir
defmodule FastAutomation do
  @activate_finder Script.tell("Finder", ["activate"])
  @activate_safari Script.tell("Safari", ["activate"])

  def activate_finder do
    ExMacOSControl.run_applescript(@activate_finder)
  end

  def activate_safari do
    ExMacOSControl.run_applescript(@activate_safari)
  end
end
```

**Benefit:** Eliminates script building time (though it's already negligible)

### Concurrent Execution

Run independent operations in parallel:

```elixir
# ❌ Sequential: 6 seconds total
ExMacOSControl.run_applescript(script1)  # 3 seconds
ExMacOSControl.run_applescript(script2)  # 3 seconds

# ✅ Parallel: 3 seconds total
task1 = Task.async(fn -> ExMacOSControl.run_applescript(script1) end)
task2 = Task.async(fn -> ExMacOSControl.run_applescript(script2) end)

{:ok, result1} = Task.await(task1, :infinity)
{:ok, result2} = Task.await(task2, :infinity)
```

**Warning:** Don't parallelize operations on the same app - they may conflict.

### Reducing Wait Times

Use polling instead of fixed sleeps:

```elixir
# ❌ Always waits 5 seconds
Safari.open_url(url)
Process.sleep(5000)
Safari.execute_javascript("document.title")

# ✅ Polls until ready (usually faster)
Safari.open_url(url)
wait_until_loaded()
Safari.execute_javascript("document.title")

defp wait_until_loaded(max_attempts \\ 50) do
  Enum.reduce_while(1..max_attempts, nil, fn attempt, _ ->
    case Safari.execute_javascript("document.readyState") do
      {:ok, "complete"} -> {:halt, :ok}
      _ ->
        Process.sleep(100)
        {:cont, nil}
    end
  end)
end
```

---

## Telemetry Integration

ExMacOSControl emits `:telemetry` events for observability.

### Available Events

```elixir
# AppleScript execution lifecycle
[:ex_macos_control, :applescript, :start]     # When execution begins
[:ex_macos_control, :applescript, :stop]      # When execution succeeds
[:ex_macos_control, :applescript, :exception] # When execution fails

# Retry logic lifecycle
[:ex_macos_control, :retry, :start]    # Retry begins
[:ex_macos_control, :retry, :attempt]  # Each retry attempt
[:ex_macos_control, :retry, :stop]     # Retry succeeds
[:ex_macos_control, :retry, :error]    # All retries exhausted
```

### Basic Telemetry Setup

```elixir
# In your application.ex
def start(_type, _args) do
  :telemetry.attach_many(
    "ex-macos-control-telemetry",
    [
      [:ex_macos_control, :applescript, :start],
      [:ex_macos_control, :applescript, :stop],
      [:ex_macos_control, :applescript, :exception]
    ],
    &MyApp.Telemetry.handle_event/4,
    nil
  )

  # ... rest of your supervision tree
end
```

### Logging Handler

```elixir
defmodule MyApp.Telemetry do
  require Logger

  def handle_event([:ex_macos_control, :applescript, :start], _measurements, metadata, _config) do
    Logger.debug("Executing AppleScript: #{String.slice(metadata.script, 0, 100)}...")
  end

  def handle_event([:ex_macos_control, :applescript, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.info("AppleScript completed in #{duration_ms}ms")
  end

  def handle_event([:ex_macos_control, :applescript, :exception], _measurements, metadata, _config) do
    Logger.error("AppleScript failed: #{inspect(metadata.error)}")
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
```

### Performance Monitoring

Track slow operations:

```elixir
defmodule MyApp.PerformanceMonitor do
  require Logger

  def handle_event([:ex_macos_control, :applescript, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    if duration_ms > 5_000 do
      Logger.warning("""
      Slow AppleScript detected!
      Duration: #{duration_ms}ms
      Script: #{String.slice(metadata.script, 0, 200)}
      Timeout: #{metadata.timeout}ms
      """)
    end
  end

  def handle_event(_, _, _, _), do: :ok
end
```

### Metrics Collection

Integrate with your metrics system:

```elixir
defmodule MyApp.Metrics do
  # Using Telemetry.Metrics (example)
  def metrics do
    [
      # Count AppleScript executions
      Telemetry.Metrics.counter("ex_macos_control.applescript.count",
        event_name: [:ex_macos_control, :applescript, :stop]
      ),

      # Track execution duration
      Telemetry.Metrics.distribution("ex_macos_control.applescript.duration",
        event_name: [:ex_macos_control, :applescript, :stop],
        measurement: :duration,
        unit: {:native, :millisecond}
      ),

      # Count failures
      Telemetry.Metrics.counter("ex_macos_control.applescript.errors",
        event_name: [:ex_macos_control, :applescript, :exception]
      ),

      # Track retry attempts
      Telemetry.Metrics.sum("ex_macos_control.retry.total_attempts",
        event_name: [:ex_macos_control, :retry, :attempt],
        measurement: :attempt
      )
    ]
  end
end
```

### Event Metadata Reference

**AppleScript Events:**

```elixir
# :start event metadata
%{
  command: "osascript",
  script: "tell application...",  # Full script
  timeout: 30_000
}

# :stop event measurements & metadata
measurements: %{
  duration: 1_234_567,  # Native time units
  script_length: 156    # Character count
}
metadata: %{
  command: "osascript",
  script: "tell application...",
  timeout: 30_000,
  result_type: :ok,
  output_length: 42
}

# :exception event metadata
%{
  command: "osascript",
  script: "tell application...",
  timeout: 30_000,
  error: %ExMacOSControl.Error{type: :timeout, ...}
}
```

**Retry Events:**

```elixir
# :attempt event metadata
%{
  attempt: 2,           # Current attempt (1-indexed)
  max_attempts: 3,
  backoff: :exponential,
  sleep_time: 400       # ms slept before this attempt
}
```

---

## Retry Strategies

### Built-in Retry

ExMacOSControl includes automatic retry for timeout errors:

```elixir
alias ExMacOSControl.Retry

# Default: 3 attempts, exponential backoff
{:ok, result} = Retry.with_retry(fn ->
  ExMacOSControl.Safari.execute_javascript("document.title")
end)
```

### Backoff Strategies

**Exponential Backoff** (default):

```elixir
# Retry delays: 200ms, 400ms, 800ms, 1600ms...
# Formula: 2^attempt * 100ms
Retry.with_retry(fn ->
  operation()
end, backoff: :exponential, max_attempts: 5)
```

**Linear Backoff:**

```elixir
# Retry delays: 1000ms, 1000ms, 1000ms...
Retry.with_retry(fn ->
  operation()
end, backoff: :linear, max_attempts: 5)
```

### When to Retry

✅ **Retry timeout errors** - may succeed on subsequent attempts
✅ **UI automation** - apps may be busy
✅ **Network-dependent operations** - transient failures

❌ **Don't retry syntax errors** - they won't fix themselves
❌ **Don't retry permission errors** - user intervention required
❌ **Don't retry not found errors** - resource still won't exist

### Custom Retry Logic

Build your own retry wrapper:

```elixir
defmodule CustomRetry do
  require Logger

  def with_custom_retry(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    delay = Keyword.get(opts, :delay, 1000)
    retry_on = Keyword.get(opts, :retry_on, [:timeout])

    do_retry(fun, 1, max_attempts, delay, retry_on)
  end

  defp do_retry(fun, attempt, max_attempts, delay, retry_on) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, %{type: type}} = error when attempt < max_attempts ->
        if type in retry_on do
          Logger.warn("Attempt #{attempt} failed with #{type}, retrying in #{delay}ms...")
          Process.sleep(delay)
          do_retry(fun, attempt + 1, max_attempts, delay, retry_on)
        else
          Logger.error("Non-retryable error: #{type}")
          error
        end

      error ->
        Logger.error("All #{max_attempts} attempts failed")
        error
    end
  end
end

# Usage: Retry on :timeout and :execution_error
CustomRetry.with_custom_retry(fn ->
  Safari.open_url(url)
end, max_attempts: 5, delay: 2000, retry_on: [:timeout, :execution_error])
```

---

## Custom Adapters

The adapter pattern allows you to mock, wrap, or replace the default osascript implementation.

### Why Custom Adapters?

- **Testing**: Mock macOS automation in tests
- **Logging**: Add detailed logging around all operations
- **Caching**: Cache script results
- **Rate Limiting**: Prevent overwhelming macOS
- **Alternative Backends**: Use different execution methods

### Creating a Custom Adapter

```elixir
defmodule MyApp.LoggingAdapter do
  @behaviour ExMacOSControl.Adapter
  require Logger

  @impl true
  def run_applescript(script, opts \\ []) do
    Logger.info("Running AppleScript: #{String.slice(script, 0, 100)}...")
    start_time = System.monotonic_time()

    result = ExMacOSControl.OSAScriptAdapter.run_applescript(script, opts)

    duration = System.convert_time_unit(
      System.monotonic_time() - start_time,
      :native,
      :millisecond
    )

    Logger.info("Completed in #{duration}ms: #{inspect(result)}")
    result
  end

  @impl true
  def run_javascript(script, opts \\ []) do
    Logger.info("Running JavaScript: #{String.slice(script, 0, 100)}...")
    ExMacOSControl.OSAScriptAdapter.run_javascript(script, opts)
  end
end
```

### Using a Custom Adapter

Configure in `config.exs`:

```elixir
# config/config.exs
config :ex_macos_control, :adapter, MyApp.LoggingAdapter

# Or for testing only
# config/test.exs
config :ex_macos_control, :adapter, MyApp.MockAdapter
```

### Rate-Limiting Adapter

Prevent overwhelming macOS with too many rapid operations:

```elixir
defmodule MyApp.RateLimitedAdapter do
  @behaviour ExMacOSControl.Adapter
  use GenServer

  # Start the GenServer
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Adapter implementation
  @impl true
  def run_applescript(script, opts \\ []) do
    GenServer.call(__MODULE__, {:run_applescript, script, opts}, :infinity)
  end

  @impl true
  def run_javascript(script, opts \\ []) do
    GenServer.call(__MODULE__, {:run_javascript, script, opts}, :infinity)
  end

  # GenServer callbacks
  @impl true
  def init(_) do
    {:ok, %{last_execution: 0, min_interval: 100}}  # 100ms between calls
  end

  @impl true
  def handle_call({:run_applescript, script, opts}, _from, state) do
    state = enforce_rate_limit(state)
    result = ExMacOSControl.OSAScriptAdapter.run_applescript(script, opts)
    {:reply, result, %{state | last_execution: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_call({:run_javascript, script, opts}, _from, state) do
    state = enforce_rate_limit(state)
    result = ExMacOSControl.OSAScriptAdapter.run_javascript(script, opts)
    {:reply, result, %{state | last_execution: System.monotonic_time(:millisecond)}}
  end

  defp enforce_rate_limit(state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_execution

    if elapsed < state.min_interval do
      Process.sleep(state.min_interval - elapsed)
    end

    state
  end
end
```

---

## Objective-C Bridge (JXA)

JavaScript for Automation (JXA) provides access to Objective-C APIs via the ObjC bridge.

### Basic ObjC Bridge Usage

```elixir
script = """
ObjC.import('Foundation')

// Create NSString
var str = $.NSString.alloc.initWithUTF8String('Hello from ObjC!')
str.description.js
"""

{:ok, result} = ExMacOSControl.run_javascript(script)
# => {:ok, "Hello from ObjC!"}
```

### Common Patterns

**Working with NSFileManager:**

```elixir
script = """
ObjC.import('Foundation')

var fileManager = $.NSFileManager.defaultManager
var homePath = fileManager.homeDirectoryForCurrentUser.path.js
homePath
"""

{:ok, home} = ExMacOSControl.run_javascript(script)
# => {:ok, "/Users/username"}
```

**Working with NSWorkspace:**

```elixir
script = """
ObjC.import('AppKit')

var workspace = $.NSWorkspace.sharedWorkspace
var apps = workspace.runningApplications.js

apps.map(app => app.localizedName.js)
"""

{:ok, apps} = ExMacOSControl.run_javascript(script)
# => {:ok, ["Finder", "Safari", "Terminal", ...]}
```

**Working with Notifications:**

```elixir
script = """
ObjC.import('Foundation')

var center = $.NSNotificationCenter.defaultCenter

center.postNotificationNameObject('MyCustomNotification', 'SomeData')
'Notification sent'
"""

ExMacOSControl.run_javascript(script)
```

### ObjC vs AppleScript

**Use ObjC When:**
- Accessing low-level macOS APIs
- Need Foundation/AppKit classes
- Working with C APIs
- Need better performance for data processing

**Use AppleScript When:**
- Controlling applications
- UI automation
- Better app-specific support
- Following existing examples

### Advanced: Calling Swift/ObjC from JXA

You can bridge to custom frameworks:

```elixir
script = """
ObjC.import('Foundation')
ObjC.import('MyCustomFramework')  // Your custom framework

var myObject = $.MyCustomClass.alloc.init
myObject.doSomethingWith('data')
"""
```

### Type Conversion Reference

| JavaScript | Objective-C | Note |
|------------|-------------|------|
| `"string"` | `NSString` | Automatic |
| `123` | `NSNumber` | Automatic |
| `true/false` | `NSNumber` | Automatic |
| `[]` | `NSArray` | Automatic |
| `{}` | `NSDictionary` | Automatic |
| `.js` suffix | Unwrap to JS | Manual |

**Example:**

```javascript
// ObjC NSString to JS string
var nsString = $.NSString.alloc.initWithUTF8String('hello')
var jsString = nsString.js  // Convert to JavaScript string

// JS array to ObjC NSArray (automatic)
var jsArray = [1, 2, 3]
$.NSArray.arrayWithArray(jsArray)
```

---

## Best Practices

### Performance

1. **Batch operations** into single scripts
2. **Use appropriate timeouts** - not too short, not too long
3. **Run independent operations in parallel**
4. **Poll instead of fixed waits** when possible

### Telemetry

1. **Monitor slow operations** (> 5 seconds)
2. **Track failure rates** by error type
3. **Alert on spikes** in execution time
4. **Log retry attempts** for debugging

### Retry

1. **Only retry transient errors** (timeouts)
2. **Use exponential backoff** for most cases
3. **Limit max attempts** (3-5 is usually enough)
4. **Log retry attempts** for visibility

### Adapters

1. **Keep adapters thin** - delegate to default adapter
2. **Test custom adapters** thoroughly
3. **Document adapter behavior** clearly
4. **Consider rate limiting** in production

### ObjC Bridge

1. **Prefer AppleScript** for app control
2. **Use ObjC** for low-level APIs only
3. **Test extensively** - ObjC errors can crash scripts
4. **Document type conversions** in comments

---

## Further Reading

- [Performance Guide](../performance.html) - Detailed performance tuning
- [Common Patterns](common_patterns.html) - Real-world examples
- [Telemetry Documentation](https://hexdocs.pm/telemetry) - Official telemetry docs
- [JXA Release Notes](https://developer.apple.com/library/archive/releasenotes/InterapplicationCommunication/RN-JavaScriptForAutomation/) - Apple's JXA reference

# Common Automation Patterns

This guide shows real-world automation patterns using ExMacOSControl. Each pattern includes complete, copy-paste-ready code with error handling and best practices.

## Table of Contents

1. [Process Management Pattern](#process-management-pattern)
2. [Browser Automation Pattern](#browser-automation-pattern)
3. [Email Notification Pattern](#email-notification-pattern)
4. [Multi-App Workflow Pattern](#multi-app-workflow-pattern)
5. [Error Handling Pattern](#error-handling-pattern)
6. [Background Job Pattern](#background-job-pattern)
7. [Testing Pattern](#testing-pattern)

---

## Process Management Pattern

**Use Case:** Ensure an application is running before automating it

### Basic Pattern

```elixir
defmodule ProcessManager do
  alias ExMacOSControl.SystemEvents

  @doc "Ensures app is running, launches if needed"
  def ensure_running(app_name) do
    case SystemEvents.process_exists?(app_name) do
      {:ok, true} ->
        {:ok, :already_running}

      {:ok, false} ->
        SystemEvents.launch_application(app_name)
        Process.sleep(1000)
        {:ok, :launched}

      error ->
        error
    end
  end

  @doc "Safe quit - only quits if app is running"
  def safe_quit(app_name) do
    case SystemEvents.process_exists?(app_name) do
      {:ok, true} ->
        SystemEvents.quit_application(app_name)

      {:ok, false} ->
        {:ok, :not_running}

      error ->
        error
    end
  end
end

# Usage
ProcessManager.ensure_running("Safari")
# Do work...
ProcessManager.safe_quit("Safari")
```

### Advanced: Restart Pattern

```elixir
defmodule ProcessManager do
  alias ExMacOSControl.SystemEvents

  def restart(app_name, wait_ms \\ 2000) do
    with :ok <- safe_quit(app_name),
         :ok <- Process.sleep(wait_ms),
         :ok <- SystemEvents.launch_application(app_name),
         :ok <- Process.sleep(wait_ms) do
      {:ok, :restarted}
    end
  end

  def safe_quit(app_name) do
    case SystemEvents.process_exists?(app_name) do
      {:ok, true} -> SystemEvents.quit_application(app_name)
      {:ok, false} -> :ok
      error -> error
    end
  end
end

# Usage: Restart Safari to clear state
ProcessManager.restart("Safari", 2000)
```

---

## Browser Automation Pattern

**Use Case:** Scrape data from websites, automate web testing

### Pattern: Navigate → Wait → Extract

```elixir
defmodule BrowserAutomation do
  alias ExMacOSControl.{Safari, Retry}
  require Logger

  def scrape_price(url, selector, opts \\ []) do
    wait_time = Keyword.get(opts, :wait, 2000)
    max_attempts = Keyword.get(opts, :retries, 3)

    Retry.with_retry(fn ->
      with :ok <- Safari.open_url(url),
           :ok <- Process.sleep(wait_time),
           {:ok, price} <- extract_text(selector) do
        {:ok, String.trim(price)}
      end
    end, max_attempts: max_attempts, backoff: :exponential)
  end

  defp extract_text(selector) do
    Safari.execute_javascript("""
      (function() {
        var element = document.querySelector('#{escape_js(selector)}');
        return element ? element.textContent : null;
      })()
    """)
  end

  defp escape_js(string) do
    String.replace(string, "'", "\\'")
  end
end

# Usage
{:ok, price} = BrowserAutomation.scrape_price(
  "https://example.com/product",
  ".price",
  wait: 3000,
  retries: 5
)
IO.puts("Current price: #{price}")
```

### Pattern: Multi-Tab Management

```elixir
defmodule MultiTabScraper do
  alias ExMacOSControl.Safari

  def scrape_multiple_urls(urls) do
    # Open all URLs in tabs
    Enum.each(urls, fn url ->
      Safari.open_url(url)
      Process.sleep(500)  # Avoid overwhelming Safari
    end)

    # Wait for all pages to load
    Process.sleep(3000)

    # Get all tab URLs to verify
    {:ok, open_tabs} = Safari.list_tabs()
    Logger.info("Opened #{length(open_tabs)} tabs")

    # Extract data from each tab
    results =
      urls
      |> Enum.with_index(1)
      |> Enum.map(fn {url, index} ->
        # Focus tab by closing tabs until we reach it
        # (Note: Better approach is to use AppleScript to switch tabs)
        extract_from_tab(index)
      end)

    {:ok, results}
  end

  defp extract_from_tab(index) do
    # Close tabs before this one to focus it
    for i <- 1..(index - 1) do
      Safari.close_tab(1)
      Process.sleep(200)
    end

    Safari.execute_javascript("document.title")
  end
end
```

### Pattern: Login and Navigate

```elixir
defmodule LoginAutomation do
  alias ExMacOSControl.Safari

  def login_and_navigate(login_url, username, password, target_url) do
    with :ok <- Safari.open_url(login_url),
         :ok <- Process.sleep(2000),
         :ok <- fill_login_form(username, password),
         :ok <- submit_form(),
         :ok <- Process.sleep(3000),  # Wait for login redirect
         :ok <- Safari.open_url(target_url),
         :ok <- Process.sleep(2000) do
      {:ok, :logged_in}
    end
  end

  defp fill_login_form(username, password) do
    Safari.execute_javascript("""
      document.querySelector('#username').value = '#{escape_js(username)}';
      document.querySelector('#password').value = '#{escape_js(password)}';
    """)
  end

  defp submit_form do
    Safari.execute_javascript("""
      document.querySelector('form').submit();
    """)
  end

  defp escape_js(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
  end
end
```

---

## Email Notification Pattern

**Use Case:** Send email notifications based on conditions

### Basic Notification

```elixir
defmodule EmailNotifier do
  alias ExMacOSControl.Mail

  def send_alert(condition_met?, message) when condition_met? do
    Mail.send_email(
      to: "admin@example.com",
      subject: "Alert: Condition Met",
      body: message
    )
  end

  def send_alert(_condition, _message), do: {:ok, :no_alert_needed}
end

# Usage
price = get_stock_price("AAPL")
EmailNotifier.send_alert(price < 150, "AAPL dropped below $150! Current: $#{price}")
```

### Daily Digest Pattern

```elixir
defmodule DailyDigest do
  alias ExMacOSControl.Mail

  def send_daily_summary do
    stats = collect_daily_stats()

    body = """
    Daily Summary for #{Date.utc_today()}

    Tasks Completed: #{stats.tasks_completed}
    New Signups: #{stats.signups}
    Revenue: $#{stats.revenue}

    Top Issues:
    #{format_issues(stats.issues)}

    —
    Automated by ExMacOSControl
    """

    Mail.send_email(
      to: "team@example.com",
      subject: "Daily Summary - #{Date.utc_today()}",
      body: body,
      cc: ["manager@example.com"]
    )
  end

  defp collect_daily_stats do
    # Your data collection logic
    %{
      tasks_completed: 42,
      signups: 15,
      revenue: 1250.00,
      issues: ["Database slow", "API timeout in prod"]
    }
  end

  defp format_issues(issues) do
    issues
    |> Enum.with_index(1)
    |> Enum.map(fn {issue, i} -> "#{i}. #{issue}" end)
    |> Enum.join("\n")
  end
end

# Schedule with Quantum or similar
# config.exs:
# config :my_app, MyApp.Scheduler,
#   jobs: [
#     {"0 9 * * *", {DailyDigest, :send_daily_summary, []}}  # 9 AM daily
#   ]
```

### Conditional Notification with Retry

```elixir
defmodule SmartNotifier do
  alias ExMacOSControl.{Mail, Retry}
  require Logger

  def notify_if_needed(check_function, opts \\ []) do
    recipient = Keyword.fetch!(opts, :to)
    subject = Keyword.get(opts, :subject, "Notification")

    case check_function.() do
      {:alert, message} ->
        send_with_retry(recipient, subject, message)

      :ok ->
        Logger.info("No notification needed")
        {:ok, :no_alert}
    end
  end

  defp send_with_retry(recipient, subject, body) do
    Retry.with_retry(fn ->
      Mail.send_email(
        to: recipient,
        subject: subject,
        body: body
      )
    end, max_attempts: 3, backoff: :linear)
  end
end

# Usage
SmartNotifier.notify_if_needed(
  fn ->
    disk_usage = get_disk_usage()
    if disk_usage > 0.9 do
      {:alert, "Disk usage at #{disk_usage * 100}%!"}
    else
      :ok
    end
  end,
  to: "ops@example.com",
  subject: "Disk Usage Alert"
)
```

---

## Multi-App Workflow Pattern

**Use Case:** Combine multiple apps to create workflows

### Pattern: Finder → Process → Mail

```elixir
defmodule FileProcessor do
  alias ExMacOSControl.{Finder, Mail}
  require Logger

  @doc "Process selected files in Finder and email report"
  def process_selected_and_notify do
    with {:ok, files} <- Finder.get_selection(),
         :ok <- validate_selection(files),
         {:ok, results} <- process_files(files),
         :ok <- send_report(results) do
      Logger.info("Processed #{length(files)} files and sent report")
      {:ok, results}
    end
  end

  defp validate_selection([]), do: {:error, "No files selected"}
  defp validate_selection(files), do: :ok

  defp process_files(files) do
    results =
      files
      |> Enum.map(&process_file/1)
      |> Enum.filter(&match?({:ok, _}, &1))

    {:ok, results}
  end

  defp process_file(path) do
    # Your processing logic
    case File.read(path) do
      {:ok, content} ->
        size = byte_size(content)
        {:ok, %{path: path, size: size}}

      error ->
        Logger.warn("Failed to process #{path}: #{inspect(error)}")
        error
    end
  end

  defp send_report(results) do
    body = """
    File Processing Report

    Processed #{length(results)} files:

    #{format_results(results)}

    —
    Automated by ExMacOSControl
    """

    Mail.send_email(
      to: "me@example.com",
      subject: "File Processing Complete",
      body: body
    )
  end

  defp format_results(results) do
    results
    |> Enum.map(fn {:ok, %{path: path, size: size}} ->
      "- #{Path.basename(path)} (#{format_bytes(size)})"
    end)
    |> Enum.join("\n")
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"
  defp format_bytes(bytes), do: "#{div(bytes, 1024 * 1024)} MB"
end
```

### Pattern: Safari → Extract → Messages

```elixir
defmodule WebToSMS do
  alias ExMacOSControl.{Safari, Messages, Retry}

  def check_and_notify(url, selector, phone_number, threshold) do
    with {:ok, value} <- scrape_value(url, selector),
         {:ok, number} <- parse_number(value),
         true <- number > threshold do
      Messages.send_message(
        phone_number,
        "Alert: Value is #{number} (threshold: #{threshold})"
      )
    else
      false ->
        {:ok, :below_threshold}

      error ->
        error
    end
  end

  defp scrape_value(url, selector) do
    Retry.with_retry(fn ->
      with :ok <- Safari.open_url(url),
           :ok <- Process.sleep(2000),
           {:ok, text} <- Safari.execute_javascript("""
             document.querySelector('#{selector}').textContent
           """) do
        {:ok, String.trim(text)}
      end
    end, max_attempts: 3)
  end

  defp parse_number(string) do
    case Float.parse(String.replace(string, ~r/[^0-9.]/, "")) do
      {number, _} -> {:ok, number}
      :error -> {:error, :invalid_number}
    end
  end
end

# Usage: Monitor stock price and SMS if it hits target
WebToSMS.check_and_notify(
  "https://example.com/stock/AAPL",
  ".price",
  "+1234567890",
  150.00
)
```

---

## Error Handling Pattern

**Use Case:** Robust automation with graceful degradation

### Comprehensive Error Handling

```elixir
defmodule RobustAutomation do
  alias ExMacOSControl.{Safari, Permissions, Retry}
  require Logger

  def run(url) do
    with :ok <- check_permissions(),
         :ok <- ensure_safari_running(),
         {:ok, data} <- scrape_with_retry(url) do
      process_data(data)
    else
      {:error, :permission_denied} ->
        handle_permission_error()

      {:error, :timeout} ->
        handle_timeout_error()

      {:error, %{type: :not_found}} ->
        handle_not_found_error()

      error ->
        handle_unknown_error(error)
    end
  end

  defp check_permissions do
    case Permissions.check_automation("Safari") do
      {:ok, :granted} ->
        :ok

      {:ok, :not_granted} ->
        Logger.error("Safari automation permission required")
        Permissions.show_automation_help("Safari")
        {:error, :permission_denied}

      error ->
        error
    end
  end

  defp ensure_safari_running do
    case ExMacOSControl.SystemEvents.process_exists?("Safari") do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        Logger.info("Launching Safari...")
        ExMacOSControl.SystemEvents.launch_application("Safari")
        Process.sleep(2000)
        :ok

      error ->
        error
    end
  end

  defp scrape_with_retry(url) do
    Retry.with_retry(fn ->
      Safari.open_url(url)
      Process.sleep(2000)
      Safari.execute_javascript("document.title")
    end, max_attempts: 3, backoff: :exponential)
  end

  defp handle_permission_error do
    Logger.error("Permission denied - cannot continue")
    {:error, :permission_denied}
  end

  defp handle_timeout_error do
    Logger.warn("Operation timed out after retries")
    {:error, :timeout}
  end

  defp handle_not_found_error do
    Logger.error("Resource not found")
    {:error, :not_found}
  end

  defp handle_unknown_error(error) do
    Logger.error("Unexpected error: #{inspect(error)}")
    {:error, :unknown}
  end

  defp process_data(data) do
    Logger.info("Successfully scraped: #{data}")
    {:ok, data}
  end
end
```

---

## Background Job Pattern

**Use Case:** Scheduled automation tasks

### GenServer-Based Automation

```elixir
defmodule AutomationWorker do
  use GenServer
  alias ExMacOSControl.{Safari, Mail}
  require Logger

  @check_interval :timer.minutes(15)

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def check_now do
    GenServer.call(__MODULE__, :check_now)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    url = Keyword.fetch!(opts, :url)
    selector = Keyword.fetch!(opts, :selector)
    threshold = Keyword.fetch!(opts, :threshold)
    email = Keyword.fetch!(opts, :email)

    schedule_check()

    {:ok,
     %{
       url: url,
       selector: selector,
       threshold: threshold,
       email: email,
       last_value: nil,
       last_check: nil,
       checks_performed: 0
     }}
  end

  @impl true
  def handle_call(:check_now, _from, state) do
    {result, new_state} = perform_check(state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:check, state) do
    {_result, new_state} = perform_check(state)
    schedule_check()
    {:noreply, new_state}
  end

  # Private Functions

  defp perform_check(state) do
    Logger.info("Performing check...")

    result =
      with :ok <- Safari.open_url(state.url),
           :ok <- Process.sleep(2000),
           {:ok, text} <- Safari.execute_javascript("""
             document.querySelector('#{state.selector}').textContent
           """),
           {:ok, value} <- parse_value(text) do
        check_threshold(value, state.threshold, state.email)
        {:ok, value}
      end

    new_state =
      state
      |> Map.put(:last_check, DateTime.utc_now())
      |> Map.put(:checks_performed, state.checks_performed + 1)
      |> maybe_update_value(result)

    {result, new_state}
  end

  defp maybe_update_value(state, {:ok, value}) do
    Map.put(state, :last_value, value)
  end

  defp maybe_update_value(state, _error), do: state

  defp check_threshold(value, threshold, email) when value > threshold do
    Logger.warn("Threshold exceeded: #{value} > #{threshold}")

    Mail.send_email(
      to: email,
      subject: "Threshold Alert",
      body: "Value #{value} exceeded threshold #{threshold}"
    )
  end

  defp check_threshold(_value, _threshold, _email), do: :ok

  defp parse_value(text) do
    case Float.parse(String.trim(text)) do
      {value, _} -> {:ok, value}
      :error -> {:error, :parse_error}
    end
  end

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval)
  end
end

# In your application.ex
children = [
  {AutomationWorker,
   url: "https://example.com/metrics",
   selector: ".value",
   threshold: 100.0,
   email: "alerts@example.com"}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

---

## Testing Pattern

**Use Case:** Test automation code without actually running macOS automation

### Using Mox for Testing

```elixir
# test/support/mocks.ex
Mox.defmock(MockAdapter, for: ExMacOSControl.Adapter)

# config/test.exs
config :ex_macos_control, :adapter, MockAdapter

# test/my_automation_test.exs
defmodule MyAutomationTest do
  use ExUnit.Case, async: true
  import Mox

  alias MyApp.Automation

  setup :verify_on_exit!

  test "scrapes price successfully" do
    MockAdapter
    |> expect(:run_applescript, fn script, _opts ->
      # Verify the script is correct
      assert script =~ "Safari"
      {:ok, ""}
    end)
    |> expect(:run_javascript, fn script, _opts ->
      # Return mock data
      {:ok, "$99.99"}
    end)

    assert {:ok, "$99.99"} = Automation.scrape_price("https://example.com")
  end

  test "handles timeout errors" do
    MockAdapter
    |> expect(:run_applescript, fn _script, _opts ->
      {:error, %ExMacOSControl.Error{type: :timeout, message: "Timed out"}}
    end)

    assert {:error, %{type: :timeout}} = Automation.scrape_price("https://example.com")
  end
end
```

### Integration Test Pattern

```elixir
defmodule SafariIntegrationTest do
  use ExUnit.Case
  alias ExMacOSControl.Safari

  @moduletag :integration

  setup do
    # Ensure Safari is running
    ExMacOSControl.SystemEvents.launch_application("Safari")
    Process.sleep(1000)

    on_exit(fn ->
      # Cleanup: close test tabs
      cleanup_tabs()
    end)

    :ok
  end

  @tag :skip  # Skip by default, run with --include skip
  test "opens URL and extracts title" do
    assert :ok = Safari.open_url("https://example.com")
    Process.sleep(2000)

    assert {:ok, title} = Safari.execute_javascript("document.title")
    assert title =~ "Example"
  end

  defp cleanup_tabs do
    # Close all but first tab
    {:ok, tabs} = Safari.list_tabs()

    for _ <- 2..length(tabs) do
      Safari.close_tab(2)
      Process.sleep(100)
    end
  end
end
```

---

## Summary

These patterns cover the most common automation scenarios:

1. **Process Management** - Ensure apps are running
2. **Browser Automation** - Web scraping and testing
3. **Email Notifications** - Alert on conditions
4. **Multi-App Workflows** - Chain multiple apps together
5. **Error Handling** - Robust automation
6. **Background Jobs** - Scheduled tasks
7. **Testing** - Test without real automation

## Best Practices Recap

- ✅ Always check permissions before automation
- ✅ Use retry logic for unreliable operations
- ✅ Add appropriate sleep delays for UI operations
- ✅ Handle all error cases explicitly
- ✅ Log important operations
- ✅ Test with Mox before running real automation
- ✅ Use GenServers for long-running automation
- ✅ Clean up resources (close tabs, quit apps)

## Next Steps

- [DSL vs Raw AppleScript](dsl_vs_raw.html) - Choose the right approach
- [Advanced Usage](advanced_usage.html) - Telemetry and optimization
- [Performance Guide](../performance.html) - Tune for production

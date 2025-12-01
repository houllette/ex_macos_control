# Testing Guide for ExMacOSControl

This guide explains how to write and run tests for ExMacOSControl, covering both unit tests and integration tests.

## Table of Contents

- [Overview](#overview)
- [Test Organization](#test-organization)
- [Running Tests](#running-tests)
- [Writing Unit Tests](#writing-unit-tests)
- [Writing Integration Tests](#writing-integration-tests)
- [Test Helpers](#test-helpers)
- [Fixtures](#fixtures)
- [Mock Adapters](#mock-adapters)
- [Platform-Specific Testing](#platform-specific-testing)

## Overview

ExMacOSControl uses a comprehensive testing strategy:

- **Unit Tests**: Fast, isolated tests using Mox for mocking
- **Integration Tests**: Real osascript execution on macOS (tagged with `:integration`)
- **Fixtures**: Sample AppleScript, JXA, and error output files
- **Test Helpers**: Utilities for common testing patterns

## Test Organization

```
test/
├── support/
│   ├── test_helpers.ex           # Common test utilities
│   ├── adapter_factory.ex        # Mock adapter factory
│   ├── fixtures/
│   │   ├── applescript/          # Sample .applescript files
│   │   ├── javascript/           # Sample .js/.jxa files
│   │   └── errors/               # Sample osascript error outputs
│   ├── test_helpers_test.exs     # Tests for test helpers
│   └── adapter_factory_test.exs  # Tests for adapter factory
├── integration/
│   ├── applescript_integration_test.exs
│   └── fixtures_integration_test.exs
├── ex_macos_control_test.exs
└── test_helper.exs
```

## Running Tests

### Run All Unit Tests

```bash
mix test
```

Integration tests are excluded by default.

### Run All Tests (Including Integration)

```bash
mix test --include integration
```

**Note**: Integration tests require macOS with `osascript` available.

### Run Specific Test File

```bash
mix test test/ex_macos_control_test.exs
```

### Run Tests Matching Pattern

```bash
mix test --only line:42
```

### Run Tests with Coverage

```bash
mix test --cover
```

## Writing Unit Tests

Unit tests use Mox to mock the adapter, avoiding actual osascript execution.

### Basic Unit Test Example

```elixir
defmodule MyModuleTest do
  use ExUnit.Case, async: true

  import Mox
  alias ExMacOSControl.AdapterFactory

  setup :verify_on_exit!

  test "executes AppleScript successfully" do
    # Set up mock to return success
    AdapterFactory.mock_applescript_success("Hello, World!")

    # Call your function
    {:ok, result} = MyModule.run_script()

    # Assert result
    assert result == "Hello, World!"
  end

  test "handles errors" do
    # Set up mock to return error
    AdapterFactory.mock_applescript_error(:syntax_error)

    # Call your function
    {:error, reason} = MyModule.run_script()

    # Assert error
    assert reason == :syntax_error
  end
end
```

### Using Custom Mock Behavior

```elixir
test "handles multiple scripts" do
  AdapterFactory.setup_mock(fn
    "return 'hello'" -> {:ok, "hello"}
    "return 'world'" -> {:ok, "world"}
    _ -> {:error, :unknown_script}
  end)

  assert {:ok, "hello"} = ExMacOSControl.run_applescript("return 'hello'")
  assert {:ok, "world"} = ExMacOSControl.run_applescript("return 'world'")
end
```

### Using Stubs for Multiple Calls

```elixir
test "executes script multiple times" do
  # Stub allows unlimited calls with same result
  AdapterFactory.stub_applescript_success("result")

  assert {:ok, "result"} = MyModule.call_script()
  assert {:ok, "result"} = MyModule.call_script()
  assert {:ok, "result"} = MyModule.call_script()
end
```

## Writing Integration Tests

Integration tests execute real osascript commands on macOS.

### Basic Integration Test Example

```elixir
defmodule MyIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.TestHelpers

  # Tag all tests in this module as integration tests
  @moduletag :integration

  setup do
    # Skip if not on macOS with osascript
    TestHelpers.skip_unless_integration()
    :ok
  end

  @tag :integration
  test "executes real AppleScript" do
    {:ok, result} = ExMacOSControl.run_applescript("return 'Hello'")
    assert TestHelpers.normalize_output(result) == "Hello"
  end
end
```

### Integration Test Best Practices

1. **Always tag with `:integration`**: This allows tests to be excluded by default
2. **Use `skip_unless_integration/0`**: Provides clear error messages on non-macOS
3. **Set `async: false`**: Integration tests may interact with system state
4. **Normalize output**: Use `TestHelpers.normalize_output/1` to handle whitespace

## Test Helpers

The `ExMacOSControl.TestHelpers` module provides utilities for testing.

### Platform Detection

```elixir
# Check if running on macOS
TestHelpers.macos?()
# => true or false

# Check if osascript is available
TestHelpers.osascript_available?()
# => true or false

# Check if integration tests should run
TestHelpers.should_run_integration_tests?()
# => true or false
```

### Skipping Tests

```elixir
# Skip test if not on macOS
TestHelpers.skip_unless_macos()

# Skip test if osascript not available
TestHelpers.skip_unless_osascript()

# Skip test if integration requirements not met
TestHelpers.skip_unless_integration()
```

### Working with Fixtures

```elixir
# Get fixtures directory path
TestHelpers.fixtures_path()
# => "/absolute/path/to/test/support/fixtures"

# Get specific fixture path
TestHelpers.fixture_path("applescript/hello_world.applescript")
# => "/absolute/path/to/test/support/fixtures/applescript/hello_world.applescript"

# Read fixture content
{:ok, content} = TestHelpers.read_fixture("errors/syntax_error.txt")

# Read fixture content (raises on error)
content = TestHelpers.read_fixture!("applescript/hello_world.applescript")

# List available fixtures
TestHelpers.applescript_fixtures()
# => ["delay_script.applescript", "hello_world.applescript", ...]

TestHelpers.javascript_fixtures()
# => ["hello_world.js", "system_events.js", ...]

TestHelpers.error_fixtures()
# => ["app_not_found.txt", "execution_error.txt", ...]
```

### Working with Temporary Files

```elixir
TestHelpers.with_temp_script("return 'test'", ".applescript", fn path ->
  # File exists at path
  assert File.exists?(path)

  # Use the file
  {:ok, result} = ExMacOSControl.run_script_file(path)
  assert result == "test"

  # File is automatically cleaned up after this block
end)
```

### Normalizing Output

```elixir
# Remove leading/trailing whitespace from osascript output
TestHelpers.normalize_output("  Hello  \n")
# => "Hello"
```

## Fixtures

Fixtures are sample files used in tests, located in `test/support/fixtures/`.

### AppleScript Fixtures

- `applescript/hello_world.applescript` - Simple hello world script
- `applescript/with_arguments.applescript` - Script that accepts arguments
- `applescript/delay_script.applescript` - Script with delay (for timeout testing)
- `applescript/syntax_error.applescript` - Invalid AppleScript (for error testing)

### JavaScript Fixtures

- `javascript/hello_world.js` - Simple JXA hello world
- `javascript/with_arguments.js` - JXA script with arguments
- `javascript/system_events.js` - JXA using System Events
- `javascript/syntax_error.js` - Invalid JavaScript (for error testing)

### Error Fixtures

- `errors/syntax_error.txt` - Sample syntax error output
- `errors/execution_error.txt` - Sample execution error output
- `errors/permission_denied.txt` - Sample permission error output
- `errors/app_not_found.txt` - Sample app not found error output

### Using Fixtures in Tests

```elixir
test "loads AppleScript fixture" do
  script_path = TestHelpers.fixture_path("applescript/hello_world.applescript")
  content = File.read!(script_path)

  assert String.contains?(content, "Hello, World!")
end

test "validates fixture is executable" do
  script_path = TestHelpers.fixture_path("applescript/hello_world.applescript")

  {output, 0} = System.cmd("osascript", [script_path])
  assert TestHelpers.normalize_output(output) == "Hello, World!"
end
```

## Mock Adapters

The `ExMacOSControl.AdapterFactory` module provides helpers for creating mock adapters.

### Available Factory Functions

```elixir
# Mock successful AppleScript execution
AdapterFactory.mock_applescript_success("result")

# Mock AppleScript error
AdapterFactory.mock_applescript_error(:syntax_error)

# Mock successful shortcut execution
AdapterFactory.mock_shortcut_success()

# Mock shortcut error
AdapterFactory.mock_shortcut_error(:not_found)

# Set up custom mock behavior
AdapterFactory.setup_mock(fn script ->
  # Return different results based on script
end)

# Stub for multiple calls (success)
AdapterFactory.stub_applescript_success("result")

# Stub for multiple calls (error)
AdapterFactory.stub_applescript_error(:error)

# Verify all expectations met
AdapterFactory.verify_mocks()
```

## Platform-Specific Testing

### Testing on macOS

When running on macOS with osascript:

```bash
# Run all tests including integration
mix test --include integration
```

You should see output like:

```
================================================================================
Test Environment Information
================================================================================
Platform: {:unix, :darwin}
macOS: true
osascript available: true
Integration tests enabled: true

To run integration tests: mix test --include integration
================================================================================
```

### Testing on Other Platforms

When running on Linux, Windows, or without osascript:

```bash
# Run unit tests only
mix test
```

You should see:

```
================================================================================
Test Environment Information
================================================================================
Platform: {:unix, :linux}
macOS: false
osascript available: false
Integration tests enabled: false

To run integration tests: mix test --include integration
================================================================================
```

Integration tests will be excluded automatically.

### Conditional Test Execution

```elixir
# Only run this test on macOS
test "macOS-specific feature" do
  if TestHelpers.macos?() do
    # macOS-specific test code
  else
    # Skip or alternative behavior
  end
end

# Skip test unless on macOS
test "requires macOS" do
  TestHelpers.skip_unless_macos()
  # This code only runs on macOS
end
```

## Best Practices

### 1. Prefer Unit Tests Over Integration Tests

- Unit tests are faster and can run on any platform
- Use integration tests to verify real osascript behavior
- Aim for high unit test coverage, selective integration test coverage

### 2. Use Async Tests When Possible

```elixir
# Unit tests can be async
defmodule MyUnitTest do
  use ExUnit.Case, async: true
  # ...
end

# Integration tests should not be async
defmodule MyIntegrationTest do
  use ExUnit.Case, async: false
  # ...
end
```

### 3. Clean Up Resources

```elixir
# Use setup/teardown for cleanup
setup do
  # Setup code
  on_exit(fn ->
    # Cleanup code
  end)
end

# Or use helpers like with_temp_script that auto-cleanup
TestHelpers.with_temp_script(content, ext, fn path ->
  # Use temp file
  # Automatically cleaned up
end)
```

### 4. Use Descriptive Test Names

```elixir
# Good
test "returns error when script has syntax error"
test "executes AppleScript with arguments successfully"

# Less good
test "test 1"
test "it works"
```

### 5. Test Error Cases

```elixir
test "handles syntax errors gracefully" do
  AdapterFactory.mock_applescript_error(:syntax_error)

  {:error, reason} = MyModule.run_script()
  assert reason == :syntax_error
end
```

### 6. Use Fixtures for Complex Inputs

```elixir
# Instead of inline scripts
test "parses complex error" do
  {:ok, error_msg} = TestHelpers.read_fixture("errors/syntax_error.txt")
  result = MyModule.parse_error(error_msg)
  assert result.type == :syntax_error
end
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]

    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.19'
          otp-version: '27'

      - name: Install dependencies
        run: mix deps.get

      - name: Run unit tests (all platforms)
        run: mix test

      - name: Run integration tests (macOS only)
        if: runner.os == 'macOS'
        run: mix test --include integration
```

## Troubleshooting

### Integration Tests Not Running

Check the test environment info:

```bash
mix test
```

Look for the platform information output. Verify:
- `macOS: true`
- `osascript available: true`

### Mox Verification Errors

Ensure you call `verify_on_exit!` in setup:

```elixir
setup :verify_on_exit!
```

### Fixture Not Found Errors

Use absolute paths from `TestHelpers.fixture_path/1`:

```elixir
# Good
path = TestHelpers.fixture_path("applescript/hello_world.applescript")

# Bad - relative paths may fail
path = "test/support/fixtures/applescript/hello_world.applescript"
```

## Summary

- Use **unit tests** for fast, cross-platform testing with mocks
- Use **integration tests** for validating real macOS behavior
- Tag integration tests with `:integration` and use `skip_unless_integration/0`
- Leverage **test helpers** for common operations
- Use **fixtures** for sample scripts and error outputs
- Use **adapter factory** for easy mock setup
- Run `mix test` for unit tests, `mix test --include integration` for all tests

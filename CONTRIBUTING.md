# Contributing to ExMacOSControl

Thank you for your interest in contributing to ExMacOSControl! This document provides guidelines and standards for contributing to this project.

## Code of Conduct

This project adheres to a code of conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Getting Started

### Prerequisites

- Elixir ~> 1.19
- Erlang/OTP compatible with your Elixir version
- macOS (for running integration tests)
- Git

### Setup

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/ex_macos_control.git`
3. Navigate to the directory: `cd ex_macos_control`
4. Install dependencies: `mix deps.get`
5. Run tests to verify setup: `mix test`

## Development Workflow

### Test-Driven Development (TDD)

We follow TDD practices for all new features and bug fixes:

1. **Write failing tests first**
   - Unit tests for all behaviors
   - Edge cases and error conditions
   - Integration tests where applicable

2. **Implement minimal code to pass tests**
   - Focus on making tests pass
   - Keep changes small and focused

3. **Refactor with green tests**
   - Clean up code while keeping tests passing
   - Improve readability and maintainability

### Code Quality Standards

All code must meet the following quality standards before being merged:

#### 1. Formatting

- All code must be formatted with `mix format`
- Line length: 120 characters (configured in `.formatter.exs`)
- Run `mix format` before committing
- Check formatting with `mix format.check` or `mix format --check-formatted`

#### 2. Credo (Static Analysis)

- All code must pass strict Credo checks
- Run `mix credo --strict` to check
- No warnings or errors allowed
- Configuration is in `.credo.exs`

**Common Credo checks:**
- Module documentation required (`@moduledoc`)
- Function documentation required (`@doc`)
- Type specifications recommended (`@spec`)
- Consistent naming conventions
- Complexity limits (cyclomatic complexity, nesting depth)
- No code smells or anti-patterns

#### 3. Dialyzer (Type Checking)

- All code must pass Dialyzer type checking
- Run `mix dialyzer` to check
- Zero warnings allowed
- Add type specs to all public functions
- Add type specs to private functions where they improve clarity

**On first run:**
- Dialyzer will build a PLT (Persistent Lookup Table) for dependencies
- This takes several minutes but only needs to be done once
- Subsequent runs will be much faster

#### 4. Test Coverage

- Aim for 100% test coverage on new code
- Minimum 90% coverage required for PRs
- Run tests with `mix test`
- Integration tests are tagged with `@tag :integration`
- Skip integration tests on non-macOS: `mix test --exclude integration`

#### 5. Documentation

All public modules and functions must be documented:

- **`@moduledoc`**: Required for all modules
  - Overview of the module's purpose
  - Usage examples
  - Links to related modules

- **`@doc`**: Required for all public functions
  - Clear description of what the function does
  - Parameter descriptions
  - Return value description
  - Usage examples
  - Any important notes or gotchas

- **`@spec`**: Required for all public functions
  - Complete type specifications
  - Use custom types where appropriate
  - Document expected errors in return types

- **`@typedoc`**: Required for custom types
  - Explain what the type represents
  - Document field meanings for structs

**Example:**
```elixir
@moduledoc """
Provides helpers for managing macOS processes via System Events.

This module wraps AppleScript calls to System Events, providing an
Elixir-friendly interface for process management tasks like listing
processes, launching applications, and checking if apps are running.

## Examples

    iex> ExMacOSControl.SystemEvents.process_exists?("Finder")
    {:ok, true}

    iex> ExMacOSControl.SystemEvents.list_processes()
    {:ok, ["Finder", "Safari", "Terminal"]}

"""

@doc """
Checks if a process with the given name is currently running.

## Parameters

  - `process_name` - The name of the application/process to check

## Returns

  - `{:ok, true}` if the process is running
  - `{:ok, false}` if the process is not running
  - `{:error, reason}` if the check failed

## Examples

    iex> ExMacOSControl.SystemEvents.process_exists?("Finder")
    {:ok, true}

    iex> ExMacOSControl.SystemEvents.process_exists?("NonExistentApp")
    {:ok, false}

"""
@spec process_exists?(String.t()) :: {:ok, boolean()} | {:error, term()}
def process_exists?(process_name) do
  # Implementation...
end
```

### Running All Quality Checks

We provide a convenient alias to run all quality checks:

```bash
mix quality
```

This runs:
1. `mix format --check-formatted` - Check code formatting
2. `mix credo --strict` - Run static analysis
3. `mix dialyzer` - Run type checking

**All these checks must pass before submitting a PR.**

### Individual Quality Commands

You can also run checks individually:

```bash
# Format code
mix format

# Check formatting without changing files
mix format.check
# or
mix format --check-formatted

# Run Credo
mix credo

# Run Credo in strict mode
mix credo --strict

# Run Credo and show all issues
mix credo --all

# Run Dialyzer
mix dialyzer

# Run tests
mix test

# Run only unit tests (exclude integration)
mix test --exclude integration

# Run all tests including integration
mix test --include integration
```

## Pull Request Process

### Before Submitting

1. **Ensure all quality checks pass:**
   ```bash
   mix quality
   ```

2. **Ensure all tests pass:**
   ```bash
   mix test
   ```

3. **Update documentation:**
   - Add or update `@moduledoc`, `@doc`, and `@spec`
   - Update README.md if adding new features
   - Update CHANGELOG.md

4. **Review your changes:**
   - Read through your diff
   - Check for any debug code, TODOs, or commented-out code
   - Ensure commit messages are clear and descriptive

### Commit Messages

Follow these guidelines for commit messages:

- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move cursor to..." not "Moves cursor to...")
- First line should be 50 characters or less
- Reference issues and PRs when relevant
- Example:
  ```
  Add process management functions to SystemEvents

  - Implement list_processes/0
  - Implement process_exists?/1
  - Add comprehensive tests and documentation
  - Fixes #123
  ```

### PR Description

Your PR description should include:

1. **Summary**: What does this PR do?
2. **Motivation**: Why is this change needed?
3. **Changes**: List of specific changes made
4. **Testing**: How was this tested?
5. **Checklist**: Use the checklist below

**PR Checklist:**
```markdown
- [ ] All tests pass (`mix test`)
- [ ] All quality checks pass (`mix quality`)
- [ ] Code is formatted (`mix format`)
- [ ] Credo passes (`mix credo --strict`)
- [ ] Dialyzer passes (`mix dialyzer`)
- [ ] Documentation added/updated
- [ ] CHANGELOG.md updated
- [ ] Integration tests pass on macOS (if applicable)
```

## Testing

### Unit Tests

- Located in `test/`
- Use Mox for mocking adapters
- Test all code paths, edge cases, and error conditions
- Keep tests focused and readable

### Integration Tests

- Tagged with `@tag :integration`
- Test actual osascript execution on macOS
- Skip on non-macOS systems
- May require specific macOS permissions

**Example:**
```elixir
@tag :integration
test "actually runs AppleScript on macOS" do
  {:ok, result} = ExMacOSControl.run_applescript("return 'hello'")
  assert result == "hello"
end
```

### Test Organization

```
test/
├── test_helper.exs          # Test configuration
├── ex_macos_control_test.exs
└── ex_macos_control/
    ├── adapter_test.exs
    └── osascript_adapter_test.exs
```

## Code Style

### General Guidelines

- Follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
- Use descriptive variable and function names
- Keep functions small and focused (single responsibility)
- Prefer pattern matching over conditionals
- Use pipes for data transformations
- Handle errors explicitly (avoid rescue in normal flow)

### Naming Conventions

- **Modules**: `PascalCase` (e.g., `ExMacOSControl.SystemEvents`)
- **Functions**: `snake_case` (e.g., `run_applescript/2`)
- **Variables**: `snake_case` (e.g., `process_name`)
- **Atoms**: `snake_case` (e.g., `:ok`, `:error`)
- **Boolean functions**: Use `?` suffix (e.g., `process_exists?/1`)

### Error Handling

- Return `{:ok, result}` or `{:error, reason}` tuples
- Use custom error types from `ExMacOSControl.Error` when available
- Provide helpful error messages
- Include remediation steps in error messages when possible

**Example:**
```elixir
def run_applescript(script) do
  case OSAScriptAdapter.run_applescript(script) do
    {:ok, result} -> {:ok, result}
    {:error, reason} -> {:error, ExMacOSControl.Error.new(:execution_error, reason)}
  end
end
```

## Getting Help

- Open an issue for bugs or feature requests
- Ask questions in discussions
- Check existing issues and PRs for similar topics

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (MIT License).

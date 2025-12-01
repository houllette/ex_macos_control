# ExMacosControl

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ex_macos_control` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_macos_control, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ex_macos_control>.

## Development

### Setup

```bash
# Install dependencies
mix deps.get

# Run tests
mix test
```

### Code Quality

This project uses strict code quality standards. All contributions must pass the following checks:

#### Run All Quality Checks

```bash
# Run all quality checks (format, credo, dialyzer)
mix quality
```

#### Individual Checks

```bash
# Format code
mix format

# Check code formatting
mix format.check

# Run Credo static analysis (strict mode)
mix credo --strict

# Run Dialyzer type checking
mix dialyzer

# Run tests
mix test
```

### Quality Standards

- **Formatting**: All code must be formatted with `mix format` (120 character line length)
- **Credo**: All code must pass strict Credo checks with zero warnings
- **Dialyzer**: All code must pass Dialyzer type checking with zero warnings
- **Tests**: Aim for 100% test coverage on new code (minimum 90%)
- **Documentation**: All public functions must have `@doc`, `@spec`, and `@moduledoc`

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed development guidelines and standards.


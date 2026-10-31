# Documentation

ExMacOSControl has three useful starting points: call an app module for a single
operation, use a built-in recipe for a common handoff, or compose your own Elixir
workflow. The guides below work as repository documentation and as ExDoc pages.

## Start here

| Goal | Read |
| --- | --- |
| Install and run your first automation | [Getting started](guides/getting_started.md) |
| Find out what each module supports | [Capabilities and limitations](capabilities.md) |
| Connect two apps with an existing recipe | [Using built-in workflows](guides/workflows.md) |
| Design a custom workflow | [Building your own workflows](guides/building_workflows.md) |

## Work through a task

| Task | Guide |
| --- | --- |
| Extract a web page, focus an app, process files, or prepare a Mail draft | [Common patterns](guides/common_patterns.md) |
| Run or build a companion macOS Shortcut | [Integrating Shortcuts](guides/shortcuts.md) |
| Reuse captured data, stage files, or inspect a failed run | [Captures and recovery](guides/captures_and_recovery.md) |
| Use the optional native Calendar/Reminders transport | [EventKit](guides/eventkit.md) |
| Configure execution, observe telemetry, or propagate task context | [Advanced usage](guides/advanced_usage.md) |
| Write an operation outside the app modules | [Script DSL and raw scripts](guides/dsl_vs_raw.md) |

## Develop and extend

- [Testing](testing.md) explains adapters, test categories, and live opt-ins.
- [Creating app modules](creating_app_modules.md) covers wrapper contracts and templates.
- [Performance](performance.md) covers deadlines, polling, batching, and measurement.
- [Git hooks](git_hooks.md) describes the optional repository hooks.
- [Contributing](../CONTRIBUTING.md) lists development and review expectations.
- [Changelog](../CHANGELOG.md) records release changes.

The [API reference](https://hexdocs.pm/ex_macos_control) lists individual
functions. Build local HTML with:

```sh
mix docs --warnings-as-errors --output tmp/docs
```

Examples that address a resource by ID expect an ID discovered from your own
apps. Placeholders such as a folder, calendar, account, chat, or Shortcut ID must
be replaced before use. A successful write acknowledges the app command; use a
verification helper when your next step depends on observing the saved state.

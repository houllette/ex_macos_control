# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-10-31

This release documents the current automation surface and adds practical workflow
guides. Older entries below describe historical behavior; consult the
[capability reference](docs/capabilities.md) for current support and limitations.

### Current source capabilities

- Cross-app workflow recipes, immutable captures, optional checksummed file
  staging, shared composition deadlines, verification, tracing and private journals.
- Owned Safari page scopes, selector/form helpers, document guards, verified Mail
  drafts, application lifecycle/focus scopes, and owned GUI command windows.
- Notes, Calendar, Reminders, Contacts, Photos, Music, TV, QuickTime, Image Events,
  Automator, System Settings and Final Cut Pro metadata APIs.
- Native Shortcuts IDs/folders, file input/output, typed results, pipelines and
  versioned companion-workflow envelopes.
- Optional EventKit helper for native Calendar events and Reminder batches with
  separate consent and references.
- Bounded command execution, structured outcomes, permission preflight, scripting
  dictionary discovery and explicit live qualification/evidence workflows.

### Documentation

- Reconciled README and guides with implementation, including execution defaults,
  permissions, return values, unsupported operations and partial-failure behavior.
- Added workflow, custom composition, Shortcuts, capture/recovery and EventKit
  guides, a documentation index, and a capability inventory.
- Corrected extension templates and public delegate documentation; included the
  guides and template assets in ExDoc navigation.

### Current limitations

- Messages unread counts return an unsupported-operation error; the old zero
  placeholder is no longer the current contract.
- Messages history/search requires an explicitly configured companion Shortcut.
  No direct SQLite Messages database reader is included.
- Dictionary declarations and native contract tests do not establish live
  app/account compatibility. Writes are not automatically replayed or rolled back.

## [0.1.0] - 2025-11-30

### Added

#### Core Features
- **AppleScript Execution**: Execute AppleScript code with timeout support and argument passing
- **JavaScript for Automation (JXA)**: Full JXA support with ObjC bridge access
- **Script File Execution**: Execute `.applescript`, `.scpt`, `.js`, and `.jxa` files with automatic language detection
- **macOS Shortcuts**: Run Shortcuts with input parameter support (strings, numbers, maps, lists)
- **Comprehensive Error Handling**: Detailed error types and messages via `ExMacOSControl.Error` module

#### Application Modules
- **SystemEvents**: Process management (list, launch, quit, check if running)
- **SystemEvents.UI**: UI automation (menu clicks, keystrokes, window properties)
- **SystemEvents.FileOps**: File operations (reveal in Finder, trash files, get selection)
- **Finder**: Control Finder application (selection, navigation, view modes)
- **Safari**: Browser automation (open URLs, execute JavaScript, manage tabs)
- **Mail**: Email automation (send emails with CC/BCC, search mailboxes, unread counts)
- **Messages**: iMessage/SMS automation (send messages, retrieve chats, unread counts)

#### Advanced Features
- **Permissions Module**: Check and manage macOS automation permissions (accessibility, automation, full disk access)
- **Script Building DSL**: Minimal DSL for constructing AppleScript programmatically
- **Retry Logic**: Automatic retry with exponential/linear backoff for timeout errors
- **Telemetry Integration**: Observability via `:telemetry` events for monitoring and debugging
- **Performance Monitoring**: Built-in telemetry events for script execution and retry operations

#### Developer Experience
- **Platform Detection**: Automatic macOS platform validation with helpful error messages
- **Test-Friendly Design**: Adapter pattern with Mox support for comprehensive testing
- **Comprehensive Documentation**: Module creation guide for extending with new app modules
- **Performance Guide**: Best practices for timeout tuning, retry strategies, and telemetry setup

### Technical Details

- **Test Coverage**: 417 tests with 100% pass rate (408 unit tests, 9 doctests, 171 integration tests)
- **Code Quality**: Zero Credo issues (strict mode), zero Dialyzer warnings
- **Dependencies**: Minimal dependencies (telemetry for monitoring, mox for testing)
- **Elixir Version**: Requires Elixir ~> 1.19

### Known Limitations

- **macOS Only**: This library only works on macOS platforms (validated at runtime)
- **Permissions Required**: Most features require macOS permissions (accessibility, automation, full disk access)
- **Application Availability**: App modules (Safari, Mail, Messages, etc.) require the respective apps to be installed and properly configured
- **Script Timeout**: Long-running scripts may timeout; use the `:timeout` option to adjust (default varies by operation)
- **Integration Tests**: Many integration tests are skipped by default to prevent destructive operations (use `mix test --include integration` to run)

### Security Considerations

- **Message Sending**: `Messages.send_message/2` sends real messages immediately with no undo
- **Email Sending**: `Mail.send_email/1` sends real emails immediately with no undo
- **File Operations**: `SystemEvents.trash_file/1` moves files to trash (not permanent but use with caution)
- **Permission Prompts**: macOS will prompt for permissions on first use; ensure users understand what permissions are needed and why

### Breaking Changes

None (initial release)

## [0.1.1] - 2025-11-30

### Fixed
- **Messages.list_chats/0**: Fixed AppleScript syntax error with `unread count` property
  - Changed from `unread count of c` to `c's unread count` (possessive form required for multi-word properties)
  - Now properly retrieves chat names from participant full names instead of missing values
  - Returns `unread: 0` for all chats as Messages AppleScript API doesn't expose unread counts
- **Messages.get_unread_count/0**: Updated to return `{:ok, 0}` as placeholder
  - Documents that real unread counts require Full Disk Access and direct SQLite database queries
- **Messages.send_message/3**: Simplified AppleScript to use `send to buddy` syntax
  - Fixed issues with service type selection that caused execution errors
  - Properly handles contact names with correct capitalization

### Added
- **Messages Group Chat Support**: New `:group_chat` option for `send_message/3`
  - Send messages to group chats by participant names (e.g., "John Doe & Jane Smith")
  - Automatically finds matching group chat via `list_chats()` and uses chat ID
  - Returns `:not_found` error if group chat doesn't exist
  - Comprehensive test coverage for group chat functionality
- **Messages Documentation**: Enhanced module documentation with group chat examples and limitations section

### Changed
- **Messages AppleScript**: Updated to use simpler and more reliable syntax patterns
  - Individual messages use `send to buddy` syntax
  - Group messages use `send to chat id` syntax

## [0.1.2] - 2025-11-30

### Fixed
- **Telemetry Performance Warning**: Fixed telemetry handler warnings in test suite
  - Changed from anonymous functions to module function references using `&Module.function/4` syntax
  - Eliminates "local function" performance penalty warnings from `:telemetry.attach_many/4`
  - Affected files: `retry_test.exs` and `osascript_adapter_telemetry_test.exs`
  - Improves test suite performance and reduces noise in test output

---

[0.3.0]: https://github.com/houllette/ex_macos_control/releases/tag/v0.3.0
[0.1.2]: https://github.com/houllette/ex_macos_control/releases/tag/v0.1.2
[0.1.1]: https://github.com/houllette/ex_macos_control/releases/tag/v0.1.1
[0.1.0]: https://github.com/houllette/ex_macos_control/releases/tag/v0.1.0

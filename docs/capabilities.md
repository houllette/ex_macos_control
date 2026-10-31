# Capabilities and limitations

This is an inventory of implemented APIs, not a claim of live compatibility with
every macOS/app/account combination. The project requires Elixir `~> 1.19`.
CI checks native contracts on macOS 26 and unit tests on Linux; live desktop and
account behavior requires a suitable Mac session and explicit qualification.

## Execution and composition

| Module | Implemented surface | Boundary |
| --- | --- | --- |
| `ExMacOSControl` | AppleScript, JXA, script files, facade Shortcut run/list, process-local execution options | Raw output is text by default; raw execution has no default deadline. |
| `Script` | Tell blocks and commands; compile, validate, decompile | Small string builder, not a full language DSL or app-command validator. |
| `Command` | Argument-vector command execution, separate stdout/stderr, deadlines, output bounds | Cancelling a command cannot recall an Apple event already sent. |
| `Composition` | Shared deadlines, named steps/effects, verification, sequential batches, task context | Cooperative callbacks; no automatic rollback or replay. |
| `Composition.Journal` | Private synced JSONL evidence and read-only inspection | Stores declared IDs/outcomes, not arbitrary results; does not resume runs. |
| `Capture` | Page, text, selection, Mail message, Calendar event, and note snapshots; rendering; optional checksummed file staging | File selections initially retain paths only; source existence is not guaranteed later. |
| `Workflows` | 22 cross-app recipes, including verified drafts and persistent workspaces | Some perform real sends/imports; see the [recipe reference](guides/workflows.md#recipe-reference). |
| `Retry`, `Wait` | Timeout retry with an explicit idempotence escape hatch; bounded boolean polling | No generic retry of syntax/permission errors, no exactly-once delivery. |

Module names in this reference are under `ExMacOSControl` unless fully qualified.

## Applications and desktop

| Module | Implemented surface | Boundary |
| --- | --- | --- |
| `Applications` | Resolve status, ensure running, open/reopen UI, activate, scoped foreground work, quit/restart | Running-process readiness does not prove loaded documents/accounts. |
| `Desktop` | Cooperative host-wide lock for participating callers | Cannot prevent a person or unrelated app changing focus. |
| `Desktop.Session` | Acquire app support windows, restore focus, clean up owned windows | Existing/document windows are retained; no application is quit. |
| `GUI` | Run a command through one owned Terminal window in Aqua, retain evidence, optional window retention | Requires a logged-in GUI session and Elixir CLI; uncertain launches are not replayed. |
| `SystemEvents` | Process discovery, app activation, window properties/bounds, menus, keystrokes/key codes, waits, bounded UI trees/attributes/actions, Finder helpers and folder actions | UI paths depend on app/localization/state and Accessibility permission. |
| `Accessibility` | Discover/query/act on targeted UI elements and verify observable UI state | Accessibility trees are bounded and can be incomplete; elements can become stale. |
| `Permissions` | Accessibility checks; active legacy Automation check; non-prompting preflight, explicit consent request, diagnostics, settings links | The user grants permissions. Preflight states do not prove every command works. |
| `Capabilities`, `ScriptingDictionary` | Installed app identity, OSA languages, cached dictionary terminology and declaration queries | Declared terminology is explicitly unverified; absent dictionaries do not imply no automation route. |
| `Platform` | macOS/native tool detection and validation | Tool availability alone does not establish GUI/account readiness. |

## Browser, files, and communication

| Module | Implemented surface | Boundary |
| --- | --- | --- |
| `Safari` | Windows/tabs, URL/source/text, JavaScript, navigation/readiness, Reading List; owned page scopes, snapshots, selectors, extraction, form fill/click, document pinning | DOM calls require JavaScript from Apple Events. Tabs use 1-based indices, not stable IDs; extra tabs invalidate owned-window assumptions. |
| `Finder` | Selections, windows/targets/views, metadata, volumes, folders, rename/copy/move/trash/eject; captured-selection and collision-checked batches | File effects persist on partial failure. Paths do not freeze bytes. |
| `Mail` | Accounts/mailboxes, paged message searches, content/flags, save attachments, sends, drafts/replies, capture handoffs, saved-draft verification/read/delete | Ordinary draft IDs are outgoing compose IDs. Verified draft attachment checks use names/sizes. Send acknowledgement does not prove delivery. |
| `Messages` | Account/chat/participant discovery; send text/files by recipient or explicit chat; sequential batch sends | Explicit recipient service/account routing is unsupported. History/search needs a configured companion Shortcut; unread counts are unavailable. |

For Messages history, configure `:message_search_shortcut` in the
`:ex_macos_control` application. `search_messages/2` calls the versioned
`messages.search` operation described by the [Shortcuts protocol](guides/shortcuts.md#define-a-versioned-workflow-protocol).
The library supplies no Messages database reader or bundled history Shortcut.

## Productivity and native EventKit

| Module | Implemented surface | Boundary |
| --- | --- | --- |
| `Notes` | Accounts/folders, paged notes, selection, HTML/plain text, create/update/delete, append, duplicate, create/show, attachment listing, capture handoffs | Plain-text helpers escape HTML; locked/shared content remains subject to Notes. Omitted folder uses the default destination. |
| `Reminders` | Accounts/lists, paged reminder reads, title/body/dates/priority/flags/completion, list CRUD, create/complete batches, capture handoffs | Uses Apple-event IDs; long GUI workflows may need normal app UI startup. |
| `Calendar` | Calendars/events, timezone-aware dates, recurrence text, attendees, display/sound/mail alarms, views, event-with-alarms composition | Open-file alarms are unsupported. The wrapper does not promise full recurrence/attendee editing. |
| `Contacts` | Contacts/groups, CRUD, email/phone/postal details, memberships, selection, create-with-details | Changes are saved through Contacts; account constraints still apply. |
| `EventKit` | Explicit helper build/install, status, full-access requests, source discovery | Optional native helper targets macOS 14+; its permissions and IDs are separate from Apple events. |
| `EventKit.Calendar` | Calendar creation/deletion; bounded-range reads; verified event create/update/delete; bounded recurrence and explicit occurrence/future scope | Uses native references; absolute timestamps and explicit recurrence scope required. |
| `EventKit.Reminders` | List creation/deletion; reminder reads; verified create/complete batches | Creation fields are title/body/priority; no due-date/alarm/general update/delete mirror. |

Apple-event list helpers generally accept `limit: 1..1000` (default 100) and
non-negative `offset`. Specific filter and pagination support varies by function.
Dates accepted by productivity writers are `DateTime` values or ISO 8601 strings
with timezone offsets, not naive wall times. See the [EventKit guide](guides/eventkit.md)
for the native transport's narrower field set and reference rules.

## Media

| Module | Implemented surface | Boundary |
| --- | --- | --- |
| `Photos` | Albums/folders, media metadata/search, favorites/keywords, import/export, slideshow controls, import-into-new-album | Account/library access and source file availability are required; imports can partially succeed. |
| `Music`, `TV` | Playback/state/current track, seek/volume/mute, playlists/tracks/search, metadata updates, create-with-tracks | Uses each app's scripting library; no streaming-service catalog or DRM bypass. |
| `QuickTime` | Open/list documents, playback, seek/trim, export, new recordings | Recording requires device/privacy access and separate live qualification. |
| `ImageEvents` | Metadata, scale/rotate/crop/flip/convert, multi-step processing, collision-checked batches | Output paths must be new; formats are PNG/JPEG/TIFF/BMP/PSD strings. |
| `FinalCutPro` | Read library/event/project/sequence identities and metadata | No general timeline-editing API. |

## Shortcuts and utilities

| Module | Implemented surface | Boundary |
| --- | --- | --- |
| `Shortcuts` | IDs/folders/metadata, run native file or text input, output modes/UTIs/paths, pipelines, versioned JSON workflows, view/sign | Shortcuts must be user-installed; JSON input is text. Signing contacts Apple. |
| `Automator` | Run an existing workflow with input and named variables | Does not author a workflow graph. |
| `Terminal` | Managed shell runs, borrowed-window script execution, session snapshots and idle waits | New tabs are unsupported. Managed runs use the GUI runner; borrowed targets stay open. |
| `StandardAdditions` | Text clipboard, dialogs, file/folder choosers, notifications, speech, volume, system info | Interactive functions require a desktop session. |
| `PropertyList` | Read/write/convert plist data via native tools | File permissions and native format constraints apply. |
| `SystemSettings` | Discover panes/anchors and reveal a pane | No universal API for changing arbitrary settings. |
| `Qualification` | Fixed `notes-crud` and local `mail-capture` profiles with manifest validation and durable effect evidence | Explicit disposable-session setup and opt-ins; no external delivery or recording. |

The qualification harness is a specialized test facility, not a production
workflow scheduler or sandbox. See [testing](testing.md) for its entry points and
the separation between native source contracts and live evidence.

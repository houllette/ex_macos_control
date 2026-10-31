# Integrating macOS Shortcuts

Use a Shortcut when an app exposes an action through Shortcuts or when you want
someone to edit part of an automation visually. ExMacOSControl runs shortcuts
already installed in the current user's Shortcuts app. It does not create their
action graphs or install a shortcut just by naming it.

## Create a small companion Shortcut

In the macOS Shortcuts app, create a Shortcut named **Normalize Text**:

1. Add a **Text** action whose content is the **Shortcut Input** variable.
2. Add **Change Case**, choose **UPPERCASE**, and use that text as input.
3. Add **Stop and Output** and return the changed text.
4. Run it once in Shortcuts to check its actions and resolve any consent prompts.

Then run from Elixir:

```elixir
alias ExMacOSControl.Shortcuts

{:ok, "HELLO"} = Shortcuts.run("Normalize Text", input: "hello", timeout: 10_000)
```

Action names and layout can differ between macOS releases; the contract is text
in and text out. Choose a unique name or use a discovered ID. A Shortcut can
perform arbitrary actions, including sending or deleting data, so design that
contract before treating it as a harmless text transformation.

## Discover names, IDs, and folders

```elixir
{:ok, names} = ExMacOSControl.list_shortcuts()
{:ok, shortcuts} = Shortcuts.list(limit: 100, offset: 0)
{:ok, folders} = Shortcuts.list_folders(limit: 100)
```

The facade lists names through the CLI. The richer module discovers IDs, names,
subtitles, input acceptance, and action counts through Shortcuts Events. It can
filter by `folder_id:`. Discovery and execution may have different permission
requirements. `Shortcuts.view/2` opens an installed shortcut in its editor.

## Choose the input representation

| Input | Representation at the Shortcut boundary |
| --- | --- |
| `input: "text"` | UTF-8 text in a private input file |
| `input: 42` | Text `42` |
| `input: map_or_list` | JSON text; parse it inside the Shortcut |
| `input_paths: [path, ...]` | Native file input from existing paths |

Map/list input is not automatically a native Shortcut dictionary. Use **Get
Dictionary from Input** for JSON. A run accepts either text/JSON `:input` or
`:input_paths`, not both. Text transport files are cleaned up by the command
runner. Passing native paths does not copy or freeze their contents.

For example, a user-installed **Summarize Record** shortcut could parse the JSON
input, extract `title` and `body`, and output JSON text:

```elixir
Shortcuts.run("Summarize Record",
  input: %{"title" => "Meeting", "body" => "Discuss the release"},
  output: :json,
  timeout: 10_000
)
```

`output: :json` decodes what the Shortcut returns; the Shortcut must emit valid
JSON. It does not convert arbitrary Shortcut objects into JSON for you.

## Handle output deliberately

| Option | Result |
| --- | --- |
| Default `output: :text` | `{:ok, text}` after trimming, or `:ok` for empty output |
| `output: :text, trim: false` | Preserves stdout whitespace |
| `output: :json` | `{:ok, decoded_value}`; invalid/empty JSON is an error |
| `output: :binary` | `{:ok, stdout_bytes}` without trimming |
| `output: :execution` | `{:ok, %{stdout: ..., stderr: ..., exit_status: 0}}` on success |
| `output_path: path` | CLI writes output there; the returned value still describes stdout |

`output_type:` passes a UTI string such as `"public.png"`. With `output_type:`
and no output path, the default mode is binary. A Shortcut's own actions determine
whether it can produce that type. The combined stdout/stderr limit defaults to
10 MiB; it does not bound files a Shortcut writes itself.

File example, assuming a user-installed **Make Preview** shortcut accepts an image
and returns image data:

```elixir
Shortcuts.run("Make Preview",
  input_paths: [Path.expand("tmp/source.png")],
  output_path: Path.expand("tmp/preview.png"),
  output_type: "public.png",
  timeout: 15_000
)
```

The source must exist and the output parent must exist. Check for an existing
destination yourself when overwriting would be undesirable; `Shortcuts.run/2`
does not enforce a new output path.

## Chain shortcuts

```elixir
Shortcuts.pipeline(["Normalize Text", "Summarize Text"], "some input",
  timeout: 20_000
)
```

Install both shortcuts first. They run sequentially with one total deadline;
each output becomes the next input. Empty text output becomes `""`. Use
`output: :json` only when every shortcut emits valid JSON; decoded intermediate
values are re-encoded as JSON text. Effects are not retried, and earlier shortcut
actions remain if a later stage fails.

## Define a versioned workflow protocol

`Shortcuts.workflow/4` is useful when one companion Shortcut supports multiple
operations. It sends JSON in this form:

```json
{"exmc": 1, "operation": "normalize", "input": {"text": "hello"}}
```

Build the Shortcut to:

1. Parse Shortcut Input as a dictionary.
2. Check `exmc` is `1` and branch on `operation`.
3. Read the operation's payload from `input`.
4. Return JSON text with `exmc: 1` and a `result` field.

For a successful response such as:

```json
{"exmc": 1, "result": {"text": "HELLO"}}
```

the Elixir call is:

```elixir
Shortcuts.workflow("My Automation Bridge", "normalize", %{"text" => "hello"},
  timeout: 10_000
)
# => {:ok, %{"text" => "HELLO"}}
```

This validates the response envelope, not the meaning or schema of its `result`.
Add application-level checks for your own result shape. The library provides no
automatic error-envelope protocol or retry of the operation.

## Connect a Shortcut to an app workflow

`Workflows.selection_to_shortcut/2` passes one captured Finder selection as
native file input. `Workflows.clipboard_to_shortcut/2` reads text once, and
`Workflows.shortcut_to_clipboard/3` writes the Shortcut's text output back to the
clipboard. See [built-in workflows](workflows.md) for their return values.

`Shortcuts.sign/3` signs an existing exported `.shortcut` file into a new output
path for distribution. Signing contacts Apple for validation. It is separate from
running a shortcut and is not an install operation.

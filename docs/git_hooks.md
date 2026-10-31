# Git hooks

The repository supplies optional hooks in `scripts/hooks/`. A clone does not
install them automatically. To copy them into this checkout's `.git/hooks/`:

```sh
./scripts/install-hooks.sh
```

The installer overwrites the local `pre-commit` and `pre-push` hook files. It
expects a `.git` directory at the repository root, so the supplied installer is
not designed for a linked worktree whose `.git` is a file. Review existing local
hooks before installation. This setup affects contributors, not library consumers.

## What runs

| Hook | Checks and side effects |
| --- | --- |
| Pre-commit | `mix deps.get --check-locked`, `mix quality`, generate `bom.xml`, then stage `bom.xml` with `git add`. |
| Pre-push | Lock check, `mix quality`, generate `tmp/bom-pre-push.xml`, run the default `mix test`, then reject uncommitted tracked changes to `bom.xml`. |

`mix quality` includes formatting verification, strict Credo, and Dialyzer. The
first Dialyzer run may build its PLT under `tmp/plts`. The pre-push test command
retains default exclusions; it does not enable live desktop/account tests.
Pre-push validates SBOM generation without rewriting the tracked SBOM's UUID and
timestamp.

## Run checks directly

```sh
mix deps.get --check-locked
mix quality
mix test
mix docs --warnings-as-errors --output tmp/docs
```

The hooks currently do not build docs. For a docs change, run the explicit docs
command as well. The SBOM generation command used by pre-commit is:

```sh
mix sbom.cyclonedx --schema 1.6 --format xml --exclude-system-dependencies --output bom.xml --force
```

Generating the tracked SBOM can change it even without dependency changes; review
that diff separately. A failing hook stops the commit/push. Resolve the reported
dependency, formatting, analysis, test, or SBOM error, then rerun the check.

## Troubleshoot local setup

Use `git config --get core.hooksPath` to check whether Git uses a custom hooks
directory. Verify executable bits on the installed hook files. Reinstall after
updating the versioned scripts when you want those changes locally; the installer
copies files rather than linking them.

Git's `--no-verify` bypasses local hooks, but does not make the checks pass.
CI has its own checks in `.github/workflows/ci.yml`, including selected native
contracts on macOS. See [testing](testing.md) for the boundary between those
contracts and live evidence.

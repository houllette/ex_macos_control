# Git Hooks Documentation

This project uses Git hooks to ensure code quality and dependency tracking before commits and pushes.

## Installed Hooks

### Pre-Commit Hook

Runs automatically before every `git commit` and performs:

1. **Dependency Lock Check** - Verifies `mix.lock` is up to date
   - Command: `mix deps.get --check-locked`
   - Ensures dependencies are properly locked

2. **Quality Checks** - Runs all code quality tools
   - Command: `mix quality`
   - Includes:
     - `mix format --check-formatted` - Code formatting
     - `mix credo --strict` - Static analysis
     - `mix dialyzer` - Type checking

3. **SBOM Generation** - Creates Software Bill of Materials
   - Command: `mix sbom.cyclonedx --schema 1.6 --format xml --exclude-system-dependencies --output bom.xml --force`
   - Generates dependency tracking file
   - Auto-stages the SBOM file for commit

### Pre-Push Hook

Runs automatically before every `git push` and performs:

1. **Dependency Lock Check** - Verifies `mix.lock` is up to date
2. **Quality Checks** - Runs `mix quality`
3. **SBOM Generation** - Validates generation in `tmp/bom-pre-push.xml` without changing the tracked SBOM's timestamp and UUID
4. **Test Suite** - Runs `mix test` to ensure all tests pass
5. **SBOM Commit Check** - Checks `bom.xml` for uncommitted changes

## Hook Behavior

### Success Flow

When all checks pass:

```bash
$ git commit -m "Add new feature"

🔍 Running pre-commit checks...

📦 Checking mix.lock is up to date...
✅ mix.lock is up to date

🔧 Running mix quality checks...
✅ All quality checks passed

📋 Generating SBOM (Software Bill of Materials)...
✅ SBOM generated successfully

📎 Staging bom.xml...
✅ SBOM file staged

🎉 All pre-commit checks passed!

[feature/new-feature abc1234] Add new feature
 2 files changed, 50 insertions(+), 5 deletions(-)
```

### Failure Flow

When checks fail:

```bash
$ git commit -m "Bad code"

🔍 Running pre-commit checks...

📦 Checking mix.lock is up to date...
✅ mix.lock is up to date

🔧 Running mix quality checks...
❌ Quality checks failed!
Fix the issues above before committing

# Commit is blocked until issues are fixed
```

## Bypassing Hooks (Emergency Use Only)

### Bypass Pre-Commit

```bash
# Skip pre-commit hook
git commit --no-verify -m "Emergency fix"
# or
git commit -n -m "Emergency fix"
```

### Bypass Pre-Push

```bash
# Skip pre-push hook
git push --no-verify
# or
git push -n
```

**⚠️ Warning:** Only bypass hooks when absolutely necessary (e.g., emergency hotfixes). Always run checks manually afterward:

```bash
# Manual quality check
mix quality

# Manual SBOM generation
mix sbom.cyclonedx --schema 1.6 --format xml --exclude-system-dependencies --output bom.xml --force

# Commit SBOM if it changed
git add bom.xml
git commit -m "Update SBOM"
```

## Troubleshooting

### Hook Not Running

**Problem:** Git hooks aren't executing

**Solution:**

1. Check if hooks are executable:
   ```bash
   ls -la .git/hooks/pre-commit .git/hooks/pre-push
   ```

2. Make them executable if needed:
   ```bash
   chmod +x .git/hooks/pre-commit .git/hooks/pre-push
   ```

### mix.lock Out of Date

**Problem:** Hook fails with "mix.lock is out of date"

**Solution:**

```bash
# Update dependencies
mix deps.get

# Commit the updated mix.lock
git add mix.lock
git commit -m "Update dependencies"
```

### Dialyzer Taking Too Long

**Problem:** Pre-commit hook is slow due to Dialyzer

**Solution:**

Dialyzer builds a PLT (Persistent Lookup Table) once, then runs fast. First-time run is slow:

```bash
# Build PLT manually (one-time setup)
mix dialyzer --plt

# Subsequent runs are fast (seconds, not minutes)
```

### Quality Checks Failing

**Problem:** `mix quality` fails

**Solution:**

Run each check individually to identify the issue:

```bash
# Check formatting
mix format --check-formatted
# Fix: mix format

# Check Credo
mix credo --strict
# Fix issues reported by Credo

# Check Dialyzer
mix dialyzer
# Fix type errors
```

### SBOM Generation Failing

**Problem:** `mix sbom.cyclonedx --schema 1.6 --format xml --exclude-system-dependencies --output bom.xml --force` fails

**Solution:**

1. Ensure sbom is installed:
   ```bash
   mix deps.get
   ```

2. Check if it's a dev-only dependency issue:
   ```bash
   MIX_ENV=dev mix sbom.cyclonedx --schema 1.6 --format xml --exclude-system-dependencies --output bom.xml --force
   ```

3. If it still fails, check the error message and ensure all dependencies are fetched

## Customizing Hooks

### Disable Specific Checks

Edit `.git/hooks/pre-commit` or `.git/hooks/pre-push` and comment out unwanted checks:

```bash
# Example: Disable SBOM generation temporarily
# echo "📋 Generating SBOM (Software Bill of Materials)..."
# if ! mix sbom.cyclonedx --schema 1.6 --format xml --exclude-system-dependencies --output bom.xml --force; then
#   echo -e "${RED}❌ SBOM generation failed!${NC}"
#   exit 1
# fi
```

### Add Custom Checks

Add new checks before the final success message:

```bash
# Example: Add test coverage check
echo "📊 Checking test coverage..."
if ! mix coveralls; then
  echo -e "${RED}❌ Coverage below threshold!${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Coverage passed${NC}"
```

## Team Setup

### Sharing Hooks with Team

Git hooks are not committed by default (they're in `.git/hooks/`). To share with your team:

**Option 1: Manual Setup (Current)**

Team members clone the repo and hooks are already there (since we created them in `.git/hooks/`)

**Option 2: Hook Template Script (Recommended for Teams)**

Create `scripts/install-hooks.sh`:

```bash
#!/bin/bash
# Install git hooks for the project

cp scripts/hooks/pre-commit .git/hooks/pre-commit
cp scripts/hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-commit .git/hooks/pre-push

echo "✅ Git hooks installed successfully!"
```

Then team members run:
```bash
./scripts/install-hooks.sh
```

**Option 3: Automated Setup**

Add to `mix.exs` aliases:

```elixir
defp aliases do
  [
    setup: ["deps.get", "cmd ./scripts/install-hooks.sh"]
  ]
end
```

Team members run:
```bash
mix setup
```

## CI/CD Integration

These checks should also run in CI/CD to catch issues if hooks are bypassed:

### GitHub Actions Example

```yaml
name: Quality Checks

on: [push, pull_request]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.19'
          otp-version: '26'

      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: deps
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}

      - name: Install dependencies
        run: mix deps.get

      - name: Check mix.lock
        run: mix deps.get --check-locked

      - name: Run quality checks
        run: mix quality

      - name: Generate SBOM
        run: mix sbom.cyclonedx --schema 1.6 --format xml --exclude-system-dependencies --output bom.xml --force

      - name: Run tests
        run: mix test
```

## Best Practices

1. **Don't bypass hooks habitually** - They exist to maintain code quality
2. **Run checks locally** before committing to catch issues early
3. **Keep hooks fast** - Slow hooks tempt developers to bypass them
4. **Update hooks as needed** - Add/remove checks based on team needs
5. **Document bypasses** - If you bypass a hook, note why in the commit message

## Summary

- ✅ **Pre-commit**: Checks formatting, linting, types, and generates SBOM
- ✅ **Pre-push**: All pre-commit checks + runs full test suite
- ✅ **Bypass**: Use `--no-verify` for emergencies only
- ✅ **Team**: Consider using hook installation scripts for consistency

These hooks help maintain code quality and ensure proper dependency tracking throughout the development lifecycle.

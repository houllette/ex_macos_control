#!/bin/bash
# Install git hooks for ExMacOSControl project
# Run this after cloning the repository

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "Installing git hooks for ExMacOSControl..."
echo ""

# Get the project root directory (one level up from scripts/)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if we're in a git repository
if [ ! -d "$PROJECT_ROOT/.git" ]; then
  echo -e "${YELLOW}Error: Not in a git repository!${NC}"
  echo "Make sure you're running this from the project root or scripts directory."
  exit 1
fi

# Copy hooks
echo "📋 Installing pre-commit hook..."
cp "$SCRIPT_DIR/hooks/pre-commit" "$PROJECT_ROOT/.git/hooks/pre-commit"
chmod +x "$PROJECT_ROOT/.git/hooks/pre-commit"
echo -e "${GREEN}✅ pre-commit hook installed${NC}"

echo "📋 Installing pre-push hook..."
cp "$SCRIPT_DIR/hooks/pre-push" "$PROJECT_ROOT/.git/hooks/pre-push"
chmod +x "$PROJECT_ROOT/.git/hooks/pre-push"
echo -e "${GREEN}✅ pre-push hook installed${NC}"

echo ""
echo -e "${GREEN}🎉 Git hooks installed successfully!${NC}"
echo ""
echo "The following checks will run automatically:"
echo "  • Pre-commit: mix.lock check, mix quality, SBOM generation"
echo "  • Pre-push: All pre-commit checks + mix test"
echo ""
echo "To bypass hooks in emergencies, use: git commit --no-verify"
echo "See docs/git_hooks.md for more information."
echo ""

exit 0

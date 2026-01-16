#!/bin/bash

# Ralph Project Setup Script for Kiro CLI
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME=${1:-"my-project"}

echo "🚀 Setting up Ralph project: $PROJECT_NAME"

# Create project directory
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

# Create structure with .kiro directory
mkdir -p {.kiro,specs/stdlib,src,examples,logs,docs/generated}

# Copy templates to .kiro directory
cp "$SCRIPT_DIR/templates/PROMPT.md" .kiro/PROMPT.md
cp "$SCRIPT_DIR/templates/fix_plan.md" .kiro/fix_plan.md
cp "$SCRIPT_DIR/templates/AGENT.md" .kiro/AGENT.md
cp -r "$SCRIPT_DIR/templates/specs/"* specs/ 2>/dev/null || true

# Initialize git
git init -q
echo "# $PROJECT_NAME" > README.md
git add .
git commit -q -m "Initial Ralph project setup"

echo "✅ Project $PROJECT_NAME created!"
echo ""
echo "Next steps:"
echo "  1. Edit .kiro/PROMPT.md with your project requirements"
echo "  2. Update specs/ with your project specifications"  
echo "  3. Run: ralph --monitor"

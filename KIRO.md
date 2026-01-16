# KIRO.md

This file provides guidance to Kiro CLI when working with code in this repository.

## Repository Overview

This is the Ralph for Kiro CLI repository - an autonomous AI development loop system that enables continuous development cycles with intelligent exit detection. This is a fork of [ralph-claude-code](https://github.com/frankbria/ralph-claude-code) adapted for Kiro CLI.

**Version**: v0.10.0 | **Tests**: 308 passing (100% pass rate)

## Key Differences from Original (Claude Code)

| Feature | Original (Claude Code) | This Fork (Kiro CLI) |
|---------|------------------------|----------------------|
| CLI Command | `claude` | `kiro-cli chat --no-interactive --trust-all-tools` |
| Prompt File | `PROMPT.md` | `.kiro/PROMPT.md` |
| Task List | `@fix_plan.md` | `.kiro/fix_plan.md` |
| Rate Limiting | Yes (100/hour) | No (not needed) |
| Session Continuity | Yes (`--continue`) | No (one-shot mode) |
| JSON Output Mode | Yes | No |
| Tool Trust | Configurable | All tools trusted |

## Core Architecture

The system consists of bash scripts and a modular library system:

### Main Scripts

1. **ralph_loop.sh** - The main autonomous loop that executes Kiro CLI repeatedly
2. **ralph_monitor.sh** - Live monitoring dashboard for tracking loop status
3. **setup.sh** - Project initialization script for new Ralph projects
4. **ralph_import.sh** - PRD/specification import tool that converts documents to Ralph format

### Library Components (lib/)

1. **lib/circuit_breaker.sh** - Circuit breaker pattern implementation
   - Prevents runaway loops by detecting stagnation
   - Three states: CLOSED (normal), HALF_OPEN (monitoring), OPEN (halted)
   - Configurable thresholds for no-progress and error detection

2. **lib/response_analyzer.sh** - Intelligent response analysis
   - Analyzes Kiro output for completion signals
   - Detects test-only loops and stuck error patterns
   - Two-stage error filtering to eliminate false positives
   - Confidence scoring for exit decisions

3. **lib/date_utils.sh** - Cross-platform date utilities
   - ISO timestamp generation for logging

## Key Commands

### Installation
```bash
# Install Ralph globally (run once)
./install.sh

# Uninstall Ralph
./uninstall.sh
```

### Setting Up a New Project
```bash
# Create a new Ralph-managed project
ralph-setup my-project-name
cd my-project-name
```

### Running the Ralph Loop
```bash
# Start with integrated tmux monitoring (recommended)
ralph --monitor

# Start without monitoring
ralph

# With custom parameters
ralph --timeout 30 --prompt custom_prompt.md

# Check current status
ralph --status

# Graceful shutdown
ralph-stop

# Circuit breaker management
ralph --reset-circuit
ralph --circuit-status
```

### Monitoring
```bash
# Integrated tmux monitoring (recommended)
ralph --monitor

# Manual monitoring in separate terminal
ralph-monitor

# tmux session management
tmux list-sessions
tmux attach -t ralph-<project>
```

### Running Tests
```bash
# Run all tests
npm test

# Run specific test suites
bats tests/unit/test_exit_detection.bats
bats tests/integration/test_loop_execution.bats
```

## Ralph Loop Configuration

The loop is controlled by several key files:

- **.kiro/PROMPT.md** - Main prompt file that drives each loop iteration
- **.kiro/fix_plan.md** - Prioritized task list that Ralph follows
- **status.json** - Real-time status tracking (JSON format)
- **logs/** - Execution logs for each loop iteration

### Kiro CLI Execution

Ralph executes Kiro in non-interactive mode with all tools trusted:

```bash
kiro-cli chat --no-interactive --trust-all-tools -p "$prompt_content"
```

**Key flags:**
- `--no-interactive` - Print response to STDOUT without interactive mode
- `--trust-all-tools` - Allow all tools without confirmation prompts
- `-p` - Pass prompt content as positional argument

### Intelligent Exit Detection

The loop uses multiple signals to detect when to exit:

**Exit conditions:**
- All items in `.kiro/fix_plan.md` marked as completed
- Multiple consecutive "done" signals from Kiro (`done_signals >= 2`)
- Too many test-only loops indicating feature completeness (`test_loops >= 3`)
- Strong completion indicators in output

**Example behavior:**
```
Loop 5: Kiro outputs "Phase complete, moving to next feature"
        → completion_indicators: 3 (high confidence from patterns)
        → EXIT_SIGNAL: false (Kiro says more work needed)
        → Result: CONTINUE

Loop 8: Kiro outputs "All tasks complete, project ready"
        → completion_indicators: 4
        → EXIT_SIGNAL: true (Kiro confirms done)
        → Result: EXIT with "project_complete"
```

### Circuit Breaker Thresholds

- `CB_NO_PROGRESS_THRESHOLD=3` - Open circuit after 3 loops with no file changes
- `CB_SAME_ERROR_THRESHOLD=5` - Open circuit after 5 loops with repeated errors

### Error Detection

Ralph uses two-stage error filtering:

**Stage 1: JSON Field Filtering**
- Filters out JSON field patterns like `"is_error": false`

**Stage 2: Actual Error Detection**
- Detects real error messages: `Error:`, `ERROR:`, `Exception`, `Fatal`

## Project Structure for Ralph-Managed Projects

Each project created with `ralph-setup` follows this structure:
```
project-name/
├── .kiro/
│   ├── PROMPT.md      # Main development instructions
│   └── fix_plan.md    # Prioritized TODO list
├── specs/             # Project specifications
├── src/               # Source code
├── logs/              # Loop execution logs
└── status.json        # Current loop status
```

## Global Installation

Ralph installs to:
- **Commands**: `~/.local/bin/` (ralph, ralph-monitor, ralph-setup, ralph-import, ralph-stop)
- **Templates**: `~/.ralph/templates/`
- **Scripts**: `~/.ralph/` (ralph_loop.sh, ralph_monitor.sh, setup.sh, ralph_import.sh)
- **Libraries**: `~/.ralph/lib/` (circuit_breaker.sh, response_analyzer.sh, date_utils.sh)

## Integration Points

Ralph integrates with:
- **Kiro CLI**: Uses `kiro-cli chat --no-interactive --trust-all-tools` as the execution engine
- **tmux**: Terminal multiplexer for integrated monitoring sessions
- **Git**: Expects projects to be git repositories
- **jq**: For JSON processing of status and exit signals
- **Standard Unix tools**: bash, grep, date, etc.

## Exit Conditions and Thresholds

### Exit Detection Thresholds
- `MAX_CONSECUTIVE_TEST_LOOPS=3` - Exit if too many test-only iterations
- `MAX_CONSECUTIVE_DONE_SIGNALS=2` - Exit on repeated completion signals

### Graceful Shutdown

```bash
# Create stop file (Ralph exits after current loop)
ralph-stop

# Or manually
touch .ralph-stop
```

## Feature Development Quality Standards

### Testing Requirements

- **Test Pass Rate**: 100% - all tests must pass
- **Test Types**: Unit tests, integration tests, end-to-end tests

### Git Workflow Requirements

1. **Commit with Clear Messages**:
   ```bash
   git commit -m "feat(module): descriptive message"
   ```

2. **Push to Remote**:
   ```bash
   git push origin <branch-name>
   ```

### Documentation Requirements

- Update `.kiro/fix_plan.md` with new tasks before starting work
- Mark items complete upon completion
- Update `.kiro/PROMPT.md` if behavior needs modification

### Feature Completion Checklist

- [ ] All tests pass
- [ ] Script functionality manually tested
- [ ] All changes committed and pushed
- [ ] `.kiro/fix_plan.md` task marked complete
- [ ] Documentation updated

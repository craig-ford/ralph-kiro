#!/bin/bash

# Kiro CLI Ralph Loop - Autonomous development with intelligent exit detection
# Stripped-down version for kiro-cli (no JSON output, no session continuity)

set -e

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/lib/date_utils.sh"
source "$SCRIPT_DIR/lib/response_analyzer.sh"
source "$SCRIPT_DIR/lib/circuit_breaker.sh"

# Configuration
PROMPT_FILE=".kiro/PROMPT.md"
LOG_DIR="logs"
STATUS_FILE="status.json"
TRUST_ALL_TOOLS=true
KIRO_AGENT=""
VERBOSE_PROGRESS=false
TIMEOUT_MINUTES=15
SLEEP_DURATION=1
CALL_COUNT_FILE=".call_count"
TIMESTAMP_FILE=".last_reset"
USE_TMUX=false

# Exit detection thresholds
MAX_CONSECUTIVE_TEST_LOOPS=3
MAX_CONSECUTIVE_DONE_SIGNALS=2

# Counters
CONSECUTIVE_TEST_LOOPS=0
CONSECUTIVE_DONE_SIGNALS=0
LOOP_COUNT=0

show_help() {
    cat << EOF
Usage: ralph [OPTIONS]

Options:
  -h, --help              Show this help message
  -p, --prompt FILE       Set prompt file (default: .kiro/PROMPT.md)
  -m, --monitor           Start with tmux session and live monitor
  -v, --verbose           Show detailed progress updates
  -t, --timeout MIN       Set execution timeout in minutes (1-120, default: 15)
  -s, --status            Show current status and exit
  -tat, --trust-all-tools Trust all Kiro tools without confirmation
  -a, --agent NAME        Use a specific Kiro agent
  --reset-circuit         Reset the circuit breaker
  --circuit-status        Show circuit breaker status

Examples:
  ralph                        Start autonomous loop
  ralph --monitor              Start with tmux monitoring
  ralph -tat                   Trust all tools (use with caution)
  ralph -a my-agent            Use specific agent
  ralph --timeout 30           30-minute timeout per loop
EOF
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/ralph.log"
    [[ "$VERBOSE_PROGRESS" == "true" ]] && echo "[$level] $message"
}

log_status() {
    log_message "$1" "$2"
}

check_stop_file() {
    if [[ -f ".ralph-stop" ]]; then
        log_message "INFO" "Stop file detected, exiting gracefully"
        rm -f ".ralph-stop"
        return 0
    fi
    return 1
}

check_tmux_available() {
    if ! command -v tmux &> /dev/null; then
        echo "Error: tmux is required for --monitor mode"
        echo "Install with: sudo apt-get install tmux (Ubuntu/Debian) or brew install tmux (macOS)"
        exit 1
    fi
}

setup_tmux_session() {
    local session_name="ralph-$(basename "$(pwd)")"
    
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "Attaching to existing session: $session_name"
        tmux attach-session -t "$session_name"
        exit 0
    fi
    
    echo "Creating new tmux session: $session_name"
    
    local ralph_cmd="$SCRIPT_DIR/ralph_loop.sh"
    [[ "$PROMPT_FILE" != ".kiro/PROMPT.md" ]] && ralph_cmd="$ralph_cmd --prompt '$PROMPT_FILE'"
    [[ "$VERBOSE_PROGRESS" == "true" ]] && ralph_cmd="$ralph_cmd --verbose"
    [[ "$TIMEOUT_MINUTES" != "15" ]] && ralph_cmd="$ralph_cmd --timeout $TIMEOUT_MINUTES"
    
    tmux new-session -d -s "$session_name" -n "ralph"
    tmux send-keys -t "$session_name:ralph" "$ralph_cmd" C-m
    tmux split-window -h -t "$session_name:ralph"
    tmux send-keys -t "$session_name:ralph.1" "ralph-monitor" C-m
    tmux select-pane -t "$session_name:ralph.0"
    tmux attach-session -t "$session_name"
    exit 0
}

update_status() {
    local status="$1"
    local message="$2"
    local timestamp=$(get_timestamp)
    
    cat > "$STATUS_FILE" << EOF
{
  "status": "$status",
  "message": "$message",
  "loop_count": $LOOP_COUNT,
  "consecutive_test_loops": $CONSECUTIVE_TEST_LOOPS,
  "consecutive_done_signals": $CONSECUTIVE_DONE_SIGNALS,
  "last_update": "$timestamp"
}
EOF
}

run_kiro() {
    local prompt_content="$1"
    local output_file="$LOG_DIR/kiro_output_$(get_file_timestamp).log"
    local timeout_seconds=$((TIMEOUT_MINUTES * 60))
    
    # Build kiro command
    local kiro_cmd="kiro-cli chat --no-interactive"
    [[ "$TRUST_ALL_TOOLS" == "true" ]] && kiro_cmd="$kiro_cmd --trust-all-tools"
    [[ -n "$KIRO_AGENT" ]] && kiro_cmd="$kiro_cmd --agent $KIRO_AGENT"
    
    log_message "INFO" "Starting kiro-cli execution (timeout: ${TIMEOUT_MINUTES}m)"
    [[ "$VERBOSE_PROGRESS" == "true" ]] && log_message "INFO" "Command: $kiro_cmd"
    
    if timeout "$timeout_seconds" $kiro_cmd -p "$prompt_content" > "$output_file" 2>&1; then
        log_message "INFO" "Kiro execution completed successfully"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_message "WARN" "Kiro execution timed out after ${TIMEOUT_MINUTES} minutes"
        else
            log_message "WARN" "Kiro execution exited with code $exit_code"
        fi
    fi
    
    echo "$output_file"
}

analyze_response() {
    local output_file="$1"
    
    if [[ ! -f "$output_file" ]]; then
        log_message "ERROR" "Output file not found: $output_file"
        return 1
    fi
    
    local content=$(cat "$output_file")
    local files_changed=0
    local has_error=false
    local is_test_only=false
    local done_signals=0
    
    # Count file changes
    files_changed=$(echo "$content" | grep -cE "(Created|Modified|Updated|Wrote|Deleted).*\.(py|js|ts|php|sh|md|json|yaml|yml|css|html)$" || echo "0")
    
    # Detect errors (two-stage filtering)
    local potential_errors=$(echo "$content" | grep -iE "error|failed|exception|traceback" || true)
    if [[ -n "$potential_errors" ]]; then
        # Filter out false positives
        local real_errors=$(echo "$potential_errors" | grep -vE \
            '"error":|"is_error":|error_log|error_handler|ErrorHandler|on_error|error\.log|logger\.error|logging\.error|test.*error|error.*test|"error": (false|null|None)|pip.*error|WARNING.*error|Traceback \(most recent|File ".*", line' || true)
        [[ -n "$real_errors" ]] && has_error=true
    fi
    
    # Detect test-only loops
    if echo "$content" | grep -qiE "running tests|pytest|jest|phpunit|bats"; then
        if ! echo "$content" | grep -qiE "implementing|creating|adding feature|building"; then
            is_test_only=true
        fi
    fi
    
    # Count done signals
    echo "$content" | grep -qiE "all (tasks|items|features).*complete" && ((done_signals++)) || true
    echo "$content" | grep -qiE "project.*complete|implementation.*complete" && ((done_signals++)) || true
    echo "$content" | grep -qiE "nothing (left|remaining|more) to" && ((done_signals++)) || true
    echo "$content" | grep -qiE "no (remaining|pending|outstanding) (tasks|items|work)" && ((done_signals++)) || true
    
    # Save analysis
    cat > ".response_analysis" << EOF
{
  "files_changed": $files_changed,
  "has_error": $has_error,
  "is_test_only": $is_test_only,
  "done_signals": $done_signals
}
EOF
    
    log_message "INFO" "Analysis: files=$files_changed, error=$has_error, test_only=$is_test_only, done_signals=$done_signals"
}

should_exit_gracefully() {
    if [[ ! -f ".response_analysis" ]]; then
        echo "continue"
        return 1
    fi
    
    local analysis=$(cat ".response_analysis")
    local done_signals=$(echo "$analysis" | jq -r '.done_signals // 0')
    local is_test_only=$(echo "$analysis" | jq -r '.is_test_only // false')
    
    # Update counters
    if [[ "$is_test_only" == "true" ]]; then
        ((CONSECUTIVE_TEST_LOOPS++))
    else
        CONSECUTIVE_TEST_LOOPS=0
    fi
    
    if [[ $done_signals -ge 2 ]]; then
        ((CONSECUTIVE_DONE_SIGNALS++))
    else
        CONSECUTIVE_DONE_SIGNALS=0
    fi
    
    # Exit conditions
    if [[ $CONSECUTIVE_TEST_LOOPS -ge $MAX_CONSECUTIVE_TEST_LOOPS ]]; then
        log_status "WARN" "Exit: $CONSECUTIVE_TEST_LOOPS consecutive test-only loops"
        echo "test_loops"
        return 0
    fi
    
    if [[ $CONSECUTIVE_DONE_SIGNALS -ge $MAX_CONSECUTIVE_DONE_SIGNALS ]]; then
        log_status "WARN" "Exit: $CONSECUTIVE_DONE_SIGNALS consecutive done signals"
        echo "done_signals"
        return 0
    fi
    
    if [[ $done_signals -ge 2 ]]; then
        log_status "WARN" "Exit: Strong completion indicators ($done_signals)"
        echo "project_complete"
        return 0
    fi
    
    # Check fix_plan.md completion
    if [[ -f ".kiro/fix_plan.md" ]]; then
        local total=$(grep -c "^- \[" ".kiro/fix_plan.md" 2>/dev/null || echo "0")
        local completed=$(grep -c "^- \[x\]" ".kiro/fix_plan.md" 2>/dev/null || echo "0")
        
        if [[ $total -gt 0 ]] && [[ $completed -eq $total ]]; then
            log_status "WARN" "Exit: All $total tasks in fix_plan.md complete"
            echo "tasks_complete"
            return 0
        fi
    fi
    
    echo "continue"
    return 1
}

main() {
    mkdir -p "$LOG_DIR"
    
    if [[ ! -f "$PROMPT_FILE" ]]; then
        echo "Error: Prompt file not found: $PROMPT_FILE"
        exit 1
    fi
    
    log_message "INFO" "=== Ralph Loop Started ==="
    log_message "INFO" "Prompt: $PROMPT_FILE, Timeout: ${TIMEOUT_MINUTES}m"
    update_status "running" "Loop started"
    
    while true; do
        ((LOOP_COUNT++))
        log_message "INFO" "--- Loop $LOOP_COUNT ---"
        
        # Check stop file
        if check_stop_file; then
            update_status "stopped" "Stop file detected"
            break
        fi
        
        # Check circuit breaker
        if ! check_circuit_breaker; then
            log_message "ERROR" "Circuit breaker is OPEN - stopping"
            update_status "circuit_open" "Circuit breaker triggered"
            break
        fi
        
        # Read and execute prompt
        local prompt_content=$(cat "$PROMPT_FILE")
        local output_file=$(run_kiro "$prompt_content")
        
        # Analyze response
        analyze_response "$output_file"
        
        # Update circuit breaker
        local files_changed=$(jq -r '.files_changed // 0' ".response_analysis" 2>/dev/null || echo "0")
        local has_error=$(jq -r '.has_error // false' ".response_analysis" 2>/dev/null || echo "false")
        update_circuit_breaker "$files_changed" "$has_error"
        
        # Check exit conditions
        local exit_reason=$(should_exit_gracefully)
        if [[ "$exit_reason" != "continue" ]]; then
            log_message "INFO" "Graceful exit: $exit_reason"
            update_status "completed" "Exit reason: $exit_reason"
            break
        fi
        
        update_status "running" "Loop $LOOP_COUNT completed"
        sleep "$SLEEP_DURATION"
    done
    
    log_message "INFO" "=== Ralph Loop Ended (${LOOP_COUNT} loops) ==="
}

show_status() {
    if [[ -f "$STATUS_FILE" ]]; then
        cat "$STATUS_FILE"
    else
        echo "No status file found. Ralph may not have run yet."
    fi
    
    if [[ -f ".circuit_breaker_state" ]]; then
        echo ""
        echo "Circuit Breaker:"
        cat ".circuit_breaker_state"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--status)
            show_status
            exit 0
            ;;
        -m|--monitor)
            USE_TMUX=true
            shift
            ;;
        -p|--prompt)
            PROMPT_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE_PROGRESS=true
            shift
            ;;
        -t|--timeout)
            if [[ "$2" =~ ^[1-9][0-9]*$ ]] && [[ "$2" -le 120 ]]; then
                TIMEOUT_MINUTES="$2"
            else
                echo "Error: Timeout must be 1-120 minutes"
                exit 1
            fi
            shift 2
            ;;
        -tat|--trust-all-tools)
            TRUST_ALL_TOOLS=true
            shift
            ;;
        -a|--agent)
            KIRO_AGENT="$2"
            shift 2
            ;;
        --reset-circuit)
            source "$SCRIPT_DIR/lib/circuit_breaker.sh"
            reset_circuit_breaker "Manual reset"
            exit 0
            ;;
        --circuit-status)
            source "$SCRIPT_DIR/lib/circuit_breaker.sh"
            show_circuit_status
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

[[ "$USE_TMUX" == "true" ]] && { check_tmux_available; setup_tmux_session; }

main

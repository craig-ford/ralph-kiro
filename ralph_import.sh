#!/bin/bash

# Ralph Import - Convert PRDs to Ralph format using Kiro CLI
# Version: 0.10.0 - Adapted for Kiro CLI
set -e

# Configuration
KIRO_CMD="kiro-cli chat --no-interactive"
TRUST_ALL_TOOLS=false

# Temporary file names
CONVERSION_OUTPUT_FILE=".ralph_conversion_output.txt"
CONVERSION_PROMPT_FILE=".ralph_conversion_prompt.md"
CONVERSION_PROMPT_FILE=".ralph_conversion_prompt.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    local message=$2
    local color=""

    case $level in
        "INFO")  color=$BLUE ;;
        "WARN")  color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "SUCCESS") color=$GREEN ;;
    esac

    echo -e "${color}[$(date '+%H:%M:%S')] [$level] $message${NC}"
}

show_help() {
    cat << HELPEOF
Ralph Import - Convert PRDs to Ralph Format

Usage: $0 [OPTIONS] <source-file> [project-name]

Arguments:
    source-file     Path to your PRD/specification file (any format)
    project-name    Name for the new Ralph project (optional, defaults to filename)

Options:
    -h, --help          Show this help message
    -tat, --trust-all-tools  Trust all Kiro tools without confirmation

Examples:
    $0 my-app-prd.md
    $0 requirements.txt my-awesome-app
    $0 -tat project-spec.json

Supported formats:
    - Markdown (.md)
    - Text files (.txt)
    - JSON (.json)
    - Any text-based format

The command will:
1. Create a new Ralph project with .kiro/ directory
2. Use Kiro CLI to intelligently convert your PRD into:
   - .kiro/PROMPT.md (Ralph instructions)
   - .kiro/fix_plan.md (prioritized tasks)
   - specs/requirements.md (technical specifications)

HELPEOF
}

# Check dependencies
check_dependencies() {
    if ! command -v ralph-setup &> /dev/null; then
        log "ERROR" "Ralph not installed. Run ./install.sh first"
        exit 1
    fi
    
    if ! command -v kiro-cli &> /dev/null; then
        log "ERROR" "Kiro CLI not found. Install from https://kiro.dev/docs/cli/installation/"
        exit 1
    fi
}

# Convert PRD using Kiro CLI
convert_prd() {
    local source_file=$1
    local project_name=$2

    log "INFO" "Converting PRD to Ralph format using Kiro CLI..."

    # Trust all tools for conversion (one-shot operation needs read/write/directory access)
    local kiro_cmd="$KIRO_CMD --trust-all-tools"

    # Create conversion prompt file
    cat > "$CONVERSION_PROMPT_FILE" << 'PROMPTEOF'
# PRD to Ralph Conversion Task

You are tasked with converting a Product Requirements Document (PRD) or specification into Ralph for Kiro CLI format.

## Input Analysis
Analyze the provided specification file and extract:
- Project goals and objectives
- Core features and requirements
- Technical constraints and preferences
- Priority levels and phases
- Success criteria

## Required Outputs

Create these files:

### 1. .kiro/PROMPT.md
Transform the PRD into Ralph development instructions:
```markdown
# Ralph Development Instructions

## Context
You are Ralph, an autonomous AI development agent working on this project.

## Current Objectives
[Extract and prioritize 4-6 main objectives from the PRD]

## Key Principles
- ONE task per loop - focus on the most important thing
- Search the codebase before assuming something isn't implemented
- Write comprehensive tests with clear documentation
- Update .kiro/fix_plan.md with your learnings
- Commit working changes with descriptive messages

## Project Requirements
[Convert PRD requirements into clear, actionable development requirements]

## Technical Constraints
[Extract any technical preferences, frameworks, languages mentioned]

## Success Criteria
[Define what "done" looks like based on the PRD]

## Current Task
Follow .kiro/fix_plan.md and choose the most important item to implement next.
```

### 2. .kiro/fix_plan.md
Convert requirements into a prioritized task list:
```markdown
# Ralph Fix Plan

## High Priority
[Extract and convert critical features into actionable tasks]

## Medium Priority
[Secondary features and enhancements]

## Low Priority
[Nice-to-have features and optimizations]

## Completed
- [x] Project initialization

## Notes
[Any important context from the original PRD]
```

### 3. specs/requirements.md
Create detailed technical specifications:
```markdown
# Technical Specifications

[Convert PRD into detailed technical requirements including:]
- System architecture requirements
- Data models and structures
- API specifications
- User interface requirements
- Performance requirements
- Security considerations

[Preserve all technical details from the original PRD]
```

## Instructions
1. Read and analyze the attached specification file
2. Create the .kiro/ directory if it doesn't exist: mkdir -p .kiro
3. Create the three files above with content derived from the PRD
4. Ensure all requirements are captured and properly prioritized
5. Make the .kiro/PROMPT.md actionable for autonomous development
6. Structure .kiro/fix_plan.md with clear, implementable tasks

PROMPTEOF

    # Append the PRD source content
    local source_basename
    source_basename=$(basename "$source_file")
    
    echo "" >> "$CONVERSION_PROMPT_FILE"
    echo "---" >> "$CONVERSION_PROMPT_FILE"
    echo "" >> "$CONVERSION_PROMPT_FILE"
    echo "## Source PRD File: $source_basename" >> "$CONVERSION_PROMPT_FILE"
    echo "" >> "$CONVERSION_PROMPT_FILE"
    cat "$source_file" >> "$CONVERSION_PROMPT_FILE"

    log "INFO" "Running Kiro CLI..."
    if $kiro_cmd "$(cat "$CONVERSION_PROMPT_FILE")" > "$CONVERSION_OUTPUT_FILE" 2>&1; then
        log "SUCCESS" "PRD conversion completed"
    else
        log "ERROR" "PRD conversion failed"
        cat "$CONVERSION_OUTPUT_FILE"
        rm -f "$CONVERSION_PROMPT_FILE" "$CONVERSION_OUTPUT_FILE"
        exit 1
    fi

    # Clean up temp files
    rm -f "$CONVERSION_PROMPT_FILE" "$CONVERSION_OUTPUT_FILE"

    # Verify files were created/updated
    local missing_files=()
    local expected_files=(".kiro/PROMPT.md" ".kiro/fix_plan.md" "specs/requirements.md")

    for file in "${expected_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done

    if [[ ${#missing_files[@]} -ne 0 ]]; then
        log "WARN" "Some files were not created: ${missing_files[*]}"
        log "INFO" "You may need to create these files manually or run the conversion again"
    else
        log "SUCCESS" "All expected files created"
    fi
}

# Main function
main() {
    local source_file="$1"
    local project_name="$2"
    
    # Validate arguments
    if [[ -z "$source_file" ]]; then
        log "ERROR" "Source file is required"
        show_help
        exit 1
    fi
    
    if [[ ! -f "$source_file" ]]; then
        log "ERROR" "Source file does not exist: $source_file"
        exit 1
    fi
    
    # Default project name from filename
    if [[ -z "$project_name" ]]; then
        project_name=$(basename "$source_file" | sed 's/\.[^.]*$//')
    fi
    
    log "INFO" "Converting PRD: $source_file"
    log "INFO" "Project name: $project_name"
    [[ "$TRUST_ALL_TOOLS" == "true" ]] && log "INFO" "Trust all tools: enabled"
    
    check_dependencies
    
    # Create project directory
    log "INFO" "Creating Ralph project: $project_name"
    ralph-setup "$project_name"
    cd "$project_name"

    # Copy source file to project (uses basename since we cd'd into project)
    local source_basename
    source_basename=$(basename "$source_file")
    cp "../$source_file" "$source_basename"

    # Run conversion using local copy (basename, not original path)
    convert_prd "$source_basename" "$project_name"
    
    log "SUCCESS" "🎉 PRD imported successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Review and edit the generated files:"
    echo "     - .kiro/PROMPT.md (Ralph instructions)"  
    echo "     - .kiro/fix_plan.md (task priorities)"
    echo "     - specs/requirements.md (technical specs)"
    echo "  2. Start autonomous development:"
    echo "     ralph --monitor"
    echo ""
    echo "Project created in: $(pwd)"
}

# Parse command line arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -tat|--trust-all-tools)
            TRUST_ALL_TOOLS=true
            shift
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional arguments
set -- "${POSITIONAL_ARGS[@]}"

# Run main with remaining arguments
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

main "$@"
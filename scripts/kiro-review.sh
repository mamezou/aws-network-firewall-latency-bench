#!/usr/bin/env bash
# kiro-review.sh — Run kiro-cli review agents and save reports to reviews/
#
# Usage:
#   ./scripts/kiro-review.sh                    # Run all review agents
#   ./scripts/kiro-review.sh security-auditor   # Run specific agent
#   ./scripts/kiro-review.sh --list             # List available agents
#
# Prerequisites:
#   - kiro-cli installed and authenticated (run `kiro-cli login` first)
#   - .kiro/agents/*.json agent definitions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$PROJECT_ROOT/.kiro/agents"
REVIEWS_DIR="$PROJECT_ROOT/reviews"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Review agents (read-only agents only; exclude write agents like doc-updater)
REVIEW_AGENTS=("security-auditor" "spec-checker" "unit-tester")

# Prompts for each agent — customize these for your project
declare -A AGENT_PROMPTS
AGENT_PROMPTS[security-auditor]="Perform a full security audit of this project. Scan all source directories for security issues. Report all findings with severity levels (CRITICAL/HIGH/MEDIUM/INFO)."
AGENT_PROMPTS[spec-checker]="Compare the current implementation against the project specification. Check API endpoints, data model, response format, and UI components. Report all divergences and missing features."
AGENT_PROMPTS[unit-tester]="Review test coverage and quality for this project. Detect test frameworks, check coverage gaps, quality issues, and missing tests. Report findings with recommendations."

usage() {
    echo "Usage: $(basename "$0") [OPTIONS] [AGENT_NAME]"
    echo ""
    echo "Run kiro-cli review agents and save reports."
    echo ""
    echo "Options:"
    echo "  --list    List available review agents and their status"
    echo "  --help    Show this help message"
    echo ""
    echo "Agents:"
    for agent in "${REVIEW_AGENTS[@]}"; do
        echo "  $agent"
    done
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                    # Run all agents"
    echo "  $(basename "$0") security-auditor   # Run one agent"
}

list_agents() {
    echo "Available review agents:"
    echo ""
    for agent in "${REVIEW_AGENTS[@]}"; do
        json_file="$AGENTS_DIR/$agent.json"
        if [[ -f "$json_file" ]]; then
            desc=$(python3 -c "import json; print(json.load(open('$json_file'))['description'])" 2>/dev/null || echo "No description")
            echo "  $agent  [OK]"
            echo "    $desc"
        else
            echo "  $agent  [MISSING] $json_file not found"
        fi
        echo ""
    done
}

run_agent() {
    local agent="$1"
    local json_file="$AGENTS_DIR/$agent.json"
    local output_file="$REVIEWS_DIR/${agent}-${TIMESTAMP}.md"
    local prompt="${AGENT_PROMPTS[$agent]}"

    if [[ ! -f "$json_file" ]]; then
        echo "ERROR: Agent config not found: $json_file" >&2
        return 1
    fi

    echo "Running $agent..."

    if kiro-cli chat \
        --agent "$agent" \
        --no-interactive \
        --trust-all-tools \
        --wrap never \
        "$prompt" > "$output_file" 2>&1; then
        echo "  Done: $output_file"
    else
        echo "  WARNING: $agent exited with non-zero status. Output saved to: $output_file" >&2
    fi
}

generate_summary() {
    local summary_file="$REVIEWS_DIR/summary-${TIMESTAMP}.md"

    {
        echo "# Review Summary"
        echo ""
        echo "**Date**: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "**Agents**: ${REVIEW_AGENTS[*]}"
        echo ""
        echo "---"
        echo ""

        for agent in "${REVIEW_AGENTS[@]}"; do
            local report="$REVIEWS_DIR/${agent}-${TIMESTAMP}.md"
            echo "## $agent"
            echo ""
            if [[ -f "$report" ]]; then
                cat "$report"
            else
                echo "*No report generated.*"
            fi
            echo ""
            echo "---"
            echo ""
        done
    } > "$summary_file"

    echo ""
    echo "Summary: $summary_file"
}

# --- Main ---

mkdir -p "$REVIEWS_DIR"

case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
    --list)
        list_agents
        exit 0
        ;;
    "")
        # Run all agents in parallel
        echo "Running all review agents..."
        echo ""

        pids=()
        for agent in "${REVIEW_AGENTS[@]}"; do
            run_agent "$agent" &
            pids+=($!)
        done

        # Wait for all agents
        failed=0
        for pid in "${pids[@]}"; do
            if ! wait "$pid"; then
                failed=$((failed + 1))
            fi
        done

        generate_summary

        if [[ $failed -gt 0 ]]; then
            echo ""
            echo "WARNING: $failed agent(s) had errors."
            exit 1
        fi
        ;;
    *)
        # Run specific agent
        agent="$1"
        valid=false
        for a in "${REVIEW_AGENTS[@]}"; do
            if [[ "$a" == "$agent" ]]; then
                valid=true
                break
            fi
        done

        if [[ "$valid" != true ]]; then
            echo "ERROR: Unknown agent '$agent'" >&2
            echo "Run with --list to see available agents." >&2
            exit 1
        fi

        run_agent "$agent"
        ;;
esac

#!/usr/bin/env bash
#
# Test script that runs each DQL .txt file from the tour in order and verifies
# they complete successfully against a local Dgraph instance.
#
# Usage: ./tests/test_tour_dql.sh
#
# Requirements:
#   - Dgraph running at localhost:8080
#   - curl and jq installed
#
set -euo pipefail

# Configuration
DGRAPH_ALPHA="${DGRAPH_ALPHA:-http://localhost:8080}"
CONTENT_DIR="${CONTENT_DIR:-content}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# DQL sections in tour order (from config.toml weights)
DQL_SECTIONS=(
    "intro"
    "basic"
    "schema"
    "moredata"
    "blocksvars"
    "search"
)

# Check if Dgraph is running
check_dgraph() {
    echo -e "${BLUE}Checking Dgraph health...${NC}"
    if ! curl -s "${DGRAPH_ALPHA}/health" | grep -q '"status":"healthy"'; then
        echo -e "${RED}Error: Dgraph is not running at ${DGRAPH_ALPHA}${NC}"
        echo "Please start Dgraph with: make setup"
        exit 1
    fi
    echo -e "${GREEN}Dgraph is healthy${NC}"
    echo ""
}

# Determine the type of DQL content and appropriate endpoint
# Returns: "query", "mutation", "schema", or "skip"
detect_dql_type() {
    local file="$1"
    local content
    content=$(cat "$file")

    # Skip empty files or files with only whitespace/comments
    local stripped
    stripped=$(echo "$content" | sed 's/#.*//g' | tr -d '[:space:]')
    if [[ -z "$stripped" ]] || [[ "$stripped" == "{}" ]]; then
        echo "skip"
        return
    fi

    # Check for pseudo-code / example syntax that won't execute
    if echo "$content" | grep -qE 'not_a_real_query|some_edge|\.\.\.'; then
        echo "skip"
        return
    fi

    # Check for mutation (set or delete blocks)
    # Handle both { set { and separate line { \n set { formats
    if echo "$content" | grep -qE '^\s*(set|delete)\s*\{'; then
        # Check if mutation body is only comments
        local mutation_body
        mutation_body=$(echo "$content" | sed -n '/set\s*{/,/}/p' | sed 's/#.*//g' | tr -d '[:space:]')
        if [[ "$mutation_body" == "set{}" ]] || [[ "$mutation_body" == "delete{}" ]]; then
            echo "skip"
            return
        fi
        echo "mutation"
        return
    fi

    # Check for schema query (schema(pred: [...]) - this is a DQL query not schema alteration)
    if echo "$content" | grep -qE '^\s*schema\s*\('; then
        echo "query"
        return
    fi

    # Check for schema alteration (doesn't start with { or contains type definitions at top level)
    local first_nonblank
    first_nonblank=$(echo "$content" | grep -v '^\s*$' | grep -v '^\s*#' | head -1)
    if [[ ! "$first_nonblank" =~ ^\s*\{ ]]; then
        # This is schema/alter content
        echo "schema"
        return
    fi

    # Check if it's a query (contains func:)
    if echo "$content" | grep -qE 'func\s*:'; then
        echo "query"
        return
    fi

    # Default: try as query
    echo "query"
}

# Execute a DQL query
run_query() {
    local file="$1"
    local query
    query=$(cat "$file")

    # Escape the query for JSON
    local json_query
    json_query=$(jq -n --arg q "$query" '{query: $q}')

    local response
    response=$(curl -s -X POST "${DGRAPH_ALPHA}/query" \
        -H "Content-Type: application/json" \
        -d "$json_query" 2>&1)

    echo "$response"
}

# Execute a DQL mutation
# The mutation files contain { set { ... } } or { delete { ... } } format
# Send directly as application/rdf with --data-binary to preserve newlines
run_mutation() {
    local file="$1"

    local response
    response=$(curl -s -X POST "${DGRAPH_ALPHA}/mutate?commitNow=true" \
        -H "Content-Type: application/rdf" \
        --data-binary "@${file}" 2>&1)

    echo "$response"
}

# Execute a schema alteration
run_schema() {
    local file="$1"

    local response
    response=$(curl -s -X POST "${DGRAPH_ALPHA}/alter" \
        --data-binary "@${file}" 2>&1)

    echo "$response"
}

# Check if response indicates success
check_response() {
    local response="$1"
    local type="$2"

    # Check for errors in JSON response
    if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        return 1
    fi

    # For queries and mutations, check for data
    if [[ "$type" == "query" ]]; then
        if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    # For mutations, check for data with uids or successful empty response
    if [[ "$type" == "mutation" ]]; then
        if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
            return 0
        fi
        # Check for RDF mutation response format
        if echo "$response" | jq -e '.code == "Success"' > /dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    # For schema, check for success code
    if [[ "$type" == "schema" ]]; then
        if echo "$response" | jq -e '.data.code == "Success"' > /dev/null 2>&1; then
            return 0
        fi
        # Also accept empty data response for schema
        if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    return 1
}

# Get sorted list of numbered .txt files in a section (as array)
get_section_files() {
    local section="$1"
    local section_dir="${PROJECT_DIR}/${CONTENT_DIR}/${section}"
    local -a files=()

    if [[ ! -d "$section_dir" ]]; then
        return
    fi

    # Find the maximum file number in this section
    local max_num=0
    for f in "$section_dir"/*.txt; do
        [[ -f "$f" ]] || continue
        local fname
        fname=$(basename "$f" .txt)
        if [[ "$fname" =~ ^[0-9]+$ ]] && (( fname > max_num )); then
            max_num=$fname
        fi
    done

    # Output files in numerical order
    for ((i=1; i<=max_num; i++)); do
        local f="${section_dir}/${i}.txt"
        if [[ -f "$f" ]]; then
            echo "$f"
        fi
    done
}

# Run tests for a single file
test_file() {
    local file="$1"
    local section="$2"
    local num
    num=$(basename "$file" .txt)
    local display_name="${section}/${num}.txt"

    local type
    type=$(detect_dql_type "$file")

    if [[ "$type" == "skip" ]]; then
        echo -e "${YELLOW}SKIP${NC}  ${display_name} (empty or placeholder)"
        ((SKIPPED++)) || true
        return 0
    fi

    local response
    case "$type" in
        query)
            response=$(run_query "$file")
            ;;
        mutation)
            response=$(run_mutation "$file")
            ;;
        schema)
            response=$(run_schema "$file")
            ;;
        *)
            echo -e "${YELLOW}SKIP${NC}  ${display_name} (unknown type)"
            ((SKIPPED++)) || true
            return 0
            ;;
    esac

    if check_response "$response" "$type"; then
        echo -e "${GREEN}PASS${NC}  ${display_name} (${type})"
        ((PASSED++)) || true
    else
        echo -e "${RED}FAIL${NC}  ${display_name} (${type})"
        echo "Response: $(echo "$response" | jq -c . 2>/dev/null || echo "$response")"
        ((FAILED++)) || true
    fi
}

# Main execution
main() {
    echo "=============================================="
    echo "  DQL Tour Query Test Suite"
    echo "=============================================="
    echo ""

    check_dgraph

    echo "Running DQL tests in tour order..."
    echo ""

    for section in "${DQL_SECTIONS[@]}"; do
        echo -e "${BLUE}=== Section: ${section} ===${NC}"

        # Read files into array to avoid stdin interference with curl
        local -a files=()
        mapfile -t files < <(get_section_files "$section")

        for file in "${files[@]}"; do
            [[ -z "$file" ]] && continue
            test_file "$file" "$section"
        done

        echo ""
    done

    echo "=============================================="
    echo "  Results"
    echo "=============================================="
    echo -e "${GREEN}Passed:${NC}  $PASSED"
    echo -e "${RED}Failed:${NC}  $FAILED"
    echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
    echo ""

    if [[ $FAILED -gt 0 ]]; then
        echo -e "${RED}Some DQL tests failed!${NC}"
        exit 1
    else
        echo -e "${GREEN}All DQL tests passed!${NC}"
        exit 0
    fi
}

main "$@"

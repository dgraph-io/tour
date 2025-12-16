#!/usr/bin/env bash
#
# Test script that runs each GraphQL .txt file from the tour in order and verifies
# they complete successfully against a local Dgraph instance.
#
# Usage: ./tests/test_tour_graphql.sh
#
# Requirements:
#   - Dgraph running at localhost:8080
#   - curl and jq installed
#
set -euo pipefail

# Configuration
DGRAPH_ALPHA="${DGRAPH_ALPHA:-http://localhost:8080}"
GRAPHQL_ENDPOINT="${DGRAPH_ALPHA}/graphql"
ADMIN_ENDPOINT="${DGRAPH_ALPHA}/admin"
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

# GraphQL sections in tour order (from config.toml weights)
GRAPHQL_SECTIONS=(
    "graphqlintro"
    "graphqlbasic"
    "graphqlschema"
    "graphqlsearch"
    "graphqlmoredata"
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

# Check if GraphQL endpoint is available
check_graphql() {
    echo -e "${BLUE}Checking GraphQL endpoint...${NC}"
    local response
    response=$(curl -s -X POST "${GRAPHQL_ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d '{"query": "{ __typename }"}' 2>&1)

    if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
        echo -e "${GREEN}GraphQL endpoint is available${NC}"
        echo ""
        return 0
    fi

    echo -e "${YELLOW}GraphQL endpoint not configured yet${NC}"
    echo ""
    return 1
}

# Apply GraphQL schema
apply_schema() {
    local schema="$1"

    # Wrap schema in the updateGQLSchema mutation
    local mutation
    mutation=$(jq -n --arg schema "$schema" '{
        query: "mutation($schema: String!) { updateGQLSchema(input: { set: { schema: $schema } }) { gqlSchema { schema } } }",
        variables: { schema: $schema }
    }')

    local response
    response=$(curl -s -X POST "${ADMIN_ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d "$mutation" 2>&1)

    echo "$response"
}

# Determine the type of GraphQL content
# Returns: "query", "mutation", "schema", or "skip"
detect_graphql_type() {
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

    # Check for placeholder comments like "# change this line" or "# Write any query"
    if echo "$content" | grep -qiE '^\s*#.*change this|^\s*#.*write any'; then
        # If it's only a comment, skip
        local non_comment_lines
        non_comment_lines=$(echo "$content" | grep -v '^\s*#' | grep -v '^\s*$' | wc -l)
        if [[ "$non_comment_lines" -eq 0 ]]; then
            echo "skip"
            return
        fi
    fi

    # Check for type definitions (GraphQL schema)
    if echo "$content" | grep -qE '^\s*type\s+[A-Z]'; then
        echo "schema"
        return
    fi

    # Check for mutation keyword
    if echo "$content" | grep -qE '^\s*mutation(\s|\{|$)'; then
        echo "mutation"
        return
    fi

    # Check for query keyword or bare query starting with {
    if echo "$content" | grep -qE '^\s*query(\s|\{|$)' || echo "$content" | grep -qE '^\s*\{'; then
        echo "query"
        return
    fi

    # Default: skip unknown content
    echo "skip"
}

# Execute a GraphQL query or mutation
run_graphql() {
    local file="$1"
    local content
    content=$(cat "$file")

    # Escape the query for JSON
    local json_query
    json_query=$(jq -n --arg q "$content" '{query: $q}')

    local response
    response=$(curl -s -X POST "${GRAPHQL_ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d "$json_query" 2>&1)

    echo "$response"
}

# Check if response indicates success
check_response() {
    local response="$1"
    local type="$2"

    # Check for errors in JSON response
    if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        # Some errors are acceptable (like "no data" on empty results)
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // ""')

        # If we also have data, it might be a partial success
        if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
            # Check if data is not null
            if ! echo "$response" | jq -e '.data == null' > /dev/null 2>&1; then
                return 0
            fi
        fi
        return 1
    fi

    # For queries and mutations, check for data
    if [[ "$type" == "query" ]] || [[ "$type" == "mutation" ]]; then
        if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    # For schema, check for gqlSchema in response
    if [[ "$type" == "schema" ]]; then
        if echo "$response" | jq -e '.data.updateGQLSchema.gqlSchema' > /dev/null 2>&1; then
            return 0
        fi
        # Also check for direct schema response
        if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    return 1
}

# Get sorted list of numbered .txt files in a section
get_section_files() {
    local section="$1"
    local section_dir="${PROJECT_DIR}/${CONTENT_DIR}/${section}"

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
    type=$(detect_graphql_type "$file")

    if [[ "$type" == "skip" ]]; then
        echo -e "${YELLOW}SKIP${NC}  ${display_name} (empty or placeholder)"
        ((SKIPPED++)) || true
        return 0
    fi

    local response
    case "$type" in
        query|mutation)
            response=$(run_graphql "$file")
            ;;
        schema)
            local schema_content
            schema_content=$(cat "$file")
            response=$(apply_schema "$schema_content")
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
    echo "  GraphQL Tour Query Test Suite"
    echo "=============================================="
    echo ""

    check_dgraph

    # Check if GraphQL is already configured
    if ! check_graphql; then
        echo "GraphQL schema needs to be applied first."
        echo "Looking for initial schema in graphqlintro/2.txt..."
        echo ""
    fi

    echo "Running GraphQL tests in tour order..."
    echo ""

    for section in "${GRAPHQL_SECTIONS[@]}"; do
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
        echo -e "${RED}Some GraphQL tests failed!${NC}"
        exit 1
    else
        echo -e "${GREEN}All GraphQL tests passed!${NC}"
        exit 0
    fi
}

main "$@"

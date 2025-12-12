#!/usr/bin/env bash
#
# Test script that verifies the 1million dataset relationships are loaded correctly.
#
# Usage: ./tests/test_1million_dataset.sh
#
# Requirements:
#   - Dgraph running at localhost:8080
#   - curl and jq installed
#
set -euo pipefail

# Configuration
DGRAPH_ALPHA="${DGRAPH_ALPHA:-http://localhost:8080}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "=== DQL Relationship Tests ==="

check_dql() {
    local name="$1"
    local query="$2"
    response=$(curl -s -X POST "${DGRAPH_ALPHA}/query" -H "Content-Type: application/json" -d "$query")
    if echo "$response" | jq -e '.data' > /dev/null 2>&1 && ! echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}  $name"
    else
        echo -e "${RED}FAIL${NC}  $name"
        echo "$response" | jq .
        exit 1
    fi
}

check_dql "1. Film with relationships" '{"query": "{ films(func: has(genre), first: 2) { name@. tagline@. initial_release_date genre { name@. } country { name@. } rating { name@. } rated { name@. } starring(first: 2) { performance.character_note@. } } }"}'
check_dql "2. Director -> Film" '{"query": "{ directors(func: has(director.film), first: 2) { name@. director.film(first: 2) { name@. genre { name@. } } } }"}'
check_dql "3. Actor -> Performance" '{"query": "{ actors(func: has(actor.film), first: 2) { name@. actor.film(first: 2) { performance.character_note@. } } }"}'
check_dql "4. Genre reverse (~genre)" '{"query": "{ genres(func: has(~genre), first: 2) { name@. ~genre(first: 2) { name@. } } }"}'
check_dql "5. Country reverse (~country)" '{"query": "{ countries(func: has(~country), first: 2) { name@. ~country(first: 2) { name@. } } }"}'

echo ""
echo -e "${GREEN}All relationship tests passed!${NC}"
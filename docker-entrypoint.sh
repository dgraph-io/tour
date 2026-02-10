#!/bin/bash
set -e

# Configuration
DGRAPH_ALPHA="${DGRAPH_ALPHA:-http://tour-dgraph:8080}"
HUGO_PORT="${HUGO_PORT:-1313}"

echo "=== Dgraph Tour Container ==="
echo "DGRAPH_ALPHA: ${DGRAPH_ALPHA}"
echo "HUGO_PORT: ${HUGO_PORT}"
echo ""

# Wait for Dgraph to be healthy
wait_for_dgraph() {
    echo "Waiting for Dgraph to be healthy..."
    local timeout=120
    while ! curl -s "${DGRAPH_ALPHA}/health" 2>/dev/null | grep -q '"status":"healthy"'; do
        sleep 1
        timeout=$((timeout - 1))
        if [[ $timeout -le 0 ]]; then
            echo "Timeout waiting for Dgraph health endpoint"
            exit 1
        fi
    done
    echo "Dgraph health endpoint ready"

    # Wait for admin endpoint
    timeout=60
    while ! curl -s -X POST "${DGRAPH_ALPHA}/admin" -H "Content-Type: application/json" \
        -d '{"query":"{ health { status } }"}' 2>/dev/null | grep -q '"status":"healthy"'; do
        sleep 1
        timeout=$((timeout - 1))
        if [[ $timeout -le 0 ]]; then
            echo "Timeout waiting for Dgraph admin endpoint"
            exit 1
        fi
    done
    echo "Dgraph admin endpoint ready"
}

# Seed the intro dataset
seed_intro_dataset() {
    echo ""

    # Check if data already exists by querying for a known record
    response=$(curl -s -X POST "${DGRAPH_ALPHA}/query" -H "Content-Type: application/json" \
        -d '{"query": "{ q(func: eq(name, \"Michael\")) { uid } }"}')
    if echo "$response" | jq -e '.data.q | length > 0' > /dev/null 2>&1; then
        echo "Tour data already exists, skipping seed."
        return 0
    fi

    echo "Loading tour DQL schema..."
    response=$(curl -s -X POST "${DGRAPH_ALPHA}/alter" -H "Content-Type: application/rdf" --data-binary @content/intro/2.txt)
    if ! echo "$response" | jq -e '.data.code == "Success"' > /dev/null 2>&1; then
        echo "Failed to load DQL schema: $response"
        exit 1
    fi

    echo "Loading tour example data..."
    response=$(curl -s -X POST "${DGRAPH_ALPHA}/mutate?commitNow=true" -H "Content-Type: application/rdf" --data-binary @content/intro/3.txt)
    if ! echo "$response" | jq -e '.data.code == "Success"' > /dev/null 2>&1; then
        echo "Failed to load tour data: $response"
        exit 1
    fi

    echo "Loading GraphQL schema..."
    schema_content=$(cat content/graphqlintro/2.txt)
    mutation=$(jq -n --arg schema "$schema_content" '{query:"mutation($schema: String!) { updateGQLSchema(input: { set: { schema: $schema } }) { gqlSchema { schema } } }", variables:{schema:$schema}}')
    response=$(curl -s -X POST "${DGRAPH_ALPHA}/admin" -H "Content-Type: application/json" -d "$mutation")
    if echo "$response" | jq -e '.errors' > /dev/null 2>&1 || ! echo "$response" | jq -e '.data.updateGQLSchema.gqlSchema.schema' > /dev/null 2>&1; then
        echo "Failed to load GraphQL schema: $response"
        exit 1
    fi

    echo "Loading GraphQL example data..."
    mutation_content=$(cat content/graphqlintro/3.txt)
    payload=$(jq -n --arg query "$mutation_content" '{query:$query}')
    response=$(curl -s -X POST "${DGRAPH_ALPHA}/graphql" -H "Content-Type: application/json" -d "$payload")
    if echo "$response" | jq -e '.errors' > /dev/null 2>&1 || ! echo "$response" | jq -e '.data' > /dev/null 2>&1; then
        echo "Failed to load GraphQL example data: $response"
        exit 1
    fi

    echo "Tour dataset loaded successfully"
}

# Start Hugo server
start_hugo() {
    echo ""

    # Create default releases.json if it doesn't exist
    if [[ ! -f releases.json ]]; then
        echo "Creating default releases.json..."
        cat > releases.json << 'EOF'
{"params": {"latestRelease": "master", "tourReleases": ["master"], "thisRelease": "master", "home": "http://localhost:1313/tour/"}}
EOF
    fi

    echo "Starting Hugo server on port ${HUGO_PORT}..."
    exec hugo server \
        --bind 0.0.0.0 \
        --port "${HUGO_PORT}" \
        --baseURL "http://localhost:${HUGO_PORT}/" \
        --config config.toml,releases.json \
        --watch
}

# Main
case "${1:-server}" in
    server)
        wait_for_dgraph
        seed_intro_dataset
        start_hugo
        ;;
    seed)
        wait_for_dgraph
        seed_intro_dataset
        ;;
    hugo)
        start_hugo
        ;;
    *)
        exec "$@"
        ;;
esac

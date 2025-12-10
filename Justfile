# Use bash for all recipes
set shell := ["bash", "-cu"]

# Private task to setup Darwin/macOS dependencies
_setup-darwin:
    #!/usr/bin/env bash
    [[ "$(uname)" == "Darwin" ]] || exit 0
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    if ! command -v hugo &> /dev/null; then
        echo "Installing hugo..."
        brew install hugo
    fi
    if ! command -v docker &> /dev/null; then
        echo "Installing docker..."
        brew install --cask docker
    fi

# Private task to setup deps on Ubuntu-derived linux distros (Mint, Pop!_OS, etc.)
_setup-ubuntu-derived-linux:
    #!/usr/bin/env bash
    command -v apt &> /dev/null || exit 0
    if ! command -v hugo &> /dev/null; then
        sudo apt install -y hugo
    fi
    if ! command -v docker &> /dev/null; then
        sudo apt install -y docker.io
    fi

# Private task to create required directories
_ensure-docker-dgraph-mount-dir:
    [[ -d docker/dgraph ]] || mkdir -p docker/dgraph

# Run local development server with hot reload
_start_server: setup
    hugo server -w --baseURL=http://localhost:8000/ --config config.toml,releases.json

# Public task that runs platform-specific setup
setup: _setup-darwin _setup-ubuntu-derived-linux _ensure-docker-dgraph-mount-dir _cluster-up _data-and-schemas


run: setup _start_server
    open http://localhost:8000/

# Start Dgraph and Ratel containers
docker-compose-up:
    docker compose up -d

# Stop Dgraph and Ratel containers
docker-compose-down:
    docker compose down

# Private task to ensure docker compose is running
_cluster-up:
    #!/usr/bin/env bash
    if ! docker compose ps --status running 2>/dev/null | grep -q dgraph-tutorial; then
        just docker-compose-up
    fi

# Private task to ensure docker compose is stopped
_cluster-down:
    #!/usr/bin/env bash
    if docker compose ps --status running 2>/dev/null | grep -q dgraph-tutorial; then
        just docker-compose-down
    fi

# Reset Dgraph data and reload sample dataset
reset: _cluster-down
    [[ -d docker/dgraph ]] && rm -rf docker/dgraph
    just setup

# Private task to download and load sample dataset into Dgraph
_data-and-schemas: _cluster-up
    #!/usr/bin/env bash
    # Wait for Dgraph to be healthy
    echo "Waiting for Dgraph to be ready..."
    until curl -s http://localhost:8080/health | grep -q '"status":"healthy"'; do
        sleep 1
    done
    # Wait for GraphQL admin to be ready
    echo "Waiting for GraphQL admin..."
    until curl -s -X POST http://localhost:8080/admin -H "Content-Type: application/json" -d '{"query":"{ health { status } }"}' | grep -q '"status":"healthy"'; do
        sleep 1
    done
    # Check if data is already loaded by querying for any node with a genre predicate
    count=$(curl -s -H "Content-Type: application/json" "http://localhost:8080/query" -d '{"query": "{ count(func: has(genre), first: 1) { count(uid) } }"}' | grep -o '"count":[0-9]\+' | tail -1 | grep -o '[0-9]\+' || echo "0")
    if [[ "$count" == "0" || -z "$count" ]]; then
      # Push GraphQL schema FIRST so types are registered before data load
      echo "Pushing GraphQL schema..."
      curl -s -X POST http://localhost:8080/admin/schema --data-binary '@resources/1million.graphql'
      echo ""
      # Now load the RDF data
      [[ -s docker/dgraph/1million.rdf.gz ]] || cp resources/1million.rdf.gz docker/dgraph/
      [[ -s docker/dgraph/1million.schema ]] || cp resources/1million.schema docker/dgraph/
      docker exec dgraph-tutorial dgraph live -f 1million.rdf.gz -s 1million.schema
      [[ -s docker/dgraph/1million.rdf.gz ]] && rm docker/dgraph/1million.rdf.gz
      [[ -s docker/dgraph/1million.schema ]] && rm docker/dgraph/1million.schema
      # Add dgraph.type labels so GraphQL can find the data
      echo "Adding type labels for GraphQL..."
      curl -s -X POST "http://localhost:8080/mutate?commitNow=true" -H "Content-Type: application/json" -d '{"query": "{ v as var(func: has(genre)) }", "set": { "uid": "uid(v)", "dgraph.type": "Film" }}' > /dev/null
      curl -s -X POST "http://localhost:8080/mutate?commitNow=true" -H "Content-Type: application/json" -d '{"query": "{ v as var(func: has(director.film)) }", "set": { "uid": "uid(v)", "dgraph.type": "Director" }}' > /dev/null
      curl -s -X POST "http://localhost:8080/mutate?commitNow=true" -H "Content-Type: application/json" -d '{"query": "{ v as var(func: has(actor.film)) }", "set": { "uid": "uid(v)", "dgraph.type": "Actor" }}' > /dev/null
      # Label genres (nodes referenced by ~genre reverse edge)
      curl -s -X POST "http://localhost:8080/mutate?commitNow=true" -H "Content-Type: application/json" -d '{"query": "{ v as var(func: has(~genre)) }", "set": { "uid": "uid(v)", "dgraph.type": "Genre" }}' > /dev/null
      echo "Done"
    fi

# Run all tests
test: _test-dql _test-graphql

# Test DQL schema with sample queries for all node types and relationships
_test-dql:
    #!/usr/bin/env bash
    check_dql() {
      local name="$1"
      local query="$2"
      response=$(curl -s -X POST http://localhost:8080/query -H "Content-Type: application/json" -d "$query")
      if echo "$response" | jq -e '.data' > /dev/null 2>&1 && ! echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        echo "$name: Success"
      else
        echo "$name: FAILED"
        echo "$response" | jq .
        exit 1
      fi
    }
    echo "=== DQL Relationship Tests ==="
    check_dql "1. Film with relationships" '{"query": "{ films(func: has(genre), first: 2) { name@. tagline@. initial_release_date genre { name@. } country { name@. } rating { name@. } rated { name@. } starring(first: 2) { performance.character_note@. } } }"}'
    check_dql "2. Director -> Film" '{"query": "{ directors(func: has(director.film), first: 2) { name@. director.film(first: 2) { name@. genre { name@. } } } }"}'
    check_dql "3. Actor -> Performance" '{"query": "{ actors(func: has(actor.film), first: 2) { name@. actor.film(first: 2) { performance.character_note@. } } }"}'
    check_dql "4. Genre reverse (~genre)" '{"query": "{ genres(func: has(~genre), first: 2) { name@. ~genre(first: 2) { name@. } } }"}'
    check_dql "5. Country reverse (~country)" '{"query": "{ countries(func: has(~country), first: 2) { name@. ~country(first: 2) { name@. } } }"}'

# Test GraphQL schema with sample queries for all node types and relationships
_test-graphql:
    #!/usr/bin/env bash
    check_gql() {
      local name="$1"
      local query="$2"
      response=$(curl -s -X POST http://localhost:8080/graphql -H "Content-Type: application/json" -d "$query")
      if echo "$response" | jq -e '.data' > /dev/null 2>&1 && ! echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        echo "$name: Success"
      else
        echo "$name: FAILED"
        echo "$response" | jq .
        exit 1
      fi
    }
    echo "=== GraphQL Relationship Tests ==="
    check_gql "1. Film -> relationships" '{"query": "{ queryFilm(first: 2) { name tagline initial_release_date genre { name } country { name } rating { name } rated { name } starring(first: 2) { character_note } } }"}'
    check_gql "2. Director -> Film" '{"query": "{ queryDirector(first: 2) { name films(first: 2) { name genre { name } } } }"}'
    check_gql "3. Actor -> Performance" '{"query": "{ queryActor(first: 2) { name films(first: 2) { character_note } } }"}'
    check_gql "4. Genre -> Film (reverse)" '{"query": "{ queryGenre(first: 2) { name films(first: 2) { name } } }"}'
    check_gql "5. Country -> Film (reverse)" '{"query": "{ queryCountry(first: 2) { name films(first: 2) { name } } }"}'
    check_gql "6. Rating -> Film (reverse)" '{"query": "{ queryRating(first: 2) { name films(first: 2) { name } } }"}'
    check_gql "7. ContentRating -> Film (reverse)" '{"query": "{ queryContentRating(first: 2) { name films(first: 2) { name } } }"}'


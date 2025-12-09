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
_setup-docker-dgraph-mount:
    mkdir -p docker/dgraph

# Public task that runs platform-specific setup
setup: _setup-darwin _setup-ubuntu-derived-linux _setup-docker-dgraph-mount _setup-sample-data

# Run local development server with hot reload
dev: setup
    ./scripts/local.sh

# Start Dgraph and Ratel containers
docker-compose-up:
    docker compose up -d

# Stop Dgraph and Ratel containers
docker-compose-down:
    docker compose down

# Private task to ensure docker compose is running
_ensure-docker-compose-up:
    #!/usr/bin/env bash
    if ! docker compose ps --status running 2>/dev/null | grep -q dgraph-tutorial; then
        just docker-compose-up
    fi

# Private task to download and load sample dataset into Dgraph
_setup-sample-data: _ensure-docker-compose-up
    #!/usr/bin/env bash
    if [[ ! -s docker/dgraph/1million.rdf.gz ]]; then
        curl -LO --output-dir docker/dgraph https://github.com/dgraph-io/dgraph-benchmarks/raw/refs/heads/main/data/1million.rdf.gz
    fi
    if [[ ! -s docker/dgraph/1million.schema ]]; then
        curl -LO --output-dir docker/dgraph https://raw.githubusercontent.com/dgraph-io/dgraph-benchmarks/refs/heads/main/data/1million.schema
    fi
    # Check if data is already loaded by querying for any node with a genre predicate
    count=$(curl -s -H "Content-Type: application/json" "http://localhost:8080/query" -d '{"query": "{ count(func: has(genre), first: 1) { count(uid) } }"}' | grep -o '"count":[0-9]\+' | tail -1 | grep -o '[0-9]\+' || echo "0")
    if [[ "$count" == "0" || -z "$count" ]]; then
        docker exec dgraph-tutorial dgraph live -f 1million.rdf.gz -s 1million.schema
    fi

# Use bash for all recipes
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# Default target
.DEFAULT_GOAL := help

# Mark all targets as phony (not files)
.PHONY: help setup run reset test docker-compose-up docker-compose-down \
        _deps-darwin _deps-linux-apt _docker-dgraph-dir _cluster-up _cluster-down \
        _schema-and-data _start-server _test-dql _test-graphql

# ============================================================================
# Public Tasks
# ============================================================================

## Show this help message
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
	@echo ""
	@echo "  setup              Install dependencies, start Dgraph, and load sample data"
	@echo "  run                Start Hugo development server with hot reload"
	@echo "  reset              Reset Dgraph data and reload sample dataset"
	@echo "  test               Run all tests (DQL and GraphQL)"
	@echo "  docker-compose-up  Start Dgraph and Ratel containers"
	@echo "  docker-compose-down Stop Dgraph and Ratel containers"

## Install dependencies, start Dgraph, and load sample data
setup: _deps-darwin _deps-linux-apt _docker-dgraph-dir _cluster-up _schema-and-data

## Start Hugo development server with hot reload
run: setup _start-server

## Reset Dgraph data and reload sample dataset
reset: _cluster-down
	@[[ -d docker/dgraph ]] && rm -rf docker/dgraph || true
	@$(MAKE) setup

## Run all tests (DQL and GraphQL)
test: _test-dql _test-graphql

## Start Dgraph and Ratel containers
docker-compose-up:
	docker compose up -d

## Stop Dgraph and Ratel containers
docker-compose-down:
	docker compose down

# ============================================================================
# Private Setup Tasks
# ============================================================================

# Install platform dependencies (hugo, docker, node, npm, npx) on macOS
_deps-darwin:
	@if [[ "$$(uname)" == "Darwin" ]]; then \
		(command -v brew &> /dev/null) || { echo "Installing Homebrew..." && /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; }; \
		(command -v hugo &> /dev/null) || { echo "Installing hugo..." && brew install hugo; }; \
		(command -v docker &> /dev/null) || { echo "Installing docker..." && brew install --cask docker; }; \
		(command -v node &> /dev/null) || { echo "Installing node..." && brew install node; }; \
		(command -v npm &> /dev/null) || { echo "Installing npm..." && brew install npm; }; \
		(command -v npx &> /dev/null) || { echo "Installing npx..." && npm install -g npx; }; \
	fi

# Install platform dependencies (hugo, docker, node, npm, npx) on Ubuntu/Debian
_deps-linux-apt:
	@if command -v apt &> /dev/null; then \
		(command -v hugo &> /dev/null) || sudo apt install -y hugo; \
		(command -v docker &> /dev/null) || sudo apt install -y docker.io; \
		(command -v node &> /dev/null) || sudo apt install -y nodejs; \
		(command -v npm &> /dev/null) || sudo apt install -y npm; \
		(command -v npx &> /dev/null) || { echo "Installing npx..." && sudo npm install -g npx; }; \
	fi

_docker-dgraph-dir:
	@[[ -d docker/dgraph ]] || mkdir -p docker/dgraph

# ============================================================================
# Private Docker Tasks
# ============================================================================

_cluster-up:
	@if ! docker compose ps --status running 2>/dev/null | grep -q dgraph-tutorial; then \
		$(MAKE) docker-compose-up; \
	fi

_cluster-down:
	@if docker compose ps --status running 2>/dev/null | grep -q dgraph-tutorial; then \
		$(MAKE) docker-compose-down; \
	fi

# ============================================================================
# Private Data Loading Tasks
# ============================================================================

_schema-and-data: _cluster-up
	@echo "Waiting for Dgraph to be ready..."
	@until curl -s http://localhost:8080/health | grep -q '"status":"healthy"'; do \
		sleep 1; \
	done
	@echo "Waiting for GraphQL admin..."
	@until curl -s -X POST http://localhost:8080/admin -H "Content-Type: application/json" -d '{"query":"{ health { status } }"}' | grep -q '"status":"healthy"'; do \
		sleep 1; \
	done
	@count=$$(curl -s -H "Content-Type: application/json" "http://localhost:8080/query" -d '{"query": "{ count(func: has(genre), first: 1) { count(uid) } }"}' | grep -o '"count":[0-9]\+' | tail -1 | grep -o '[0-9]\+' || echo "0"); \
	if [[ "$$count" == "0" || -z "$$count" ]]; then \
		echo "Pushing GraphQL schema..."; \
		curl -s -X POST http://localhost:8080/admin/schema --data-binary '@resources/1million.graphql'; \
		echo ""; \
		[[ -s docker/dgraph/1million.rdf.gz ]] || cp resources/1million.rdf.gz docker/dgraph/; \
		[[ -s docker/dgraph/1million.schema ]] || cp resources/1million.schema docker/dgraph/; \
		docker exec dgraph-tutorial dgraph live -f 1million.rdf.gz -s 1million.schema; \
		[[ -s docker/dgraph/1million.rdf.gz ]] && rm docker/dgraph/1million.rdf.gz || true; \
		[[ -s docker/dgraph/1million.schema ]] && rm docker/dgraph/1million.schema || true; \
		echo "Adding type labels for GraphQL..."; \
		curl -s -X POST "http://localhost:8080/mutate?commitNow=true" -H "Content-Type: application/json" -d '{"query": "{ v as var(func: has(genre)) }", "set": { "uid": "uid(v)", "dgraph.type": "Film" }}' > /dev/null; \
		curl -s -X POST "http://localhost:8080/mutate?commitNow=true" -H "Content-Type: application/json" -d '{"query": "{ v as var(func: has(director.film)) }", "set": { "uid": "uid(v)", "dgraph.type": "Director" }}' > /dev/null; \
		curl -s -X POST "http://localhost:8080/mutate?commitNow=true" -H "Content-Type: application/json" -d '{"query": "{ v as var(func: has(actor.film)) }", "set": { "uid": "uid(v)", "dgraph.type": "Actor" }}' > /dev/null; \
		curl -s -X POST "http://localhost:8080/mutate?commitNow=true" -H "Content-Type: application/json" -d '{"query": "{ v as var(func: has(~genre)) }", "set": { "uid": "uid(v)", "dgraph.type": "Genre" }}' > /dev/null; \
		echo "Done"; \
	fi

# ============================================================================
# Private Hugo Tasks
# ============================================================================

_start-server: setup
	hugo server -w --baseURL=http://localhost:8000/ --config config.toml,releases.json

# ============================================================================
# Private Test Tasks
# ============================================================================

_test-dql:
	@echo "=== DQL Relationship Tests ==="
	@check_dql() { \
		local name="$$1"; \
		local query="$$2"; \
		response=$$(curl -s -X POST http://localhost:8080/query -H "Content-Type: application/json" -d "$$query"); \
		if echo "$$response" | jq -e '.data' > /dev/null 2>&1 && ! echo "$$response" | jq -e '.errors' > /dev/null 2>&1; then \
			echo "$$name: Success"; \
		else \
			echo "$$name: FAILED"; \
			echo "$$response" | jq .; \
			exit 1; \
		fi; \
	}; \
	check_dql "1. Film with relationships" '{"query": "{ films(func: has(genre), first: 2) { name@. tagline@. initial_release_date genre { name@. } country { name@. } rating { name@. } rated { name@. } starring(first: 2) { performance.character_note@. } } }"}'; \
	check_dql "2. Director -> Film" '{"query": "{ directors(func: has(director.film), first: 2) { name@. director.film(first: 2) { name@. genre { name@. } } } }"}'; \
	check_dql "3. Actor -> Performance" '{"query": "{ actors(func: has(actor.film), first: 2) { name@. actor.film(first: 2) { performance.character_note@. } } }"}'; \
	check_dql "4. Genre reverse (~genre)" '{"query": "{ genres(func: has(~genre), first: 2) { name@. ~genre(first: 2) { name@. } } }"}'; \
	check_dql "5. Country reverse (~country)" '{"query": "{ countries(func: has(~country), first: 2) { name@. ~country(first: 2) { name@. } } }"}'

_test-graphql:
	@echo "=== GraphQL Relationship Tests ==="
	@check_gql() { \
		local name="$$1"; \
		local query="$$2"; \
		response=$$(curl -s -X POST http://localhost:8080/graphql -H "Content-Type: application/json" -d "$$query"); \
		if echo "$$response" | jq -e '.data' > /dev/null 2>&1 && ! echo "$$response" | jq -e '.errors' > /dev/null 2>&1; then \
			echo "$$name: Success"; \
		else \
			echo "$$name: FAILED"; \
			echo "$$response" | jq .; \
			exit 1; \
		fi; \
	}; \
	check_gql "1. Film -> relationships" '{"query": "{ queryFilm(first: 2) { name tagline initial_release_date genre { name } country { name } rating { name } rated { name } starring(first: 2) { character_note } } }"}'; \
	check_gql "2. Director -> Film" '{"query": "{ queryDirector(first: 2) { name films(first: 2) { name genre { name } } } }"}'; \
	check_gql "3. Actor -> Performance" '{"query": "{ queryActor(first: 2) { name films(first: 2) { character_note } } }"}'; \
	check_gql "4. Genre -> Film (reverse)" '{"query": "{ queryGenre(first: 2) { name films(first: 2) { name } } }"}'; \
	check_gql "5. Country -> Film (reverse)" '{"query": "{ queryCountry(first: 2) { name films(first: 2) { name } } }"}'; \
	check_gql "6. Rating -> Film (reverse)" '{"query": "{ queryRating(first: 2) { name films(first: 2) { name } } }"}'; \
	check_gql "7. ContentRating -> Film (reverse)" '{"query": "{ queryContentRating(first: 2) { name films(first: 2) { name } } }"}'

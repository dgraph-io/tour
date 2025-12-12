# Makefile for Dgraph Tour
#
# Usage: make [target]
#
# Run `make help` to see available targets.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Configuration
DGRAPH_ALPHA := http://localhost:8080
HUGO_PORT := 8000

# =============================================================================
# Help
# =============================================================================

.PHONY: help
help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# =============================================================================
# Development
# =============================================================================

.PHONY: setup
setup: deps docker-dir docker-up load-data ## Install dependencies, start Dgraph, and load sample data

.PHONY: start
start: setup server ## Start Hugo development server with hot reload

.PHONY: stop
stop: ## Stop Hugo server and Dgraph containers
	@if pgrep -f "hugo server" > /dev/null; then \
		echo "Stopping Hugo server..."; \
		pkill -f "hugo server" || true; \
	fi
	@if docker compose ps --status running 2>/dev/null | grep -q tour-dgraph; then \
		docker compose down; \
	fi

.PHONY: restart
restart: stop start ## Restart Hugo server and Dgraph containers

.PHONY: reset
reset: ## Reset Dgraph data and reload sample dataset
	@if docker compose ps --status running 2>/dev/null | grep -q tour-dgraph; then \
		docker compose down; \
	fi
	@[[ -d docker/dgraph ]] && rm -rf docker/dgraph || true
	@$(MAKE) setup

# =============================================================================
# Testing
# =============================================================================

.PHONY: test
test: reset test-data test-tour ## Run all tests

.PHONY: test-data
test-data: ## Test 1million dataset relationships
	@echo "=== DQL Relationship Tests ==="
	@check_dql() { \
		local name="$$1"; \
		local query="$$2"; \
		response=$$(curl -s -X POST $(DGRAPH_ALPHA)/query -H "Content-Type: application/json" -d "$$query"); \
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

.PHONY: test-tour
test-tour: ## Test tour example queries
	@./tests/test_tour_dql.sh
	@./tests/test_tour_graphql.sh

# =============================================================================
# Docker
# =============================================================================

.PHONY: docker-up
docker-up: ## Start Dgraph and Ratel containers
	@if ! docker compose ps --status running 2>/dev/null | grep -q tour-dgraph; then \
		docker compose up -d; \
	fi

.PHONY: docker-down
docker-down: ## Stop Dgraph and Ratel containers
	docker compose down

# =============================================================================
# Internal targets (not shown in help)
# =============================================================================

.PHONY: deps
deps:
	@if [[ "$$(uname)" == "Darwin" ]]; then \
		(command -v brew &> /dev/null) || { echo "Installing Homebrew..." && /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; }; \
		(command -v hugo &> /dev/null) || { echo "Installing hugo..." && brew install hugo; }; \
		(command -v docker &> /dev/null) || { echo "Installing docker..." && brew install --cask docker; }; \
		(command -v jq &> /dev/null) || { echo "Installing jq..." && brew install jq; }; \
		(command -v node &> /dev/null) || { echo "Installing node..." && brew install node; }; \
		(command -v npm &> /dev/null) || { echo "Installing npm..." && brew install npm; }; \
		(command -v npx &> /dev/null) || { echo "Installing npx..." && npm install -g npx; }; \
	elif command -v apt &> /dev/null; then \
		(command -v hugo &> /dev/null) || sudo apt install -y hugo; \
		(command -v docker &> /dev/null) || sudo apt install -y docker.io; \
		(command -v jq &> /dev/null) || sudo apt install -y jq; \
		(command -v node &> /dev/null) || sudo apt install -y nodejs; \
		(command -v npm &> /dev/null) || sudo apt install -y npm; \
		(command -v npx &> /dev/null) || { echo "Installing npx..." && sudo npm install -g npx; }; \
	fi

.PHONY: docker-dir
docker-dir:
	@[[ -d docker/dgraph ]] || mkdir -p docker/dgraph

.PHONY: load-data
load-data: docker-up
	@echo "Waiting for Dgraph to be ready..."
	@until curl -s $(DGRAPH_ALPHA)/health | grep -q '"status":"healthy"'; do \
		sleep 1; \
	done
	@echo "Waiting for GraphQL admin..."
	@until curl -s -X POST $(DGRAPH_ALPHA)/admin -H "Content-Type: application/json" -d '{"query":"{ health { status } }"}' | grep -q '"status":"healthy"'; do \
		sleep 1; \
	done
	@count=$$(curl -s -H "Content-Type: application/json" "$(DGRAPH_ALPHA)/query" -d '{"query": "{ count(func: has(genre), first: 1) { count(uid) } }"}' | grep -o '"count":[0-9]\+' | tail -1 | grep -o '[0-9]\+' || echo "0"); \
	if [[ "$$count" == "0" || -z "$$count" ]]; then \
		echo "Loading DQL schema and data..."; \
		[[ -s docker/dgraph/1million.rdf.gz ]] || cp resources/1million.rdf.gz docker/dgraph/; \
		[[ -s docker/dgraph/1million.schema ]] || cp resources/1million.schema docker/dgraph/; \
		docker exec tour-dgraph dgraph live -f 1million.rdf.gz -s 1million.schema; \
		[[ -s docker/dgraph/1million.rdf.gz ]] && rm docker/dgraph/1million.rdf.gz || true; \
		[[ -s docker/dgraph/1million.schema ]] && rm docker/dgraph/1million.schema || true; \
		echo "Done"; \
	fi

.PHONY: server
server:
	hugo server -w --baseURL=http://localhost:$(HUGO_PORT)/ --config config.toml,releases.json

# Makefile for Dgraph Tour
#
# Usage: make [target]
#
# Run `make help` to see available targets.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

.PHONY: help setup start stop restart reset test test-tour-dql test-tour-graphql \
        test-movies-dataset docker-up docker-down deps docker-dir dgraph-healthy load-tour-dataset load-movies-dataset server

# Configuration
DGRAPH_ALPHA := http://localhost:8080
HUGO_PORT := 8000

# =============================================================================
# Help
# =============================================================================

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# =============================================================================
# Development
# =============================================================================

setup: deps docker-dir docker-up ## Install dependencies and start Dgraph

start: setup server ## Start Hugo development server with hot reload

stop: ## Stop Hugo server and Dgraph containers
	@if pgrep -f "hugo server" > /dev/null; then \
		echo "Stopping Hugo server..."; \
		pkill -f "hugo server" || true; \
	fi
	@if docker compose ps --status running 2>/dev/null | grep -q tour-dgraph; then \
		docker compose down; \
	fi

restart: stop start ## Restart Hugo server and Dgraph containers

reset: ## Reset Dgraph data to empty state
	@if docker compose ps --status running 2>/dev/null | grep -q tour-dgraph; then \
		docker compose down; \
	fi
	@[[ -d docker/dgraph ]] && (rm -rf docker/dgraph 2>/dev/null || docker run --rm -v "$(PWD)/docker:/data" alpine rm -rf /data/dgraph) || true
	@$(MAKE) setup

# =============================================================================
# Testing
# =============================================================================

test: setup test-tour-dql test-tour-graphql load-movies-dataset test-movies-dataset ## Run all tests

test-tour-dql: ## Run DQL tour tests
	@./tests/test_tour_dql.sh

test-tour-graphql: ## Run GraphQL tour tests
	@./tests/test_tour_graphql.sh

test-movies-dataset: ## Test movies dataset relationships
	@./tests/test_movies_dataset.sh

# =============================================================================
# Docker
# =============================================================================

docker-up: ## Start Dgraph and Ratel containers
	@if ! docker compose ps --status running 2>/dev/null | grep -q tour-dgraph; then \
		docker compose up -d; \
	fi

docker-down: ## Stop Dgraph and Ratel containers
	docker compose down

# =============================================================================
# Internal targets (not shown in help)
# =============================================================================

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

docker-dir:
	@[[ -d docker/dgraph ]] || mkdir -p docker/dgraph

dgraph-healthy: docker-up
	@timeout=60; while ! curl -s $(DGRAPH_ALPHA)/health | grep -q '"status":"healthy"'; do \
		sleep 1; \
		timeout=$$((timeout - 1)); \
		if [[ $$timeout -le 0 ]]; then echo "Timeout waiting for health endpoint to report healthy status (GET $(DGRAPH_ALPHA)/health)"; exit 1; fi; \
	done
	@timeout=60; while ! curl -s -X POST $(DGRAPH_ALPHA)/admin -H "Content-Type: application/json" -d '{"query":"{ health { status } }"}' | grep -q '"status":"healthy"'; do \
		sleep 1; \
		timeout=$$((timeout - 1)); \
		if [[ $$timeout -le 0 ]]; then echo "Timeout waiting for admin endpoint to report healthy status (POST $(DGRAPH_ALPHA)/admin)"; exit 1; fi; \
	done

load-tour-dataset: dgraph-healthy ## Load the tour sample dataset (DQL + GraphQL)
	@echo "Loading tour DQL schema..."
	@response=$$(curl -s -X POST $(DGRAPH_ALPHA)/alter -H "Content-Type: application/rdf" --data-binary @content/intro/2.txt); \
	if ! echo "$$response" | jq -e '.data.code == "Success"' > /dev/null 2>&1; then \
		echo "Failed to load DQL schema: $$response"; exit 1; \
	fi
	@echo "Loading tour example data..."
	@response=$$(curl -s -X POST $(DGRAPH_ALPHA)/mutate?commitNow=true -H "Content-Type: application/rdf" --data-binary @content/intro/3.txt); \
	if ! echo "$$response" | jq -e '.data.code == "Success"' > /dev/null 2>&1; then \
		echo "Failed to load tour data: $$response"; exit 1; \
	fi
	@echo "Loading GraphQL schema..."
	@schema_content=$$(cat content/graphqlintro/2.txt); \
	mutation=$$(jq -n --arg schema "$$schema_content" '{query:"mutation($$schema: String!) { updateGQLSchema(input: { set: { schema: $$schema } }) { gqlSchema { schema } } }", variables:{schema:$$schema}}'); \
	response=$$(curl -s -X POST $(DGRAPH_ALPHA)/admin -H "Content-Type: application/json" -d "$$mutation"); \
	if echo "$$response" | jq -e '.errors' > /dev/null 2>&1 || ! echo "$$response" | jq -e '.data.updateGQLSchema.gqlSchema.schema' > /dev/null 2>&1; then \
		echo "Failed to load GraphQL schema: $$response"; exit 1; \
	fi
	@echo "Loading GraphQL example data..."
	@mutation_content=$$(cat content/graphqlintro/3.txt); \
	payload=$$(jq -n --arg query "$$mutation_content" '{query:$$query}'); \
	response=$$(curl -s -X POST $(DGRAPH_ALPHA)/graphql -H "Content-Type: application/json" -d "$$payload"); \
	if echo "$$response" | jq -e '.errors' > /dev/null 2>&1 || ! echo "$$response" | jq -e '.data' > /dev/null 2>&1; then \
		echo "Failed to load GraphQL example data: $$response"; exit 1; \
	fi
	@echo "Tour dataset loaded."

load-movies-dataset: dgraph-healthy ## Load the movies dataset into Dgraph
	@count=$$(curl -s -H "Content-Type: application/json" "$(DGRAPH_ALPHA)/query" -d '{"query": "{ count(func: has(genre), first: 1) { count(uid) } }"}' | grep -o '"count":[0-9]\+' | tail -1 | grep -o '[0-9]\+' || echo "0"); \
	if [[ "$$count" == "0" || -z "$$count" ]]; then \
		echo "Loading movies schema and data..."; \
		[[ -s docker/dgraph/1million.rdf.gz ]] || cp resources/1million.rdf.gz docker/dgraph/; \
		[[ -s docker/dgraph/1million.schema ]] || cp resources/1million.schema docker/dgraph/; \
		docker exec tour-dgraph dgraph live -f 1million.rdf.gz -s 1million.schema; \
		[[ -s docker/dgraph/1million.rdf.gz ]] && rm docker/dgraph/1million.rdf.gz || true; \
		[[ -s docker/dgraph/1million.schema ]] && rm docker/dgraph/1million.schema || true; \
		echo "Done"; \
	fi

server:
	hugo server -w --baseURL=http://localhost:$(HUGO_PORT)/ --config config.toml,releases.json

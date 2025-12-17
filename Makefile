# Makefile for Dgraph Tour
#
# Usage: make [target]
#
# Run `make help` to see available targets.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

.PHONY: help \
        start stop reset \
        dev-setup dev-start dev-stop dev-restart \
        test test-template-links test-tour-dql test-tour-graphql test-movie-dataset test-tour-links \
        docker-up docker-stop \
        seed-basic-facets seed-intro-dataset seed-movie-dataset \
        deps-start deps-dev docker-dgraph-dir docker-dgraph-dir-clean dgraph-ready tour-ready hugo-ready

# Configuration
DGRAPH_ALPHA := http://localhost:8080
HUGO_PORT := 1313

# Use local lychee if available, otherwise use Docker
LYCHEE_LOCAL := $(shell command -v lychee 2>/dev/null)
ifdef LYCHEE_LOCAL
  LYCHEE := lychee
  LYCHEE_TEMPLATES_CONFIG := lychee-templates.toml
  LYCHEE_TOUR_CONFIG := lychee-tour.toml
  LYCHEE_ROOT := .
  LYCHEE_CONTENT := 'content/**/*.md' 'themes/**/layouts/**/*.html'
else
  LYCHEE := docker run --rm -v "$(PWD):/input:ro" lycheeverse/lychee
  LYCHEE_TEMPLATES_CONFIG := /input/lychee-templates.toml
  LYCHEE_TOUR_CONFIG := /input/lychee-tour.toml
  LYCHEE_ROOT := /input
  LYCHEE_CONTENT := '/input/content/**/*.md' '/input/themes/**/layouts/**/*.html'
endif

# =============================================================================
# Help
# =============================================================================

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# =============================================================================
# Tour (Docker-based)
# =============================================================================

start: deps-start docker-dgraph-dir docker-up dgraph-ready tour-ready ## Start the tour
	@if command -v open &> /dev/null; then \
		open http://localhost:$(HUGO_PORT)/; \
	else \
		echo "To take the tour, open http://localhost:$(HUGO_PORT)/ in a browser"; \
	fi

stop: docker-stop ## Stop the tour

reset: docker-stop docker-dgraph-dir-clean ## Reset Dgraph data

# =============================================================================
# Development (local Hugo with hot reload)
# =============================================================================

dev-setup: deps-dev docker-dgraph-dir ## Install dev dependencies

dev-start: dev-setup docker-up dgraph-ready ## Start Hugo dev server with hot reload

dev-stop: docker-stop ## Stop Hugo server and Docker containers

dev-restart: dev-stop dev-start ## Restart dev environment

# =============================================================================
# Testing
# =============================================================================

test: reset deps-dev docker-up dgraph-ready hugo-ready test-template-links test-tour-links test-tour-dql test-tour-graphql seed-movie-dataset test-movie-dataset ## Run all tests

test-template-links:
	@echo "Testing external link validity in templates..."
	@$(LYCHEE) --no-progress --config $(LYCHEE_TEMPLATES_CONFIG) --root-dir $(LYCHEE_ROOT) $(LYCHEE_CONTENT)

test-tour-dql:
	@echo "Testing tour DQL queries..."
	@./tests/test_tour_dql.sh

test-tour-graphql:
	@echo "Testing tour graphql queries..."
	@./tests/test_tour_graphql.sh

test-movie-dataset:
	@echo "Testing movies dataset..."
	@./tests/test_movies_dataset.sh

test-tour-links: 
	@echo "Testing link validity in running tour at http://localhost:$(HUGO_PORT)/..."
	@$(LYCHEE) --no-progress --config $(LYCHEE_TOUR_CONFIG) "http://localhost:$(HUGO_PORT)/"

# =============================================================================
# Docker
# =============================================================================

docker-up: ## Start Docker containers
	@if ! docker compose ps --status running 2>/dev/null | grep -q tour-; then \
		docker compose up -d; \
	fi

docker-stop: ## Stop Docker containers
	@if docker compose ps --status running 2>/dev/null | grep -q tour-dgraph; then \
		docker compose down; \
	fi

# =============================================================================
# Data Seeding
# =============================================================================

seed-basic-facets: dgraph-ready ## Seed facet sample data for the facets lesson
	@echo "=== Seeding Facet Sample Data ==="
	@echo ""
	@echo "This mutation adds sample data with facets (edge attributes) for the facets lesson."
	@echo "Facets allow you to store key-value pairs on edges, not just nodes."
	@echo ""
	@echo "Request: POST $(DGRAPH_ALPHA)/mutate?commitNow=true"
	@echo "Content-Type: application/rdf"
	@echo ""
	@echo "Payload (contents of resources/facets.rdf):"
	@echo "─────────────────────────────────"
	@cat resources/facets.rdf
	@echo "─────────────────────────────────"
	@echo ""
	@echo "Executing mutation..."
	@response=$$(curl -s -X POST $(DGRAPH_ALPHA)/mutate?commitNow=true -H "Content-Type: application/rdf" --data-binary @resources/facets.rdf); \
	if ! echo "$$response" | jq -e '.data.code == "Success"' > /dev/null 2>&1; then \
		echo "Failed to load facets data: $$response"; exit 1; \
	fi
	@echo "Facets sample data seeded successfully."

seed-intro-dataset: dgraph-ready ## Load the tour sample dataset (DQL + GraphQL)
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

seed-movie-dataset: dgraph-ready ## Load the movies dataset into Dgraph
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

# =============================================================================
# Internal targets (not shown in help)
# =============================================================================

deps-start:
	@if [[ "$$(uname)" == "Darwin" ]]; then \
		if ! command -v docker &> /dev/null; then \
			(command -v brew &> /dev/null) || { echo "Installing Homebrew..." && /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; }; \
			echo "Installing docker..." && brew install --cask docker; \
		fi; \
	elif command -v apt &> /dev/null; then \
		(command -v docker &> /dev/null) || sudo apt install -y docker.io; \
	fi

deps-dev: deps-start
	@if [[ "$$(uname)" == "Darwin" ]]; then \
		(command -v brew &> /dev/null) || { echo "Installing Homebrew..." && /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; }; \
		(command -v hugo &> /dev/null) || { echo "Installing hugo..." && brew install hugo; }; \
		(command -v jq &> /dev/null) || { echo "Installing jq..." && brew install jq; }; \
		(command -v node &> /dev/null) || { echo "Installing node..." && brew install node; }; \
		(command -v npm &> /dev/null) || { echo "Installing npm..." && brew install npm; }; \
		(command -v npx &> /dev/null) || { echo "Installing npx..." && npm install -g npx; }; \
		(command -v lychee &> /dev/null) || { echo "Installing lychee..." && brew install lychee; }; \
	elif command -v apt &> /dev/null; then \
		(command -v hugo &> /dev/null) || sudo apt install -y hugo; \
		(command -v jq &> /dev/null) || sudo apt install -y jq; \
		(command -v node &> /dev/null) || sudo apt install -y nodejs; \
		(command -v npm &> /dev/null) || sudo apt install -y npm; \
		(command -v npx &> /dev/null) || { echo "Installing npx..." && sudo npm install -g npx; }; \
	fi

docker-dgraph-dir:
	@[[ -d docker/dgraph ]] || mkdir -p docker/dgraph

docker-dgraph-dir-clean:
	@echo "Cleaning dgraph docker data dir (docker/dgraph)"
	@[[ -d docker/dgraph ]] && (rm -rf docker/dgraph 2>/dev/null || docker run --rm -v "$(PWD)/docker:/data" alpine rm -rf /data/dgraph) || true

dgraph-ready:
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

tour-ready:
	@timeout=120; while ! curl -s http://localhost:$(HUGO_PORT)/ > /dev/null 2>&1; do \
		sleep 1; \
		timeout=$$((timeout - 1)); \
		if [[ $$timeout -le 0 ]]; then echo "Timeout waiting for Hugo to be ready at http://localhost:$(HUGO_PORT)/"; exit 1; fi; \
	done

hugo-ready:
	@timeout=120; while ! curl -s http://localhost:$(HUGO_PORT)/ > /dev/null 2>&1; do \
		sleep 1; \
		timeout=$$((timeout - 1)); \
		if [[ $$timeout -le 0 ]]; then echo "Timeout waiting for Hugo to be ready at http://localhost:$(HUGO_PORT)/"; exit 1; fi; \
	done

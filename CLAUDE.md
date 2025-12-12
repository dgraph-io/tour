# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is "A Tour of Dgraph" - a step-by-step tutorial site built with Hugo. The live site is at https://dgraph.io/tour.

## Common Commands

```bash
make setup      # Install dependencies, start Dgraph, and load sample data
make start      # Start Hugo development server with hot reload
make stop       # Stop Hugo server and Dgraph containers
make restart    # Restart Hugo server and Dgraph containers
make reset      # Reset Dgraph data and reload sample dataset
make test       # Run all tests (DQL + GraphQL)
make docker-up  # Start Dgraph and Ratel containers
make docker-down # Stop Dgraph and Ratel containers

# Build for production (commits to published/ folder)
python3 scripts/build.py
```

## Local Services

When running `make start`, the following services are available:
- **Hugo Tour**: http://localhost:8000/ - The tutorial site
- **Dgraph Alpha**: http://localhost:8080/ - GraphQL and DQL endpoints
- **Ratel UI**: http://localhost:8001/ - Dgraph query interface

## Testing

Test scripts in `tests/`:
- `test_1million_dataset.sh` - Validates movie dataset relationships (5 tests)
- `test_tour_dql.sh` - Tests all DQL examples from the tour (42 tests)
- `test_tour_graphql.sh` - Tests all GraphQL examples from the tour (33 tests)

## Architecture

### Content Structure
Tutorial content lives in `content/` as Markdown files, organized by section:

**DQL Sections:**
- `intro/` - Introduction to Dgraph and graph databases
- `basic/` - Querying graph data basics
- `schema/` - Schema operations and mutations
- `moredata/` - Loading larger datasets with dgraph live loader
- `blocksvars/` - Query blocks and variables
- `search/` - Dgraph search features

**GraphQL Sections:**
- `graphqlintro/` - Introduction to GraphQL with Dgraph
- `graphqlbasic/` - Basic GraphQL queries
- `graphqlschema/` - GraphQL schema operations
- `graphqlsearch/` - GraphQL search features
- `graphqlmoredata/` - Working with larger datasets

Each section has numbered `.md` files (1.md, 2.md, etc.) for tutorial steps and `.txt` files for executable query examples.

### Build System
- `Makefile` - Task runner with setup, start, stop, reset, test targets
- `docker-compose.yml` - Dgraph (`tour-dgraph`) and Ratel (`tour-ratel`) containers
- `resources/1million.schema` - DQL schema for the sample movie dataset
- `resources/1million.rdf.gz` - Sample movie dataset (1 million triples)
- `scripts/build.py` - Production build script that:
  - Finds all `dgraph-<version>` branches
  - Builds each branch to `published/<branch>/`
  - Builds the latest release to the root `published/` folder
  - Generates `releases.json` for version switching
- Hugo config: `config.toml` + `releases.json` (generated)

### Theme
Custom Hugo theme in `themes/hugo-tutorials/` with layouts and static assets.

### Versioning
- `master` branch contains changes for latest Dgraph development
- `dgraph-<version>` branches contain version-specific tutorial content
- Version switcher on the site mirrors Dgraph Docs release structure
- To create a new version: `git checkout master && git checkout -b dgraph-<NEW_SEMVER>`

### Deployment
- `published/` folder contains built static content
- Server pulls from git every 2 minutes via cron
- Nginx config in `nginx/tour.conf`

## Important Behavioral Guidelines

- Do not make changes to the hugo build output directories (public, published) when making changes. Focus on the templates. Do not consider those output directories unless you are verifying that hugo is producing expected output.
- play.dgraph.io DOES NOT EXIST - there is no remote Ratel UI anymore. All queries run against local Dgraph.
- Dgraph Cloud no longer exists as a product - only self-hosted open source Dgraph.
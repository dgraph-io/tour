# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is "A Tour of Dgraph" - a step-by-step tutorial site built with Hugo. The live site is at https://dgraph.io/tour.

## Common Commands

```bash
# Install dependencies, start Dgraph, and load sample data
make setup

# Run local development server with hot reload
make run

# Reset Dgraph data and reload sample dataset
make reset

# Run all DQL and GraphQL tests
make test

# Start/stop Docker containers manually
make docker-compose-up
make docker-compose-down

# Build for production (commits to published/ folder)
python3 scripts/build.py
```

## Local Services

When running `make run`, the following services are available:
- **Hugo Tour**: http://localhost:8000/ - The tutorial site
- **Dgraph Alpha**: http://localhost:8080/ - GraphQL and DQL endpoints
- **Ratel UI**: http://localhost:8001/ - Dgraph query interface

## Architecture

### Content Structure
Tutorial content lives in `content/` as Markdown files, organized by section:
- `intro/` - Introduction to Dgraph and graph databases
- `basic/` - Querying graph data basics
- `schema/` - Schema operations and mutations
- `moredata/` - Loading larger datasets with dgraph live loader
- `blocksvars/` - Query blocks and variables
- `search/` - Dgraph search features

Each section has numbered `.md` files (1.md, 2.md, etc.) representing tutorial steps.

### Build System
- `Makefile` - Task runner with setup, run, test, reset tasks
- `docker-compose.yml` - Dgraph and Ratel containers for local development
- `resources/1million.graphql` - GraphQL schema for the sample movie dataset
- `resources/1million.schema` - DQL schema for the sample movie dataset
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
IMPORTANT: When applicable, prefer using jetbrains-index MCP tools for code navigation and refactoring.
- memory Do not make changes to the hugo build output directories (public, published) when making changes.  Focus on the templates.  Do not consider those output directories unless you are verifying that hugo is producing expected output.
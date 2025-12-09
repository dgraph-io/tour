# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is "A Tour of Dgraph" - a step-by-step tutorial site built with Hugo. The live site is at https://dgraph.io/tour.

## Common Commands

```bash
# Install dependencies (hugo)
just setup

# Run local development server (watches for changes)
./scripts/local.sh

# Build for local testing with version redirects
just build-local
# or directly:
TOUR_BASE_URL=http://localhost:8000 python3 scripts/build.py

# Build for production (commits to published/ folder)
python3 scripts/build.py
```

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
- `scripts/build.py` - Main build script that:
  - Finds all `dgraph-<version>` branches
  - Builds each branch to `published/<branch>/`
  - Builds the latest release to the root `published/` folder
  - Generates `releases.json` for version switching
- `scripts/local.sh` - Local development server with hot reload
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
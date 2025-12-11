# A Tour of Dgraph

A step by step introductory tutorial of Dgraph. Built with [Hugo](https://gohugo.io/).

Visit https://dgraph.io/tour for the running instance.

**Use [Discuss Issues](https://discuss.dgraph.io/tags/c/issues/35/tutorial) for reporting issues about this repository.**

## Local Development

### Prerequisites

`make` is pre-installed on macOS and most Linux distributions.

### Quick Start

```bash
# Clone and setup (installs dependencies, starts Dgraph, loads sample data)
git clone https://github.com/dgraph-io/tutorial.git
cd tutorial
make setup

# Start development server with hot reload
make start
```

The tour will be available at http://localhost:8000/

### Available Tasks

| Task | Description |
|------|-------------|
| `make setup` | Install dependencies, start Dgraph, and load sample data |
| `make start` | Start Hugo development server with hot reload |
| `make stop` | Stop Hugo server and Dgraph containers |
| `make restart` | Restart Hugo server and Dgraph containers |
| `make reset` | Reset Dgraph data and reload sample dataset |
| `make test` | Run all DQL and GraphQL tests |
| `make docker-compose-up` | Start Dgraph and Ratel containers |
| `make docker-compose-down` | Stop Dgraph and Ratel containers |

Run `make help` to see all available tasks.

### Services

When running locally, the following services are available:

- **Hugo Tour**: http://localhost:8000/ - The tutorial site
- **Dgraph Alpha**: http://localhost:8080/ - GraphQL and DQL endpoints
- **Ratel UI**: http://localhost:8001/ - Dgraph query interface

### Legacy Development

To develop and test version redirects locally run the build script:
`TOUR_BASE_URL=http://localhost:8000 python3 scripts/build.py`

This will recompile `master` and all `dgraph-<version>` branches and store the static site content in the `published/` folder

## Dgraph Release Process

Structure of the tour releases/version switcher must mirror the structure of the Dgraph Docs releases/versions. (Starting from Dgraph 1.0.16 onwards).

### Where to make changes

- All changes/updates reflecting the changes in Dgraph master should be committed into the `master` branch of this repository (`dgraph-io/tutorial`).
- Fixes and changes for older versions of the tour should be committed into relevant `dgraph-$version` branch.
- As part of the release process for Dgraph a new branch `dgraph-$version` must be cut here (`git checkout master; git checkout -b dgraph-<NEW_SEMVER>`).

## Deploying to Live Site

Run the build script:
`python3 scripts/build.py`

Once it finishes without errors it will commit all static content
into the `published/` folder.

After that you can `git push` and the server will pick up the changes.

## Server config

File `nginx/tour.conf` is symlinked to Nginx's `sites-available`
when you edit it you must ssh and run `nginx -s reload`.

Cron task

```sh
*/2 *    *   *   *   cd /home/ubuntu/dgraph-tour && git pull
```

Pulls new commits from git.

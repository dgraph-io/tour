# A Tour of Dgraph

A step by step introductory tutorial of Dgraph.

## Taking the Tour

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)

### macOS / Linux

```bash
git clone https://github.com/dgraph-io/tour.git
cd tour
make start
```

The tour will automatically open in your browser.

### Windows

```powershell
git clone https://github.com/dgraph-io/tour.git
cd tour
docker compose up -d
```

Then open http://localhost:1313/ in your browser.

### Stopping the Tour

**macOS / Linux:**
```bash
make stop
```

**Windows:**
```powershell
docker compose down
```

## Local Services

When running the tour, the following services are available:

| Service | URL | Description |
|---------|-----|-------------|
| Hugo Tour | http://localhost:1313/ | The tutorial site |
| Dgraph Alpha | http://localhost:8080/ | GraphQL and DQL endpoints |
| Ratel UI | http://localhost:8000/ | Dgraph query interface |

## Development

### Prerequisites

- `make` (pre-installed on macOS and most Linux distributions)
- Docker

### Available Commands

| Command | Description |
|---------|-------------|
| `make start` | Start the tour |
| `make stop` | Stop the tour |
| `make reset` | Reset Dgraph data and reload sample dataset |
| `make test` | Run all tests |

Run `make help` to see all available commands.

### Testing

The test suite validates all tour examples work correctly:

```bash
make test
```

This runs:
- Link validation for templates and live tour
- DQL query tests (42 tests)
- GraphQL query tests (33 tests)
- Movie dataset relationship tests

### Legacy Development

To develop and test version redirects locally run the build script:
`TOUR_BASE_URL=http://localhost:8000 python3 scripts/build.py`

This will recompile `master` and all `dgraph-<version>` branches and store the static site content in the `published/` folder

## Dgraph Release Process

Structure of the tour releases/version switcher must mirror the structure of the Dgraph Docs releases/versions. (Starting from Dgraph 1.0.16 onwards).

### Where to make changes

- All changes/updates reflecting the changes in Dgraph master should be committed into the `master` branch of this repository (`dgraph-io/tour`).
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

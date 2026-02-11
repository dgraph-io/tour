# A Tour of Dgraph

A step-by-step introductory tutorial for [Dgraph](https://dgraph.io), the distributed graph database.

## Taking the Tour

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)

### macOS / Linux

```bash
git clone https://github.com/dgraph-io/tour.git
cd tour
make start
```

The tour opens automatically in your default browser.

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

| Service | URL | Description |
|---------|-----|-------------|
| Tour site | http://localhost:1313/ | The tutorial |
| Dgraph Alpha | http://localhost:8080/ | GraphQL and DQL endpoints |
| Ratel UI | http://localhost:8000/ | Dgraph query interface |

## Development

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- `make` (pre-installed on macOS and most Linux distributions)

### Available Commands

| Command | Description |
|---------|-------------|
| `make start` | Start the tour (Dgraph + Hugo + sample data) |
| `make stop` | Stop the tour |
| `make restart` | Drop all data and restart the tour |
| `make clean` | Drop all data, stop containers, and remove images |
| `make test` | Run all tests (DQL + GraphQL + dataset) |
| `make seed-basic-facets` | Load facet sample data for the facets lesson |
| `make dev-setup` | Install dev dependencies (Hugo, linters) |
| `make dev-start` | Start Hugo dev server with hot reload |
| `make dev-stop` | Stop Hugo server and Docker containers |
| `make dev-restart` | Restart dev environment |

Run `make help` for the full list of targets.

### Testing

```bash
make test
```

The test suite runs:
- DQL query tests (42 tests)
- GraphQL query tests (33 tests)
- Movie dataset relationship tests (5 tests)

### Building for Production

To build all versioned branches locally:

```bash
TOUR_BASE_URL=http://localhost:8000 python3 scripts/build.py
```

This compiles `master` and every `dgraph-<version>` branch into the `published/` folder.

## Release Process

The tour's version switcher mirrors Dgraph Docs releases.

- Commit changes for the latest Dgraph release to the `master` branch.
- Commit fixes for older versions to the relevant `dgraph-<version>` branch.
- When Dgraph releases a new version, cut a branch: `git checkout master && git checkout -b dgraph-<NEW_SEMVER>`.

## Deploying to Live Site

Run the build script:

```bash
python3 scripts/build.py
```

The script commits all static content to the `published/` folder. Push the result and the server picks up changes within two minutes via cron.

## Server Configuration

`nginx/tour.conf` is symlinked into Nginx's `sites-available`. After editing, SSH in and run `nginx -s reload`.

Cron job (pulls every 2 minutes):

```sh
*/2 *    *   *   *   cd /home/ubuntu/dgraph-tour && git pull
```

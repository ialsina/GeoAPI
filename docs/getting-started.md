# Getting started

The supported setup uses Docker Compose for PostgreSQL/PostGIS and the API, then
the repository's pipeline to initialize and populate the database.

## Prerequisites

- Git
- Docker with the Compose plugin
- Bash
- `curl` and `unzip`

The data pipeline also pulls a GDAL image for geospatial imports. Allow enough
disk space for the source datasets, database, and container images.

For local API development outside Docker, install Go 1.24 or later.

## Clone the repository

```bash
git clone <repository-url>
cd GeoAPI
git submodule update --init --recursive
```

The pipeline can initialize the data submodules itself, but initializing them
at clone time makes the checkout complete immediately.

## Start and populate the stack

```bash
docker compose up -d --build
./scripts/pipeline.sh
```

The first command starts:

- `geoapi-db`, a PostgreSQL 15/PostGIS 3.4 database published on port 5433;
- `geoapi-api`, the API published on port 8080.

The pipeline waits for the database, downloads missing data, applies pending
migrations, and populates every data table in dependency order. Downloads under
`data/` are ignored by Git.

When it completes, verify the service:

```bash
curl http://localhost:8080/health
curl "http://localhost:8080/city?name=Paris&country=FR"
```

The interactive Swagger UI is available at
<http://localhost:8080/docs/>.

## Pipeline options

Force every downloadable source to refresh:

```bash
./scripts/pipeline.sh --force
```

Reset migration tracking and reapply every migration:

```bash
./scripts/pipeline.sh --reset
```

`--reset` is destructive with the current initial migration: it drops and
recreates all domain tables before the pipeline reloads them. Use it only when
rebuilding a development database. The flags can be combined for a complete
refresh:

```bash
./scripts/pipeline.sh --force --reset
```

## Common service commands

```bash
# Follow API logs
docker compose logs -f api

# Inspect service state
docker compose ps

# Stop the stack but retain database data
docker compose down

# Stop the stack and remove the database volume
docker compose down -v
```

Removing the volume deletes the populated database.

## Local API process

To run the Go process on the host while keeping the Compose database:

```bash
docker compose up -d db
export DATABASE_URL="postgres://geouser:geopass@localhost:5433/geodb"
go run github.com/swaggo/swag/cmd/swag@v1.8.1 \
  init -g cmd/server/main.go -o internal/swagger
go run ./cmd/server
```

Populate the database with `./scripts/pipeline.sh` before querying data. Further
development commands are in [Development](development.md).

# Development

## Toolchain

The module targets Go 1.24.5. Runtime dependencies include Chi, pgx, PostGIS,
and swaggo. Bash scripts and Docker provide the data-loading toolchain.

Install Go dependencies with:

```bash
go mod download
```

## Run the API locally

Keep PostgreSQL in Compose and run only the API process on the host:

```bash
docker compose up -d db
./scripts/pipeline.sh

export DATABASE_URL="postgres://geouser:geopass@localhost:5433/geodb"
go run github.com/swaggo/swag/cmd/swag@v1.8.1 \
  init -g cmd/server/main.go -o internal/swagger
go run ./cmd/server
```

`DATABASE_URL` is the only environment variable read by the Go application. It
is required; the process exits during startup when it is absent.

## Swagger workflow

Endpoint annotations in `cmd/server/main.go` and `internal/handlers/` are the
source of truth for the OpenAPI 2.0 specification. Regenerate after changing
routes, parameters, models, or API metadata:

```bash
go run github.com/swaggo/swag/cmd/swag@v1.8.1 \
  init -g cmd/server/main.go -o internal/swagger
```

`internal/swagger/` is a generated, ignored Go package. Do not edit its
`docs.go`, `swagger.json`, or `swagger.yaml` files manually. The server imports
the package for registration, and serves Swagger UI at `/docs/`; the URL does
not depend on the generated directory name.

The Docker build runs the same `swag` version before compiling. The generated
specification is embedded through `docs.go`, so the distroless runtime image
only needs the `geoapi` binary.

## Build and checks

```bash
# Compile all packages and run all committed tests
go test ./...

# Build the server
go build -o geoapi ./cmd/server

# Build the production container
docker build -t geoapi:latest .
```

There are currently no committed `*_test.go` files. `go test ./...` is still a
useful compile check, but it does not provide behavior or database integration
coverage yet.

The repository includes a pre-commit configuration:

```bash
pre-commit install
pre-commit run --all-files
```

Its hooks check basic file hygiene and YAML, run `shellcheck` and `shfmt` on
shell scripts, and run Go module tidy checks. Install `pre-commit`,
`shellcheck`, and `shfmt` on the host before using all hooks. Run `gofmt` on Go
changes.

## Project layout

```text
cmd/server/             executable entry point and routes
internal/db/            pgx pool configuration
internal/handlers/      HTTP validation, SQL, and Swagger annotations
internal/models/        JSON response models
internal/swagger/       generated Swagger package (ignored)
migrations/             ordered SQL migrations
scripts/                downloads, migrations, and population
data/                   downloaded files (ignored)
docs/                   maintained project documentation
geojson-world-cities/   city-boundary data submodule
ourairports-data/       airport data submodule
```

The Go module is currently named `city-api`, even though the project and binary
are called GeoAPI.

## Compose and image configuration

Compose passes the API this database URL:

```text
postgres://geouser:geopass@db:5432/geodb
```

The API image name is assembled from these Compose substitutions:

- `CI_REGISTRY_IMAGE`, when supplied by GitLab CI;
- otherwise `REGISTRY_IMAGE`, commonly set in a local `.env`;
- otherwise `geoapi`;
- `IMAGE_TAG`, defaulting to `latest`.

Copy `.env.example` to `.env` and replace its placeholder registry path when a
registry-qualified image name is needed. `.env` is ignored by Git.

The Compose credentials are development defaults. For deployment, provide
managed secrets, restrict database exposure, put TLS and request controls in a
reverse proxy or gateway, and establish backups and monitoring. The service
itself currently has no authentication or rate limiting.

## Troubleshooting

### The Go build cannot find `city-api/internal/swagger`

Generate the ignored package with the pinned command in
[Swagger workflow](#swagger-workflow). A Docker build does this automatically.

### The API exits with `DATABASE_URL not set`

Export the host connection string before a local run, or start the API through
Compose so the value is injected.

### The database is not ready

```bash
docker compose ps
docker compose logs db
docker exec geoapi-db pg_isready -U geouser -d geodb
```

### A migration edit is not applied

Applied filenames are recorded in `schema_migrations`. In a disposable
development database, run `./scripts/pipeline.sh --reset`. This drops and
reloads all domain tables.

### A geospatial population step cannot connect

Check that the database and temporary GDAL container share the network named by
`DOCKER_NETWORK`. The default for this repository is `geoapi_default`.

### API results are empty or missing

Run the complete pipeline instead of an individual population script, then
inspect its reported row counts. Parent country data must be loaded before
cities, administrative boundaries, and airports.

## Licensing status

The repository does not currently contain a root project license. Dataset
submodules have their own upstream licenses. The Swagger metadata currently
declares Apache 2.0, but without a root license file that declaration should not
be treated as the repository's licensing terms.

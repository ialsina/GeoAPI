# GeoAPI

GeoAPI is a read-only REST API for cities, airports, countries, and geographic
boundaries. It combines a Go HTTP service with PostgreSQL/PostGIS and a
repeatable Bash data pipeline.

## Capabilities

- exact and fuzzy city lookup, including alternate names;
- exact airport-code lookup and fuzzy airport-name search;
- country metadata lookup and pagination;
- city, ADM0, ADM1, and ADM2 boundary queries by city, shape name, country, or
  coordinates;
- PostGIS containment and nearest-city operations;
- interactive Swagger API documentation;
- Docker Compose deployment and an end-to-end data-loading pipeline.

## Quick start

Prerequisites are Git, Docker with the Compose plugin, Bash, `curl`, and
`unzip`.

```bash
git clone <repository-url>
cd GeoAPI
git submodule update --init --recursive

docker compose up -d --build
./scripts/pipeline.sh
```

The pipeline waits for PostgreSQL, downloads missing datasets, applies
migrations, and populates all tables. Initial loading can take time and requires
disk space for the source data and PostGIS database.

Verify the running service:

```bash
curl http://localhost:8080/health
curl "http://localhost:8080/city?name=Paris&country=FR"
curl "http://localhost:8080/airport?iata=SFO"
```

- API base URL: <http://localhost:8080>
- Swagger UI: <http://localhost:8080/docs/>

See [Getting started](docs/getting-started.md) for local development, refresh
options, and service commands.

## API overview

| Endpoint | Purpose |
| --- | --- |
| `GET /health` | API and database health |
| `GET /city` | Retrieve a city by GeoNames ID or name |
| `GET /cities` | Fuzzy-search city and alternate names |
| `GET /airport` | Retrieve an airport by ID, ident, code, or name |
| `GET /airports` | Search airports by name or exact IATA/ICAO code |
| `GET /boundary` | Retrieve city, ADM0, ADM1, or ADM2 GeoJSON |
| `GET /country` | Retrieve country metadata by ISO code |
| `GET /countries` | List countries with pagination |
| `GET /docs/*` | Interactive Swagger reference |

The service currently has no authentication or API version prefix. Read
[API usage](docs/api.md) for examples and boundary-selection behavior. Swagger
is the source for detailed request parameters and response schemas.

## Architecture

```text
Client --> Go API (Chi + pgx) --> PostgreSQL/PostGIS
                                      ^
                                      |
                     Bash pipeline <--+-- external datasets
```

Handlers validate HTTP query parameters and execute SQL through a shared pgx
pool. The pipeline separately loads country, city, boundary, and airport data
in foreign-key order.

Read [Architecture](docs/architecture.md) for component and data flow details.

## Documentation

- [Getting started](docs/getting-started.md)
- [API usage](docs/api.md)
- [Architecture](docs/architecture.md)
- [Database](docs/database.md)
- [Data pipeline](docs/data-pipeline.md)
- [Development, deployment, and troubleshooting](docs/development.md)

The documentation is plain Markdown. Generated Swagger artifacts live in the
ignored `internal/swagger/` package and are rebuilt from Go annotations. This
keeps `docs/` available for maintained project documentation and allows a site
generator such as MkDocs to be added later without restructuring the content.

## Development

The module targets Go 1.24.5. For a host-run API using the Compose database:

```bash
docker compose up -d db
export DATABASE_URL="postgres://geouser:geopass@localhost:5433/geodb"

go run github.com/swaggo/swag/cmd/swag@v1.8.1 \
  init -g cmd/server/main.go -o internal/swagger
go test ./...
go run ./cmd/server
```

There are currently no committed Go test files, so `go test ./...` primarily
provides a compile check. See [Development](docs/development.md) for Swagger,
pre-commit, build, configuration, and deployment details.

## Data sources

- [GeoNames cities1000](https://download.geonames.org/export/dump/) for cities
  and alternate names;
- [geoBoundaries CGAZ](https://www.geoboundaries.org/) for ADM0, ADM1, and ADM2
  boundaries;
- [geojson-world-cities](https://github.com/drei01/geojson-world-cities) for
  city polygons;
- [OurAirports](https://ourairports.com/data/) for airports;
- [datasets/country-codes](https://github.com/datasets/country-codes) for
  country metadata.

The two repository submodules retain their upstream documentation and licenses.
See [Data pipeline](docs/data-pipeline.md) for download paths and loading order.

## Contributing

Keep handler Swagger annotations synchronized with API changes and regenerate
`internal/swagger/` before compiling locally. Update the relevant Markdown guide
when changing architecture, schema, pipeline, or operational behavior.

Run the available checks before submitting changes:

```bash
go test ./...
pre-commit run --all-files
```

## License

This repository does not currently include a project license. The bundled data
submodules and upstream datasets have their own terms.

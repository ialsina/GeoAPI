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

GeoAPI loads third-party geographic data through `scripts/pipeline.sh`. Download
paths, refresh flags, and load order are documented in
[Data pipeline](docs/data-pipeline.md).

| Source | Used for | How loaded | License |
| --- | --- | --- | --- |
| [GeoNames cities1000](https://download.geonames.org/export/dump/) | City records and alternate names | Downloaded by `scripts/download_cities1000.sh` | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| [geoBoundaries CGAZ](https://www.geoboundaries.org/) | ADM0, ADM1, and ADM2 boundaries | Downloaded by `scripts/download_geoboundaries_adm*.sh` | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) (project); individual boundaries may also be [ODbL](https://opendatacommons.org/licenses/odbl/1-0/), [CC BY-SA](https://creativecommons.org/licenses/by-sa/4.0/), or other open terms |
| [geojson-world-cities](https://github.com/drei01/geojson-world-cities) | City polygons | Git submodule (`scripts/download_city_boundaries.sh`) | [Apache 2.0](geojson-world-cities/LICENSE) |
| [OurAirports](https://ourairports.com/data/) | Airport records | Git submodule (`scripts/download_ourairports_data.sh`) | [The Unlicense](ourairports-data/LICENSE) |
| [datasets/country-codes](https://github.com/datasets/country-codes) | Country metadata (ISO codes, names, capitals, etc.) | Downloaded by `scripts/download_countries.sh` | [ODC-PDDL 1.0](https://opendatacommons.org/licenses/pddl/1-0/) |

The two Git submodules retain their upstream documentation and license files.
Pipeline-downloaded files are stored under `data/` and are not committed to this
repository.

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

### Application code

GeoAPI application code — the Go HTTP service, SQL migrations, Bash pipeline
scripts, and project documentation — is licensed under the
[Apache License, Version 2.0](LICENSE).

### Third-party data

The datasets listed in [Data sources](#data-sources) are **not** licensed under
Apache 2.0. Each retains its upstream terms. Using them in GeoAPI is compatible
with Apache 2.0 application code, but redistribution or public use of the data
itself (for example, via the `GET /boundary` endpoint) must comply with the
relevant upstream license.

| Source | License | Attribution / obligations |
| --- | --- | --- |
| GeoNames cities1000 | CC BY 4.0 | Credit [GeoNames](https://www.geonames.org/) when using or redistributing the data. |
| geoBoundaries CGAZ | CC BY 4.0 (project); mixed per-boundary | Credit [geoBoundaries](https://www.geoboundaries.org/) and the original boundary providers. See [citation guidance](https://www.geoboundaries.org/#citation) and per-boundary metadata. Boundaries under ODbL or CC BY-SA may impose additional share-alike or access obligations when adapted or redistributed. |
| geojson-world-cities | Apache 2.0 | Preserve upstream copyright and license notices when redistributing the dataset. |
| OurAirports | Unlicense | No attribution required. |
| datasets/country-codes | ODC-PDDL 1.0 | No attribution required by the dataset maintainers. Note that some upstream facts (notably ISO country codes) may be subject to separate terms; review upstream sources before commercial redistribution. |

For submodule license texts, see `geojson-world-cities/LICENSE` and
`ourairports-data/LICENSE`.

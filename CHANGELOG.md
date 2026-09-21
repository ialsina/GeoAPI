# Changelog

All notable changes to GeoAPI are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Pre-release versions are not listed separately.

## [Unreleased]

### Fixed

- geoBoundaries downloads now retry on failure, write to a `.partial` file, verify
  size and GDAL readability before promotion, and replace truncated copies on the
  next pipeline run

## [0.3.0] - 2026-09-19

### Added

- Container startup data initialization through `docker-entrypoint.sh`, driven
  by `AUTO_POPULATE_DATA` and `FORCE_POPULATE`.
- Idempotent first-boot detection that skips `scripts/pipeline.sh` when core
  tables (`countries`, `cities_1000`) are already populated.
- `GEOAPI_DATA_DIR` support in `scripts/common.sh` for configurable download
  paths inside containers.
- Docker Compose health checks, database readiness gating, and `.env.example`
  variables for automatic population.

### Changed

- Replaced the distroless runtime image with a Debian-based stage that includes
  `curl`, `git`, and the Docker CLI so the in-container pipeline can download
  datasets and run GDAL import steps.
- Docker Compose now persists downloaded datasets on the host through
  `./data:/app/data`, mounts the same directory read-only into PostGIS at
  `/data`, and exposes `/var/run/docker.sock` for pipeline operations.
- Aligned both Dockerfile stages on Debian Bookworm (`golang:1.24-bookworm`
  builder, `debian:bookworm-slim` runtime), replacing bullseye in the build
  stage.

### Fixed

- Replaced the Debian `docker.io` package in the runtime image with the official
  static Docker CLI (27.5.1). The distro package speaks API ~1.41 and fails
  against modern Docker daemons (minimum API 1.44+), which caused the startup
  pipeline to hang retrying `docker exec` during database readiness checks.
- Population scripts now truncate `cities_1000` and
  `cities_1000_alternate_names` in a single statement to satisfy PostgreSQL
  foreign-key constraints.
- All migration and population `psql` invocations use `ON_ERROR_STOP=1` so a
  failed SQL step aborts the pipeline instead of leaving a partially imported
  database.
- `docker-entrypoint.sh` no longer treats a populated `countries` table as proof
  of a complete import; it also requires `cities_1000` rows and automatically
  re-runs the pipeline when the database is only partially initialized.
- geoBoundaries download scripts now fetch CGAZ GeoJSON from
  `media.githubusercontent.com` instead of `github.com/raw/`, which previously
  saved Git LFS pointer stubs that GDAL could not open.
- GDAL `ogr2ogr` steps now use `docker run --volumes-from geoapi-api` instead of
  `-v /app/data:/data`, which previously mounted a non-existent host path when
  the pipeline ran inside the API container via the Docker socket.
- Population scripts verify dataset files on the PostGIS `/data` mount and reject
  Git LFS pointer stubs before `COPY FROM` or `ogr2ogr`.

## [0.2.0] - 2026-09-13

### Added

- Airport support backed by OurAirports data:
  - `GET /airport` lookups by ID, ident, IATA code, ICAO code, or name.
  - `GET /airports` exact code lookup and fuzzy name search.
  - Airport models, schema, indexes, download, and population scripts.
  - The `ourairports-data` Git submodule.
- ADM1 province/state boundary storage, spatial indexing, download, population,
  and API lookup.
- A complete `scripts/pipeline.sh` workflow that downloads sources, applies
  migrations, and populates tables in dependency order.
- Shared pipeline configuration and helpers in `scripts/common.sh`, including
  support for alternate Compose environments.
- Migration tracking through `schema_migrations`, plus `--reset` support for
  rebuilding development databases.
- Alternate GeoNames city names, including their table, indexes, population,
  exact lookup, and fuzzy-search integration.
- Expanded `GET /boundary` behavior:
  - city lookup through `geonameid` or the `city` parameter;
  - boundary shape lookup by `name`;
  - standalone country-to-ADM0 lookup;
  - ISO alpha-2, ISO alpha-3, and English country-name resolution;
  - explicit `city`, `adm0`, `adm1`, and `adm2` boundary types;
  - automatic boundary selection and broader-level upscaling;
  - nearest-city details for coordinate lookups.
- Plain-Markdown project documentation covering architecture, setup, API usage,
  database structure, the data pipeline, development, deployment, and
  troubleshooting.
- GitLab container-registry image configuration through `.env.example`,
  `REGISTRY_IMAGE`, `CI_REGISTRY_IMAGE`, and `IMAGE_TAG`.
- An Apache License 2.0 project license.

### Changed

- Moved generated Swagger files from `docs/` to the ignored
  `internal/swagger/` package, leaving `docs/` for maintained documentation.
- Replaced the monolithic README with a concise project overview and
  documentation index.
- Normalized database country columns to `country`, using ISO alpha-2 for
  cities and airports and ISO alpha-3 for administrative boundaries.
- Allowed city and airport rows with unknown or disputed country codes to load
  with a null country, while filtering invalid administrative-boundary country
  references.
- Reworked geospatial population scripts to load through disposable staging
  tables while preserving migration-owned schemas and foreign keys.
- Updated the pre-commit `shfmt` hook to format shell scripts in place.
- Updated the OurAirports submodule data.

## [0.1.0] - 2026-02-24

### Added

- A Go 1.24 HTTP service using Chi, pgx, PostgreSQL, PostGIS, and `pg_trgm`.
- City endpoints:
  - `GET /city` lookup by GeoNames ID or city name.
  - `GET /cities` fuzzy name and ASCII-name search with country, limit, and
    similarity-threshold filters.
- Country endpoints:
  - `GET /country` lookup by ISO alpha-2 or alpha-3 code.
  - `GET /countries` paginated country listing.
- `GET /boundary` queries using city names, GeoNames IDs, or coordinates,
  backed by city, ADM0, and ADM2 geometries.
- `GET /health` database connectivity checks.
- Swagger/OpenAPI annotations, generated specifications, and interactive
  documentation at `/docs/`.
- Database tables for countries, GeoNames cities, ADM0 boundaries, ADM2
  boundaries, and city polygons.
- PostGIS spatial indexes, trigram text indexes, and country foreign keys.
- Download and population scripts for country metadata, GeoNames cities,
  geoBoundaries data, and city polygons.
- The `geojson-world-cities` Git submodule.
- Docker and Docker Compose configurations for the API and PostGIS database.
- Project setup, API, deployment, data-source, and troubleshooting guidance in
  the README.
- Pre-commit checks for file hygiene, YAML, shell scripts, and Go modules.

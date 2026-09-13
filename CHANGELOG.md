# Changelog

All notable changes to GeoAPI are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Pre-release versions are not listed separately.

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

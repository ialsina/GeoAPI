# Data pipeline

The Go API only reads the database. `scripts/pipeline.sh` owns database
initialization and data loading, including dependency order between datasets.

## Prerequisites

Start the Compose stack before the pipeline:

```bash
docker compose up -d
./scripts/pipeline.sh
```

The scripts require Bash, Docker, `curl`, `unzip`, and Git. PostgreSQL commands
run inside the database container. Geospatial imports run `ogr2ogr` from
`ghcr.io/osgeo/gdal:alpine-small-3.8.4`, so GDAL does not need to be installed
on the host.

## Pipeline phases

### Phase 0: downloads

The pipeline obtains:

- country metadata from `datasets/country-codes`;
- `cities1000` from GeoNames;
- ADM0, ADM1, and ADM2 CGAZ GeoJSON from geoBoundaries;
- airport data from the `ourairports-data` Git submodule;
- city polygons from the `geojson-world-cities` Git submodule.

Regular file downloads are skipped when their extracted output already exists.
Submodule download scripts initialize missing submodules or update initialized
ones.

### Phase 1: migrations

`scripts/run_migrations.sh` creates `schema_migrations` if needed and applies
unrecorded `.sql` files from `migrations/` in alphabetical order.

The current `001_init.sql` migration drops and recreates all domain tables.
Migration tracking keeps normal reruns safe by preventing it from being applied
again. `--reset` clears that tracking and is therefore a destructive
development operation.

### Phase 2: root data

Countries load first because cities, airports, and administrative boundaries
reference country codes.

### Phase 3: dependent data

The pipeline loads, in order:

1. cities and their alternate names;
2. ADM0 boundaries;
3. ADM1 boundaries;
4. ADM2 boundaries;
5. airports.

Rows with source country codes absent from `countries` are either retained with
a null country (cities and airports) or skipped (administrative boundaries), as
defined by the individual population scripts.

### Phase 4: standalone data

City polygons load last. `city_boundaries` has no country relationship and is
independent of the other geographic tables.

## Commands and refresh behavior

```bash
# Reuse existing downloads and apply only pending migrations
./scripts/pipeline.sh

# Refresh source downloads and submodules
./scripts/pipeline.sh --force

# Reapply migrations and repopulate all tables (destructive)
./scripts/pipeline.sh --reset

# Refresh everything and rebuild the database
./scripts/pipeline.sh --force --reset
```

Population scripts truncate or overwrite their target tables, so they can be
rerun after their prerequisite data and parent tables are available.

## Script catalog

| Concern | Scripts |
| --- | --- |
| Orchestration | `pipeline.sh`, `common.sh` |
| Schema | `run_migrations.sh` |
| Countries | `download_countries.sh`, `populate_countries.sh` |
| Cities | `download_cities1000.sh`, `populate_cities.sh` |
| Administrative boundaries | `download_geoboundaries_adm{0,1,2}.sh`, `populate_geoboundaries_adm{0,1,2}.sh` |
| Airports | `download_ourairports_data.sh`, `populate_airports.sh` |
| City polygons | `download_city_boundaries.sh`, `populate_city_boundaries.sh` |

The administrative population scripts first let `ogr2ogr` write a disposable
staging table, then transfer valid rows into the migration-owned final table.
The airports CSV is copied from its submodule into the database container
temporarily. Country and GeoNames files are read through the Compose `data/`
bind mount.

## Paths and source formats

| Data | Local path | Format |
| --- | --- | --- |
| Countries | `data/countries/country-codes.csv` | CSV with header |
| Cities | `data/cities1000/cities1000.txt` | 19-column tab-separated file without a header |
| Administrative boundaries | `data/geoBoundaries/geoBoundariesCGAZ_ADM*.geojson` | GeoJSON |
| Airports | `ourairports-data/airports.csv` | CSV with header |
| City polygons | `geojson-world-cities/cities.geojson` | GeoJSON |

The contents of `data/` are ignored by Git. The two dataset subdirectories are
Git submodules and retain their upstream licenses and documentation.

## Container and network configuration

`scripts/common.sh` defaults to:

- database container `geoapi-db`;
- database host `db`;
- Compose network `geoapi_default`;
- database `geodb` and user `geouser`.

`DB_CONTAINER`, `DB_HOST`, and `DOCKER_NETWORK` can override those values.
Setting `GEOAPI_COMPOSE=dev`, or using a `COMPOSE_FILE` containing
`docker-compose.dev`, selects the alternate development-stack defaults. The
helper also detects a running `geo-db-dev` container when the default container
is unavailable.

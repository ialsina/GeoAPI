# Database

GeoAPI stores reference data in PostgreSQL 15 with PostGIS. The schema is
defined by `migrations/001_init.sql`; this document describes that migration,
but the SQL remains the source of truth.

## Extensions and coordinate system

The migration enables:

- `postgis` for geometry types and spatial queries;
- `pg_trgm` for fuzzy text matching.

All geometries use WGS 84 (SRID 4326). Cities are stored as points. City and
administrative boundaries are stored as multipolygons.

## Tables

### `countries`

Country metadata keyed internally by a serial `id`. `iso2` is required and
unique; `iso3` is unique when present. The table also stores the English name,
M49 numeric code, region, sub-region, capital, top-level domain, and continent.

This is the parent table for cities, administrative boundaries, and airports.

### `cities_1000`

GeoNames locations with population at least 1,000. The GeoNames ID is the
primary key. Each row contains official and ASCII names, ISO alpha-2 country
code, population, latitude, longitude, and a point geometry.

### `cities_1000_alternate_names`

One alternate city name per row, derived from the GeoNames comma-separated
alternate-name field. Rows reference `cities_1000.geonameid` and are deleted
when their city is deleted.

### `adm0_boundaries`

Country-level GeoBoundaries CGAZ multipolygons. ADM0 source features do not
provide a unique shape ID, so the table uses a serial primary key. `country`
contains an ISO alpha-3 code.

### `adm1_boundaries`

Province- or state-level GeoBoundaries CGAZ multipolygons. The source `shapeID`
is the primary key and `country` contains an ISO alpha-3 code.

### `adm2_boundaries`

District- or county-level GeoBoundaries CGAZ multipolygons. The source
`shapeID` is the primary key and `country` contains an ISO alpha-3 code.

### `city_boundaries`

City multipolygons from the `geojson-world-cities` submodule, keyed by name.
This source has no country field or foreign key, so duplicate city names cannot
be disambiguated in this table.

### `airports`

OurAirports records keyed by the source numeric ID. Rows include ident, airport
type, name, ISO alpha-2 country code, municipality, coordinates, elevation in
metres, IATA code, and ICAO code.

### `schema_migrations`

Created by `scripts/run_migrations.sh`, not by `001_init.sql`. It records each
applied migration filename and timestamp so normal pipeline runs skip completed
migrations.

## Relationships

```text
countries.iso2
    +-- cities_1000.country
    +-- airports.country

countries.iso3
    +-- adm0_boundaries.country
    +-- adm1_boundaries.country
    +-- adm2_boundaries.country

cities_1000.geonameid
    +-- cities_1000_alternate_names.geonameid (ON DELETE CASCADE)

city_boundaries
    (standalone)
```

Countries must therefore be loaded before cities, administrative boundaries,
and airports. `scripts/pipeline.sh` enforces this order.

## Indexes

Spatial GIST indexes exist on the city point geometry and all four boundary
geometry columns. They support point containment and nearest-neighbour queries.

Text and code indexes include:

- GIN trigram indexes on country names, city names, city ASCII names, alternate
  city names, and airport names;
- B-tree indexes on airport ident, IATA code, and ICAO code;
- an index on alternate-name `geonameid`;
- unique indexes on country ISO alpha-2 and alpha-3 codes.

Administrative `shape_name` columns do not currently have trigram indexes.
Their API lookup is a case-insensitive exact match.

## Migration behavior

Run pending migrations with:

```bash
./scripts/run_migrations.sh
```

The initial migration begins by dropping every domain table and then rebuilding
the schema. Migration tracking prevents it from running repeatedly during
normal operation.

After changing an already-applied migration in development, rebuild with:

```bash
./scripts/pipeline.sh --reset
```

This removes migration tracking, reruns the destructive initial migration, and
reloads the data. Do not use `--reset` against a database whose contents must be
preserved.

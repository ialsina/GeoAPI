CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ─────────────────────────────────────────────────────────────────────────────
-- Clean slate — drop all tables so re-running this migration is always safe.
-- CASCADE handles FK dependencies automatically regardless of drop order.
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS airports        CASCADE;
DROP TABLE IF EXISTS cities_1000     CASCADE;
DROP TABLE IF EXISTS city_boundaries CASCADE;
DROP TABLE IF EXISTS adm0_boundaries CASCADE;
DROP TABLE IF EXISTS adm1_boundaries CASCADE;
DROP TABLE IF EXISTS adm2_boundaries CASCADE;
DROP TABLE IF EXISTS countries        CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- Countries
-- Source: https://github.com/datasets/country-codes/blob/main/data/country-codes.csv
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE countries (
    id          SERIAL PRIMARY KEY,
    -- Two-letter ISO 3166-1 alpha-2 code
    iso2        TEXT UNIQUE NOT NULL,
    -- Three-letter ISO 3166-1 alpha-3 code
    iso3        TEXT UNIQUE,
    -- Official English short name
    name        TEXT NOT NULL,
    -- Numeric country code (M49 / ISO 3166-1 numeric)
    m49_code    INTEGER,
    -- Region and sub-region names from the dataset
    region      TEXT,
    sub_region  TEXT,
    -- Capital city name
    capital     TEXT,
    -- Top-level domain (e.g. .us, .de)
    tld         TEXT,
    -- Primary continent (e.g. EU, AS, AF)
    continent   TEXT
);

-- ─────────────────────────────────────────────────────────────────────────────
-- ADM0 country-level boundaries
-- Source: geoBoundaries CGAZ — https://github.com/wmgeolab/geoBoundaries
-- GeoJSON properties present: shapeName, shapeGroup (ISO 3166-1 alpha-3), shapeType
-- NOTE: ADM0 features have NO unique shapeID; a serial PK is used instead.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE adm0_boundaries (
    id          SERIAL PRIMARY KEY,
    shape_name  TEXT,
    -- ISO 3166-1 alpha-3 (shapeGroup field in source data)
    country     TEXT,
    geom        GEOMETRY(MultiPolygon, 4326)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- ADM1 province/state-level boundaries
-- Source: geoBoundaries CGAZ — https://github.com/wmgeolab/geoBoundaries
-- GeoJSON properties present: shapeID, shapeName, shapeGroup (ISO 3166-1 alpha-3), shapeType
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE adm1_boundaries (
    -- shapeID from source data
    shape_id    TEXT PRIMARY KEY,
    shape_name  TEXT,
    -- ISO 3166-1 alpha-3 (shapeGroup field in source data)
    country     TEXT,
    geom        GEOMETRY(MultiPolygon, 4326)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- ADM2 sub-national boundaries
-- Source: geoBoundaries CGAZ
-- GeoJSON properties present: shapeID, shapeName, shapeGroup (ISO 3166-1 alpha-3), shapeType
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE adm2_boundaries (
    -- shapeID from source data
    shape_id    TEXT PRIMARY KEY,
    shape_name  TEXT,
    -- ISO 3166-1 alpha-3 (shapeGroup field in source data)
    country     TEXT,
    geom        GEOMETRY(MultiPolygon, 4326)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Cities ≥ 1000 population
-- Source: GeoNames cities1000 — https://download.geonames.org/export/dump/
-- File format: tab-separated, NO header row
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE cities_1000 (
    geonameid   BIGINT PRIMARY KEY,
    name        TEXT,
    asciiname   TEXT,
    -- ISO 3166-1 alpha-2 (country_code column in source)
    country     TEXT,
    population  BIGINT,
    latitude    DOUBLE PRECISION,
    longitude   DOUBLE PRECISION,
    geom        GEOMETRY(Point, 4326)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- City polygon boundaries
-- Source: geojson-world-cities submodule
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE city_boundaries (
    name  TEXT PRIMARY KEY,
    geom  GEOMETRY(MultiPolygon, 4326)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Airports
-- Source: OurAirports — https://ourairports.com/data/ (git submodule)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE airports (
    id           BIGINT PRIMARY KEY,
    ident        TEXT,
    type         TEXT,
    name         TEXT,
    -- ISO 3166-1 alpha-2 (iso_country column in source)
    country      TEXT,
    municipality TEXT,
    latitude     DOUBLE PRECISION,
    longitude    DOUBLE PRECISION,
    -- Elevation in metres (converted from feet at load time)
    elevation    DOUBLE PRECISION,
    iata         TEXT,
    icao         TEXT
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Indexes
-- ─────────────────────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX countries_iso2_idx        ON countries       (iso2);
CREATE UNIQUE INDEX countries_iso3_idx        ON countries       (iso3);
CREATE INDEX        countries_name_trgm_idx   ON countries       USING GIN (name gin_trgm_ops);

CREATE INDEX        cities_geom_idx           ON cities_1000     USING GIST (geom);
CREATE INDEX        cities_name_trgm_idx      ON cities_1000     USING GIN  (name gin_trgm_ops);
CREATE INDEX        cities_asciiname_trgm_idx ON cities_1000     USING GIN  (asciiname gin_trgm_ops);

CREATE INDEX        adm0_geom_idx             ON adm0_boundaries USING GIST (geom);
CREATE INDEX        adm1_geom_idx             ON adm1_boundaries USING GIST (geom);
CREATE INDEX        adm2_geom_idx             ON adm2_boundaries USING GIST (geom);

CREATE INDEX        city_boundaries_geom_idx  ON city_boundaries USING GIST (geom);

CREATE INDEX        airports_name_trgm_idx    ON airports        USING GIN (name gin_trgm_ops);
CREATE INDEX        airports_ident_idx        ON airports        (ident);
CREATE INDEX        airports_iata_idx         ON airports        (iata);
CREATE INDEX        airports_icao_idx         ON airports        (icao);

-- ─────────────────────────────────────────────────────────────────────────────
-- Foreign keys
-- ─────────────────────────────────────────────────────────────────────────────

-- cities_1000.country → countries.iso2  (GeoNames uses alpha-2)
ALTER TABLE cities_1000
    ADD CONSTRAINT fk_cities_1000_country
    FOREIGN KEY (country) REFERENCES countries (iso2);

-- adm0_boundaries.country → countries.iso3  (geoBoundaries shapeGroup is alpha-3)
ALTER TABLE adm0_boundaries
    ADD CONSTRAINT fk_adm0_boundaries_country
    FOREIGN KEY (country) REFERENCES countries (iso3);

-- adm1_boundaries.country → countries.iso3  (geoBoundaries shapeGroup is alpha-3)
ALTER TABLE adm1_boundaries
    ADD CONSTRAINT fk_adm1_boundaries_country
    FOREIGN KEY (country) REFERENCES countries (iso3);

-- adm2_boundaries.country → countries.iso3  (geoBoundaries shapeGroup is alpha-3)
ALTER TABLE adm2_boundaries
    ADD CONSTRAINT fk_adm2_boundaries_country
    FOREIGN KEY (country) REFERENCES countries (iso3);

-- airports.country → countries.iso2  (OurAirports iso_country is alpha-2)
ALTER TABLE airports
    ADD CONSTRAINT fk_airports_country
    FOREIGN KEY (country) REFERENCES countries (iso2);

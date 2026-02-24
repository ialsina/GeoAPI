CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ─────────────────────────────────────────────────────────────────────────────
-- Countries
-- Source: https://github.com/datasets/country-codes/blob/main/data/country-codes.csv
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS countries (
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
CREATE TABLE IF NOT EXISTS adm0_boundaries (
    id          SERIAL PRIMARY KEY,
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
CREATE TABLE IF NOT EXISTS adm2_boundaries (
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
CREATE TABLE IF NOT EXISTS cities_1000 (
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
CREATE TABLE IF NOT EXISTS city_boundaries (
    name  TEXT PRIMARY KEY,
    geom  GEOMETRY(MultiPolygon, 4326)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Airports
-- Source: OurAirports — https://ourairports.com/data/ (git submodule)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS airports (
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
CREATE UNIQUE INDEX IF NOT EXISTS countries_iso2_idx        ON countries      (iso2);
CREATE UNIQUE INDEX IF NOT EXISTS countries_iso3_idx        ON countries      (iso3);
CREATE INDEX        IF NOT EXISTS countries_name_trgm_idx   ON countries      USING GIN (name gin_trgm_ops);

CREATE INDEX        IF NOT EXISTS cities_geom_idx           ON cities_1000    USING GIST (geom);
CREATE INDEX        IF NOT EXISTS cities_name_trgm_idx      ON cities_1000    USING GIN  (name gin_trgm_ops);
CREATE INDEX        IF NOT EXISTS cities_asciiname_trgm_idx ON cities_1000    USING GIN  (asciiname gin_trgm_ops);

CREATE INDEX        IF NOT EXISTS adm0_geom_idx             ON adm0_boundaries USING GIST (geom);
CREATE INDEX        IF NOT EXISTS adm2_geom_idx             ON adm2_boundaries USING GIST (geom);

CREATE INDEX        IF NOT EXISTS city_boundaries_geom_idx  ON city_boundaries USING GIST (geom);

CREATE INDEX        IF NOT EXISTS airports_name_trgm_idx    ON airports       USING GIN (name gin_trgm_ops);
CREATE INDEX        IF NOT EXISTS airports_ident_idx        ON airports       (ident);
CREATE INDEX        IF NOT EXISTS airports_iata_idx         ON airports       (iata);
CREATE INDEX        IF NOT EXISTS airports_icao_idx         ON airports       (icao);

-- ─────────────────────────────────────────────────────────────────────────────
-- Foreign keys (wrapped in DO blocks so re-running this migration is safe)
-- ─────────────────────────────────────────────────────────────────────────────

-- cities_1000.country → countries.iso2  (GeoNames uses alpha-2)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_cities_1000_country'
    ) THEN
        ALTER TABLE cities_1000
            ADD CONSTRAINT fk_cities_1000_country
            FOREIGN KEY (country) REFERENCES countries (iso2);
    END IF;
END $$;

-- adm0_boundaries.country → countries.iso3  (geoBoundaries shapeGroup is alpha-3)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_adm0_boundaries_country'
    ) THEN
        ALTER TABLE adm0_boundaries
            ADD CONSTRAINT fk_adm0_boundaries_country
            FOREIGN KEY (country) REFERENCES countries (iso3);
    END IF;
END $$;

-- adm2_boundaries.country → countries.iso3  (geoBoundaries shapeGroup is alpha-3)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_adm2_boundaries_country'
    ) THEN
        ALTER TABLE adm2_boundaries
            ADD CONSTRAINT fk_adm2_boundaries_country
            FOREIGN KEY (country) REFERENCES countries (iso3);
    END IF;
END $$;

-- airports.country → countries.iso2  (OurAirports iso_country is alpha-2)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_airports_country'
    ) THEN
        ALTER TABLE airports
            ADD CONSTRAINT fk_airports_country
            FOREIGN KEY (country) REFERENCES countries (iso2);
    END IF;
END $$;

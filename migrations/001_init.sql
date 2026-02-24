CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Countries table based on https://github.com/datasets/country-codes/blob/main/data/country-codes.csv
-- Source columns are documented in that dataset; we only keep a useful subset for the API.

CREATE TABLE countries (
    id SERIAL PRIMARY KEY,
    -- Two-letter ISO 3166-1 alpha-2 code
    iso2 TEXT UNIQUE NOT NULL,
    -- Three-letter ISO 3166-1 alpha-3 code
    iso3 TEXT,
    -- Official English short name
    name TEXT NOT NULL,
    -- Numeric country code (M49 / ISO 3166-1 numeric)
    m49_code INTEGER,
    -- Region and sub-region names from the dataset
    region TEXT,
    sub_region TEXT,
    -- Capital city name
    capital TEXT,
    -- Top-level domain (e.g. .us, .de)
    tld TEXT,
    -- Primary continent (e.g. EU, AS, AF)
    continent TEXT
);

CREATE TABLE adm0_boundaries (
    shape_id TEXT PRIMARY KEY,
    shape_name TEXT,
    country TEXT,
    geom GEOMETRY(MultiPolygon, 4326)
);

CREATE TABLE adm2_boundaries (
    shape_id TEXT PRIMARY KEY,
    shape_name TEXT,
    country TEXT,
    geom GEOMETRY(MultiPolygon, 4326)
);

CREATE TABLE cities_1000 (
    geonameid BIGINT PRIMARY KEY,
    name TEXT,
    asciiname TEXT,
    country TEXT,
    population BIGINT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    geom GEOMETRY(Point, 4326)
);

CREATE TABLE city_boundaries (
    name TEXT PRIMARY KEY,
    geom GEOMETRY(MultiPolygon, 4326)
);

CREATE TABLE airports (
    id BIGINT PRIMARY KEY,
    ident TEXT,
    type TEXT,
    name TEXT,
    country TEXT,
    municipality TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    elevation DOUBLE PRECISION,
    iata TEXT,
    icao TEXT
);

CREATE UNIQUE INDEX countries_iso2_idx ON countries (iso2);
CREATE UNIQUE INDEX countries_iso3_idx ON countries (iso3);
CREATE INDEX countries_name_trgm_idx ON countries USING GIN (name gin_trgm_ops);
CREATE INDEX cities_geom_idx ON cities_1000 USING GIST (geom);
CREATE INDEX cities_name_trgm_idx ON cities_1000 USING GIN (name gin_trgm_ops);
CREATE INDEX cities_asciiname_trgm_idx ON cities_1000 USING GIN (asciiname gin_trgm_ops);
CREATE INDEX adm0_geom_idx ON adm0_boundaries USING GIST (geom);
CREATE INDEX adm2_geom_idx ON adm2_boundaries USING GIST (geom);
CREATE INDEX city_boundaries_geom_idx ON city_boundaries USING GIST (geom);
CREATE INDEX airports_name_trgm_idx ON airports USING GIN (name gin_trgm_ops);
CREATE INDEX airports_ident_idx ON airports (ident);
CREATE INDEX airports_iata_idx ON airports (iata);
CREATE INDEX airports_icao_idx ON airports (icao);

ALTER TABLE cities_1000
    ADD CONSTRAINT fk_cities_1000_country
    FOREIGN KEY (country) REFERENCES countries (iso2);

ALTER TABLE adm0_boundaries
    ADD CONSTRAINT fk_adm0_boundaries_country
    FOREIGN KEY (country) REFERENCES countries (iso2);

ALTER TABLE adm2_boundaries
    ADD CONSTRAINT fk_adm2_boundaries_country
    FOREIGN KEY (country) REFERENCES countries (iso2);

ALTER TABLE airports
    ADD CONSTRAINT fk_airports_country
    FOREIGN KEY (country) REFERENCES countries (iso2);


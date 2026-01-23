CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE cities_1000 (
    geonameid BIGINT PRIMARY KEY,
    name TEXT,
    asciiname TEXT,
    country_code TEXT,
    population BIGINT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    geom GEOMETRY(Point, 4326)
);

CREATE TABLE adm2_boundaries (
    shape_id TEXT PRIMARY KEY,
    shape_name TEXT,
    country_code TEXT,
    geom GEOMETRY(MultiPolygon, 4326)
);

CREATE INDEX cities_geom_idx ON cities_1000 USING GIST (geom);
CREATE INDEX cities_name_trgm_idx ON cities_1000 USING GIN (name gin_trgm_ops);
CREATE INDEX cities_asciiname_trgm_idx ON cities_1000 USING GIN (asciiname gin_trgm_ops);
CREATE INDEX adm2_geom_idx ON adm2_boundaries USING GIST (geom);


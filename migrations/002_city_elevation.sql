ALTER TABLE cities_1000
    ADD COLUMN IF NOT EXISTS elevation INTEGER;

-- Backfill deployments populated before elevation was retained. The source
-- GeoNames file is kept in the shared data directory by the import pipeline.
CREATE TEMP TABLE tmp_city_elevations (
    geonameid         BIGINT,
    name              TEXT,
    asciiname         TEXT,
    alternatenames    TEXT,
    latitude          DOUBLE PRECISION,
    longitude         DOUBLE PRECISION,
    feature_class     TEXT,
    feature_code      TEXT,
    country_code      TEXT,
    cc2               TEXT,
    admin1_code       TEXT,
    admin2_code       TEXT,
    admin3_code       TEXT,
    admin4_code       TEXT,
    population        BIGINT,
    elevation         INTEGER,
    dem               INTEGER,
    timezone          TEXT,
    modification_date DATE
);

COPY tmp_city_elevations
FROM '/data/cities1000/cities1000.txt'
DELIMITER E'\t'
CSV;

UPDATE cities_1000 AS city
SET elevation = source.elevation
FROM tmp_city_elevations AS source
WHERE source.geonameid = city.geonameid;

DROP TABLE tmp_city_elevations;

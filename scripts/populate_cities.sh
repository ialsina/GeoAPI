#!/bin/bash
set -e

# Populates cities_1000 table from cities1000.txt
# Works with data/ one level above scripts/

DB_CONTAINER="city-db"
CSV_PATH="/data/cities1000/cities1000.txt"

echo "Populating cities_1000..."

docker exec -i $DB_CONTAINER psql -U geouser -d geodb <<SQL
-- Optional: truncate table to re-run safely
TRUNCATE TABLE cities_1000;

-- Temporary table matching full CSV
CREATE TEMP TABLE tmp_cities (
    geonameid BIGINT,
    name TEXT,
    asciiname TEXT,
    alternatenames TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    feature_class TEXT,
    feature_code TEXT,
    country_code TEXT,
    cc2 TEXT,
    admin1_code TEXT,
    admin2_code TEXT,
    admin3_code TEXT,
    admin4_code TEXT,
    population BIGINT,
    elevation INT,
    dem INT,
    timezone TEXT,
    modification_date DATE
);

-- Import CSV into temporary table
COPY tmp_cities
FROM '$CSV_PATH'
DELIMITER E'\t'
CSV HEADER;

-- Insert needed columns into cities_1000
INSERT INTO cities_1000(geonameid, name, asciiname, country_code, population, latitude, longitude, geom)
SELECT geonameid, name, asciiname, country_code, population, latitude, longitude,
       ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
FROM tmp_cities;

DROP TABLE tmp_cities;

-- Verify
SELECT COUNT(*) AS total_cities FROM cities_1000;
SQL

echo "cities_1000 populated."

#!/usr/bin/env bash
set -euo pipefail

# Populates the cities_1000 table from data/cities1000/cities1000.txt.
# The data/ directory is mounted read-only at /data inside the DB container
# (see docker-compose.yml), so COPY FROM uses the /data container path.
#
# GeoNames cities1000.txt is a tab-separated file with NO header row.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

HOST_TXT="${DATA_DIR}/cities1000/cities1000.txt"
CONTAINER_TXT="/data/cities1000/cities1000.txt"

require_file "${HOST_TXT}"

echo "Populating cities_1000..."

docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << SQL
TRUNCATE TABLE cities_1000_alternate_names;
TRUNCATE TABLE cities_1000;

-- Temporary table matching all 19 columns of the GeoNames cities1000 format
-- (tab-separated, no header — see https://download.geonames.org/export/dump/readme.txt)
CREATE TEMP TABLE tmp_cities (
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

-- GeoNames files are tab-separated with NO header row.
COPY tmp_cities
FROM '${CONTAINER_TXT}'
DELIMITER E'\t'
CSV;

-- Set country to NULL when country_code is not in countries (disputed territories, unused codes)
INSERT INTO cities_1000 (geonameid, name, asciiname, country, population, latitude, longitude, geom)
SELECT
    t.geonameid,
    t.name,
    t.asciiname,
    CASE WHEN t.country_code IN (SELECT iso2 FROM countries WHERE iso2 IS NOT NULL)
         THEN t.country_code END,
    t.population,
    t.latitude,
    t.longitude,
    ST_SetSRID(ST_MakePoint(t.longitude, t.latitude), 4326)
FROM tmp_cities t;

-- Populate alternate names by splitting the comma-separated alternatenames
-- column. Only insert names for cities present in cities_1000.
INSERT INTO cities_1000_alternate_names (geonameid, name)
SELECT t.geonameid, trim(alt_name)
FROM tmp_cities t
CROSS JOIN LATERAL unnest(string_to_array(t.alternatenames, ',')) AS alt_name
WHERE t.alternatenames <> ''
  AND trim(alt_name) <> ''
  AND t.geonameid IN (SELECT geonameid FROM cities_1000);

DROP TABLE tmp_cities;

SELECT COUNT(*) AS total_cities       FROM cities_1000;
SELECT COUNT(*) AS total_alt_names    FROM cities_1000_alternate_names;
SQL

echo "cities_1000 and cities_1000_alternate_names tables populated."

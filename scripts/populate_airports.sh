#!/bin/bash
set -e

# Populates airports table from airports.csv
# Works with ourairports-data submodule one level above scripts/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CSV_PATH="${ROOT_DIR}/ourairports-data/airports.csv"
CONTAINER_CSV_PATH="/tmp/airports.csv"

DB_CONTAINER="geoapi-db"

echo "Copying airports.csv into container..."
docker cp "$CSV_PATH" "${DB_CONTAINER}:${CONTAINER_CSV_PATH}"

echo "Populating airports..."

docker exec -i $DB_CONTAINER psql -U geouser -d geodb <<SQL
-- Optional: truncate table to re-run safely
TRUNCATE TABLE airports;

-- Temporary table matching full CSV
CREATE TEMP TABLE tmp_airports (
    id BIGINT,
    ident TEXT,
    type TEXT,
    name TEXT,
    latitude_deg DOUBLE PRECISION,
    longitude_deg DOUBLE PRECISION,
    elevation_ft INT,
    continent TEXT,
    iso_country TEXT,
    iso_region TEXT,
    municipality TEXT,
    scheduled_service TEXT,
    icao_code TEXT,
    iata_code TEXT,
    gps_code TEXT,
    local_code TEXT,
    home_link TEXT,
    wikipedia_link TEXT,
    keywords TEXT
);

-- Import CSV into temporary table
COPY tmp_airports
FROM '$CONTAINER_CSV_PATH'
WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Insert needed columns into airports
-- Convert elevation from feet to meters (1 foot = 0.3048 meters)
INSERT INTO airports(id, ident, type, name, iso_country, municipality, latitude, longitude, elevation, iata_code, icao_code)
SELECT id, ident, type, name, iso_country, municipality, latitude_deg, longitude_deg,
       CASE WHEN elevation_ft IS NOT NULL THEN elevation_ft * 0.3048 ELSE NULL END,
       UPPER(iata_code), UPPER(icao_code)
FROM tmp_airports
WHERE latitude_deg IS NOT NULL AND longitude_deg IS NOT NULL;

DROP TABLE tmp_airports;

-- Verify
SELECT COUNT(*) AS total_airports FROM airports;
SQL

echo "Cleaning up temporary file..."
docker exec $DB_CONTAINER rm -f "$CONTAINER_CSV_PATH"

echo "airports populated."


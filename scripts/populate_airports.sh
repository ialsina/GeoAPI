#!/usr/bin/env bash
set -euo pipefail

# Populates the airports table from ourairports-data/airports.csv.
# The CSV is copied into the container at runtime because the submodule
# directory is not part of the docker-compose data/ volume mount.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

HOST_CSV="${ROOT_DIR}/ourairports-data/airports.csv"
CONTAINER_CSV="/tmp/airports.csv"

require_file "${HOST_CSV}"

echo "Copying airports.csv into container..."
docker cp "$HOST_CSV" "${DB_CONTAINER}:${CONTAINER_CSV}"

echo "Populating airports..."

docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << SQL
TRUNCATE TABLE airports;

-- Temporary table matching all columns in the OurAirports airports.csv
CREATE TEMP TABLE tmp_airports (
    id                BIGINT,
    ident             TEXT,
    type              TEXT,
    name              TEXT,
    latitude_deg      DOUBLE PRECISION,
    longitude_deg     DOUBLE PRECISION,
    elevation_ft      INTEGER,
    continent         TEXT,
    iso_country       TEXT,
    iso_region        TEXT,
    municipality      TEXT,
    scheduled_service TEXT,
    icao_code         TEXT,
    iata_code         TEXT,
    gps_code          TEXT,
    local_code        TEXT,
    home_link         TEXT,
    wikipedia_link    TEXT,
    keywords          TEXT
);

COPY tmp_airports
FROM '${CONTAINER_CSV}'
WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Elevation converted from feet to metres (1 ft = 0.3048 m).
-- Rows without coordinates are skipped; they cannot be geo-located.
INSERT INTO airports (id, ident, type, name, country, municipality,
                      latitude, longitude, elevation, iata, icao)
SELECT
    id,
    ident,
    type,
    name,
    iso_country,
    municipality,
    latitude_deg,
    longitude_deg,
    CASE WHEN elevation_ft IS NOT NULL THEN elevation_ft * 0.3048 END,
    UPPER(NULLIF(iata_code, '')),
    UPPER(NULLIF(icao_code, ''))
FROM tmp_airports
WHERE latitude_deg IS NOT NULL
  AND longitude_deg IS NOT NULL;

DROP TABLE tmp_airports;

SELECT COUNT(*) AS total_airports FROM airports;
SQL

echo "Cleaning up temporary file in container..."
docker exec "$DB_CONTAINER" rm -f "$CONTAINER_CSV"

echo "airports table populated."

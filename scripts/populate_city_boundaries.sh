#!/bin/bash
set -euo pipefail

# ============================
# Configuration
# ============================
DB_HOST="db"
DB_NAME="geodb"
DB_USER="geouser"
DB_PASS="geopass"
DOCKER_NETWORK="geoapi_default"

# Path inside the Docker volume (geojson-world-cities/ mounted to /data/geojson-world-cities)
GEOJSON_FILE="/data/geojson-world-cities/cities.geojson"

# ============================
# Helper function
# ============================
function check_file_exists() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "ERROR: File not found: $file"
    exit 1
  fi
}

# ============================
# Populate city_boundaries
# ============================
echo "Populating city_boundaries..."

# Resolve paths relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GEOJSON_PATH="${ROOT_DIR}/geojson-world-cities/cities.geojson"

check_file_exists "${GEOJSON_PATH}"

docker run --rm \
  --network "$DOCKER_NETWORK" \
  -v "$(realpath "${ROOT_DIR}/geojson-world-cities"):/data/geojson-world-cities:ro" \
  -e PGUSER="$DB_USER" \
  -e PGPASSWORD="$DB_PASS" \
  ghcr.io/osgeo/gdal:alpine-small-3.8.4 \
  ogr2ogr \
  -f PostgreSQL \
  PG:"dbname=$DB_NAME user=$DB_USER password=$DB_PASS host=$DB_HOST" \
  "$GEOJSON_FILE" \
  -nln city_boundaries \
  -lco GEOMETRY_NAME=geom \
  -nlt MULTIPOLYGON \
  -a_srs "EPSG:4326" \
  -overwrite \
  -sql "SELECT NAME as name FROM cities"

echo "city_boundaries populated successfully!"


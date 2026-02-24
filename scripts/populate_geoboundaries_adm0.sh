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

# Path inside the Docker volume (data/ mounted to /data)
GEOJSON_FILE="/data/geoBoundaries/geoBoundariesCGAZ_ADM0.geojson"

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
# Populate adm0_boundaries
# ============================
echo "Populating adm0_boundaries..."

docker run --rm \
  --network "$DOCKER_NETWORK" \
  -v "$(realpath ../data):/data:ro" \
  -e PGUSER="$DB_USER" \
  -e PGPASSWORD="$DB_PASS" \
  ghcr.io/osgeo/gdal:alpine-small-3.8.4 \
  ogr2ogr \
  -f PostgreSQL \
  PG:"dbname=$DB_NAME user=$DB_USER password=$DB_PASS host=$DB_HOST" \
  "$GEOJSON_FILE" \
  -nln adm0_boundaries \
  -lco GEOMETRY_NAME=geom \
  -nlt MULTIPOLYGON \
  -a_srs "EPSG:4326" \
  -overwrite \
  -select shapeID,shapeName,shapeGroup,shapeType

echo "adm0_boundaries populated successfully!"



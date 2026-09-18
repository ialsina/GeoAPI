#!/usr/bin/env bash
set -euo pipefail

# Populates the city_boundaries table from the geojson-world-cities submodule.
# The submodule lives in the image at /app/geojson-world-cities, so the GeoJSON
# is staged onto the shared data volume before ogr2ogr runs.
#
# city_boundaries has no FK to countries, so -overwrite is safe here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

SUBMODULE_DIR="${ROOT_DIR}/geojson-world-cities"
SOURCE_GEOJSON="${SUBMODULE_DIR}/cities.geojson"
STAGED_GEOJSON="${DATA_DIR}/city_boundaries/cities.geojson"
DB_GEOJSON="${DB_DATA_DIR}/city_boundaries/cities.geojson"

require_file "${SOURCE_GEOJSON}"

echo "Staging city boundaries GeoJSON on the shared data volume..."
mkdir -p "$(dirname "${STAGED_GEOJSON}")"
cp -f "${SOURCE_GEOJSON}" "${STAGED_GEOJSON}"
require_db_data_file "${DB_GEOJSON}" "${STAGED_GEOJSON}"

echo "Populating city_boundaries..."

run_gdal_ogr2ogr \
	-f PostgreSQL \
	"PG:dbname=${DB_NAME} user=${DB_USER} password=${DB_PASS} host=${DB_HOST}" \
	"${STAGED_GEOJSON}" \
	-nln city_boundaries \
	-nlt MULTIPOLYGON \
	-lco GEOMETRY_NAME=geom \
	-a_srs "EPSG:4326" \
	-overwrite \
	-sql "SELECT NAME AS name FROM cities"

echo "city_boundaries table populated."

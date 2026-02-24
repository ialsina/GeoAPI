#!/usr/bin/env bash
set -euo pipefail

# Populates the city_boundaries table from the geojson-world-cities submodule.
# The submodule lives outside data/ so it is bind-mounted separately into the
# ephemeral ogr2ogr container.
#
# city_boundaries has no FK to countries, so -overwrite is safe here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

SUBMODULE_DIR="${ROOT_DIR}/geojson-world-cities"
HOST_GEOJSON="${SUBMODULE_DIR}/cities.geojson"
CONTAINER_GEOJSON="/data/geojson-world-cities/cities.geojson"

require_file "${HOST_GEOJSON}"

echo "Populating city_boundaries..."

docker run --rm \
	--network "${DOCKER_NETWORK}" \
	-v "${SUBMODULE_DIR}:/data/geojson-world-cities:ro" \
	-e PGPASSWORD="${DB_PASS}" \
	"${GDAL_IMAGE}" \
	ogr2ogr \
	-f PostgreSQL \
	"PG:dbname=${DB_NAME} user=${DB_USER} password=${DB_PASS} host=${DB_HOST}" \
	"${CONTAINER_GEOJSON}" \
	-nln city_boundaries \
	-nlt MULTIPOLYGON \
	-lco GEOMETRY_NAME=geom \
	-a_srs "EPSG:4326" \
	-overwrite \
	-sql "SELECT NAME AS name FROM cities"

echo "city_boundaries table populated."

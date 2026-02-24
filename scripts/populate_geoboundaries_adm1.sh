#!/usr/bin/env bash
set -euo pipefail

# Populates the adm1_boundaries table from the geoBoundaries CGAZ ADM1 GeoJSON.
#
# Two-step approach to preserve the migration-defined schema and FK constraints:
#   1. ogr2ogr loads the GeoJSON into a disposable staging table.
#   2. A psql step transfers from staging → adm1_boundaries with explicit column
#      mapping, filtering to only shapeGroup values present in countries.iso3.
#
# Source GeoJSON properties: shapeID, shapeName, shapeGroup (ISO 3166-1 alpha-3), shapeType

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

HOST_GEOJSON="${DATA_DIR}/geoBoundaries/geoBoundariesCGAZ_ADM1.geojson"
CONTAINER_GEOJSON="/data/geoBoundaries/geoBoundariesCGAZ_ADM1.geojson"

require_file "${HOST_GEOJSON}"

# ── Step 1: Load raw GeoJSON into a staging table via ogr2ogr ─────────────────
# -overwrite on the staging table is intentional — it has no FK constraints.
# ogr2ogr lowercases field names: shapeID→shapeid, shapeName→shapename, etc.
echo "Loading ADM1 GeoJSON into staging table..."

docker run --rm \
	--network "${DOCKER_NETWORK}" \
	-v "${DATA_DIR}:/data:ro" \
	-e PGPASSWORD="${DB_PASS}" \
	"${GDAL_IMAGE}" \
	ogr2ogr \
	-f PostgreSQL \
	"PG:dbname=${DB_NAME} user=${DB_USER} password=${DB_PASS} host=${DB_HOST}" \
	"${CONTAINER_GEOJSON}" \
	-nln staging_adm1 \
	-nlt MULTIPOLYGON \
	-lco GEOMETRY_NAME=geom \
	-a_srs "EPSG:4326" \
	-overwrite

# ── Step 2: Transfer from staging → final table ───────────────────────────────
# Rows whose shapeGroup has no matching iso3 in countries (e.g. disputed
# territories) are skipped to satisfy the FK constraint.
echo "Transferring ADM1 data to adm1_boundaries..."

docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << SQL
TRUNCATE TABLE adm1_boundaries;

INSERT INTO adm1_boundaries (shape_id, shape_name, country, geom)
SELECT
	shapeid    AS shape_id,
	shapename  AS shape_name,
	shapegroup AS country,
	ST_Multi(geom)::GEOMETRY(MultiPolygon, 4326)
FROM staging_adm1
WHERE shapegroup IN (SELECT iso3 FROM countries WHERE iso3 IS NOT NULL);

DROP TABLE IF EXISTS staging_adm1;

SELECT COUNT(*) AS total_adm1 FROM adm1_boundaries;
SQL

echo "adm1_boundaries table populated."

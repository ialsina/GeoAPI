#!/usr/bin/env bash
set -euo pipefail

# Populates the adm0_boundaries table from the geoBoundaries CGAZ ADM0 GeoJSON.
#
# Two-step approach to preserve the migration-defined schema and FK constraints:
#   1. ogr2ogr loads the GeoJSON into a disposable staging table.
#   2. A psql step transfers from staging → adm0_boundaries with explicit column
#      mapping, filtering to only shapeGroup values present in countries.iso3.
#
# Source GeoJSON properties: shapeName, shapeGroup (ISO 3166-1 alpha-3), shapeType
# NOTE: ADM0 features have no shapeID field.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

HOST_GEOJSON="${DATA_DIR}/geoBoundaries/geoBoundariesCGAZ_ADM0.geojson"
CONTAINER_GEOJSON="/data/geoBoundaries/geoBoundariesCGAZ_ADM0.geojson"

require_file "${HOST_GEOJSON}"

# ── Step 1: Load raw GeoJSON into a staging table via ogr2ogr ─────────────────
# -overwrite on the staging table is intentional — it has no FK constraints.
# ogr2ogr lowercases field names: shapeName→shapename, shapeGroup→shapegroup.
echo "Loading ADM0 GeoJSON into staging table..."

docker run --rm \
	--network "${DOCKER_NETWORK}" \
	-v "${DATA_DIR}:/data:ro" \
	-e PGPASSWORD="${DB_PASS}" \
	"${GDAL_IMAGE}" \
	ogr2ogr \
	-f PostgreSQL \
	"PG:dbname=${DB_NAME} user=${DB_USER} password=${DB_PASS} host=${DB_HOST}" \
	"${CONTAINER_GEOJSON}" \
	-nln staging_adm0 \
	-nlt MULTIPOLYGON \
	-lco GEOMETRY_NAME=geom \
	-a_srs "EPSG:4326" \
	-overwrite

# ── Step 2: Transfer from staging → final table ───────────────────────────────
# Rows whose shapeGroup has no matching iso3 in countries (e.g. disputed
# territories) are skipped to satisfy the FK constraint.
echo "Transferring ADM0 data to adm0_boundaries..."

docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << SQL
TRUNCATE TABLE adm0_boundaries;

INSERT INTO adm0_boundaries (shape_name, country, geom)
SELECT
    shapename   AS shape_name,
    shapegroup  AS country,
    ST_Multi(geom)::GEOMETRY(MultiPolygon, 4326)
FROM staging_adm0
WHERE shapegroup IN (SELECT iso3 FROM countries WHERE iso3 IS NOT NULL);

DROP TABLE IF EXISTS staging_adm0;

SELECT COUNT(*) AS total_adm0 FROM adm0_boundaries;
SQL

echo "adm0_boundaries table populated."

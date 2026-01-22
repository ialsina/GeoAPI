#!/bin/bash
set -e

# Populates adm2_boundaries table from geoBoundaries GeoJSON
# Works with data/ one level above scripts/

DB_HOST="db"
DB_NAME="geodb"
DB_USER="geouser"
DB_PASS="geopass"
DOCKER_NETWORK="city-api_default"
GEOJSON_PATH="/data/geoBoundaries/geoBoundariesCGAZ_ADM2.geojson"

echo "Populating adm2_boundaries..."

docker run --rm \
  --network $DOCKER_NETWORK \
  -v "$(dirname "$PWD")/data:/data:ro" \
  -e PGUSER=$DB_USER \
  -e PGPASSWORD=$DB_PASS \
  ghcr.io/osgeo/gdal:alpine-small-3.8.4 \
  ogr2ogr \
  -f PostgreSQL \
  PG:"dbname=$DB_NAME user=$DB_USER password=$DB_PASS host=$DB_HOST" \
  /data/geoBoundaries/geoBoundariesCGAZ_ADM2.geojson \
  -nln adm2_boundaries \
  -lco GEOMETRY_NAME=geom \
  -nlt MULTIPOLYGON \
  -a_srs "EPSG:4326"

echo "adm2_boundaries populated."

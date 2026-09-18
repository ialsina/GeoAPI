#!/usr/bin/env bash
# =============================================================================
# common.sh — Shared configuration and helpers for GeoAPI pipeline scripts.
#
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# =============================================================================

# ── Paths ─────────────────────────────────────────────────────────────────────
# Always resolved relative to this file so scripts can be called from anywhere.
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPTS_DIR}/.." && pwd)"
DATA_DIR="${GEOAPI_DATA_DIR:-${ROOT_DIR}/data}"
# Container name for --volumes-from when spawning GDAL from inside geoapi-api.
GEOAPI_API_CONTAINER="${GEOAPI_API_CONTAINER:-geoapi-api}"
# Path prefix inside the PostGIS container (see docker-compose /data mount).
DB_DATA_DIR="/data"

# ── Database ──────────────────────────────────────────────────────────────────
# DB_CONTAINER : docker container_name (used with docker exec)
# DB_HOST      : service hostname reachable from other containers on the same network
# DOCKER_NETWORK : network for ogr2ogr/GDAL steps (must include the DB container)
#
# Preset by compose file: set GEOAPI_COMPOSE=dev when using docker-compose.dev.yml
# from the repo root (or set COMPOSE_FILE to a path containing "docker-compose.dev").
# Individual DB_CONTAINER / DB_HOST / DOCKER_NETWORK still override the preset.
DB_NAME="${DB_NAME:-geodb}"
DB_USER="${DB_USER:-geouser}"
DB_PASS="${DB_PASS:-geopass}"

_geoapi_compose_preset() {
	if [[ "${GEOAPI_COMPOSE:-}" == "dev" ]]; then
		return 0
	fi
	[[ -n "${COMPOSE_FILE:-}" && "${COMPOSE_FILE}" == *"docker-compose.dev"* ]]
}

if _geoapi_compose_preset; then
	DB_CONTAINER="${DB_CONTAINER:-geo-db-dev}"
	DB_HOST="${DB_HOST:-geo-db}"
	DOCKER_NETWORK="${DOCKER_NETWORK:-city-orchestration_city-orchestration-dev}"
else
	DB_CONTAINER="${DB_CONTAINER:-geoapi-db}"
	DB_HOST="${DB_HOST:-db}"
	DOCKER_NETWORK="${DOCKER_NETWORK:-geoapi_default}"
fi

# Auto-detect dev stack: if default container is not running but geo-db-dev is, use it
# (Must set DOCKER_NETWORK too, else GDAL/ogr2ogr steps still use geoapi_default.)
_container_running() { docker inspect "$1" --format '{{.State.Running}}' 2> /dev/null | grep -q true; }
if ! _container_running "$DB_CONTAINER"; then
	if _container_running "geo-db-dev"; then
		DB_CONTAINER="geo-db-dev"
		DB_HOST="geo-db"
		DOCKER_NETWORK="$(docker inspect geo-db-dev --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)"
		[[ -z "$DOCKER_NETWORK" ]] && DOCKER_NETWORK="city-orchestration_city-orchestration-dev"
	fi
fi

# ── GDAL image (ogr2ogr) ──────────────────────────────────────────────────────
GDAL_IMAGE="ghcr.io/osgeo/gdal:alpine-small-3.8.4"

# geoBoundaries CGAZ GeoJSON files are stored in Git LFS. github.com/raw/ URLs
# return pointer stubs that GDAL cannot read; media.githubusercontent.com serves
# the actual file bytes.
geoboundaries_cgaz_url() {
	local level="$1"
	echo "https://media.githubusercontent.com/media/wmgeolab/geoBoundaries/main/releaseData/CGAZ/geoBoundariesCGAZ_${level}.geojson"
}

# Return 0 when the file looks like a real GeoJSON FeatureCollection.
is_valid_geoboundaries_geojson() {
	local file="$1"
	[[ -s "${file}" ]] || return 1
	if head -c 128 "${file}" | grep -q 'git-lfs.github.com/spec/v1'; then
		return 1
	fi
	head -c 1 "${file}" | grep -q '{'
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# Die with a message if a required file is absent.
require_file() {
	local file="$1"
	if [[ ! -f "$file" ]]; then
		echo "ERROR: Required file not found: ${file}"
		echo "       Run the corresponding download script first."
		exit 1
	fi
}

# Die if a geoBoundaries GeoJSON file is missing or is a Git LFS pointer stub.
require_geoboundaries_geojson() {
	local file="$1"
	require_file "${file}"
	if is_valid_geoboundaries_geojson "${file}"; then
		return 0
	fi
	echo "ERROR: Invalid geoBoundaries GeoJSON: ${file}"
	echo "       The file is empty or looks like a Git LFS pointer."
	echo "       Re-run the corresponding download script with --force."
	exit 1
}

# Die unless a file is visible on the PostGIS /data bind mount (used by COPY FROM).
require_db_data_file() {
	local container_path="$1"
	local label="${2:-${container_path}}"

	if docker exec "${DB_CONTAINER}" test -f "${container_path}" 2> /dev/null; then
		return 0
	fi

	echo "ERROR: ${label} is not visible inside ${DB_CONTAINER} at ${container_path}"
	echo "       Pipeline DATA_DIR: ${DATA_DIR}"
	echo "       PostGIS and geoapi-api must bind-mount the same host directory."
	exit 1
}

# Validate geoBoundaries content on the PostGIS /data mount before ogr2ogr.
require_db_geoboundaries_geojson() {
	local container_path="$1"
	local header=""

	require_db_data_file "${container_path}"
	header="$(docker exec "${DB_CONTAINER}" head -c 128 "${container_path}" 2> /dev/null || true)"
	if echo "${header}" | grep -q 'git-lfs.github.com/spec/v1'; then
		echo "ERROR: ${container_path} on ${DB_CONTAINER} is a Git LFS pointer."
		echo "       Re-run the geoBoundaries download scripts with --force."
		exit 1
	fi
	if ! echo "${header}" | grep -q '{'; then
		echo "ERROR: ${container_path} on ${DB_CONTAINER} is not valid GeoJSON."
		exit 1
	fi
}

# Run ogr2ogr in GDAL sharing geoapi-api's bind mounts (avoids host path guessing).
run_gdal_ogr2ogr() {
	docker run --rm \
		--network "${DOCKER_NETWORK}" \
		--volumes-from "${GEOAPI_API_CONTAINER}:ro" \
		-e PGPASSWORD="${DB_PASS}" \
		"${GDAL_IMAGE}" \
		ogr2ogr "$@"
}

# Prefixed log line (uses the calling script's basename).
log() { echo "[$(basename "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")] $*"; }

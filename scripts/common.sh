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

# Minimum byte size (≈95% of upstream Content-Length) to catch truncated downloads.
geoboundaries_min_bytes() {
	case "$1" in
		ADM0) echo 380000000 ;;
		ADM1) echo 340000000 ;;
		ADM2) echo 520000000 ;;
		*) echo 100000000 ;;
	esac
}

_geoboundaries_level_from_path() {
	basename "$1" | sed -n 's/^geoBoundariesCGAZ_\(ADM[0-2]\)\.geojson$/\1/p'
}

geoboundaries_file_size_ok() {
	local level="$1"
	local file="$2"
	local min_bytes size

	min_bytes="$(geoboundaries_min_bytes "${level}")"
	size="$(stat -c%s "${file}" 2> /dev/null || wc -c < "${file}" | tr -d '[:space:]')"
	[[ "${size}" -ge "${min_bytes}" ]]
}

# Return 0 when GDAL can open the GeoJSON (catches truncated/corrupt files).
geoboundaries_geojson_readable() {
	local file="$1"
	local gdal_file="${file}"

	is_valid_geoboundaries_geojson "${file}" || return 1

	if ! command -v docker > /dev/null 2>&1; then
		return 0
	fi

	if _container_running "${GEOAPI_API_CONTAINER}"; then
		docker run --rm \
			--volumes-from "${GEOAPI_API_CONTAINER}:ro" \
			"${GDAL_IMAGE}" \
			ogrinfo -ro -q -so "${gdal_file}" > /dev/null 2>&1
		return $?
	fi

	gdal_file="/app/data/geoBoundaries/$(basename "${file}")"
	docker run --rm \
		-v "${DATA_DIR}:/app/data:ro" \
		"${GDAL_IMAGE}" \
		ogrinfo -ro -q -so "${gdal_file}" > /dev/null 2>&1
}

# Header, size, and GDAL checks combined.
geoboundaries_geojson_usable() {
	local level="$1"
	local file="$2"

	is_valid_geoboundaries_geojson "${file}" || return 1
	geoboundaries_file_size_ok "${level}" "${file}" || return 1
	geoboundaries_geojson_readable "${file}"
}

# Download one CGAZ GeoJSON with retries and validation before replacing the target.
download_geoboundaries_geojson_file() {
	local level="$1"
	local force="${2:-false}"
	local output_file="${DATA_DIR}/geoBoundaries/geoBoundariesCGAZ_${level}.geojson"
	local url partial
	url="$(geoboundaries_cgaz_url "${level}")"
	partial="${output_file}.partial"

	mkdir -p "$(dirname "${output_file}")"

	if [[ -f "${output_file}" && "${force}" != true ]]; then
		if geoboundaries_geojson_usable "${level}" "${output_file}"; then
			echo "GeoJSON already exists (use -f to re-download)"
			return 0
		fi
		echo "Removing corrupt or incomplete GeoJSON; re-downloading..."
		rm -f "${output_file}"
	fi

	rm -f "${partial}"
	echo "Downloading GeoJSON (${level})..."
	curl -fL --retry 5 --retry-delay 10 --retry-all-errors \
		"${url}" -o "${partial}"

	if ! geoboundaries_geojson_usable "${level}" "${partial}"; then
		rm -f "${partial}"
		echo "ERROR: Downloaded ${level} GeoJSON is incomplete or unreadable by GDAL."
		echo "       Check network stability and disk space, then re-run with --force."
		exit 1
	fi

	mv -f "${partial}" "${output_file}"
	echo "geoBoundaries ${level} ready at ${output_file}"
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

# Die if a geoBoundaries GeoJSON file is missing, truncated, or unreadable.
require_geoboundaries_geojson() {
	local file="$1"
	local level

	require_file "${file}"
	level="$(_geoboundaries_level_from_path "${file}")"
	if [[ -n "${level}" ]] && geoboundaries_geojson_usable "${level}" "${file}"; then
		return 0
	fi
	echo "ERROR: Invalid or incomplete geoBoundaries GeoJSON: ${file}"
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

# Validate geoBoundaries on the PostGIS /data mount before ogr2ogr.
require_db_geoboundaries_geojson() {
	local container_path="$1"
	local level api_path

	require_db_data_file "${container_path}"
	level="$(_geoboundaries_level_from_path "${container_path}")"
	api_path="${DATA_DIR}${container_path#"${DB_DATA_DIR}"}"
	if [[ -n "${level}" ]] && geoboundaries_geojson_usable "${level}" "${api_path}"; then
		return 0
	fi
	echo "ERROR: ${container_path} on ${DB_CONTAINER} is missing, truncated, or corrupt."
	echo "       Re-run the geoBoundaries download scripts with --force."
	exit 1
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

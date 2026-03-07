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
DATA_DIR="${ROOT_DIR}/data"

# ── Database ──────────────────────────────────────────────────────────────────
# DB_CONTAINER : docker container_name (used with docker exec)
# DB_HOST      : service hostname reachable from other containers on the same network
# DOCKER_NETWORK : network for ogr2ogr/GDAL steps (must include the DB container)
#
# Preset by compose file: set GEOAPI_COMPOSE=dev when using docker-compose.dev.yml
# from the repo root (or set COMPOSE_FILE to a path containing "docker-compose.dev").
# Individual DB_CONTAINER / DB_HOST / DOCKER_NETWORK still override the preset.
DB_NAME="geodb"
DB_USER="geouser"
DB_PASS="geopass"

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
_container_running() { docker inspect "$1" --format '{{.State.Running}}' 2>/dev/null | grep -q true; }
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

# Prefixed log line (uses the calling script's basename).
log() { echo "[$(basename "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")] $*"; }

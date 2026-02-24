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
DB_CONTAINER="geoapi-db"
DB_HOST="db"
DB_NAME="geodb"
DB_USER="geouser"
DB_PASS="geopass"
DOCKER_NETWORK="geoapi_default"

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

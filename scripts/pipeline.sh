#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# pipeline.sh — Full GeoAPI data pipeline
#
# Runs every step in strict dependency order:
#
#   Phase 0 — Downloads   (idempotent; skipped if data already present)
#   Phase 1 — Migrations  (tracked; each file applied exactly once)
#   Phase 2 — Root data   countries  (no FK dependencies)
#   Phase 3 — FK data     cities_1000, adm0_boundaries, adm2_boundaries,
#                         airports  (all reference countries)
#   Phase 4 — Standalone  city_boundaries  (no FK to countries)
#
# Usage:
#   ./scripts/pipeline.sh            # skip already-downloaded files
#   ./scripts/pipeline.sh --force    # re-download all data sources
#
# Prerequisites:
#   - Docker Compose stack is running  (docker compose up -d)
#   - The geoapi-db container is healthy before this script is called
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

FORCE_FLAG=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		-f | --force)
			FORCE_FLAG="--force"
			shift
			;;
		*)
			echo "Unknown option: $1"
			echo "Usage: $0 [--force]"
			exit 1
			;;
	esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
banner() {
	echo
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "  $*"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

step() {
	echo
	echo "── $* ──"
}

run() {
	local script="${SCRIPT_DIR}/$1"
	shift
	echo "→ $(basename "$script") $*"
	bash "$script" "$@"
}

# ── Wait for DB ───────────────────────────────────────────────────────────────
banner "Waiting for database to be ready"
for i in $(seq 1 30); do
	if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" -q 2> /dev/null; then
		echo "Database is ready."
		break
	fi
	echo "  attempt ${i}/30 — waiting 2 s ..."
	sleep 2
	if [[ $i -eq 30 ]]; then
		echo "ERROR: Database did not become ready in time."
		exit 1
	fi
done

# ═════════════════════════════════════════════════════════════════════════════
banner "Phase 0 — Downloads"
# ═════════════════════════════════════════════════════════════════════════════

step "Country codes (CSV)"
run download_countries.sh ${FORCE_FLAG}

step "GeoNames cities1000 (ZIP → TXT)"
run download_cities1000.sh ${FORCE_FLAG}

step "geoBoundaries ADM0 (GeoJSON)"
run download_geoboundaries_adm0.sh ${FORCE_FLAG}

step "geoBoundaries ADM2 (GeoJSON)"
run download_geoboundaries_adm2.sh ${FORCE_FLAG}

step "OurAirports data (git submodule)"
run download_ourairports_data.sh ${FORCE_FLAG}

step "City boundaries (git submodule)"
run download_city_boundaries.sh ${FORCE_FLAG}

# ═════════════════════════════════════════════════════════════════════════════
banner "Phase 1 — Migrations"
# ═════════════════════════════════════════════════════════════════════════════
run run_migrations.sh

# ═════════════════════════════════════════════════════════════════════════════
banner "Phase 2 — Root data (no FK dependencies)"
# ═════════════════════════════════════════════════════════════════════════════
run populate_countries.sh

# ═════════════════════════════════════════════════════════════════════════════
banner "Phase 3 — Tables that reference countries"
# ═════════════════════════════════════════════════════════════════════════════

step "cities_1000  (FK → countries.iso2)"
run populate_cities.sh

step "adm0_boundaries  (FK → countries.iso3)"
run populate_geoboundaries_adm0.sh

step "adm2_boundaries  (FK → countries.iso3)"
run populate_geoboundaries_adm2.sh

step "airports  (FK → countries.iso2)"
run populate_airports.sh

# ═════════════════════════════════════════════════════════════════════════════
banner "Phase 4 — Standalone tables"
# ═════════════════════════════════════════════════════════════════════════════

step "city_boundaries  (no FK)"
run populate_city_boundaries.sh

# ═════════════════════════════════════════════════════════════════════════════
banner "Pipeline complete"
# ═════════════════════════════════════════════════════════════════════════════
echo "All phases finished successfully."

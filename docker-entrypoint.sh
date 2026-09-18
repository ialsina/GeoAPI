#!/usr/bin/env bash
set -euo pipefail

export DB_NAME="${POSTGRES_DB:-${DB_NAME:-geodb}}"
export DB_USER="${POSTGRES_USER:-${DB_USER:-geouser}}"
export DB_PASS="${POSTGRES_PASSWORD:-${DB_PASS:-geopass}}"
export DB_CONTAINER="${DB_CONTAINER:-geoapi-db}"
export DB_HOST="${DB_HOST:-db}"
export GEOAPI_API_CONTAINER="${GEOAPI_API_CONTAINER:-geoapi-api}"
export GEOAPI_DATA_DIR="${GEOAPI_DATA_DIR:-/app/data}"

mkdir -p "${GEOAPI_DATA_DIR}"

# Submodule URLs in .gitmodules use SSH; rewrite for container clones.
git config --global url."https://github.com/".insteadOf "git@github.com:" 2> /dev/null || true

if [[ -z "${DOCKER_NETWORK:-}" ]]; then
	DOCKER_NETWORK="$(
		docker inspect "${DB_CONTAINER}" \
			--format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' \
			2> /dev/null | head -1 || true
	)"
	export DOCKER_NETWORK
fi

_is_truthy() {
	case "${1:-}" in
		true | 1 | yes | TRUE | YES) return 0 ;;
		*) return 1 ;;
	esac
}

_db_table_count() {
	local table="$1"
	docker exec "${DB_CONTAINER}" psql -v ON_ERROR_STOP=1 -U "${DB_USER}" -d "${DB_NAME}" -tAc \
		"SELECT COUNT(*) FROM ${table};" 2> /dev/null | tr -d '[:space:]' || true
}

_is_database_populated() {
	local countries cities

	countries="$(_db_table_count countries)"
	cities="$(_db_table_count cities_1000)"

	if [[ -z "${countries}" || "${countries}" == "0" ]]; then
		echo "Database appears empty (countries=${countries:-unknown})."
		return 1
	fi

	if [[ -z "${cities}" || "${cities}" == "0" ]]; then
		echo "Database is incomplete (${countries} countries, ${cities:-0} cities)."
		return 1
	fi

	echo "Database already populated (${countries} countries, ${cities} cities)."
	return 0
}

_should_run_pipeline() {
	if ! _is_truthy "${AUTO_POPULATE_DATA:-false}"; then
		echo "AUTO_POPULATE_DATA is disabled — skipping data pipeline."
		return 1
	fi

	if _is_truthy "${FORCE_POPULATE:-false}"; then
		echo "FORCE_POPULATE is enabled — running data pipeline."
		return 0
	fi

	if _is_database_populated; then
		echo "Skipping data pipeline."
		return 1
	fi

	echo "Running data pipeline to complete database initialization."
	return 0
}

_verify_data_mount_shared() {
	local probe=".geoapi_mount_probe"
	local token
	token="geoapi-mount-$(date +%s)-$$"

	echo "${token}" > "${GEOAPI_DATA_DIR}/${probe}"
	local db_token=""
	db_token="$(docker exec "${DB_CONTAINER}" cat "/data/${probe}" 2> /dev/null || true)"
	rm -f "${GEOAPI_DATA_DIR}/${probe}"

	if [[ "${db_token}" != "${token}" ]]; then
		echo "ERROR: ${GEOAPI_DATA_DIR} is not shared with ${DB_CONTAINER} at /data."
		echo "       geoapi-api and PostGIS must bind-mount the same host directory."
		exit 1
	fi

	echo "Shared data volume verified."
}

if _should_run_pipeline; then
	_verify_data_mount_shared
	pipeline_args=()
	if _is_truthy "${FORCE_POPULATE:-false}"; then
		pipeline_args+=(--force)
	fi
	bash /app/scripts/pipeline.sh "${pipeline_args[@]}"
fi

exec /app/geoapi

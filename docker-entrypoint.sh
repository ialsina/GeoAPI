#!/usr/bin/env bash
set -euo pipefail

export DB_NAME="${POSTGRES_DB:-${DB_NAME:-geodb}}"
export DB_USER="${POSTGRES_USER:-${DB_USER:-geouser}}"
export DB_PASS="${POSTGRES_PASSWORD:-${DB_PASS:-geopass}}"
export DB_CONTAINER="${DB_CONTAINER:-geoapi-db}"
export DB_HOST="${DB_HOST:-db}"
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

_should_run_pipeline() {
	if ! _is_truthy "${AUTO_POPULATE_DATA:-false}"; then
		echo "AUTO_POPULATE_DATA is disabled — skipping data pipeline."
		return 1
	fi

	if _is_truthy "${FORCE_POPULATE:-false}"; then
		echo "FORCE_POPULATE is enabled — running data pipeline."
		return 0
	fi

	local count=""
	count="$(
		docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -tAc \
			"SELECT COUNT(*) FROM countries;" 2> /dev/null | tr -d '[:space:]' || true
	)"

	if [[ -z "${count}" || "${count}" == "0" ]]; then
		echo "Database appears empty — running data pipeline."
		return 0
	fi

	echo "Database already populated (${count} countries) — skipping pipeline."
	return 1
}

if _should_run_pipeline; then
	pipeline_args=()
	if _is_truthy "${FORCE_POPULATE:-false}"; then
		pipeline_args+=(--force)
	fi
	bash /app/scripts/pipeline.sh "${pipeline_args[@]}"
fi

exec /app/geoapi

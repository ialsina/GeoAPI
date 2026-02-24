#!/usr/bin/env bash
set -euo pipefail

# Applies all pending SQL migrations from the migrations/ directory.
# Migrations are tracked in the schema_migrations table so each file
# is applied exactly once, in alphabetical (version) order.
#
# Flags:
#   --reset   Wipe the migration tracking table and re-apply every migration
#             from scratch. Use this whenever the schema changes (dev only).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

MIGRATIONS_DIR="${ROOT_DIR}/migrations"
RESET=false

while [[ $# -gt 0 ]]; do
	case "$1" in
		--reset)
			RESET=true
			shift
			;;
		*)
			echo "Unknown option: $1"
			exit 1
			;;
	esac
done

# ── Bootstrap / reset migration tracking table ────────────────────────────────
if [[ "$RESET" == true ]]; then
	echo "  --reset: dropping migration tracking table ..."
	docker exec "$DB_CONTAINER" \
		psql -U "$DB_USER" -d "$DB_NAME" -c "DROP TABLE IF EXISTS schema_migrations;"
fi

docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << 'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
    filename   TEXT        PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

# ── Apply pending migrations ───────────────────────────────────────────────────
echo "Running migrations from ${MIGRATIONS_DIR} ..."

while IFS= read -r -d '' migration; do
	name=$(basename "$migration")

	applied=$(docker exec "$DB_CONTAINER" \
		psql -U "$DB_USER" -d "$DB_NAME" -t -c \
		"SELECT COUNT(*) FROM schema_migrations WHERE filename = '${name}';" |
		tr -d '[:space:]')

	if [[ "$applied" -gt 0 ]]; then
		echo "  skip  ${name}  (already applied)"
		continue
	fi

	echo "  apply ${name} ..."
	if docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" < "$migration"; then
		docker exec "$DB_CONTAINER" \
			psql -U "$DB_USER" -d "$DB_NAME" -c \
			"INSERT INTO schema_migrations (filename) VALUES ('${name}');"
		echo "  done  ${name}"
	else
		echo "ERROR: Migration '${name}' failed — pipeline aborted."
		exit 1
	fi
done < <(find "$MIGRATIONS_DIR" -name "*.sql" -not -name "*.down.sql" -type f -print0 | sort -z)

echo "All migrations up to date."

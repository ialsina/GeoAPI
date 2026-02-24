#!/usr/bin/env bash
set -euo pipefail

# Applies all pending SQL migrations from the migrations/ directory.
# Migrations are tracked in the schema_migrations table so each file
# is applied exactly once, in alphabetical (version) order.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

MIGRATIONS_DIR="${ROOT_DIR}/migrations"

# ── Bootstrap migration tracking table ────────────────────────────────────────
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

#!/bin/bash
set -e

# Runs all migrations in the migrations/ directory
# Migrations are executed in alphabetical order by filename

DB_CONTAINER="geoapi-db"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATIONS_DIR="$ROOT_DIR/migrations"

echo "Running migrations..."

# Get all SQL files from migrations directory, sorted
MIGRATIONS=$(find "$MIGRATIONS_DIR" -name "*.sql" -type f | sort)

if [ -z "$MIGRATIONS" ]; then
	echo "No migration files found in $MIGRATIONS_DIR"
	exit 1
fi

# Run each migration
for migration in $MIGRATIONS; do
	migration_name=$(basename "$migration")
	echo "Running migration: $migration_name"

	if docker exec -i "$DB_CONTAINER" psql -U geouser -d geodb < "$migration"; then
		echo "Successfully applied: $migration_name"
	else
		echo "Failed to apply: $migration_name"
		exit 1
	fi
done

echo "All migrations completed successfully."

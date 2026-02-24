#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUBMODULE_DIR="${ROOT_DIR}/geojson-world-cities"

FORCE=false

# Parse flags
while [[ $# -gt 0 ]]; do
	case "$1" in
		-f | --force)
			FORCE=true
			shift
			;;
		*)
			echo "Unknown option: $1"
			exit 1
			;;
	esac
done

echo "City boundaries download (git submodule)"
echo "Force mode: ${FORCE}"

# Check if submodule exists and is initialized in the correct location
cd "${ROOT_DIR}"

# Initialize submodule if it doesn't exist or isn't initialized
if [[ ! -d "${SUBMODULE_DIR}" ]] || [[ ! -f "${SUBMODULE_DIR}/.git" ]]; then
	echo "Initializing git submodule..."
	git submodule update --init --recursive geojson-world-cities
else
	echo "Updating git submodule..."
	if [[ "${FORCE}" == true ]]; then
		git submodule update --remote --force geojson-world-cities
	else
		git submodule update --remote geojson-world-cities
	fi
fi

echo "City boundaries ready at ${SUBMODULE_DIR}/cities.geojson"

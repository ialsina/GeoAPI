#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUBMODULE_DIR="${ROOT_DIR}/ourairports-data"

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

echo "OurAirports data (git submodule)"
echo "Force mode: ${FORCE}"

# Check if submodule exists and is initialized in the correct location
cd "${ROOT_DIR}"

# Initialize submodule if it doesn't exist or isn't initialized
if [[ ! -d "${SUBMODULE_DIR}" ]] || [[ ! -f "${SUBMODULE_DIR}/.git" ]]; then
	echo "Initializing git submodule..."
	git submodule update --init --recursive ourairports-data
else
	echo "Updating git submodule..."
	if [[ "${FORCE}" == true ]]; then
		git submodule update --remote --force ourairports-data
	else
		git submodule update --remote ourairports-data
	fi
fi

echo "OurAirports data ready at ${SUBMODULE_DIR}"

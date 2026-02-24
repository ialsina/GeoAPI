#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${ROOT_DIR}/data/countries"

CSV_URL="https://raw.githubusercontent.com/datasets/country-codes/main/data/country-codes.csv"
CSV_FILE="${DATA_DIR}/country-codes.csv"

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

echo "Country codes download"
echo "Force mode: ${FORCE}"

mkdir -p "${DATA_DIR}"

if [[ -f "${CSV_FILE}" && "${FORCE}" == false ]]; then
	echo "country-codes.csv already exists (use -f to re-download)"
	exit 0
fi

echo "Downloading CSV..."
curl -L "${CSV_URL}" -o "${CSV_FILE}"

echo "country-codes.csv ready at ${CSV_FILE}"

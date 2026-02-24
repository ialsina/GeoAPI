#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${ROOT_DIR}/data/cities1000"

ZIP_URL="https://download.geonames.org/export/dump/cities1000.zip"
ZIP_FILE="${DATA_DIR}/cities1000.zip"
TXT_FILE="${DATA_DIR}/cities1000.txt"

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

echo "GeoNames cities1000 download"
echo "Force mode: ${FORCE}"

mkdir -p "${DATA_DIR}"

if [[ -f "${TXT_FILE}" && "${FORCE}" == false ]]; then
	echo "cities1000.txt already exists (use -f to re-download)"
	exit 0
fi

echo " Downloading ZIP..."
curl -L "${ZIP_URL}" -o "${ZIP_FILE}"

echo "Unzipping..."
unzip -o "${ZIP_FILE}" -d "${DATA_DIR}"

echo "Cleaning up ZIP..."
rm -f "${ZIP_FILE}"

echo "cities1000.txt ready at ${TXT_FILE}"

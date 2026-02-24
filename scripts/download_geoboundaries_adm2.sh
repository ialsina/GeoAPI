#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${ROOT_DIR}/data/geoBoundaries"

GEOJSON_URL="https://github.com/wmgeolab/geoBoundaries/raw/main/releaseData/CGAZ/geoBoundariesCGAZ_ADM2.geojson"
OUTPUT_FILE="${DATA_DIR}/geoBoundariesCGAZ_ADM2.geojson"

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

echo "geoBoundaries ADM2 download"
echo "Force mode: ${FORCE}"

mkdir -p "${DATA_DIR}"

if [[ -f "${OUTPUT_FILE}" && "${FORCE}" == false ]]; then
	echo "GeoJSON already exists (use -f to re-download)"
	exit 0
fi

echo " Downloading GeoJSON..."
curl -L "${GEOJSON_URL}" -o "${OUTPUT_FILE}"

echo "geoBoundaries ADM2 ready at ${OUTPUT_FILE}"

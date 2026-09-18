#!/usr/bin/env bash
set -euo pipefail

# Downloads the geoBoundaries CGAZ ADM0 GeoJSON.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

OUTPUT_DIR="${DATA_DIR}/geoBoundaries"
OUTPUT_FILE="${OUTPUT_DIR}/geoBoundariesCGAZ_ADM0.geojson"
GEOJSON_URL="$(geoboundaries_cgaz_url ADM0)"

FORCE=false

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

echo "geoBoundaries ADM0 download"
echo "Force mode: ${FORCE}"

mkdir -p "${OUTPUT_DIR}"

if [[ -f "${OUTPUT_FILE}" && "${FORCE}" == false ]]; then
	if is_valid_geoboundaries_geojson "${OUTPUT_FILE}"; then
		echo "GeoJSON already exists (use -f to re-download)"
		exit 0
	fi
	echo "Removing invalid GeoJSON (likely a Git LFS pointer); re-downloading..."
	rm -f "${OUTPUT_FILE}"
fi

echo "Downloading GeoJSON..."
curl -fL "${GEOJSON_URL}" -o "${OUTPUT_FILE}"

if ! is_valid_geoboundaries_geojson "${OUTPUT_FILE}"; then
	rm -f "${OUTPUT_FILE}"
	echo "ERROR: Downloaded file is not valid GeoJSON (got a Git LFS pointer or empty response)."
	exit 1
fi

echo "geoBoundaries ADM0 ready at ${OUTPUT_FILE}"

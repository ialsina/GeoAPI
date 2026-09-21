#!/usr/bin/env bash
set -euo pipefail

# Downloads the geoBoundaries CGAZ ADM1 (province/state) GeoJSON.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

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

echo "geoBoundaries ADM1 download"
echo "Force mode: ${FORCE}"

download_geoboundaries_geojson_file ADM1 "${FORCE}"

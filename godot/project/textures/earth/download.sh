#!/usr/bin/env bash
# Downloads Earth textures from Solar System Scope (CC BY 4.0)
# https://www.solarsystemscope.com/textures/
# Run from this directory: bash download.sh

set -e
cd "$(dirname "$0")"

BASE="https://www.solarsystemscope.com/textures/download"

declare -A TEXTURES=(
    ["earth_daymap.jpg"]="${BASE}/8k_earth_daymap.jpg"
    ["earth_nightmap.jpg"]="${BASE}/8k_earth_nightmap.jpg"
    ["earth_clouds.jpg"]="${BASE}/8k_earth_clouds.jpg"
)

for FILE in "${!TEXTURES[@]}"; do
    if [ -f "$FILE" ]; then
        echo "  skip  $FILE (already exists)"
        continue
    fi
    echo "  fetch $FILE ..."
    curl -fL --retry 3 --progress-bar -o "$FILE" "${TEXTURES[$FILE]}"
done

echo "Done. Import textures in the Godot editor before running the project."

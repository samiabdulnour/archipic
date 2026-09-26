#!/bin/bash
# Render every camera look on a folder of photos into one contact sheet, then open it.
# Usage:  bash tools/looks-preview/preview.sh [folder-of-photos]
# Default folder: tools/looks-preview/samples/  (drop your own JPG/PNG/HEIC in there)
set -e
here="$(cd "$(dirname "$0")" && pwd)"
dir="${1:-$here/samples}"
engine="$here/../../Archipic/Archipic/Camera/CameraProcessing.swift"
mkdir -p "$dir"
swiftc -O "$here/main.swift" "$engine" -o "$here/.render"
"$here/.render" "$dir"
open "$dir/_looks-preview.png"

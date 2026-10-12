#!/bin/zsh
# Regenerates the README screenshots in docs/ with sample data.
set -euo pipefail
cd "${0:A:h}/.."

./build.sh
build/BudsBar.app/Contents/MacOS/BudsBar --render-preview docs
echo "Updated docs/"

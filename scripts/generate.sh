#!/bin/zsh
# Regenerates Marqet.xcodeproj from project.yml – the only way the project file may change.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
echo "Marqet.xcodeproj generated from project.yml"

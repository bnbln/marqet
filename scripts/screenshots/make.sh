#!/bin/zsh
# App Store screenshots and posters (docs/KONZEPT-SCREENSHOTS.md). Texts, devices, shots: shots.json.
#
#   scripts/screenshots/make.sh                       build, capture everything, frame
#   scripts/screenshots/make.sh frame                 re-frame existing captures (texts or look changed)
#   scripts/screenshots/make.sh capture --devices iphone --langs en --shots 02-voice
#
# Captures: screenshots/raw/<lang>/<device>/…  Posters: screenshots/final/<lang>/<device>/…
set -euo pipefail
cd "$(dirname "$0")/../.."

tool=.build/screenshots-tool
mkdir -p .build
if [[ ! -x $tool || scripts/screenshots/Screenshots.swift -nt $tool ]]; then
    echo "▸ Tool bauen"
    swiftc -O -swift-version 5 scripts/screenshots/Screenshots.swift -o $tool
fi

if [[ "${1:-all}" != frame ]]; then
    echo "▸ App bauen (Debug, Simulator)"
    xcodebuild build -project Marqet.xcodeproj -scheme Marqet \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath .build/DerivedData -quiet
fi

$tool "$@"

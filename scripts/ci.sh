#!/bin/zsh
# Full verification, locally and in CI. Exits non-zero on the first failure.
#   1. project file matches project.yml
#   2. package tests (macOS, fast)
#   3. app build + app-hosted tests on an iPhone simulator
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Project file up to date"
xcodegen generate --quiet
if ! git diff --quiet -- Marqet.xcodeproj; then
    echo "✘ Marqet.xcodeproj differs from project.yml – run scripts/generate.sh and commit." >&2
    git --no-pager diff --stat -- Marqet.xcodeproj >&2
    exit 1
fi

echo "▸ Package tests"
(cd Packages/MarqetKit && swift test --quiet)

echo "▸ App tests"
DEVICE_ID="${MARQET_SIMULATOR_ID:-$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
phones = [d for runtime, list in devices.items() if "iOS" in runtime for d in list if d["name"].startswith("iPhone")]
print(phones[-1]["udid"])')}"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
# EventKit integration tests need Reminders access; without it they are skipped, not failed.
xcrun simctl privacy "$DEVICE_ID" grant reminders app.marqet.Marqet 2>/dev/null || true
xcodebuild test \
    -project Marqet.xcodeproj -scheme Marqet \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" \
    -derivedDataPath .build/DerivedData \
    -quiet
echo "✔ All checks passed"

#!/bin/zsh
# Full verification, locally and in CI. Exits non-zero on the first failure.
#   1. project file matches project.yml
#   2. package tests (macOS, fast)
#   3. app build + app-hosted tests on an iPhone simulator
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Project file up to date"
before="$(shasum Marqet.xcodeproj/project.pbxproj)"
xcodegen generate --quiet
if [[ "$(shasum Marqet.xcodeproj/project.pbxproj)" != "$before" ]]; then
    echo "✘ Marqet.xcodeproj was out of date with project.yml – it has been regenerated; review and commit it." >&2
    git --no-pager diff --stat -- Marqet.xcodeproj >&2
    git --no-pager diff -- Marqet.xcodeproj >&2
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
XCODEBUILD=(-project Marqet.xcodeproj -scheme Marqet
    -destination "platform=iOS Simulator,id=$DEVICE_ID"
    -derivedDataPath .build/DerivedData)
xcodebuild build-for-testing "${XCODEBUILD[@]}" -quiet
# Not quiet, so failing expectations show up in the log. The app speaks German first, and so do its tests.
xcodebuild test-without-building "${XCODEBUILD[@]}" -testLanguage de -testRegion DE
echo "✔ All checks passed"

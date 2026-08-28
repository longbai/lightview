#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_root="$(mktemp -d)"
app="$temporary_root/HarnessFixture.app"
output="$temporary_root/raw.tsv"
cleanup() { rm -rf "$temporary_root"; }
trap cleanup EXIT
mkdir -p "$app/Contents/MacOS"

printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0"><dict>' \
    '<key>CFBundleExecutable</key><string>HarnessFixture</string>' \
    '<key>CFBundleIdentifier</key><string>app.lightview.LightView</string>' \
    '</dict></plist>' >"$app/Contents/Info.plist"
printf '%s\n' '#!/bin/bash' 'sleep 30 & child=$!' 'wait "$child"' >"$app/Contents/MacOS/HarnessFixture"
chmod +x "$app/Contents/MacOS/HarnessFixture"
printf 'fixture\n' >"$temporary_root/input.png"

"$project_root/scripts/benchmark-app.sh" "$app" "$temporary_root/input.png" helper "$output" 0.1 5
[[ "$(awk 'END {print NR}' "$output")" == 6 ]]
awk -F '\t' 'NR > 1 { if ($6 <= 0 || $7 <= 0) exit 1 }' "$output"
! pgrep -f "$app/Contents/MacOS/HarnessFixture" >/dev/null 2>&1
echo "Benchmark harness self-test passed"

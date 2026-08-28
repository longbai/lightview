#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="${1:-$project_root/Tests/Fixtures/Static/oriented-6.jpg}"
result_root="${2:-$project_root/build/benchmark-results/$(date +%Y-%m-%dT%H%M%S)}"
rounds="${LIGHTVIEW_BENCHMARK_ROUNDS:-3}"
mkdir -p "$result_root/raw"

apps=(
    "$project_root/build/releases/Release-Direct/LightView.app|LightView"
    "/Applications/qView.app|qView"
    "/Applications/Tovi.app|Tovi-2.0.4"
    "/Applications/SimpView.app|SimpView"
)

{
    printf '{\n'
    printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "macOS": "%s",\n' "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    printf '  "machine": "%s",\n' "$(uname -m)"
    printf '  "fixture": "%s",\n' "$fixture"
    printf '  "fixtureSHA256": "%s"\n' "$(shasum -a 256 "$fixture" | awk '{print $1}')"
    printf '}\n'
} >"$result_root/environment.json"

printf 'round\tlabel\tapp_logical_bytes\tapp_allocated_kib\tmacho_bytes\tarchitectures\tversion\n' >"$result_root/raw/sizes.tsv"
for entry in "${apps[@]}"; do
    app="${entry%%|*}"
    label="${entry#*|}"
    [[ -d "$app" ]] || continue
    executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
    executable="$app/Contents/MacOS/$executable_name"
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || echo unknown)"
    logical="$(find "$app" -type f -exec stat -f %z {} + | awk '{sum += $1} END {print sum + 0}')"
    allocated="$(du -sk "$app" | awk '{print $1}')"
    printf '0\t%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$logical" "$allocated" "$(stat -f %z "$executable")" "$(lipo -archs "$executable")" "$version" >>"$result_root/raw/sizes.tsv"
done

for round in $(seq 1 "$rounds"); do
    if (( round % 2 == 1 )); then order=(0 1 2 3); else order=(3 2 1 0); fi
    for index in "${order[@]}"; do
        entry="${apps[$index]}"
        app="${entry%%|*}"
        label="${entry#*|}"
        [[ -d "$app" ]] || continue
        "$project_root/scripts/benchmark-app.sh" "$app" "$fixture" "$label" "$result_root/raw/round-$round.tsv"
    done
done

echo "$result_root"

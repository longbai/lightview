#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
result_root="$project_root/build/smoke-results"
mkdir -p "$result_root"

smoke() {
    local configuration="$1"
    local app="$project_root/build/releases/$configuration/LightView.app"
    local executable="$app/Contents/MacOS/LightView"
    local log="$result_root/$configuration.log"
    "$project_root/scripts/verify-artifact.sh" "$app" "$configuration"
    "$executable" -ApplePersistenceIgnoreState YES -LightViewUITestEmptyWindow YES >"$log" 2>&1 &
    local pid=$!
    trap 'kill "$pid" 2>/dev/null || true' RETURN
    sleep 3
    kill -0 "$pid"
    ps -p "$pid" -o pid=,rss=,etime=,command= >"$result_root/$configuration.process.txt"
    kill "$pid"
    wait "$pid" 2>/dev/null || true
    trap - RETURN
}

smoke Release-Direct
smoke Release-AppStore
echo "Release smoke results: $result_root"

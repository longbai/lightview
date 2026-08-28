#!/bin/bash
set -euo pipefail

app_path="${1:?usage: benchmark-app.sh APP FIXTURE LABEL OUTPUT_TSV [SETTLE_SECONDS] [SAMPLES]}"
fixture="${2:?fixture path required}"
label="${3:?label required}"
output="${4:?output TSV required}"
settle_seconds="${5:-5}"
sample_count="${6:-5}"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
executable="$app_path/Contents/MacOS/$executable_name"

[[ -x "$executable" ]] || { echo "Missing executable: $executable" >&2; exit 2; }
[[ -f "$fixture" ]] || { echo "Missing fixture: $fixture" >&2; exit 2; }
if pgrep -f "$executable" >/dev/null 2>&1; then
    echo "Refusing to benchmark while $executable_name is already active" >&2
    exit 3
fi

mkdir -p "$(dirname "$output")"
if [[ ! -f "$output" ]]; then
    printf 'timestamp\tlabel\tbundle_id\tpid\tsample\tmain_rss_kib\tchild_rss_kib\twebkit_global_rss_kib\n' >"$output"
fi

sum_webkit_rss() {
    ps -axo rss=,command= | awk '/com\.apple\.WebKit\.(WebContent|GPU|Networking)/ { total += $1 } END { print total + 0 }'
}

sum_child_rss() {
    local parent="$1"
    local pending="$parent"
    local total=0
    local next child rss current_parent
    while [[ -n "$pending" ]]; do
        next=""
        for current_parent in $pending; do
            for child in $(pgrep -P "$current_parent" 2>/dev/null || true); do
                rss="$(ps -p "$child" -o rss= | awk '{print $1 + 0}')"
                total=$((total + rss))
                next="$next $child"
            done
        done
        pending="$next"
    done
    echo "$total"
}

webkit_before="$(sum_webkit_rss)"
launch_log="${output%.tsv}-$label-launch.log"
if [[ "$bundle_id" == "app.lightview.LightView" ]]; then
    "$executable" -ApplePersistenceIgnoreState YES -LightViewUITestOpenPath "$fixture" >"$launch_log" 2>&1 &
    pid=$!
else
    : >"$launch_log"
    open -na "$app_path" "$fixture"
    pid=""
    for _ in $(seq 1 50); do
        pid="$(pgrep -f "$executable" | tail -n 1 || true)"
        [[ -n "$pid" ]] && break
        sleep 0.1
    done
    [[ -n "$pid" ]] || { echo "Could not discover launched PID for $label" >&2; exit 4; }
fi
cleanup() {
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
sleep "$settle_seconds"
kill -0 "$pid" 2>/dev/null || { echo "$label exited before sampling" >&2; exit 4; }

for sample in $(seq 1 "$sample_count"); do
    main_rss="$(ps -p "$pid" -o rss= | awk '{print $1 + 0}')"
    child_rss="$(sum_child_rss "$pid")"
    webkit_now="$(sum_webkit_rss)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$label" "$bundle_id" "$pid" "$sample" \
        "$main_rss" "$child_rss" "$webkit_now" >>"$output"
    sleep 0.5
done

webkit_after="$(sum_webkit_rss)"
printf '%s\t%s\t%s\t%s\t%s\n' "$label" "$webkit_before" "$webkit_after" "$((webkit_after - webkit_before))" "$pid" \
    >"${output%.tsv}-$label-webkit.tsv"

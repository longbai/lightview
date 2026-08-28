#!/bin/bash
set -euo pipefail

app="${1:?usage: verify-compatibility.sh APP Release-Direct|Release-AppStore}"
configuration="${2:?configuration required}"
project_root="$(cd "$(dirname "$0")/.." && pwd)"

"$project_root/scripts/verify-artifact.sh" "$app" "$configuration"
executable="$app/Contents/MacOS/LightView"

signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
grep -q 'flags=.*runtime' <<<"$signature" || { echo "Hardened Runtime is missing" >&2; exit 20; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LightViewDistributionChannel' "$app/Contents/Info.plist")" == \
    "$([[ "$configuration" == Release-AppStore ]] && echo app-store || echo direct)" ]] || {
    echo "Distribution channel metadata does not match $configuration" >&2
    exit 21
}

for license in Vendor/NanoSVG/upstream/LICENSE.txt Vendor/libwebp/upstream/COPYING; do
    [[ -s "$project_root/$license" ]] || { echo "Missing third-party license: $license" >&2; exit 22; }
done

if [[ "${LIGHTVIEW_REQUIRE_DISTRIBUTION_SIGNATURE:-0}" == 1 ]]; then
    grep -q 'Signature=adhoc' <<<"$signature" && { echo "Distribution artifact is ad hoc signed" >&2; exit 23; }
    if [[ "$configuration" == Release-Direct ]]; then
        spctl --assess --type execute --verbose=4 "$app"
        xcrun stapler validate "$app"
    fi
fi

echo "Compatibility inspection passed for $configuration"

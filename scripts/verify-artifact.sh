#!/bin/bash
set -euo pipefail

app_path="${1:?usage: verify-artifact.sh APP_PATH Release-Direct|Release-AppStore}"
configuration="${2:?usage: verify-artifact.sh APP_PATH Release-Direct|Release-AppStore}"
executable="$app_path/Contents/MacOS/LightView"
[[ -x "$executable" ]] || { echo "Missing executable: $executable" >&2; exit 2; }

architectures="$(lipo -archs "$executable")"
[[ " $architectures " == *" x86_64 "* && " $architectures " == *" arm64 "* ]] || {
    echo "Expected x86_64 and arm64, found: $architectures" >&2
    exit 3
}

minimum_os() {
    local architecture="$1"
    otool -arch "$architecture" -l "$executable" | awk '
        /LC_BUILD_VERSION/ { build = 1; next }
        build && /minos/ { print $2; exit }
        /LC_VERSION_MIN_MACOSX/ { legacy = 1; next }
        legacy && /version/ { print $2; exit }
    '
}

[[ "$(minimum_os x86_64)" == 10.15* ]] || { echo "Intel slice must target macOS 10.15" >&2; exit 4; }
[[ "$(minimum_os arm64)" == 11.* ]] || { echo "arm64 slice must target macOS 11" >&2; exit 5; }

if otool -L "$executable" | grep -Eiq 'SwiftUI|WebKit'; then
    echo "Forbidden SwiftUI or WebKit linkage detected" >&2
    exit 6
fi

codesign --verify --deep --strict "$app_path"
entitlements_file="$(mktemp)"
trap 'rm -f "$entitlements_file"' EXIT
codesign -d --entitlements :- "$app_path" >"$entitlements_file" 2>/dev/null

has_entitlement() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$entitlements_file" >/dev/null 2>&1
}

if [[ "$configuration" == "Release-AppStore" ]]; then
    for key in \
        com.apple.security.app-sandbox \
        com.apple.security.files.user-selected.read-only \
        com.apple.security.files.bookmarks.app-scope; do
        has_entitlement "$key" || { echo "Missing entitlement: $key" >&2; exit 7; }
    done
else
    ! has_entitlement com.apple.security.app-sandbox || { echo "Direct build is unexpectedly sandboxed" >&2; exit 8; }
fi

for key in com.apple.security.network.client com.apple.security.network.server; do
    ! has_entitlement "$key" || { echo "Unexpected network entitlement: $key" >&2; exit 9; }
done

[[ -f "$app_path/Contents/Resources/Base.lproj/Localizable.strings" ]] || { echo "Missing Base localization" >&2; exit 10; }
[[ -f "$app_path/Contents/Resources/zh-Hans.lproj/Localizable.strings" ]] || { echo "Missing zh-Hans localization" >&2; exit 11; }

echo "Verified $configuration: $architectures, Intel $(minimum_os x86_64), arm64 $(minimum_os arm64)"

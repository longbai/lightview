#!/bin/bash
set -euo pipefail

configuration="${1:-Release-Direct}"
case "$configuration" in
    Release-Direct) entitlements="Config/Direct.entitlements" ;;
    Release-AppStore) entitlements="Config/AppStore.entitlements" ;;
    *) echo "Unsupported configuration: $configuration" >&2; exit 2 ;;
esac

project_root="$(cd "$(dirname "$0")/.." && pwd)"
release_root="$project_root/build/releases/$configuration"
x86_root="$release_root/x86_64"
arm_root="$release_root/arm64"
output_app="$release_root/LightView.app"
sign_identity="${LIGHTVIEW_CODE_SIGN_IDENTITY:--}"

build_slice() {
    local architecture="$1"
    local minimum_os="$2"
    local derived_data="$3"
    xcodebuild \
        -project "$project_root/LightView.xcodeproj" \
        -scheme LightView \
        -configuration "$configuration" \
        -derivedDataPath "$derived_data" \
        ARCHS="$architecture" \
        ONLY_ACTIVE_ARCH=YES \
        MACOSX_DEPLOYMENT_TARGET="$minimum_os" \
        CODE_SIGNING_ALLOWED=NO \
        build
}

resource_digest() {
    local resource_root="$1"
    if [[ ! -d "$resource_root" ]]; then
        echo "empty"
        return
    fi
    (
        cd "$resource_root"
        find . -type f -print0 \
            | LC_ALL=C sort -z \
            | xargs -0 shasum -a 256 \
            | shasum -a 256 \
            | awk '{print $1}'
    )
}

build_slice x86_64 10.15 "$x86_root"
build_slice arm64 11.0 "$arm_root"

x86_app="$x86_root/Build/Products/$configuration/LightView.app"
arm_app="$arm_root/Build/Products/$configuration/LightView.app"
[[ -d "$x86_app" && -d "$arm_app" ]] || { echo "A slice application is missing" >&2; exit 3; }

x86_resources="$(resource_digest "$x86_app/Contents/Resources")"
arm_resources="$(resource_digest "$arm_app/Contents/Resources")"
[[ "$x86_resources" == "$arm_resources" ]] || {
    echo "Architecture resource payloads differ" >&2
    exit 4
}

rm -rf "$output_app"
cp -R "$x86_app" "$output_app"
lipo -create \
    "$x86_app/Contents/MacOS/LightView" \
    "$arm_app/Contents/MacOS/LightView" \
    -output "$output_app/Contents/MacOS/LightView.universal"
mv "$output_app/Contents/MacOS/LightView.universal" "$output_app/Contents/MacOS/LightView"

if [[ -d "$output_app/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' output_binary; do
        relative_path="${output_binary#"$output_app/"}"
        x86_binary="$x86_app/$relative_path"
        arm_binary="$arm_app/$relative_path"
        if [[ -f "$x86_binary" && -f "$arm_binary" ]] && file "$x86_binary" | grep -q 'Mach-O'; then
            x86_archs="$(lipo -archs "$x86_binary")"
            arm_archs="$(lipo -archs "$arm_binary")"
            if [[ "$x86_archs" == "$arm_archs" ]]; then
                cmp -s "$x86_binary" "$arm_binary" || {
                    echo "Shared framework payload differs: $relative_path" >&2
                    exit 5
                }
            else
                lipo -create "$x86_binary" "$arm_binary" -output "$output_binary.universal"
                mv "$output_binary.universal" "$output_binary"
            fi
        fi
    done < <(find "$output_app/Contents/Frameworks" -type f -print0)
fi

if [[ -d "$output_app/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' nested_code; do
        if file "$nested_code" | grep -q 'Mach-O'; then
            codesign --force --sign "$sign_identity" --timestamp=none "$nested_code"
        fi
    done < <(find "$output_app/Contents/Frameworks" -type f -print0)
fi
codesign --force --sign "$sign_identity" --timestamp=none --options runtime \
    --entitlements "$project_root/$entitlements" "$output_app"

"$project_root/scripts/verify-artifact.sh" "$output_app" "$configuration"
echo "$output_app"

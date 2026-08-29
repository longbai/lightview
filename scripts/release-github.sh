#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
info_plist="$project_root/Resources/Info.plist"
configuration="Release-Direct"
entitlements="$project_root/Config/Direct.entitlements"

plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
version="${1:-$plist_version}"
tag="v$version"

repository="${LIGHTVIEW_GITHUB_REPOSITORY:-longbai/lightview}"
notary_profile="${LIGHTVIEW_NOTARY_PROFILE:-LightView-Notary}"
sign_identity="${LIGHTVIEW_CODE_SIGN_IDENTITY:-}"

if [[ "$version" != "$plist_version" ]]; then
    echo "Requested version $version does not match Info.plist version $plist_version" >&2
    exit 2
fi

required_commands=(codesign ditto file gh git hdiutil lipo security shasum spctl xcodebuild xcrun)
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null || {
        echo "Required command is unavailable: $command_name" >&2
        exit 3
    }
done

cd "$project_root"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "The working tree must be clean before publishing a release." >&2
    git status --short >&2
    exit 4
fi

current_branch="$(git branch --show-current)"
if [[ "$current_branch" != "main" ]]; then
    echo "Releases must be published from main; current branch is $current_branch." >&2
    exit 4
fi

git fetch origin main
remote_main="$(git rev-parse FETCH_HEAD)"
if [[ "$(git rev-parse HEAD)" != "$remote_main" ]]; then
    echo "Local main must exactly match origin/main before publishing." >&2
    exit 4
fi

if git show-ref --verify --quiet "refs/tags/$tag"; then
    echo "Local tag already exists: $tag" >&2
    exit 5
fi

set +e
git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1
remote_tag_status=$?
set -e
case "$remote_tag_status" in
    0)
        echo "Remote tag already exists: $tag" >&2
        exit 5
        ;;
    2)
        ;;
    *)
        echo "Unable to check the remote tag on origin." >&2
        exit 6
        ;;
esac

gh auth status >/dev/null
xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null

if [[ -z "$sign_identity" ]]; then
    sign_identity="$(
        security find-identity -v -p codesigning \
            | awk '/Developer ID Application/ && !found { print $2; found = 1 }'
    )"
fi

if [[ -z "$sign_identity" ]]; then
    echo "No valid Developer ID Application identity was found." >&2
    exit 7
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_root="$project_root/build/releases/${tag}-github-$timestamp"
staging_root="$output_root/staging"
x86_output="$output_root/x86_64"
arm_output="$output_root/arm64"

mkdir -p "$staging_root" "$x86_output" "$arm_output"

echo "Publishing LightView $version"
echo "Repository: $repository"
echo "Notary profile: $notary_profile"
echo "Signing identity: $sign_identity"
echo "Output: $output_root"

LIGHTVIEW_CODE_SIGN_IDENTITY="$sign_identity" \
    "$project_root/scripts/build-universal.sh" "$configuration"

x86_source="$project_root/build/releases/$configuration/x86_64/Build/Products/$configuration/LightView.app"
arm_source="$project_root/build/releases/$configuration/arm64/Build/Products/$configuration/LightView.app"
x86_app="$x86_output/LightView.app"
arm_app="$arm_output/LightView.app"

[[ -d "$x86_source" && -d "$arm_source" ]] || {
    echo "An architecture-specific application is missing." >&2
    exit 8
}

ditto "$x86_source" "$x86_app"
ditto "$arm_source" "$arm_app"

sign_app() {
    local app="$1"

    if [[ -d "$app/Contents/Frameworks" ]]; then
        while IFS= read -r -d '' binary; do
            if file "$binary" | grep -q 'Mach-O'; then
                codesign --force --sign "$sign_identity" --timestamp "$binary"
            fi
        done < <(find "$app/Contents/Frameworks" -type f -print0)
    fi

    codesign \
        --force \
        --sign "$sign_identity" \
        --timestamp \
        --options runtime \
        --entitlements "$entitlements" \
        "$app"

    codesign --verify --deep --strict --verbose=2 "$app"
}

sign_app "$x86_app"
sign_app "$arm_app"

[[ "$(lipo -archs "$x86_app/Contents/MacOS/LightView")" == "x86_64" ]] || {
    echo "The Intel application is not x86_64-only." >&2
    exit 9
}
[[ "$(lipo -archs "$arm_app/Contents/MacOS/LightView")" == "arm64" ]] || {
    echo "The Apple silicon application is not arm64-only." >&2
    exit 9
}

for app in "$x86_app" "$arm_app"; do
    built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
    [[ "$built_version" == "$version" ]] || {
        echo "Built application version is $built_version instead of $version." >&2
        exit 10
    }
done

x86_notary_zip="$output_root/LightView-$version-macos-x86_64-notary.zip"
arm_notary_zip="$output_root/LightView-$version-macos-arm64-notary.zip"

ditto -c -k --keepParent "$x86_app" "$x86_notary_zip"
ditto -c -k --keepParent "$arm_app" "$arm_notary_zip"

xcrun notarytool submit "$x86_notary_zip" --keychain-profile "$notary_profile" --wait
xcrun notarytool submit "$arm_notary_zip" --keychain-profile "$notary_profile" --wait

xcrun stapler staple "$x86_app"
xcrun stapler staple "$arm_app"
xcrun stapler validate "$x86_app"
xcrun stapler validate "$arm_app"
spctl --assess --type execute --verbose=4 "$x86_app"
spctl --assess --type execute --verbose=4 "$arm_app"

x86_staging="$staging_root/x86_64"
arm_staging="$staging_root/arm64"
mkdir -p "$x86_staging" "$arm_staging"
ditto "$x86_app" "$x86_staging/LightView.app"
ditto "$arm_app" "$arm_staging/LightView.app"
ln -s /Applications "$x86_staging/Applications"
ln -s /Applications "$arm_staging/Applications"

x86_dmg="$output_root/LightView-$version-macos-x86_64.dmg"
arm_dmg="$output_root/LightView-$version-macos-arm64.dmg"

hdiutil create -volname LightView -srcfolder "$x86_staging" -format UDZO "$x86_dmg"
hdiutil create -volname LightView -srcfolder "$arm_staging" -format UDZO "$arm_dmg"

codesign --force --sign "$sign_identity" --timestamp "$x86_dmg"
codesign --force --sign "$sign_identity" --timestamp "$arm_dmg"

xcrun notarytool submit "$x86_dmg" --keychain-profile "$notary_profile" --wait
xcrun notarytool submit "$arm_dmg" --keychain-profile "$notary_profile" --wait

xcrun stapler staple "$x86_dmg"
xcrun stapler staple "$arm_dmg"
codesign --verify --verbose=2 "$x86_dmg"
codesign --verify --verbose=2 "$arm_dmg"
xcrun stapler validate "$x86_dmg"
xcrun stapler validate "$arm_dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$x86_dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$arm_dmg"

checksums="$output_root/SHA256SUMS.txt"
(
    cd "$output_root"
    shasum -a 256 \
        "$(basename "$x86_dmg")" \
        "$(basename "$arm_dmg")" \
        >"$(basename "$checksums")"
)

release_notes="$output_root/release-notes.md"
printf '%s\n' \
    "LightView $version" \
    "" \
    "Native lightweight image viewer for macOS." \
    "" \
    "Downloads:" \
    "- Apple Silicon: LightView-$version-macos-arm64.dmg" \
    "- Intel: LightView-$version-macos-x86_64.dmg" \
    "" \
    "Compatibility:" \
    "- Apple Silicon: macOS 11 Big Sur or later" \
    "- Intel: macOS 10.15 Catalina or later" \
    "" \
    "Both disk images are signed with Apple Developer ID, notarized by Apple, and include stapled notarization tickets." \
    >"$release_notes"

git tag -a "$tag" -m "LightView $version" HEAD
git push origin "$tag"

gh release create "$tag" \
    "$x86_dmg" \
    "$arm_dmg" \
    "$checksums" \
    --repo "$repository" \
    --verify-tag \
    --title "LightView $version" \
    --notes-file "$release_notes" \
    --latest

echo "Published $tag to https://github.com/$repository/releases/tag/$tag"
echo "GitHub automatically provides Source code (zip) and Source code (tar.gz) from the tag."

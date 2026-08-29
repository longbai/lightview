#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
env_file="${LIGHTVIEW_NOTARY_ENV_FILE:-$project_root/.env.notary}"
expect_helper="$project_root/scripts/store-notary-credentials.expect"

if [[ ! -f "$env_file" || -L "$env_file" ]]; then
    echo "Create a private notarization environment file first:" >&2
    echo "  cp '$project_root/.env.notary.example' '$project_root/.env.notary'" >&2
    echo "  chmod 600 '$project_root/.env.notary'" >&2
    exit 2
fi

permissions="$(stat -f '%Lp' "$env_file")"
if (( (8#$permissions & 8#077) != 0 )); then
    echo "$env_file must not be readable or writable by group or other users." >&2
    echo "Run: chmod 600 '$env_file'" >&2
    exit 3
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a
# Keep the secret out of the environment inherited by Expect and notarytool.
export -n LIGHTVIEW_APP_SPECIFIC_PASSWORD 2>/dev/null || true

: "${LIGHTVIEW_NOTARY_PROFILE:=LightView-Notary}"
: "${LIGHTVIEW_APPLE_ID:?Set LIGHTVIEW_APPLE_ID in $env_file}"
: "${LIGHTVIEW_TEAM_ID:?Set LIGHTVIEW_TEAM_ID in $env_file}"
: "${LIGHTVIEW_APP_SPECIFIC_PASSWORD:?Set LIGHTVIEW_APP_SPECIFIC_PASSWORD in $env_file}"

command -v xcrun >/dev/null || { echo "xcrun is required." >&2; exit 4; }
[[ -x /usr/bin/expect ]] || { echo "/usr/bin/expect is required." >&2; exit 4; }
[[ -x "$expect_helper" ]] || { echo "$expect_helper is not executable." >&2; exit 4; }

cleanup() {
    LIGHTVIEW_APP_SPECIFIC_PASSWORD=""
    unset LIGHTVIEW_APP_SPECIFIC_PASSWORD
}
trap cleanup EXIT

# Send the password over a pipe to Expect. It is never placed in command-line
# arguments, echoed to the terminal, or written anywhere except the Keychain.
printf '%s\n' "$LIGHTVIEW_APP_SPECIFIC_PASSWORD" \
    | "$expect_helper" \
        "$LIGHTVIEW_NOTARY_PROFILE" \
        "$LIGHTVIEW_APPLE_ID" \
        "$LIGHTVIEW_TEAM_ID"

cleanup
trap - EXIT

xcrun notarytool history --keychain-profile "$LIGHTVIEW_NOTARY_PROFILE" >/dev/null
echo "Notarization profile '$LIGHTVIEW_NOTARY_PROFILE' is stored and validated."

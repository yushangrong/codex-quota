#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-0.1.0}"
dist="$root/dist"
app="$dist/Codex Quota.app"
dmg_name="Codex-Quota-v${version}-macOS-universal.dmg"
dmg="$dist/$dmg_name"
checksum="$dmg.sha256"

fail() {
    print -u2 -- "build-dmg: $1"
    exit 1
}

for tool in hdiutil mktemp shasum; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done

[[ "$version" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || fail "version must contain one to three numeric components"
"$root/scripts/build-app.sh" "$version"
[[ -d "$app" ]] || fail "application builder did not produce: $app"

stage="$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-dmg.XXXXXX")"
cleanup() {
    rm -rf -- "$stage"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
volume="$stage/Codex Quota"
temporary_dmg="$stage/$dmg_name"
mkdir -p "$volume"
cp -R "$app" "$volume/Codex Quota.app"
ln -s /Applications "$volume/Applications"

hdiutil create -volname "Codex Quota" -srcfolder "$volume" -fs HFS+ -format UDZO "$temporary_dmg" >/dev/null
rm -f -- "$dmg" "$checksum"
mv "$temporary_dmg" "$dmg"
(
    cd "$dist"
    shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)
print -- "$dmg"
print -- "$checksum"

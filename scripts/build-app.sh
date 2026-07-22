#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-0.1.0}"
dist="$root/dist"
app="$dist/Codex Quota.app"

fail() {
    print -u2 -- "build-app: $1"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

[[ "$version" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || fail "version must contain one to three numeric components"
[[ -f "$root/Resources/Info.plist" ]] || fail "missing Resources/Info.plist"
[[ -f "$root/Resources/AppIcon.svg" ]] || fail "missing Resources/AppIcon.svg"
[[ -x /usr/libexec/PlistBuddy ]] || fail "required tool not found: /usr/libexec/PlistBuddy"

for tool in swift lipo codesign qlmanage sips iconutil mktemp; do
    require_command "$tool"
done
require_command xattr

swift_build() {
    local args=(--package-path "$root" -c release)
    if [[ "${CODEX_QUOTA_SWIFT_DISABLE_SANDBOX:-0}" == "1" ]]; then
        args+=(--disable-sandbox)
    fi
    if [[ -n "${CODEX_QUOTA_SDKROOT:-}" ]]; then
        [[ -d "$CODEX_QUOTA_SDKROOT" ]] || fail "CODEX_QUOTA_SDKROOT is not a directory: $CODEX_QUOTA_SDKROOT"
        env SDKROOT="$CODEX_QUOTA_SDKROOT" swift build "${args[@]}" "$@"
    else
        swift build "${args[@]}" "$@"
    fi
}

mkdir -p "$dist"
stage="$(mktemp -d "$dist/.build-app.XXXXXX")"
cleanup() {
    rm -rf -- "$stage"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
staged_app="$stage/Codex Quota.app"
macos="$staged_app/Contents/MacOS"
resources="$staged_app/Contents/Resources"
icon_tmp="$stage/icon-preview"
iconset="$stage/AppIcon.iconset"
mkdir -p "$macos" "$resources" "$icon_tmp" "$iconset"

swift_build --triple arm64-apple-macosx13.0
swift_build --triple x86_64-apple-macosx13.0
arm_bin="$(swift_build --triple arm64-apple-macosx13.0 --show-bin-path)"
intel_bin="$(swift_build --triple x86_64-apple-macosx13.0 --show-bin-path)"
[[ -x "$arm_bin/CodexQuota" ]] || fail "arm64 executable was not produced"
[[ -x "$intel_bin/CodexQuota" ]] || fail "x86_64 executable was not produced"
lipo -create "$arm_bin/CodexQuota" "$intel_bin/CodexQuota" -output "$macos/CodexQuota"

cp "$root/Resources/Info.plist" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$staged_app/Contents/Info.plist"

qlmanage -t -s 1024 -o "$icon_tmp" "$root/Resources/AppIcon.svg" >/dev/null 2>&1 || fail "Quick Look could not render Resources/AppIcon.svg"
rendered_icons=("$icon_tmp"/*.png(N))
(( ${#rendered_icons[@]} == 1 )) || fail "Quick Look produced ${#rendered_icons[@]} PNG files; expected exactly one"
rendered_icon="${rendered_icons[1]}"

make_icon() {
    local pixels="$1"
    local filename="$2"
    sips -s format png -z "$pixels" "$pixels" "$rendered_icon" --out "$iconset/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png
iconutil -c icns "$iconset" -o "$resources/AppIcon.icns"

xattr -cr "$staged_app"
codesign --force --sign - --timestamp=none "$staged_app"
rm -rf -- "$app"
mv "$staged_app" "$app"
print -- "$app"

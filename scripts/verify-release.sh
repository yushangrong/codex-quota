#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$root/dist/Codex Quota.app}"
plist="$app/Contents/Info.plist"

fail() {
    print -u2 -- "verify-release: $1"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

for tool in plutil lipo codesign grep; do
    require_command "$tool"
done
[[ -x /usr/libexec/PlistBuddy ]] || fail "required tool not found: /usr/libexec/PlistBuddy"
[[ -d "$app" ]] || fail "application bundle not found: $app"
[[ -f "$plist" ]] || fail "Info.plist not found: $plist"
plutil -lint "$plist" >/dev/null || fail "Info.plist failed plutil validation"

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || fail "Info.plist is missing $1"
}

expect_plist() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(plist_value "$key")"
    [[ "$actual" == "$expected" ]] || fail "$key is '$actual'; expected '$expected'"
}

expect_plist CFBundleIdentifier io.github.yushangrong.codex-quota
expect_plist LSMinimumSystemVersion 13.0
expect_plist LSUIElement true
expect_plist CFBundleIconFile AppIcon
expect_plist CFBundleExecutable CodexQuota

short_version="$(plist_value CFBundleShortVersionString)"
bundle_version="$(plist_value CFBundleVersion)"
[[ "$short_version" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || fail "invalid CFBundleShortVersionString: $short_version"
[[ "$bundle_version" == "$short_version" ]] || fail "CFBundleVersion does not match CFBundleShortVersionString"

executable="$app/Contents/MacOS/CodexQuota"
icon="$app/Contents/Resources/AppIcon.icns"
[[ -x "$executable" ]] || fail "bundle executable is missing or not executable: $executable"
[[ -s "$icon" ]] || fail "bundle icon is missing or empty: $icon"

architectures="$(lipo -archs "$executable")"
[[ " $architectures " == *" arm64 "* ]] || fail "executable is missing arm64 architecture: $architectures"
[[ " $architectures " == *" x86_64 "* ]] || fail "executable is missing x86_64 architecture: $architectures"
codesign --verify --deep --strict "$app" || fail "code signature verification failed"

if grep -R -F -q -- "PRIVATE_TEXT_MUST_NOT_SURVIVE" "$app"; then
    fail "private fixture marker is present in the application bundle"
fi

print -- "PASS: verified Codex Quota $short_version ($architectures)"

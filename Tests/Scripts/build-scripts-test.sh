#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"

fail() {
    print -u2 -- "FAIL: $1"
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "missing file: ${1#$root/}"
}

require_executable() {
    [[ -x "$1" ]] || fail "not executable: ${1#$root/}"
}

require_text() {
    local file="$1"
    local text="$2"
    grep -Fq -- "$text" "$file" || fail "${file#$root/} is missing: $text"
}

require_before() {
    local file="$1"
    local first="$2"
    local second="$3"
    awk -v first="$first" -v second="$second" '
        index($0, first) && !first_line { first_line = NR }
        index($0, second) && !second_line { second_line = NR }
        END { exit !(first_line && second_line && first_line < second_line) }
    ' "$file" || fail "${file#$root/} must place '$first' before '$second'"
}

for script in build-app.sh build-dmg.sh verify-release.sh; do
    script_path="$root/scripts/$script"
    require_file "$script_path"
    require_executable "$script_path"
    require_text "$script_path" "set -euo pipefail"
done

require_file "$root/Resources/Info.plist"
require_file "$root/Resources/AppIcon.svg"
plutil -lint "$root/Resources/Info.plist" >/dev/null || fail "Info.plist is invalid"

build_script="$root/scripts/build-app.sh"
require_text "$build_script" "arm64-apple-macosx13.0"
require_text "$build_script" "x86_64-apple-macosx13.0"
require_text "$build_script" "--show-bin-path"
require_text "$build_script" "lipo -create"
require_text "$build_script" "qlmanage -t -s 1024"
require_text "$build_script" "iconutil -c icns"
require_text "$build_script" "require_command xattr"
require_text "$build_script" 'xattr -cr "$staged_app"'
require_before "$build_script" 'xattr -cr "$staged_app"' "codesign --force --sign - --timestamp=none"
require_text "$build_script" "codesign --force --sign - --timestamp=none"

dmg_script="$root/scripts/build-dmg.sh"
require_text "$dmg_script" "hdiutil create"
require_text "$dmg_script" "-fs HFS+"
require_text "$dmg_script" "shasum -a 256"

print -- "PASS: release build script policy"

#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
info_plist="$project_dir/Resources/Info.plist"
version="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")}"
output_dir="$project_dir/dist"
dmg_name="Skill-Manager-$version.dmg"
dmg_path="$output_dir/$dmg_name"
checksum_path="$dmg_path.sha256"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-manager-dmg.XXXXXX")"

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

"$project_dir/scripts/build-app.sh"

mkdir -p "$output_dir"
rm -f "$dmg_path" "$checksum_path"
ditto "$project_dir/.build/release-app/Skill Manager.app" "$staging_dir/Skill Manager.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "Skill Manager" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

(
    cd "$output_dir"
    shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)

echo "$dmg_path"

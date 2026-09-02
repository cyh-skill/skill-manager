#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
output_root="$project_dir/.build/release-app"
app_dir="$output_root/Skill Manager.app"

if [ -e "$app_dir" ]; then
    rm -rf "$app_dir"
fi

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/SkillManager" "$app_dir/Contents/MacOS/SkillManager"
cp "$bin_dir/skill-manager-cli" "$app_dir/Contents/Resources/skill-manager-cli"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
source_revision="$(git rev-parse --short=12 HEAD 2>/dev/null || true)"
if [ -n "$source_revision" ]; then
    if [ -n "$(git status --porcelain)" ]; then
        source_revision="$source_revision-dirty"
    fi
    /usr/libexec/PlistBuddy -c "Add :SkillManagerSourceRevision string $source_revision" "$app_dir/Contents/Info.plist"
fi
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"
mkdir -p "$app_dir/Contents/Resources/skill-router"
cp "$project_dir/Sources/SkillManagerApp/Resources/skill-router/SKILL.md" "$app_dir/Contents/Resources/skill-router/SKILL.md"
for localization in zh-Hans en; do
    localization_dir="$app_dir/Contents/Resources/$localization.lproj"
    mkdir -p "$localization_dir"
    strings_file="$project_dir/Sources/SkillManagerApp/Resources/Localization/$localization.lproj/Localizable.strings"
    if [ -f "$strings_file" ]; then
        cp "$strings_file" "$localization_dir/Localizable.strings"
    fi
done

chmod 755 "$app_dir/Contents/MacOS/SkillManager" "$app_dir/Contents/Resources/skill-manager-cli"
codesign --force --deep --sign - "$app_dir"

test -f "$app_dir/Contents/Resources/skill-router/SKILL.md"
test -f "$app_dir/Contents/Resources/LICENSE"
test -f "$app_dir/Contents/Resources/zh-Hans.lproj/Localizable.strings"
test -f "$app_dir/Contents/Resources/en.lproj/Localizable.strings"

echo "$app_dir"

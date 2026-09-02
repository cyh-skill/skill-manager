#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="${1:-$project_dir/.build/release-app/Skill Manager.app}"
smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-manager-smoke.XXXXXX")"
smoke_pid=""

cleanup() {
    if [ -n "$smoke_pid" ] && kill -0 "$smoke_pid" >/dev/null 2>&1; then
        kill -TERM "$smoke_pid" >/dev/null 2>&1 || true
        wait "$smoke_pid" >/dev/null 2>&1 || true
    fi
    rm -rf "$smoke_root"
}
trap cleanup EXIT

if [ ! -x "$app_dir/Contents/MacOS/SkillManager" ]; then
    echo "Missing Skill Manager executable in $app_dir" >&2
    exit 1
fi
for required_resource in \
    "$app_dir/Contents/Resources/LICENSE" \
    "$app_dir/Contents/Resources/skill-router/SKILL.md" \
    "$app_dir/Contents/Resources/zh-Hans.lproj/Localizable.strings" \
    "$app_dir/Contents/Resources/en.lproj/Localizable.strings"; do
    if [ ! -f "$required_resource" ]; then
        echo "Missing packaged resource: $required_resource" >&2
        exit 1
    fi
done
if ! cmp -s "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"; then
    echo "Packaged LICENSE does not match the repository LICENSE" >&2
    exit 1
fi
bundle_copyright="$(/usr/libexec/PlistBuddy -c 'Print :NSHumanReadableCopyright' "$app_dir/Contents/Info.plist")"
if [ "$bundle_copyright" != "Copyright © 2026 cyh-skill" ]; then
    echo "Unexpected bundle copyright: $bundle_copyright" >&2
    exit 1
fi
bundle_revision="$(/usr/libexec/PlistBuddy -c 'Print :SkillManagerSourceRevision' "$app_dir/Contents/Info.plist")"
expected_revision="$(git -C "$project_dir" rev-parse --short=12 HEAD)"
if [ -n "$(git -C "$project_dir" status --porcelain)" ]; then
    expected_revision="$expected_revision-dirty"
fi
if [ "$bundle_revision" != "$expected_revision" ]; then
    echo "Unexpected source revision: $bundle_revision (expected $expected_revision)" >&2
    exit 1
fi

SKILL_MANAGER_HOME="$smoke_root/manager" \
SKILL_MANAGER_CODEX_SKILLS_DIR="$smoke_root/codex-skills" \
SKILL_MANAGER_CLAUDE_SKILLS_DIR="$smoke_root/claude-skills" \
"$app_dir/Contents/MacOS/SkillManager" \
    >"$smoke_root/stdout.log" \
    2>"$smoke_root/stderr.log" &
smoke_pid="$!"

for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! kill -0 "$smoke_pid" >/dev/null 2>&1; then
        echo "Skill Manager exited during smoke test" >&2
        cat "$smoke_root/stderr.log" >&2
        exit 1
    fi
    sleep 0.5
done

echo "Skill Manager remained running for 5 seconds"

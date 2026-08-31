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
    "$app_dir/Contents/Resources/skill-router/SKILL.md" \
    "$app_dir/Contents/Resources/zh-Hans.lproj/Localizable.strings" \
    "$app_dir/Contents/Resources/en.lproj/Localizable.strings"; do
    if [ ! -f "$required_resource" ]; then
        echo "Missing packaged resource: $required_resource" >&2
        exit 1
    fi
done

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

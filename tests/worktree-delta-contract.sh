#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/worktree-delta.XXXXXX")
STATE=$(mktemp "${TMPDIR:-/tmp}/worktree-state.XXXXXX")
trap 'rm -rf "$FIXTURE"; rm -f "$STATE"' EXIT HUP INT TERM

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.name 'Delta Contract'
git -C "$FIXTURE" config user.email 'delta@example.invalid'
printf '%s\n' baseline > "$FIXTURE/tracked.txt"
git -C "$FIXTURE" add tracked.txt
git -C "$FIXTURE" commit -qm baseline

ruby "$ROOT/scripts/worktree-delta.rb" snapshot "$STATE" "$FIXTURE" >/dev/null
empty_exit=0
ruby "$ROOT/scripts/worktree-delta.rb" check "$STATE" "$FIXTURE" > "$FIXTURE-result" || empty_exit=$?
[ "$empty_exit" -eq 3 ]
grep -F 'STATUS: empty' "$FIXTURE-result" >/dev/null
printf 'PASS: deterministic empty delta\n'

printf '%s\n' changed > "$FIXTURE/tracked.txt"
ruby "$ROOT/scripts/worktree-delta.rb" check "$STATE" "$FIXTURE" > "$FIXTURE-result"
grep -F 'STATUS: changed' "$FIXTURE-result" >/dev/null
grep -F 'CHANGE: modified: tracked.txt' "$FIXTURE-result" >/dev/null
printf 'PASS: deterministic tracked modification\n'

printf '%s\n' new > "$FIXTURE/new.txt"
ruby "$ROOT/scripts/worktree-delta.rb" check "$STATE" "$FIXTURE" > "$FIXTURE-result"
grep -F 'CHANGE: added: new.txt' "$FIXTURE-result" >/dev/null
printf 'PASS: deterministic untracked addition\n'

rm "$FIXTURE/tracked.txt"
ruby "$ROOT/scripts/worktree-delta.rb" check "$STATE" "$FIXTURE" > "$FIXTURE-result"
grep -F 'CHANGE: deleted: tracked.txt' "$FIXTURE-result" >/dev/null
printf 'PASS: deterministic deletion\n'

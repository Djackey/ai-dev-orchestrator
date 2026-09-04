#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
GUARD=$ROOT/scripts/protected-paths.rb
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/protected-paths.XXXXXX")
STATE=$(mktemp "${TMPDIR:-/tmp}/protected-state.XXXXXX")
RESULT=$(mktemp "${TMPDIR:-/tmp}/protected-result.XXXXXX")
trap 'rm -rf "$FIXTURE"; rm -f "$STATE" "$RESULT"' EXIT HUP INT TERM

mkdir -p "$FIXTURE/.claude" "$FIXTURE/.codex" "$FIXTURE/node_modules" "$FIXTURE/secrets"
printf '%s\n' 'API_KEY=baseline' > "$FIXTURE/.env"
printf '%s\n' '{"permissions":{}}' > "$FIXTURE/.claude/settings.local.json"
printf '%s\n' 'model = "baseline"' > "$FIXTURE/.codex/config.toml"
printf '%s\n' '//registry.example/:_authToken=baseline' > "$FIXTURE/.npmrc"
printf '%s\n' 'TOKEN=nested' > "$FIXTURE/node_modules/.env"
printf '%s\n' '{"token":"baseline"}' > "$FIXTURE/secrets/local.json"

snapshot() {
  ruby "$GUARD" snapshot "$STATE" "$FIXTURE" > "$RESULT"
  grep -F 'STATUS: captured' "$RESULT" >/dev/null
}

expect_unchanged() {
  name=$1
  ruby "$GUARD" check "$STATE" "$FIXTURE" > "$RESULT"
  grep -F 'STATUS: unchanged' "$RESULT" >/dev/null
  grep -F 'VIOLATIONS: none' "$RESULT" >/dev/null
  printf 'PASS: %s\n' "$name"
}

expect_violation() {
  name=$1
  expected=$2
  exit_code=0
  ruby "$GUARD" check "$STATE" "$FIXTURE" > "$RESULT" || exit_code=$?
  [ "$exit_code" -eq 4 ] || {
    printf 'FAIL: %s exited %s, expected 4\n' "$name" "$exit_code" >&2
    cat "$RESULT" >&2
    exit 1
  }
  grep -F 'STATUS: violation' "$RESULT" >/dev/null
  grep -Fx "VIOLATION: $expected" "$RESULT" >/dev/null || {
    printf 'FAIL: %s did not report "%s"\n' "$name" "$expected" >&2
    cat "$RESULT" >&2
    exit 1
  }
  printf 'PASS: %s\n' "$name"
}

snapshot
expect_unchanged 'untouched protected local state is unchanged'

printf '%s\n' 'API_KEY=leaked' > "$FIXTURE/.env"
expect_violation 'modified .env is a violation' 'modified: .env'
printf '%s\n' 'API_KEY=baseline' > "$FIXTURE/.env"
expect_unchanged 'restored .env content is unchanged again'

printf '%s\n' 'API_KEY=shadow' > "$FIXTURE/.env.local"
expect_violation 'added .env.local is a violation' 'added: .env.local'
rm "$FIXTURE/.env.local"

printf '%s\n' '{"permissions":{"allow":["Bash"]}}' > "$FIXTURE/.claude/settings.local.json"
expect_violation 'modified .claude/settings.local.json is a violation' 'modified: .claude/settings.local.json'
printf '%s\n' '{"permissions":{}}' > "$FIXTURE/.claude/settings.local.json"

printf '%s\n' 'model = "swapped"' > "$FIXTURE/.codex/config.toml"
expect_violation 'modified .codex config is a violation' 'modified: .codex/config.toml'
printf '%s\n' 'model = "baseline"' > "$FIXTURE/.codex/config.toml"

printf '%s\n' 'profile = "new"' > "$FIXTURE/.codex/profiles.toml"
expect_violation 'added .codex file is a violation' 'added: .codex/profiles.toml'
rm "$FIXTURE/.codex/profiles.toml"

rm "$FIXTURE/.npmrc"
expect_violation 'deleted .npmrc is a violation' 'deleted: .npmrc'
printf '%s\n' '//registry.example/:_authToken=baseline' > "$FIXTURE/.npmrc"
expect_unchanged 'all defaults restored'

# node_modules/.env exists but no default pattern may reach it.
printf '%s\n' 'TOKEN=rotated' > "$FIXTURE/node_modules/.env"
expect_unchanged 'default patterns never reach node_modules'

printf '%s\n' '# project-declared sensitive ignored paths' 'secrets/local.json' '**/.env' > "$FIXTURE/.ai-orchestrator-protected-paths"
snapshot
grep -F 'FILES: 6' "$RESULT" >/dev/null || {
  printf 'FAIL: declared inventory excluded node_modules incorrectly\n' >&2
  cat "$RESULT" >&2
  exit 1
}
printf 'PASS: declared patterns are inventoried and node_modules stays excluded\n'

printf '%s\n' 'TOKEN=exfiltrated' > "$FIXTURE/node_modules/.env"
expect_unchanged 'excluded node_modules is still not inventoried under **/.env'

printf '%s\n' '{"token":"rotated"}' > "$FIXTURE/secrets/local.json"
expect_violation 'declared sensitive path is guarded' 'modified: secrets/local.json'

printf '%s\n' '# emptied by the task' > "$FIXTURE/.ai-orchestrator-protected-paths"
expect_violation 'removing a configured pattern cannot shrink the guard' 'modified: secrets/local.json'
printf '%s\n' '{"token":"baseline"}' > "$FIXTURE/secrets/local.json"
expect_unchanged 'union of baseline and current patterns stays in force'

inside_exit=0
ruby "$GUARD" snapshot "$FIXTURE/state.json" "$FIXTURE" > "$RESULT" 2>&1 || inside_exit=$?
[ "$inside_exit" -eq 2 ]
grep -F 'state file must be outside the protected root' "$RESULT" >/dev/null
printf 'PASS: state file inside the protected root is refused\n'

mkdir -p "$FIXTURE/bigdir"
i=0
while [ "$i" -lt 501 ]; do
  : > "$FIXTURE/bigdir/file-$i"
  i=$((i + 1))
done
printf '%s\n' 'bigdir/' > "$FIXTURE/.ai-orchestrator-protected-paths"
cap_exit=0
ruby "$GUARD" snapshot "$STATE" "$FIXTURE" > "$RESULT" 2>&1 || cap_exit=$?
[ "$cap_exit" -eq 2 ]
grep -F 'exceeds the 500 limit' "$RESULT" >/dev/null
printf 'PASS: oversized protected inventory fails loudly instead of scanning a tree\n'

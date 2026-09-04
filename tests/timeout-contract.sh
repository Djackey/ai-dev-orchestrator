#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CONTRACT=$ROOT/contracts/IMPLEMENTATION_LANE_CONTRACT.md
cd "$ROOT"
CONSTRUCTOR=$(awk '
  /<!-- CODEX_ARGV_CONTRACT_START -->/ { capture=1; next }
  /<!-- CODEX_ARGV_CONTRACT_END -->/ { capture=0 }
  capture && $0 !~ /^```/ { print }
' "$CONTRACT")
[ -n "$CONSTRUCTOR" ] || {
  printf '%s\n' 'FAIL: executable argv contract block not found' >&2
  exit 1
}
CONSTRUCTOR="$CONSTRUCTOR
for argument do
  printf \"%s\\n\" \"\$argument\"
done"

expect_case() {
  shell_name=$1
  timeout_path=$2
  effort=$3
  expected=$4

  if ! command -v "$shell_name" >/dev/null 2>&1; then
    printf 'SKIP: %s unavailable\n' "$shell_name"
    return 0
  fi

  actual=$(
    TIMEOUT_BIN="$timeout_path" \
    TIMEOUT_SECONDS=600 \
    CODEX_BIN=/resolved/codex \
    MODEL=gpt-5.6-luna \
    EFFORT="$effort" \
    FINAL=/tmp/final-message \
    "$shell_name" -c "$CONSTRUCTOR"
  )

  if [ "$actual" != "$expected" ]; then
    printf 'FAIL: %s timeout=%s effort=%s\n' "$shell_name" "${timeout_path:-absent}" "${effort:-absent}" >&2
    printf 'EXPECTED:\n%s\nACTUAL:\n%s\n' "$expected" "$actual" >&2
    exit 1
  fi

  printf 'PASS: %s timeout=%s effort=%s\n' "$shell_name" "${timeout_path:-absent}" "${effort:-absent}"
}

COMMON_SUFFIX='--sandbox
workspace-write
--skip-git-repo-check
--cd
'"$ROOT"'
--output-last-message
/tmp/final-message
-'
NO_TIMEOUT_PREFIX='WARN: no timeout binary; Codex runs uncapped
'

WITH_TIMEOUT_AND_EFFORT='/fake/gtimeout
600
/resolved/codex
--ask-for-approval
never
exec
--model
gpt-5.6-luna
-c
model_reasoning_effort=max
'"$COMMON_SUFFIX"

WITHOUT_TIMEOUT_WITH_EFFORT="$NO_TIMEOUT_PREFIX"'/resolved/codex
--ask-for-approval
never
exec
--model
gpt-5.6-luna
-c
model_reasoning_effort=max
'"$COMMON_SUFFIX"

WITH_TIMEOUT_NO_EFFORT='/fake/gtimeout
600
/resolved/codex
--ask-for-approval
never
exec
--model
gpt-5.6-luna
'"$COMMON_SUFFIX"

WITHOUT_TIMEOUT_OR_EFFORT="$NO_TIMEOUT_PREFIX"'/resolved/codex
--ask-for-approval
never
exec
--model
gpt-5.6-luna
'"$COMMON_SUFFIX"

for shell_name in bash zsh; do
  expect_case "$shell_name" /fake/gtimeout max "$WITH_TIMEOUT_AND_EFFORT"
  expect_case "$shell_name" '' max "$WITHOUT_TIMEOUT_WITH_EFFORT"
  expect_case "$shell_name" /fake/gtimeout '' "$WITH_TIMEOUT_NO_EFFORT"
  expect_case "$shell_name" '' '' "$WITHOUT_TIMEOUT_OR_EFFORT"
done

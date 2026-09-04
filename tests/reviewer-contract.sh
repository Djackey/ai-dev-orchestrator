#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/reviewer-contract.XXXXXX")
trap 'rm -rf "$FIXTURE_ROOT"' EXIT HUP INT TERM
PROMPT_FILE=$FIXTURE_ROOT/prompt.txt
printf '%s\n' 'Return REVIEW REPORT and VERDICT: ACCEPT.' > "$PROMPT_FILE"

cat > "$FIXTURE_ROOT/claude" <<'EOF'
#!/bin/sh
if [ "${1-}" = --version ]; then
  printf '%s\n' 'fixture claude 1.0'
  exit 0
fi
case "${FAKE_REVIEW_MODE-available}" in
  available)
    printf '%s\n' '{"modelUsage":{"claude-fable-5-1":{}},"permission_denials":[],"result":"REVIEW REPORT\nVERDICT: ACCEPT"}'
    ;;
  agent)
    printf '%s\n' 'Agent fable-advisor not found' >&2
    exit 2
    ;;
  model)
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[],"result":"REVIEW REPORT\nVERDICT: ACCEPT"}'
    ;;
  multimodel)
    printf '%s\n' '{"modelUsage":{"claude-fable-5-1":{},"claude-sonnet-5":{}},"permission_denials":[],"result":"REVIEW REPORT\nVERDICT: ACCEPT"}'
    ;;
  transport)
    printf '%s\n' 'connection closed' >&2
    exit 3
    ;;
  output)
    printf '%s\n' 'not-json'
    ;;
  null)
    printf '%s\n' 'null'
    ;;
  permission)
    printf '%s\n' '{"modelUsage":{"claude-fable-5-1":{}},"permission_denials":["Read denied"],"result":"REVIEW REPORT\nVERDICT: ACCEPT"}'
    ;;
esac
EOF
chmod +x "$FIXTURE_ROOT/claude"

run_available() {
  output=$(env FAKE_REVIEW_MODE=available PATH="$FIXTURE_ROOT:/usr/bin:/bin" "$ROOT/scripts/run-clean-context-review.sh" "$PROMPT_FILE")
  printf '%s' "$output" | grep -F 'STATUS: AVAILABLE' >/dev/null
  printf '%s' "$output" | grep -F 'RESOLVED_MODEL: claude-fable-5-1' >/dev/null
  printf 'PASS: reviewer available and consumable\n'
}

run_unavailable() {
  mode=$1
  expected=$2
  result_file=$FIXTURE_ROOT/result-$mode
  if env FAKE_REVIEW_MODE="$mode" PATH="$FIXTURE_ROOT:/usr/bin:/bin" "$ROOT/scripts/run-clean-context-review.sh" "$PROMPT_FILE" > "$result_file"; then
    printf 'FAIL: reviewer mode %s unexpectedly succeeded\n' "$mode" >&2
    exit 1
  fi
  grep -F 'STATUS: UNAVAILABLE' "$result_file" >/dev/null
  grep -F "CLASSIFICATION: $expected" "$result_file" >/dev/null
  printf 'PASS: reviewer classification %s\n' "$expected"
}

run_available
run_unavailable agent AGENT_NOT_INVOKED
run_unavailable model MODEL_UNRESOLVED
run_unavailable multimodel MODEL_UNRESOLVED
run_unavailable transport TRANSPORT_FAILED
run_unavailable output OUTPUT_NOT_CAPTURED
run_unavailable null OUTPUT_NOT_CAPTURED
run_unavailable permission TOOL_PERMISSION_FAILURE

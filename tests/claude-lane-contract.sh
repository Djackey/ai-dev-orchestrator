#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claude-lane-contract.XXXXXX")
trap 'rm -rf "$FIXTURE_ROOT"' EXIT HUP INT TERM

REPO=$FIXTURE_ROOT/repo
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.name 'Claude Lane Contract'
git -C "$REPO" config user.email 'claude-lane@example.invalid'
printf '%s\n' baseline > "$REPO/tracked.txt"
printf '%s\n' '.env' > "$REPO/.gitignore"
printf '%s\n' 'API_KEY=baseline' > "$REPO/.env"
git -C "$REPO" add tracked.txt .gitignore
git -C "$REPO" commit -qm baseline

SPEC_FILE=$FIXTURE_ROOT/spec.txt
printf '%s\n' 'Do the fixture task.' > "$SPEC_FILE"

ARGV_LOG=$FIXTURE_ROOT/argv.log
: > "$ARGV_LOG"

FRESH_GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STALE_GENERATED_AT=$(python3 -c "
import datetime
print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=40)).strftime('%Y-%m-%dT%H:%M:%SZ'))
")

write_model_map() {
  path=$1
  generated_at=$2
  cat > "$path" <<EOF
{"generatedAt": "$generated_at", "claudeVersion": "fixture claude 1.0", "aliases": {"sonnet": "claude-sonnet-5", "opus": "claude-opus-5", "haiku": "claude-haiku-4-5-20251001", "fable": "claude-fable-5-1"}, "probeCostUsd": 0.01}
EOF
}

MODEL_MAP=$FIXTURE_ROOT/model-map.json
STALE_MODEL_MAP=$FIXTURE_ROOT/model-map-stale.json
write_model_map "$MODEL_MAP" "$FRESH_GENERATED_AT"
write_model_map "$STALE_MODEL_MAP" "$STALE_GENERATED_AT"

SHIM_DIR=$FIXTURE_ROOT/bin
mkdir -p "$SHIM_DIR"
cat > "$SHIM_DIR/claude" <<'EOF'
#!/bin/sh
if [ "${1-}" = --version ]; then
  printf '%s\n' 'fixture claude 1.0'
  exit 0
fi

: > "$FAKE_LANE_ARGV_FILE"
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$FAKE_LANE_ARGV_FILE"
done

case "${FAKE_LANE_MODE-available}" in
  available)
    printf 'edited\n' >> tracked.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[],"is_error":false,"subtype":"success","total_cost_usd":0.03,"num_turns":4,"result":"done"}'
    ;;
  no_model)
    printf '%s\n' '{"modelUsage":{},"permission_denials":[],"is_error":false,"result":"done"}'
    ;;
  multi_model)
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{},"claude-opus-5":{}},"permission_denials":[],"is_error":false,"result":"done"}'
    ;;
  wrong_model)
    printf '%s\n' '{"modelUsage":{"claude-opus-5":{}},"permission_denials":[],"is_error":false,"result":"done"}'
    ;;
  empty_delta)
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[],"is_error":false,"result":"nothing changed"}'
    ;;
  protected_violation)
    printf 'edited\n' >> tracked.txt
    printf 'LEAK=1\n' >> .env
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[],"is_error":false,"result":"done"}'
    ;;
  budget_exceeded)
    printf 'edited\n' >> tracked.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[],"is_error":true,"subtype":"error_max_budget_usd","total_cost_usd":0.02,"result":"partial work"}'
    ;;
  write_denied)
    printf 'edited\n' >> tracked.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[{"tool_name":"Write","tool_input":{}}],"is_error":false,"result":"done"}'
    ;;
  bash_denied)
    printf 'edited\n' >> tracked.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[{"tool_name":"Bash","tool_input":{}}],"is_error":false,"result":"done"}'
    ;;
esac
EOF
chmod +x "$SHIM_DIR/claude"

run_lane() {
  mode=$1
  shift
  RESULT_FILE=$FIXTURE_ROOT/result-$mode
  LANE_EXIT=0
  env FAKE_LANE_MODE="$mode" FAKE_LANE_ARGV_FILE="$ARGV_LOG" \
    PATH="$SHIM_DIR:/usr/bin:/bin" \
    "$ROOT/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$REPO" --model-map "$MODEL_MAP" "$@" \
    > "$RESULT_FILE" 2>&1 || LANE_EXIT=$?
}

assert_report() {
  file=$1
  status=$2
  classification=$3
  grep -Fx "STATUS: $status" "$file" >/dev/null || {
    printf 'FAIL: expected STATUS: %s in %s\n' "$status" "$file" >&2
    cat "$file" >&2
    exit 1
  }
  grep -Fx "CLASSIFICATION: $classification" "$file" >/dev/null || {
    printf 'FAIL: expected CLASSIFICATION: %s in %s\n' "$classification" "$file" >&2
    cat "$file" >&2
    exit 1
  }
}

assert_exit() {
  name=$1
  expected=$2
  actual=$3
  [ "$actual" -eq "$expected" ] || {
    printf 'FAIL: %s exited %s, expected %s\n' "$name" "$actual" "$expected" >&2
    cat "$RESULT_FILE" >&2
    exit 1
  }
}

# (a) success
run_lane available
assert_exit '(a) success' 0 "$LANE_EXIT"
assert_report "$RESULT_FILE" complete-candidate none
printf 'PASS: (a) success -> complete-candidate/none, exit 0\n'

# (b) no modelUsage key
run_lane no_model
assert_exit '(b) no modelUsage key' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable MODEL_UNRESOLVED
printf 'PASS: (b) empty modelUsage -> unavailable/MODEL_UNRESOLVED\n'

# (c) two modelUsage keys
run_lane multi_model
assert_exit '(c) two modelUsage keys' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable MULTI_MODEL
printf 'PASS: (c) two modelUsage keys -> unavailable/MULTI_MODEL\n'

# (d) wrong modelUsage key
run_lane wrong_model
assert_exit '(d) wrong modelUsage key' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable MODEL_UNRESOLVED
printf 'PASS: (d) wrong modelUsage key -> unavailable/MODEL_UNRESOLVED\n'

# (e) shim changes nothing
run_lane empty_delta
assert_exit '(e) empty delta' 3 "$LANE_EXIT"
assert_report "$RESULT_FILE" refused EMPTY_DELTA
printf 'PASS: (e) empty delta -> refused/EMPTY_DELTA, exit 3\n'

# (f) shim appends to .env (and edits the tracked file)
run_lane protected_violation
assert_exit '(f) protected state violation' 3 "$LANE_EXIT"
assert_report "$RESULT_FILE" refused PROTECTED_STATE_VIOLATION
printf 'PASS: (f) protected state violation -> refused/PROTECTED_STATE_VIOLATION, exit 3\n'

# (g) subtype error_max_budget_usd with a real delta
run_lane budget_exceeded
assert_exit '(g) budget exceeded' 2 "$LANE_EXIT"
assert_report "$RESULT_FILE" partial BUDGET_EXCEEDED
printf 'PASS: (g) budget exceeded -> partial/BUDGET_EXCEEDED, exit 2\n'

# (h) permission_denials containing a Write denial with a real delta
run_lane write_denied
assert_exit '(h) write denied' 2 "$LANE_EXIT"
assert_report "$RESULT_FILE" partial TOOL_PERMISSION_FAILURE
printf 'PASS: (h) Write denial -> partial/TOOL_PERMISSION_FAILURE, exit 2\n'

# (i) permission_denials containing only a Bash denial with a real delta
run_lane bash_denied
assert_exit '(i) bash denied' 0 "$LANE_EXIT"
assert_report "$RESULT_FILE" complete-candidate none
grep -Fx 'BOUNDARY_EVENTS: 1 denial(s): Bash' "$RESULT_FILE" >/dev/null || {
  printf 'FAIL: (i) expected a single Bash boundary event\n' >&2
  cat "$RESULT_FILE" >&2
  exit 1
}
printf 'PASS: (i) Bash-only denial -> complete-candidate with 1 boundary event\n'

# (j) model map generatedAt 40 days old
STALE_RESULT=$FIXTURE_ROOT/result-stale
STALE_EXIT=0
env FAKE_LANE_MODE=available FAKE_LANE_ARGV_FILE="$ARGV_LOG" \
  PATH="$SHIM_DIR:/usr/bin:/bin" \
  "$ROOT/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$REPO" --model-map "$STALE_MODEL_MAP" \
  > "$STALE_RESULT" 2>&1 || STALE_EXIT=$?
[ "$STALE_EXIT" -eq 1 ] || {
  printf 'FAIL: (j) stale model map exited %s, expected 1\n' "$STALE_EXIT" >&2
  cat "$STALE_RESULT" >&2
  exit 1
}
assert_report "$STALE_RESULT" unavailable MAPPING_STALE
printf 'PASS: (j) stale model map -> unavailable/MAPPING_STALE\n'

# (k) invocation boundary argv assertions, using the (a) success run's log.
grep -Fx -- '--restricted' "$ARGV_LOG" >/dev/null || {
  printf 'FAIL: (k) --restricted not found in argv\n' >&2
  cat "$ARGV_LOG" >&2
  exit 1
}
grep -Fx -- '--permission-prompts' "$ARGV_LOG" >/dev/null || {
  printf 'FAIL: (k) --permission-prompts not found in argv\n' >&2
  exit 1
}
grep -Fx 'none' "$ARGV_LOG" >/dev/null || {
  printf 'FAIL: (k) --permission-prompts value "none" not found in argv\n' >&2
  exit 1
}
grep -Fx -- '--no-session-persistence' "$ARGV_LOG" >/dev/null || {
  printf 'FAIL: (k) --no-session-persistence not found in argv\n' >&2
  exit 1
}
grep -F 'Edit(./.env)' "$ARGV_LOG" >/dev/null || {
  printf 'FAIL: (k) deny list missing Edit(./.env)\n' >&2
  exit 1
}
grep -F 'Write(./.git/**)' "$ARGV_LOG" >/dev/null || {
  printf 'FAIL: (k) deny list missing Write(./.git/**)\n' >&2
  exit 1
}
if grep -Fx -- '--fallback-model' "$ARGV_LOG" >/dev/null; then
  printf 'FAIL: (k) --fallback-model must never be passed\n' >&2
  exit 1
fi
if grep -Fx -- '--dangerously-skip-permissions' "$ARGV_LOG" >/dev/null; then
  printf 'FAIL: (k) --dangerously-skip-permissions must never be passed\n' >&2
  exit 1
fi
printf 'PASS: (k) invocation boundary argv contains the required flags and omits the forbidden ones\n'

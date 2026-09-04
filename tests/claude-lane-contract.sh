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

FRESH_GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STALE_GENERATED_AT=$(python3 -c "
import datetime
print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=40)).strftime('%Y-%m-%dT%H:%M:%SZ'))
")
FUTURE_GENERATED_AT=$(python3 -c "
import datetime
print((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))
")

write_model_map() {
  path=$1
  generated_at=$2
  cat > "$path" <<EOF
{"generatedAt": "$generated_at", "claudeVersion": "fixture claude 1.0", "aliases": {"sonnet": "claude-sonnet-5", "opus": "claude-opus-5", "haiku": "claude-haiku-4-5-20251001", "fable": "claude-fable-5-1"}, "probeCostUsd": 0.01}
EOF
}

write_model_map_custom() {
  path=$1
  generated_at=$2
  claude_version=$3
  sonnet_json=$4
  cat > "$path" <<EOF
{"generatedAt": "$generated_at", "claudeVersion": "$claude_version", "aliases": {"sonnet": $sonnet_json, "opus": "claude-opus-5", "haiku": "claude-haiku-4-5-20251001", "fable": "claude-fable-5-1"}, "probeCostUsd": 0.01}
EOF
}

MODEL_MAP=$FIXTURE_ROOT/model-map.json
STALE_MODEL_MAP=$FIXTURE_ROOT/model-map-stale.json
FUTURE_MODEL_MAP=$FIXTURE_ROOT/model-map-future.json
VERSION_MISMATCH_MODEL_MAP=$FIXTURE_ROOT/model-map-version-mismatch.json
BADCANONICAL_MODEL_MAP=$FIXTURE_ROOT/model-map-badcanonical.json
write_model_map "$MODEL_MAP" "$FRESH_GENERATED_AT"
write_model_map "$STALE_MODEL_MAP" "$STALE_GENERATED_AT"
write_model_map_custom "$FUTURE_MODEL_MAP" "$FUTURE_GENERATED_AT" 'fixture claude 1.0' '"claude-sonnet-5"'
write_model_map_custom "$VERSION_MISMATCH_MODEL_MAP" "$FRESH_GENERATED_AT" 'fixture claude 9.9' '"claude-sonnet-5"'
write_model_map_custom "$BADCANONICAL_MODEL_MAP" "$FRESH_GENERATED_AT" 'fixture claude 1.0' '"gpt-x"'

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

if [ -n "${FAKE_LANE_STDIN_FILE-}" ]; then
  cat > "$FAKE_LANE_STDIN_FILE"
else
  cat > /dev/null
fi

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
  protected_violation_malformed_json)
    printf 'edited\n' >> tracked.txt
    printf 'LEAK=1\n' >> .env
    printf 'not valid json{{{\n'
    ;;
  budget_exceeded)
    printf 'edited\n' >> tracked.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[],"is_error":true,"subtype":"error_max_budget_usd","total_cost_usd":0.02,"result":"partial work"}'
    ;;
  turns_exceeded)
    printf 'edited\n' >> tracked.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[],"is_error":true,"subtype":"error_max_turns","result":"partial work"}'
    ;;
  write_denied)
    printf 'edited\n' >> tracked.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[{"tool_name":"Write","tool_input":{}}],"is_error":false,"result":"done"}'
    ;;
  bash_denied)
    printf 'edited\n' >> tracked.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[{"tool_name":"Bash","tool_input":{}}],"is_error":false,"result":"done"}'
    ;;
  transport_boom)
    printf 'boom: fixture transport\n' >&2
    exit 7
    ;;
  scope_violation)
    printf 'edited\n' >> tracked.txt
    mkdir -p outside
    printf 'stray\n' >> outside/other.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[],"is_error":false,"result":"done"}'
    ;;
esac
EOF
chmod +x "$SHIM_DIR/claude"

run_lane() {
  name=$1
  mode=$2
  shift 2
  RESULT_FILE=$FIXTURE_ROOT/result-$name
  ARGV_FILE=$FIXTURE_ROOT/argv-$name.log
  STDIN_FILE=$FIXTURE_ROOT/stdin-$name.log
  LANE_EXIT=0
  env FAKE_LANE_MODE="$mode" FAKE_LANE_ARGV_FILE="$ARGV_FILE" FAKE_LANE_STDIN_FILE="$STDIN_FILE" \
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

assert_reason_contains() {
  file=$1
  text=$2
  grep -F -- "$text" "$file" >/dev/null || {
    printf 'FAIL: expected REASON to contain "%s" in %s\n' "$text" "$file" >&2
    cat "$file" >&2
    exit 1
  }
}

assert_pair() {
  file=$1
  flag=$2
  value=$3
  result=$(awk -v flag="$flag" -v value="$value" '
    { lines[NR] = $0 }
    END {
      for (i = 1; i < NR; i++) {
        if (lines[i] == flag && lines[i + 1] == value) { print "FOUND"; exit }
      }
    }
  ' "$file")
  [ "$result" = "FOUND" ] || {
    printf 'FAIL: expected adjacent pair "%s" "%s" in %s\n' "$flag" "$value" "$file" >&2
    cat "$file" >&2
    exit 1
  }
}

assert_flag_present() {
  file=$1
  flag=$2
  grep -Fx -- "$flag" "$file" >/dev/null || {
    printf 'FAIL: expected flag %s in %s\n' "$flag" "$file" >&2
    cat "$file" >&2
    exit 1
  }
}

assert_flag_absent() {
  file=$1
  flag=$2
  if grep -Fx -- "$flag" "$file" >/dev/null; then
    printf 'FAIL: forbidden flag %s found in %s\n' "$flag" "$file" >&2
    exit 1
  fi
}

# (a) success
run_lane a available --effort medium --max-turns 30 --max-budget-usd 5
assert_exit '(a) success' 0 "$LANE_EXIT"
assert_report "$RESULT_FILE" complete-candidate none
printf 'PASS: (a) success -> complete-candidate/none, exit 0\n'

# (b) no modelUsage key
run_lane b no_model
assert_exit '(b) no modelUsage key' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable MODEL_UNRESOLVED
printf 'PASS: (b) empty modelUsage -> unavailable/MODEL_UNRESOLVED\n'

# (c) two modelUsage keys
run_lane c multi_model
assert_exit '(c) two modelUsage keys' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable MULTI_MODEL
printf 'PASS: (c) two modelUsage keys -> unavailable/MULTI_MODEL\n'

# (d) wrong modelUsage key
run_lane d wrong_model
assert_exit '(d) wrong modelUsage key' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable MODEL_UNRESOLVED
printf 'PASS: (d) wrong modelUsage key -> unavailable/MODEL_UNRESOLVED\n'

# (e) shim changes nothing
run_lane e empty_delta
assert_exit '(e) empty delta' 3 "$LANE_EXIT"
assert_report "$RESULT_FILE" refused EMPTY_DELTA
printf 'PASS: (e) empty delta -> refused/EMPTY_DELTA, exit 3\n'

# (f) shim appends to .env (and edits the tracked file)
run_lane f protected_violation
assert_exit '(f) protected state violation' 3 "$LANE_EXIT"
assert_report "$RESULT_FILE" refused PROTECTED_STATE_VIOLATION
printf 'PASS: (f) protected state violation -> refused/PROTECTED_STATE_VIOLATION, exit 3\n'

# (g) subtype error_max_budget_usd with a real delta
run_lane g budget_exceeded
assert_exit '(g) budget exceeded' 2 "$LANE_EXIT"
assert_report "$RESULT_FILE" partial BUDGET_EXCEEDED
printf 'PASS: (g) budget exceeded -> partial/BUDGET_EXCEEDED, exit 2\n'

# (h) permission_denials containing a Write denial with a real delta
run_lane h write_denied
assert_exit '(h) write denied' 2 "$LANE_EXIT"
assert_report "$RESULT_FILE" partial TOOL_PERMISSION_FAILURE
printf 'PASS: (h) Write denial -> partial/TOOL_PERMISSION_FAILURE, exit 2\n'

# (i) permission_denials containing only a Bash denial with a real delta
run_lane i bash_denied
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
env FAKE_LANE_MODE=available FAKE_LANE_ARGV_FILE="$FIXTURE_ROOT/argv-stale.log" \
  FAKE_LANE_STDIN_FILE="$FIXTURE_ROOT/stdin-stale.log" \
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

# (k) invocation boundary: exact-argv assertions on the (a) success run.
K_ARGV=$FIXTURE_ROOT/argv-a.log
K_STDIN=$FIXTURE_ROOT/stdin-a.log

assert_pair "$K_ARGV" '--model' 'sonnet'
assert_pair "$K_ARGV" '--permission-mode' 'acceptEdits'
assert_pair "$K_ARGV" '--permission-prompts' 'none'
assert_pair "$K_ARGV" '--tools' 'Read,Edit,Write,Grep,Glob,Bash'
assert_pair "$K_ARGV" '--allowedTools' 'Read,Edit,Write,Grep,Glob'
assert_pair "$K_ARGV" '--output-format' 'json'
assert_pair "$K_ARGV" '--effort' 'medium'
assert_pair "$K_ARGV" '--max-turns' '30'
assert_pair "$K_ARGV" '--max-budget-usd' '5'

assert_flag_present "$K_ARGV" '--restricted'
assert_flag_present "$K_ARGV" '--strict-mcp-config'
assert_flag_present "$K_ARGV" '--no-session-persistence'

SETTINGS_JSON=$(awk '
  { lines[NR] = $0 }
  END {
    for (i = 1; i < NR; i++) {
      if (lines[i] == "--settings") { print lines[i + 1]; exit }
    }
  }
' "$K_ARGV")
[ -n "$SETTINGS_JSON" ] || {
  printf 'FAIL: (k) --settings value not found in %s\n' "$K_ARGV" >&2
  exit 1
}
python3 -c '
import json, sys
data = json.loads(sys.argv[1])
deny = data["permissions"]["deny"]
required = ["Read(./.env)", "Write(./.git/**)", "Write(./.claude/**)"]
missing = [r for r in required if r not in deny]
if missing:
    sys.stderr.write("missing: %s\n" % missing)
    sys.exit(1)
' "$SETTINGS_JSON" || {
  printf 'FAIL: (k) --settings deny list missing required entries\n' >&2
  exit 1
}

if grep -Fx -- 'Do the fixture task.' "$K_ARGV" >/dev/null 2>&1; then
  printf 'FAIL: (k) spec text found in argv; it must be piped via stdin\n' >&2
  exit 1
fi
cmp -s "$SPEC_FILE" "$K_STDIN" || {
  printf 'FAIL: (k) stdin file is not byte-identical to the spec file\n' >&2
  exit 1
}

assert_flag_absent "$K_ARGV" '--fallback-model'
assert_flag_absent "$K_ARGV" '--dangerously-skip-permissions'
assert_flag_absent "$K_ARGV" '--allow-dangerously-skip-permissions'
assert_flag_absent "$K_ARGV" '--mcp-config'
printf 'PASS: (k) invocation boundary argv contains the required flags and omits the forbidden ones\n'

# (l) two --allow-bash prefixes combine into one exact --allowedTools value.
run_lane l available --allow-bash 'pnpm exec' --allow-bash 'git status'
assert_exit '(l) allow-bash prefixes' 0 "$LANE_EXIT"
assert_pair "$FIXTURE_ROOT/argv-l.log" '--allowedTools' 'Read,Edit,Write,Grep,Glob,Bash(pnpm exec:*),Bash(git status:*)'
printf 'PASS: (l) --allow-bash prefixes -> exact --allowedTools value\n'

# (m) model map generatedAt one day in the future
FUTURE_RESULT=$FIXTURE_ROOT/result-m
FUTURE_EXIT=0
env FAKE_LANE_MODE=available FAKE_LANE_ARGV_FILE="$FIXTURE_ROOT/argv-m.log" \
  FAKE_LANE_STDIN_FILE="$FIXTURE_ROOT/stdin-m.log" \
  PATH="$SHIM_DIR:/usr/bin:/bin" \
  "$ROOT/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$REPO" --model-map "$FUTURE_MODEL_MAP" \
  > "$FUTURE_RESULT" 2>&1 || FUTURE_EXIT=$?
[ "$FUTURE_EXIT" -eq 1 ] || {
  printf 'FAIL: (m) future model map exited %s, expected 1\n' "$FUTURE_EXIT" >&2
  cat "$FUTURE_RESULT" >&2
  exit 1
}
assert_report "$FUTURE_RESULT" unavailable MAPPING_STALE
printf 'PASS: (m) model map generatedAt in the future -> unavailable/MAPPING_STALE\n'

# (n) model map claudeVersion differs from the running claude --version
VERSION_RESULT=$FIXTURE_ROOT/result-n
VERSION_EXIT=0
env FAKE_LANE_MODE=available FAKE_LANE_ARGV_FILE="$FIXTURE_ROOT/argv-n.log" \
  FAKE_LANE_STDIN_FILE="$FIXTURE_ROOT/stdin-n.log" \
  PATH="$SHIM_DIR:/usr/bin:/bin" \
  "$ROOT/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$REPO" --model-map "$VERSION_MISMATCH_MODEL_MAP" \
  > "$VERSION_RESULT" 2>&1 || VERSION_EXIT=$?
[ "$VERSION_EXIT" -eq 1 ] || {
  printf 'FAIL: (n) version-mismatch model map exited %s, expected 1\n' "$VERSION_EXIT" >&2
  cat "$VERSION_RESULT" >&2
  exit 1
}
assert_report "$VERSION_RESULT" unavailable MAPPING_STALE
assert_reason_contains "$VERSION_RESULT" 'fixture claude 9.9'
assert_reason_contains "$VERSION_RESULT" 'fixture claude 1.0'
printf 'PASS: (n) model map claudeVersion mismatch -> unavailable/MAPPING_STALE, REASON names both versions\n'

# (o) model map canonical for sonnet is not a model id
BADCANONICAL_RESULT=$FIXTURE_ROOT/result-o
BADCANONICAL_EXIT=0
env FAKE_LANE_MODE=available FAKE_LANE_ARGV_FILE="$FIXTURE_ROOT/argv-o.log" \
  FAKE_LANE_STDIN_FILE="$FIXTURE_ROOT/stdin-o.log" \
  PATH="$SHIM_DIR:/usr/bin:/bin" \
  "$ROOT/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$REPO" --model-map "$BADCANONICAL_MODEL_MAP" \
  > "$BADCANONICAL_RESULT" 2>&1 || BADCANONICAL_EXIT=$?
[ "$BADCANONICAL_EXIT" -eq 1 ] || {
  printf 'FAIL: (o) bad canonical model map exited %s, expected 1\n' "$BADCANONICAL_EXIT" >&2
  cat "$BADCANONICAL_RESULT" >&2
  exit 1
}
assert_report "$BADCANONICAL_RESULT" unavailable MODEL_UNRESOLVED
printf 'PASS: (o) model map canonical is not a model id -> unavailable/MODEL_UNRESOLVED\n'

# (p) protected violation AND malformed JSON output
run_lane p protected_violation_malformed_json
assert_exit '(p) protected violation + malformed JSON' 3 "$LANE_EXIT"
assert_report "$RESULT_FILE" refused PROTECTED_STATE_VIOLATION
printf 'PASS: (p) protected violation wins over malformed JSON -> refused/PROTECTED_STATE_VIOLATION\n'

# (q) transport failure: non-zero exit, empty stdout, stderr excerpt surfaced
run_lane q transport_boom
assert_exit '(q) transport failure' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable TRANSPORT_FAILED
assert_reason_contains "$RESULT_FILE" 'boom: fixture transport'
printf 'PASS: (q) non-zero exit with empty stdout -> unavailable/TRANSPORT_FAILED with stderr excerpt\n'

# (r) --allow-path scope violation, then the same run allowed by a second glob
run_lane r1 scope_violation --allow-path 'tracked.txt'
assert_exit '(r1) scope violation' 3 "$LANE_EXIT"
assert_report "$RESULT_FILE" refused SCOPE_VIOLATION
assert_reason_contains "$RESULT_FILE" 'outside/other.txt'
printf 'PASS: (r1) changed path outside a declared --allow-path -> refused/SCOPE_VIOLATION\n'

run_lane r2 scope_violation --allow-path 'tracked.txt' --allow-path 'outside/**'
assert_exit '(r2) scope allowed by a second glob' 0 "$LANE_EXIT"
assert_report "$RESULT_FILE" complete-candidate none
grep -F 'SCOPE: ok' "$RESULT_FILE" >/dev/null || {
  printf 'FAIL: (r2) expected SCOPE: ok in %s\n' "$RESULT_FILE" >&2
  cat "$RESULT_FILE" >&2
  exit 1
}
printf 'PASS: (r2) all changed paths within the declared --allow-path globs -> complete-candidate, SCOPE: ok\n'

# (s) subtype error_max_turns
run_lane s turns_exceeded
assert_exit '(s) turns exceeded' 2 "$LANE_EXIT"
assert_report "$RESULT_FILE" partial TURNS_EXCEEDED
printf 'PASS: (s) turns exceeded -> partial/TURNS_EXCEEDED, exit 2\n'

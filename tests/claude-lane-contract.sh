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
mkdir -p "$REPO/src"
printf '%s\n' baseline > "$REPO/src/tracked.txt"
printf '%s\n' '.env' > "$REPO/.gitignore"
printf '%s\n' 'API_KEY=baseline' > "$REPO/.env"
git -C "$REPO" add tracked.txt src/tracked.txt .gitignore
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
  malformed_denials_string)
    printf 'edited\n' >> tracked.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":"not-an-array","is_error":false,"result":"done"}'
    ;;
  non_json_clean_exit)
    printf 'edited\n' >> tracked.txt
    printf 'this is not json at all\n'
    ;;
  transport_boom_multiline)
    printf 'boom line one\nboom line two\n' >&2
    exit 7
    ;;
  src_edit)
    printf 'edited\n' >> src/tracked.txt
    printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[],"is_error":false,"result":"done"}'
    ;;
  delete_tracked)
    rm -f tracked.txt
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
    PATH="$SHIM_DIR:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
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

assert_no_argv_log() {
  name=$1
  path=$2
  [ ! -e "$path" ] || {
    printf 'FAIL: %s: claude argv log unexpectedly exists at %s (model map should be validated before claude is invoked)\n' "$name" "$path" >&2
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
  PATH="$SHIM_DIR:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
  "$ROOT/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$REPO" --model-map "$STALE_MODEL_MAP" \
  > "$STALE_RESULT" 2>&1 || STALE_EXIT=$?
[ "$STALE_EXIT" -eq 1 ] || {
  printf 'FAIL: (j) stale model map exited %s, expected 1\n' "$STALE_EXIT" >&2
  cat "$STALE_RESULT" >&2
  exit 1
}
assert_report "$STALE_RESULT" unavailable MAPPING_STALE
assert_no_argv_log '(j) stale model map' "$FIXTURE_ROOT/argv-stale.log"
printf 'PASS: (j) stale model map -> unavailable/MAPPING_STALE, claude never invoked\n'

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
assert_pair "$K_ARGV" '--setting-sources' ''
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
  PATH="$SHIM_DIR:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
  "$ROOT/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$REPO" --model-map "$FUTURE_MODEL_MAP" \
  > "$FUTURE_RESULT" 2>&1 || FUTURE_EXIT=$?
[ "$FUTURE_EXIT" -eq 1 ] || {
  printf 'FAIL: (m) future model map exited %s, expected 1\n' "$FUTURE_EXIT" >&2
  cat "$FUTURE_RESULT" >&2
  exit 1
}
assert_report "$FUTURE_RESULT" unavailable MAPPING_STALE
assert_no_argv_log '(m) future model map' "$FIXTURE_ROOT/argv-m.log"
printf 'PASS: (m) model map generatedAt in the future -> unavailable/MAPPING_STALE, claude never invoked\n'

# (n) model map claudeVersion differs from the running claude --version
VERSION_RESULT=$FIXTURE_ROOT/result-n
VERSION_EXIT=0
env FAKE_LANE_MODE=available FAKE_LANE_ARGV_FILE="$FIXTURE_ROOT/argv-n.log" \
  FAKE_LANE_STDIN_FILE="$FIXTURE_ROOT/stdin-n.log" \
  PATH="$SHIM_DIR:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
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
assert_no_argv_log '(n) version-mismatch model map' "$FIXTURE_ROOT/argv-n.log"
printf 'PASS: (n) model map claudeVersion mismatch -> unavailable/MAPPING_STALE, REASON names both versions, claude never invoked\n'

# (o) model map canonical for sonnet is not a model id
BADCANONICAL_RESULT=$FIXTURE_ROOT/result-o
BADCANONICAL_EXIT=0
env FAKE_LANE_MODE=available FAKE_LANE_ARGV_FILE="$FIXTURE_ROOT/argv-o.log" \
  FAKE_LANE_STDIN_FILE="$FIXTURE_ROOT/stdin-o.log" \
  PATH="$SHIM_DIR:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
  "$ROOT/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$REPO" --model-map "$BADCANONICAL_MODEL_MAP" \
  > "$BADCANONICAL_RESULT" 2>&1 || BADCANONICAL_EXIT=$?
[ "$BADCANONICAL_EXIT" -eq 1 ] || {
  printf 'FAIL: (o) bad canonical model map exited %s, expected 1\n' "$BADCANONICAL_EXIT" >&2
  cat "$BADCANONICAL_RESULT" >&2
  exit 1
}
assert_report "$BADCANONICAL_RESULT" unavailable MODEL_UNRESOLVED
assert_no_argv_log '(o) bad canonical model map' "$FIXTURE_ROOT/argv-o.log"
printf 'PASS: (o) model map canonical is not a model id -> unavailable/MODEL_UNRESOLVED, claude never invoked\n'

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

# (t) --allow-path '' is a usage error, not a silently-unchecked scope
run_lane t available --allow-path ''
assert_exit '(t) empty --allow-path glob' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable GUARD_FAILED
assert_reason_contains "$RESULT_FILE" '--allow-path requires a non-empty glob'
printf 'PASS: (t) --allow-path with an empty glob -> unavailable/GUARD_FAILED\n'

# (u) worktree-delta.rb refuses a changed path containing a control character
CTRL_ROOT=$FIXTURE_ROOT/ctrl-repo
mkdir -p "$CTRL_ROOT"
git -C "$CTRL_ROOT" init -q
git -C "$CTRL_ROOT" config user.name 'Claude Lane Contract'
git -C "$CTRL_ROOT" config user.email 'claude-lane@example.invalid'
printf '%s\n' baseline > "$CTRL_ROOT/tracked.txt"
git -C "$CTRL_ROOT" add tracked.txt
git -C "$CTRL_ROOT" commit -qm baseline

CTRL_STATE=$FIXTURE_ROOT/ctrl-state.json
ruby "$ROOT/scripts/worktree-delta.rb" snapshot "$CTRL_STATE" "$CTRL_ROOT" >/dev/null

CTRL_NAME=$(printf 'bad\nname.txt')
: > "$CTRL_ROOT/$CTRL_NAME"

CTRL_RESULT=$FIXTURE_ROOT/result-ctrl
CTRL_EXIT=0
ruby "$ROOT/scripts/worktree-delta.rb" check "$CTRL_STATE" "$CTRL_ROOT" > "$CTRL_RESULT" 2>&1 || CTRL_EXIT=$?
[ "$CTRL_EXIT" -eq 2 ] || {
  printf 'FAIL: (u) worktree-delta.rb on a control-character path exited %s, expected 2\n' "$CTRL_EXIT" >&2
  cat "$CTRL_RESULT" >&2
  exit 1
}
grep -F 'contains a control character' "$CTRL_RESULT" >/dev/null || {
  printf 'FAIL: (u) expected a control-character error in %s\n' "$CTRL_RESULT" >&2
  cat "$CTRL_RESULT" >&2
  exit 1
}
printf 'PASS: (u) worktree-delta.rb refuses a changed path with an embedded control character\n'

# (v) permission_denials present but not an array (a string)
run_lane v malformed_denials_string
assert_exit '(v) malformed permission_denials (string)' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable OUTPUT_NOT_CAPTURED
printf 'PASS: (v) permission_denials is a string, not an array -> unavailable/OUTPUT_NOT_CAPTURED\n'

# (w) claude exits 0 but stdout is not JSON
run_lane w non_json_clean_exit
assert_exit '(w) non-JSON stdout, clean exit' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable OUTPUT_NOT_CAPTURED
printf 'PASS: (w) claude exit 0 with non-JSON stdout -> unavailable/OUTPUT_NOT_CAPTURED\n'

# (x) parse-lane-result.rb: worktree-delta exit 0 (changed) but zero parsed
# CHANGE: lines is format drift, not an empty delta -> GUARD_FAILED, not a
# vacuous SCOPE: ok next to WORKTREE_DELTA: changed.
X_JSON=$FIXTURE_ROOT/x-result.json
printf '%s\n' '{"modelUsage":{"claude-sonnet-5":{}},"permission_denials":[],"is_error":false,"result":"done"}' > "$X_JSON"
X_ERROR=$FIXTURE_ROOT/x-error.log
X_GUARD_ERROR=$FIXTURE_ROOT/x-guard-error.log
X_DELTA_STDOUT=$FIXTURE_ROOT/x-delta-stdout.log
: > "$X_ERROR"
: > "$X_GUARD_ERROR"
: > "$X_DELTA_STDOUT"
X_RESULT=$FIXTURE_ROOT/result-x
X_EXIT=0
ruby "$ROOT/scripts/parse-lane-result.rb" "$X_JSON" claude-sonnet-5 sonnet 0 0 0 \
  "$X_ERROR" "$X_GUARD_ERROR" "$X_DELTA_STDOUT" > "$X_RESULT" 2>&1 || X_EXIT=$?
[ "$X_EXIT" -eq 1 ] || {
  printf 'FAIL: (x) parse-lane-result.rb with delta_exit=0 and no CHANGE lines exited %s, expected 1\n' "$X_EXIT" >&2
  cat "$X_RESULT" >&2
  exit 1
}
assert_report "$X_RESULT" unavailable GUARD_FAILED
assert_reason_contains "$X_RESULT" 'worktree-delta reported a change but no CHANGE: lines were parsed'
printf 'PASS: (x) worktree-delta exit 0 with zero parsed CHANGE lines -> unavailable/GUARD_FAILED\n'

# (y) REASON collapses a multi-line stderr excerpt to a single line
run_lane y transport_boom_multiline
assert_exit '(y) multi-line stderr excerpt' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable TRANSPORT_FAILED
assert_reason_contains "$RESULT_FILE" 'boom line one boom line two'
printf 'PASS: (y) multi-line stderr excerpt collapses to a single REASON line\n'

# (z1) D1: --allow-path globs must never be pathname-expanded by the runner's
# own shell against its launch cwd. The launch cwd contains a real decoy file
# (src/decoy.txt) that would make 'src/**' expand to 'src/decoy.txt' if the
# runner's for-loop did not disable globbing; the actual task change is
# src/tracked.txt inside the fixture repo (WORKDIR), which is unrelated to the
# launch cwd's contents.
Z1_LAUNCH=$FIXTURE_ROOT/z1-launch
mkdir -p "$Z1_LAUNCH/src"
printf 'decoy\n' > "$Z1_LAUNCH/src/decoy.txt"
Z1_RESULT=$FIXTURE_ROOT/result-z1
Z1_EXIT=0
(
  cd "$Z1_LAUNCH" && \
  env FAKE_LANE_MODE=src_edit FAKE_LANE_ARGV_FILE="$FIXTURE_ROOT/argv-z1.log" \
    FAKE_LANE_STDIN_FILE="$FIXTURE_ROOT/stdin-z1.log" \
    PATH="$SHIM_DIR:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
    "$ROOT/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$REPO" --model-map "$MODEL_MAP" --allow-path 'src/**'
) > "$Z1_RESULT" 2>&1 || Z1_EXIT=$?
[ "$Z1_EXIT" -eq 0 ] || {
  printf 'FAIL: (z1) expected exit 0, got %s\n' "$Z1_EXIT" >&2
  cat "$Z1_RESULT" >&2
  exit 1
}
assert_report "$Z1_RESULT" complete-candidate none
grep -Fx 'SCOPE: ok (1 changed paths within 1 allowed globs)' "$Z1_RESULT" >/dev/null || {
  printf 'FAIL: (z1) expected SCOPE: ok (1 changed paths within 1 allowed globs) in %s\n' "$Z1_RESULT" >&2
  cat "$Z1_RESULT" >&2
  exit 1
}
if grep -F 'SCOPE_VIOLATION' "$Z1_RESULT" >/dev/null; then
  printf 'FAIL: (z1) SCOPE_VIOLATION found; --allow-path glob was pathname-expanded in the launch cwd\n' >&2
  cat "$Z1_RESULT" >&2
  exit 1
fi
printf 'PASS: (z1) --allow-path globs are passed literally, never expanded against the runner launch cwd\n'

# (z2) D2: an --allow-bash prefix containing disallowed characters is a usage
# error, and claude must never be invoked.
run_lane z2 available --allow-bash 'x:*),Bash(curl'
assert_exit '(z2) invalid --allow-bash prefix (parens/comma)' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable GUARD_FAILED
assert_reason_contains "$RESULT_FILE" '--allow-bash prefix'
assert_no_argv_log '(z2) invalid --allow-bash prefix' "$FIXTURE_ROOT/argv-z2.log"
printf 'PASS: (z2) --allow-bash prefix with disallowed characters -> unavailable/GUARD_FAILED, claude never invoked\n'

# (z3) D2: an empty --allow-bash prefix is the same usage error.
run_lane z3 available --allow-bash ''
assert_exit '(z3) empty --allow-bash prefix' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable GUARD_FAILED
assert_reason_contains "$RESULT_FILE" '--allow-bash prefix'
assert_no_argv_log '(z3) empty --allow-bash prefix' "$FIXTURE_ROOT/argv-z3.log"
printf 'PASS: (z3) --allow-bash with an empty prefix -> unavailable/GUARD_FAILED, claude never invoked\n'

# (z4) D3: the runner refuses to run from a checkout inside the WORKDIR it is
# operating on, even when the model map is explicitly valid.
INNER_REPO=$FIXTURE_ROOT/inner-repo
mkdir -p "$INNER_REPO/scripts"
cp "$ROOT"/scripts/*.sh "$ROOT"/scripts/*.rb "$INNER_REPO/scripts/"
chmod +x "$INNER_REPO/scripts/run-claude-lane.sh" "$INNER_REPO/scripts/probe-model-map.sh"
git -C "$INNER_REPO" init -q
git -C "$INNER_REPO" config user.name 'Claude Lane Contract'
git -C "$INNER_REPO" config user.email 'claude-lane@example.invalid'
printf '%s\n' baseline > "$INNER_REPO/tracked.txt"
git -C "$INNER_REPO" add tracked.txt scripts
git -C "$INNER_REPO" commit -qm baseline

Z4_RESULT=$FIXTURE_ROOT/result-z4
Z4_EXIT=0
env FAKE_LANE_MODE=available FAKE_LANE_ARGV_FILE="$FIXTURE_ROOT/argv-z4.log" \
  FAKE_LANE_STDIN_FILE="$FIXTURE_ROOT/stdin-z4.log" \
  PATH="$SHIM_DIR:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
  "$INNER_REPO/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$INNER_REPO" --model-map "$MODEL_MAP" \
  > "$Z4_RESULT" 2>&1 || Z4_EXIT=$?
[ "$Z4_EXIT" -eq 1 ] || {
  printf 'FAIL: (z4) runner-checkout-inside-WORKDIR exited %s, expected 1\n' "$Z4_EXIT" >&2
  cat "$Z4_RESULT" >&2
  exit 1
}
assert_report "$Z4_RESULT" unavailable GUARD_FAILED
assert_reason_contains "$Z4_RESULT" 'inside WORKDIR'
assert_no_argv_log '(z4) runner checkout inside WORKDIR' "$FIXTURE_ROOT/argv-z4.log"
printf 'PASS: (z4) runner refuses to run from a checkout inside WORKDIR\n'

# (z5) D6: worktree-delta scope checking must see deletions, not just
# modifications and additions.
run_lane z5 delete_tracked --allow-path 'tracked.txt'
assert_exit '(z5) deleted tracked file within allowed glob' 0 "$LANE_EXIT"
assert_report "$RESULT_FILE" complete-candidate none
grep -Fx 'SCOPE: ok (1 changed paths within 1 allowed globs)' "$RESULT_FILE" >/dev/null || {
  printf 'FAIL: (z5) expected SCOPE: ok (1 changed paths within 1 allowed globs) in %s\n' "$RESULT_FILE" >&2
  cat "$RESULT_FILE" >&2
  exit 1
}
printf 'PASS: (z5) worktree-delta scope checking sees a deletion within an allowed --allow-path glob\n'

# (z6) D8: an option requiring a value as the last argument is a usage error,
# not a shift past the end of the argument list.
run_lane z6 available --effort
assert_exit '(z6) --effort missing value' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable GUARD_FAILED
assert_reason_contains "$RESULT_FILE" 'requires a value'
assert_no_argv_log '(z6) --effort missing value' "$FIXTURE_ROOT/argv-z6.log"
printf 'PASS: (z6) --effort as the last argument -> unavailable/GUARD_FAILED, claude never invoked\n'

# (z7) a git prefix that could grant commit/merge/push authority is refused;
# read-only git prefixes are still accepted (a) and (k) already prove.
run_lane z7 available --allow-bash git
assert_exit '(z7) bare git prefix' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable GUARD_FAILED
assert_reason_contains "$RESULT_FILE" 'read-only subcommand'
assert_no_argv_log '(z7) bare git prefix' "$FIXTURE_ROOT/argv-z7.log"
run_lane z7b available --allow-bash 'git commit'
assert_exit '(z7b) git commit prefix' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable GUARD_FAILED
assert_reason_contains "$RESULT_FILE" 'read-only subcommand'
assert_no_argv_log '(z7b) git commit prefix' "$FIXTURE_ROOT/argv-z7b.log"
run_lane z7c available --allow-bash 'git status' --allow-bash 'git diff --stat'
assert_exit '(z7c) read-only git prefixes' 0 "$LANE_EXIT"
assert_report "$RESULT_FILE" complete-candidate none
grep -F 'Bash(git status:*),Bash(git diff --stat:*)' "$FIXTURE_ROOT/argv-z7c.log" >/dev/null || {
  printf 'FAIL: (z7c) expected both read-only git permissions in argv\n' >&2; cat "$FIXTURE_ROOT/argv-z7c.log" >&2; exit 1; }
printf 'PASS: (z7) git prefixes: bare git and git commit refused, read-only git subcommands accepted\n'

# (z8) D3, nested case: the runner checkout is a subdirectory of WORKDIR.
OUTER_REPO=$FIXTURE_ROOT/outer-repo
mkdir -p "$OUTER_REPO/nested/scripts"
cp "$ROOT"/scripts/*.sh "$ROOT"/scripts/*.rb "$OUTER_REPO/nested/scripts/"
chmod +x "$OUTER_REPO/nested/scripts/run-claude-lane.sh"
git -C "$OUTER_REPO" init -q
git -C "$OUTER_REPO" config user.name 'Claude Lane Contract'
git -C "$OUTER_REPO" config user.email 'claude-lane@example.invalid'
printf '%s\n' baseline > "$OUTER_REPO/tracked.txt"
git -C "$OUTER_REPO" add tracked.txt nested
git -C "$OUTER_REPO" commit -qm baseline
Z8_RESULT=$FIXTURE_ROOT/result-z8
Z8_EXIT=0
env FAKE_LANE_MODE=available FAKE_LANE_ARGV_FILE="$FIXTURE_ROOT/argv-z8.log" \
  FAKE_LANE_STDIN_FILE="$FIXTURE_ROOT/stdin-z8.log" \
  PATH="$SHIM_DIR:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
  "$OUTER_REPO/nested/scripts/run-claude-lane.sh" "$SPEC_FILE" sonnet "$OUTER_REPO" --model-map "$MODEL_MAP" \
  > "$Z8_RESULT" 2>&1 || Z8_EXIT=$?
[ "$Z8_EXIT" -eq 1 ] || { printf 'FAIL: (z8) nested runner checkout exited %s, expected 1\n' "$Z8_EXIT" >&2; cat "$Z8_RESULT" >&2; exit 1; }
assert_report "$Z8_RESULT" unavailable GUARD_FAILED
assert_reason_contains "$Z8_RESULT" 'inside WORKDIR'
assert_no_argv_log '(z8) nested runner checkout' "$FIXTURE_ROOT/argv-z8.log"
printf 'PASS: (z8) runner refuses to run from a checkout nested inside WORKDIR\n'

# (z9) an option token is never consumed as another option's value.
run_lane z9 available --effort --max-turns 5
assert_exit '(z9) --effort followed by an option' 1 "$LANE_EXIT"
assert_report "$RESULT_FILE" unavailable GUARD_FAILED
assert_reason_contains "$RESULT_FILE" 'requires a value'
assert_no_argv_log '(z9) --effort followed by an option' "$FIXTURE_ROOT/argv-z9.log"
printf 'PASS: (z9) an option token is not accepted as a value -> unavailable/GUARD_FAILED\n'

# (z10) the git rule cannot be sidestepped by the literal forms the guard is
# meant to catch: a path to git, a wrapper in front of it, an environment
# assignment in front of it, a leading space, or a different case.
for z10_prefix in '/opt/homebrew/bin/git commit' 'command git push' 'env git commit' \
  'X=1 git commit' ' git commit' 'git log ' 'GIT push' 'nohup git push'; do
  run_lane z10 available --allow-bash "$z10_prefix"
  assert_exit "(z10) prefix '$z10_prefix'" 1 "$LANE_EXIT"
  assert_report "$RESULT_FILE" unavailable GUARD_FAILED
  assert_no_argv_log "(z10) prefix '$z10_prefix'" "$FIXTURE_ROOT/argv-z10.log"
done
run_lane z10b available --allow-bash 'GIT log'
assert_exit '(z10b) GIT log' 0 "$LANE_EXIT"
assert_report "$RESULT_FILE" complete-candidate none
grep -F 'Bash(GIT log:*)' "$FIXTURE_ROOT/argv-z10b.log" >/dev/null || {
  printf 'FAIL: (z10b) expected Bash(GIT log:*) in argv\n' >&2; cat "$FIXTURE_ROOT/argv-z10b.log" >&2; exit 1; }
printf 'PASS: (z10) git via path, wrapper, env assignment, leading/trailing space or GIT refused; GIT log accepted\n'

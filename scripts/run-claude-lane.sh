#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

LANE_PREAMBLE='You are an implementation lane. Change only the files the spec allows. Run the VERIFICATION command(s) and paste their actual output. Never commit, merge, push, deploy, or edit files outside the working directory. End your final message with a block containing the lines CHANGES:, VERIFIED:, JUDGMENT_CALLS:, GAPS:.'

ALIAS=
EXPECTED_CANONICAL=

unavailable() {
  classification=$1
  reason=$2
  requested=$ALIAS
  [ -z "$EXPECTED_CANONICAL" ] || requested=$EXPECTED_CANONICAL
  [ -n "$requested" ] || requested=unknown
  printf '%s\n' \
    'IMPLEMENTATION REPORT' \
    'LANE: claude' \
    "REQUESTED_MODEL: $requested" \
    'RESOLVED_MODEL_EVIDENCE: unavailable' \
    'STATUS: unavailable' \
    "CLASSIFICATION: $classification" \
    "REASON: $reason" \
    'COST_USD: unknown' \
    'NUM_TURNS: unknown' \
    'BOUNDARY_EVENTS: 0 denial(s): none' \
    'PROTECTED_STATE: error' \
    'WORKTREE_DELTA: error' \
    'MODEL_SAID:' \
    ''
  exit 1
}

SPEC_FILE=${1-}
ALIAS=${2-}
WORKDIR=${3-}
[ -n "$SPEC_FILE" ] && [ -n "$ALIAS" ] && [ -n "$WORKDIR" ] || \
  unavailable GUARD_FAILED 'usage: run-claude-lane.sh SPEC_FILE ALIAS WORKDIR [--effort LEVEL] [--max-turns N] [--max-budget-usd X] [--allow-bash PREFIX]... [--model-map PATH]'
shift 3

EFFORT=
MAX_TURNS=
MAX_BUDGET_USD=
MODEL_MAP_PATH=
ALLOW_BASH_LIST=

while [ $# -gt 0 ]; do
  case "$1" in
    --effort) EFFORT=${2-}; shift 2 ;;
    --max-turns) MAX_TURNS=${2-}; shift 2 ;;
    --max-budget-usd) MAX_BUDGET_USD=${2-}; shift 2 ;;
    --allow-bash) ALLOW_BASH_LIST="$ALLOW_BASH_LIST
${2-}"; shift 2 ;;
    --model-map) MODEL_MAP_PATH=${2-}; shift 2 ;;
    *) unavailable GUARD_FAILED "unknown argument: $1" ;;
  esac
done

[ -f "$SPEC_FILE" ] || unavailable GUARD_FAILED "SPEC_FILE does not exist: $SPEC_FILE"

# --- Preflight -----------------------------------------------------------

CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
[ -n "$CLAUDE_BIN" ] || unavailable TRANSPORT_FAILED 'claude executable not found on PATH'

version_exit=0
CLAUDE_VERSION_OUTPUT=$("$CLAUDE_BIN" --version 2>&1) || version_exit=$?
[ "$version_exit" -eq 0 ] || unavailable TRANSPORT_FAILED "claude --version failed with exit $version_exit: $CLAUDE_VERSION_OUTPUT"

[ -n "$MODEL_MAP_PATH" ] || MODEL_MAP_PATH=$ROOT/docs/model-map.json
[ -f "$MODEL_MAP_PATH" ] || unavailable MODEL_UNRESOLVED "model map not found: $MODEL_MAP_PATH"

MAP_PROBE=$(python3 - "$MODEL_MAP_PATH" "$ALIAS" <<'PY'
import datetime
import json
import sys

path, alias = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except Exception as exc:  # noqa: BLE001 - reported to the caller, not swallowed
    print("ERROR:%s" % exc)
    sys.exit(0)

if not isinstance(data, dict):
    print("ERROR:model map is not a JSON object")
    sys.exit(0)

aliases = data.get("aliases")
if not isinstance(aliases, dict) or alias not in aliases or aliases[alias] is None:
    print("UNRESOLVED")
    sys.exit(0)

canonical = aliases[alias]
generated_raw = data.get("generatedAt")
if not isinstance(generated_raw, str):
    print("ERROR:generatedAt missing or not a string")
    sys.exit(0)

try:
    generated = datetime.datetime.fromisoformat(generated_raw.replace("Z", "+00:00"))
except ValueError as exc:
    print("ERROR:invalid generatedAt: %s" % exc)
    sys.exit(0)

if generated.tzinfo is None:
    generated = generated.replace(tzinfo=datetime.timezone.utc)

age_days = (datetime.datetime.now(datetime.timezone.utc) - generated).total_seconds() / 86400.0
if age_days > 30:
    print("STALE:%s" % canonical)
else:
    print("OK:%s" % canonical)
PY
)

case "$MAP_PROBE" in
  ERROR:*)
    unavailable MODEL_UNRESOLVED "model map error reading $MODEL_MAP_PATH: ${MAP_PROBE#ERROR:}"
    ;;
  UNRESOLVED)
    unavailable MODEL_UNRESOLVED "alias '$ALIAS' is not present or is null in the model map $MODEL_MAP_PATH"
    ;;
  STALE:*)
    EXPECTED_CANONICAL=${MAP_PROBE#STALE:}
    unavailable MAPPING_STALE "model map generatedAt in $MODEL_MAP_PATH is older than 30 days"
    ;;
  OK:*)
    EXPECTED_CANONICAL=${MAP_PROBE#OK:}
    ;;
  *)
    unavailable MODEL_UNRESOLVED "unexpected model map probe output: $MAP_PROBE"
    ;;
esac

[ -d "$WORKDIR" ] || unavailable GUARD_FAILED "WORKDIR does not exist: $WORKDIR"
WORKDIR=$(CDPATH= cd -- "$WORKDIR" && pwd)
git -C "$WORKDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
  unavailable GUARD_FAILED "WORKDIR is not inside a git repository: $WORKDIR"

# --- Guard snapshots (outside the workdir) --------------------------------

DELTA_STATE=$(mktemp -t claude-lane-delta.XXXXXX)
PROTECTED_STATE=$(mktemp -t claude-lane-protected.XXXXXX)
JSON_FILE=$(mktemp -t claude-lane-result.XXXXXX)
ERROR_FILE=$(mktemp -t claude-lane-error.XXXXXX)
trap 'rm -f "$DELTA_STATE" "$PROTECTED_STATE" "$JSON_FILE" "$ERROR_FILE"' EXIT HUP INT TERM

delta_snapshot_exit=0
ruby "$ROOT/scripts/worktree-delta.rb" snapshot "$DELTA_STATE" "$WORKDIR" >/dev/null 2>"$ERROR_FILE" || delta_snapshot_exit=$?
[ "$delta_snapshot_exit" -eq 0 ] || unavailable GUARD_FAILED "worktree-delta snapshot failed: $(cat "$ERROR_FILE")"

protected_snapshot_exit=0
ruby "$ROOT/scripts/protected-paths.rb" snapshot "$PROTECTED_STATE" "$WORKDIR" >/dev/null 2>"$ERROR_FILE" || protected_snapshot_exit=$?
[ "$protected_snapshot_exit" -eq 0 ] || unavailable GUARD_FAILED "protected-paths snapshot failed: $(cat "$ERROR_FILE")"

# --- Permission deny list --------------------------------------------------

DENY_JSON=$(python3 - "$WORKDIR" <<'PY'
import json
import os
import sys

workdir = sys.argv[1]
patterns = ["./.env", "./.env.*", "./.claude/settings.local.json", "./.codex/**", "./.npmrc", "./.git/**"]

config_path = os.path.join(workdir, ".ai-orchestrator-protected-paths")
if os.path.isfile(config_path):
    with open(config_path, encoding="utf-8") as f:
        for line in f:
            entry = line.split("#", 1)[0].strip()
            if not entry:
                continue
            if not entry.startswith("./") and not entry.startswith("/"):
                entry = "./" + entry
            patterns.append(entry)

deny = []
for pattern in patterns:
    for verb in ("Read", "Edit", "Write"):
        deny.append("%s(%s)" % (verb, pattern))

print(json.dumps({"permissions": {"deny": deny}}))
PY
)
deny_build_exit=$?
[ "$deny_build_exit" -eq 0 ] && [ -n "$DENY_JSON" ] || unavailable GUARD_FAILED 'failed to build the permission deny list'

# --- Invocation -------------------------------------------------------------

ALLOWED_TOOLS='Read,Edit,Write,Grep,Glob'
if [ -n "$ALLOW_BASH_LIST" ]; then
  OLD_IFS=$IFS
  IFS='
'
  for prefix in $ALLOW_BASH_LIST; do
    [ -n "$prefix" ] || continue
    ALLOWED_TOOLS="$ALLOWED_TOOLS,Bash($prefix:*)"
  done
  IFS=$OLD_IFS
fi

set -- -p --restricted \
  --tools "Read,Edit,Write,Grep,Glob,Bash" \
  --allowedTools "$ALLOWED_TOOLS" \
  --permission-mode acceptEdits --permission-prompts none \
  --settings "$DENY_JSON" \
  --model "$ALIAS"

[ -z "$EFFORT" ] || set -- "$@" --effort "$EFFORT"
[ -z "$MAX_TURNS" ] || set -- "$@" --max-turns "$MAX_TURNS"
[ -z "$MAX_BUDGET_USD" ] || set -- "$@" --max-budget-usd "$MAX_BUDGET_USD"

set -- "$@" \
  --output-format json --no-session-persistence \
  --append-system-prompt "$LANE_PREAMBLE" \
  "$(cat "$SPEC_FILE")"

CLAUDE_EXIT=0
(cd "$WORKDIR" && "$CLAUDE_BIN" "$@") > "$JSON_FILE" 2> "$ERROR_FILE" || CLAUDE_EXIT=$?

# --- Post-run guard checks ---------------------------------------------------

DELTA_EXIT=0
ruby "$ROOT/scripts/worktree-delta.rb" check "$DELTA_STATE" "$WORKDIR" >/dev/null 2>/dev/null || DELTA_EXIT=$?

PROTECTED_EXIT=0
ruby "$ROOT/scripts/protected-paths.rb" check "$PROTECTED_STATE" "$WORKDIR" >/dev/null 2>/dev/null || PROTECTED_EXIT=$?

ruby "$ROOT/scripts/parse-lane-result.rb" "$JSON_FILE" "$EXPECTED_CANONICAL" "$DELTA_EXIT" "$PROTECTED_EXIT" "$CLAUDE_EXIT"

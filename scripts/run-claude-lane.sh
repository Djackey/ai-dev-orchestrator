#!/bin/sh
set -u

# Hard dependencies: python3 (model-map parsing) and ruby (guards, parser).
# This script fails closed if either is missing from PATH.

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

LANE_PREAMBLE='You are an implementation lane. Change only the files the spec allows. Run the VERIFICATION command(s) and paste their actual output. Never commit, merge, push, deploy, or edit files outside the working directory. End your final message with a block containing the lines CHANGES:, VERIFIED:, JUDGMENT_CALLS:, GAPS:.'

ALIAS=
EXPECTED_CANONICAL=
MAP_GENERATED_AT=
MAP_CLAUDE_VERSION=
ALLOW_PATH_LIST=

unavailable() {
  classification=$1
  reason=$2
  requested_alias=$ALIAS
  [ -n "$requested_alias" ] || requested_alias=unknown
  expected_display=$EXPECTED_CANONICAL
  [ -n "$expected_display" ] || expected_display=unresolved
  map_generated=$MAP_GENERATED_AT
  [ -n "$map_generated" ] || map_generated=unknown
  map_version=$MAP_CLAUDE_VERSION
  [ -n "$map_version" ] || map_version=unknown
  printf '%s\n' \
    'IMPLEMENTATION REPORT' \
    'LANE: claude' \
    "REQUESTED_ALIAS: $requested_alias" \
    "EXPECTED_CANONICAL: $expected_display (model map $map_generated, claude $map_version)" \
    'RESOLVED_MODEL_EVIDENCE: unavailable' \
    'STATUS: unavailable' \
    "CLASSIFICATION: $classification" \
    "REASON: $reason" \
    'COST_USD: unknown' \
    'NUM_TURNS: unknown' \
    'BOUNDARY_EVENTS: 0 denial(s): none' \
    'PROTECTED_STATE: error' \
    'WORKTREE_DELTA: error' \
    'SCOPE: unchecked (lane did not run)' \
    'MODEL_SAID:' \
    ''
  exit 1
}

command -v python3 >/dev/null 2>&1 || unavailable GUARD_FAILED 'python3 not found on PATH (hard dependency)'
command -v ruby >/dev/null 2>&1 || unavailable GUARD_FAILED 'ruby not found on PATH (hard dependency)'

SPEC_FILE=${1-}
ALIAS=${2-}
WORKDIR=${3-}
[ -n "$SPEC_FILE" ] && [ -n "$ALIAS" ] && [ -n "$WORKDIR" ] || \
  unavailable GUARD_FAILED 'usage: run-claude-lane.sh SPEC_FILE ALIAS WORKDIR [--effort LEVEL] [--max-turns N] [--max-budget-usd X] [--allow-bash PREFIX]... [--allow-path GLOB]... [--model-map PATH]'
shift 3

EFFORT=
MAX_TURNS=
MAX_BUDGET_USD=
MODEL_MAP_PATH=
ALLOW_BASH_LIST=

while [ $# -gt 0 ]; do
  case "$1" in
    --effort|--max-turns|--max-budget-usd|--allow-bash|--allow-path|--model-map)
      [ $# -ge 2 ] || unavailable GUARD_FAILED "$1 requires a value"
      ;;
  esac
  case "$1" in
    --effort) EFFORT=$2; shift 2 ;;
    --max-turns) MAX_TURNS=$2; shift 2 ;;
    --max-budget-usd) MAX_BUDGET_USD=$2; shift 2 ;;
    --allow-bash)
      case "$2" in
        *[!A-Za-z0-9_./=" "-]*|'')
          unavailable GUARD_FAILED "--allow-bash prefix contains a character outside [A-Za-z0-9_./ =-]"
          ;;
      esac
      ALLOW_BASH_LIST="$ALLOW_BASH_LIST
$2"; shift 2 ;;
    --allow-path)
      [ -n "$2" ] || unavailable GUARD_FAILED '--allow-path requires a non-empty glob'
      ALLOW_PATH_LIST="$ALLOW_PATH_LIST
$2"; shift 2 ;;
    --model-map) MODEL_MAP_PATH=$2; shift 2 ;;
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

MAP_GENERATED_AT=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    value = data.get("generatedAt") if isinstance(data, dict) else None
    print(value if isinstance(value, str) else "")
except Exception:
    print("")
' "$MODEL_MAP_PATH")

MAP_CLAUDE_VERSION=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    value = data.get("claudeVersion") if isinstance(data, dict) else None
    print(value if isinstance(value, str) else "")
except Exception:
    print("")
' "$MODEL_MAP_PATH")

MAP_PROBE=$(python3 - "$MODEL_MAP_PATH" "$ALIAS" "$CLAUDE_VERSION_OUTPUT" <<'PY'
import datetime
import json
import re
import sys

path, alias, running_version = sys.argv[1], sys.argv[2], sys.argv[3]
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
if not isinstance(canonical, str) or not re.match(r"^claude-[a-z0-9.-]+$", canonical):
    print("BADCANONICAL")
    sys.exit(0)

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

now = datetime.datetime.now(datetime.timezone.utc)
age_days = (now - generated).total_seconds() / 86400.0
if age_days < 0:
    print("FUTURE")
    sys.exit(0)
if age_days > 30:
    print("STALE:%s" % canonical)
    sys.exit(0)

map_version = data.get("claudeVersion")
if map_version != running_version:
    print("VERSIONMISMATCH:%s" % map_version)
    sys.exit(0)

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
  BADCANONICAL)
    unavailable MODEL_UNRESOLVED "model map canonical for $ALIAS is not a model id"
    ;;
  FUTURE)
    unavailable MAPPING_STALE 'model map generatedAt is in the future'
    ;;
  VERSIONMISMATCH:*)
    map_version_seen=${MAP_PROBE#VERSIONMISMATCH:}
    unavailable MAPPING_STALE "model map was probed with $map_version_seen, running $CLAUDE_VERSION_OUTPUT; re-run scripts/probe-model-map.sh"
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

ROOT_PHYS=$(CDPATH= cd -- "$ROOT" && pwd -P)
WORKDIR_PHYS=$(CDPATH= cd -- "$WORKDIR" && pwd -P)
case "$ROOT_PHYS" in
  "$WORKDIR_PHYS"|"$WORKDIR_PHYS"/*)
    unavailable GUARD_FAILED "runner checkout $ROOT_PHYS is inside WORKDIR; run the lane from a separate checkout"
    ;;
esac

# --- Guard snapshots (outside the workdir) --------------------------------

DELTA_STATE=$(mktemp -t claude-lane-delta.XXXXXX)
PROTECTED_STATE=$(mktemp -t claude-lane-protected.XXXXXX)
JSON_FILE=$(mktemp -t claude-lane-result.XXXXXX)
ERROR_FILE=$(mktemp -t claude-lane-error.XXXXXX)
GUARD_ERROR_FILE=$(mktemp -t claude-lane-guard-error.XXXXXX)
DELTA_STDOUT_FILE=$(mktemp -t claude-lane-delta-out.XXXXXX)
trap 'rm -f "$DELTA_STATE" "$PROTECTED_STATE" "$JSON_FILE" "$ERROR_FILE" "$GUARD_ERROR_FILE" "$DELTA_STDOUT_FILE"' EXIT HUP INT TERM

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
patterns = ["./.env", "./.env.*", "./.claude/**", "./.codex/**", "./.npmrc", "./.git/**"]

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
  case $- in
    *f*) BASH_NOGLOB_WAS_SET=1 ;;
    *) BASH_NOGLOB_WAS_SET=0 ;;
  esac
  set -f
  for prefix in $ALLOW_BASH_LIST; do
    [ -n "$prefix" ] || continue
    ALLOWED_TOOLS="$ALLOWED_TOOLS,Bash($prefix:*)"
  done
  [ "$BASH_NOGLOB_WAS_SET" -eq 1 ] || set +f
  IFS=$OLD_IFS
fi

set -- -p --restricted --strict-mcp-config --setting-sources "" \
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
  --append-system-prompt "$LANE_PREAMBLE"

CLAUDE_EXIT=0
(cd "$WORKDIR" && "$CLAUDE_BIN" "$@") < "$SPEC_FILE" > "$JSON_FILE" 2> "$ERROR_FILE" || CLAUDE_EXIT=$?

# --- Post-run guard checks ---------------------------------------------------

DELTA_EXIT=0
ruby "$ROOT/scripts/worktree-delta.rb" check "$DELTA_STATE" "$WORKDIR" > "$DELTA_STDOUT_FILE" 2>"$GUARD_ERROR_FILE" || DELTA_EXIT=$?

PROTECTED_EXIT=0
ruby "$ROOT/scripts/protected-paths.rb" check "$PROTECTED_STATE" "$WORKDIR" >/dev/null 2>>"$GUARD_ERROR_FILE" || PROTECTED_EXIT=$?

set -- "$JSON_FILE" "$EXPECTED_CANONICAL" "$ALIAS" "$DELTA_EXIT" "$PROTECTED_EXIT" "$CLAUDE_EXIT" \
  "$ERROR_FILE" "$GUARD_ERROR_FILE" "$DELTA_STDOUT_FILE"

if [ -n "$ALLOW_PATH_LIST" ]; then
  OLD_IFS=$IFS
  IFS='
'
  case $- in
    *f*) PATH_NOGLOB_WAS_SET=1 ;;
    *) PATH_NOGLOB_WAS_SET=0 ;;
  esac
  set -f
  for glob in $ALLOW_PATH_LIST; do
    [ -n "$glob" ] || continue
    set -- "$@" "$glob"
  done
  [ "$PATH_NOGLOB_WAS_SET" -eq 1 ] || set +f
  IFS=$OLD_IFS
fi

CLAUDE_LANE_MAP_GENERATED_AT="$MAP_GENERATED_AT" CLAUDE_LANE_MAP_CLAUDE_VERSION="$MAP_CLAUDE_VERSION" \
  ruby "$ROOT/scripts/parse-lane-result.rb" "$@"

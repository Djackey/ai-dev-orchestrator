#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PROMPT_FILE=${1-}

unavailable() {
  classification=$1
  reason=$2
  printf '%s\n' \
    'REVIEWER CAPABILITY REPORT' \
    'STATUS: UNAVAILABLE' \
    "CLASSIFICATION: $classification" \
    "REASON: $reason"
  exit 1
}

[ -n "$PROMPT_FILE" ] || unavailable HOST_LIMITATION 'review prompt file argument is required'
[ -f "$PROMPT_FILE" ] || unavailable HOST_LIMITATION 'review prompt file does not exist'

CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
[ -n "$CLAUDE_BIN" ] || unavailable HOST_LIMITATION 'claude executable not found on PATH'
[ -x "$CLAUDE_BIN" ] || unavailable HOST_LIMITATION 'claude candidate is not executable'

version_exit=0
version_output=$("$CLAUDE_BIN" --version 2>&1) || version_exit=$?
[ "$version_exit" -eq 0 ] || unavailable HOST_LIMITATION "claude --version failed with exit $version_exit: $version_output"

JSON_FILE=$(mktemp -t reviewer-result.XXXXXX)
ERROR_FILE=$(mktemp -t reviewer-error.XXXXXX)
trap 'rm -f "$JSON_FILE" "$ERROR_FILE"' EXIT HUP INT TERM

review_exit=0
"$CLAUDE_BIN" -p \
  --agent fable-advisor \
  --plugin-dir "$ROOT" \
  --tools "Read,Grep,Glob" \
  --permission-mode dontAsk \
  --output-format json \
  --no-session-persistence \
  "$(cat "$PROMPT_FILE")" > "$JSON_FILE" 2> "$ERROR_FILE" || review_exit=$?

if [ "$review_exit" -ne 0 ]; then
  error_output=$(cat "$ERROR_FILE")
  case "$error_output" in
    *[Aa]gent*not*found*|*unknown*agent*) classification=AGENT_NOT_INVOKED ;;
    *model*unavailable*|*model*not*found*|*access*model*) classification=MODEL_UNRESOLVED ;;
    *permission*denied*|*tool*denied*) classification=TOOL_PERMISSION_FAILURE ;;
    *) classification=TRANSPORT_FAILED ;;
  esac
  unavailable "$classification" "claude review exited $review_exit: $error_output"
fi

ruby "$ROOT/scripts/parse-review-result.rb" "$JSON_FILE"

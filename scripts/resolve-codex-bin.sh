#!/bin/sh
set -u

report_unavailable() {
  source_name=$1
  candidate_name=$2
  reason=$3
  printf '%s\n' \
    'CODEX RESOLUTION REPORT' \
    'STATUS: unavailable' \
    "SOURCE: $source_name" \
    "CANDIDATE: $candidate_name" \
    "REASON: $reason" >&2
  exit 1
}

if [ "${AI_ORCHESTRATOR_CODEX_BIN+x}" = x ]; then
  source_name=explicit
  requested_candidate=$AI_ORCHESTRATOR_CODEX_BIN
  if [ -z "$requested_candidate" ]; then
    report_unavailable "$source_name" '<empty>' 'AI_ORCHESTRATOR_CODEX_BIN is empty; explicit configuration does not fall back to PATH'
  fi
  case "$requested_candidate" in
    */*) candidate=$requested_candidate ;;
    *) candidate=$(command -v "$requested_candidate" 2>/dev/null || true) ;;
  esac
  if [ -z "$candidate" ]; then
    report_unavailable "$source_name" "$requested_candidate" 'explicit binary was not found; PATH fallback is disabled when the override is set'
  fi
else
  source_name=path
  candidate=$(command -v codex 2>/dev/null || true)
  if [ -z "$candidate" ]; then
    report_unavailable none '<none>' 'no codex binary found on PATH and AI_ORCHESTRATOR_CODEX_BIN is unset'
  fi
fi

if [ ! -x "$candidate" ]; then
  report_unavailable "$source_name" "$candidate" 'candidate is not executable'
fi

version_exit=0
version_output=$("$candidate" --version 2>&1) || version_exit=$?
if [ "$version_exit" -ne 0 ]; then
  report_unavailable "$source_name" "$candidate" "codex --version failed with exit $version_exit: $version_output"
fi
if [ -z "$version_output" ]; then
  report_unavailable "$source_name" "$candidate" 'codex --version returned empty output'
fi

auth_exit=0
auth_output=$("$candidate" login status 2>&1) || auth_exit=$?
if [ "$auth_exit" -ne 0 ]; then
  report_unavailable "$source_name" "$candidate" "codex login status failed with exit $auth_exit: $auth_output"
fi

printf '%s\n' \
  'CODEX RESOLUTION REPORT' \
  'STATUS: available' \
  "SOURCE: $source_name" \
  "VERSION: $version_output" >&2
printf '%s\n' "$candidate"

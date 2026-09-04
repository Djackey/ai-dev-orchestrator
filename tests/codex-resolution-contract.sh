#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
RESOLVER=$ROOT/scripts/resolve-codex-bin.sh
FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/codex-resolution.XXXXXX")
trap 'rm -rf "$FIXTURE_ROOT"' EXIT HUP INT TERM

mkdir -p "$FIXTURE_ROOT/valid" "$FIXTURE_ROOT/broken" "$FIXTURE_ROOT/empty" "$FIXTURE_ROOT/model"

create_valid_binary() {
  target=$1
  auth_status=$2
  model_status=$3
  cat > "$target" <<EOF
#!/bin/sh
case "\${1-}" in
  --version)
    printf '%s\n' 'codex-cli fixture-1.0'
    exit 0
    ;;
  login)
    if [ "\${2-}" = status ]; then
      if [ "$auth_status" -eq 0 ]; then
        printf '%s\n' 'Logged in using fixture auth'
        exit 0
      fi
      printf '%s\n' 'authentication unavailable' >&2
      exit "$auth_status"
    fi
    ;;
  exec)
    if [ "$model_status" -ne 0 ]; then
      printf '%s\n' 'requested model unavailable' >&2
      exit "$model_status"
    fi
    printf '%s\n' 'MODEL_OK'
    exit 0
    ;;
esac
exit 2
EOF
  chmod +x "$target"
}

create_valid_binary "$FIXTURE_ROOT/valid/codex" 0 0
create_valid_binary "$FIXTURE_ROOT/valid/auth-fail" 23 0
create_valid_binary "$FIXTURE_ROOT/model/codex" 0 42

cat > "$FIXTURE_ROOT/broken/codex" <<'EOF'
#!/bin/sh
printf '%s\n' 'broken shim: native executable missing' >&2
exit 127
EOF
chmod +x "$FIXTURE_ROOT/broken/codex"

expect_success() {
  name=$1
  expected=$2
  shift 2
  actual=$("$@" 2> "$FIXTURE_ROOT/report") || {
    printf 'FAIL: %s unexpectedly failed\n' "$name" >&2
    cat "$FIXTURE_ROOT/report" >&2
    exit 1
  }
  [ "$actual" = "$expected" ] || {
    printf 'FAIL: %s resolved %s, expected %s\n' "$name" "$actual" "$expected" >&2
    exit 1
  }
  grep -F 'STATUS: available' "$FIXTURE_ROOT/report" >/dev/null
  printf 'PASS: %s\n' "$name"
}

expect_failure() {
  name=$1
  expected_text=$2
  shift 2
  if "$@" > "$FIXTURE_ROOT/result" 2> "$FIXTURE_ROOT/report"; then
    printf 'FAIL: %s unexpectedly succeeded\n' "$name" >&2
    exit 1
  fi
  grep -F 'STATUS: unavailable' "$FIXTURE_ROOT/report" >/dev/null
  grep -F "$expected_text" "$FIXTURE_ROOT/report" >/dev/null
  printf 'PASS: %s\n' "$name"
}

expect_success \
  'explicit valid binary overrides broken PATH shim' \
  "$FIXTURE_ROOT/valid/codex" \
  env AI_ORCHESTRATOR_CODEX_BIN="$FIXTURE_ROOT/valid/codex" PATH="$FIXTURE_ROOT/broken:/usr/bin:/bin" "$RESOLVER"

expect_failure \
  'explicit invalid binary does not fall back to valid PATH' \
  'candidate is not executable' \
  env AI_ORCHESTRATOR_CODEX_BIN="$FIXTURE_ROOT/missing/codex" PATH="$FIXTURE_ROOT/valid:/usr/bin:/bin" "$RESOLVER"

expect_success \
  'PATH valid binary' \
  "$FIXTURE_ROOT/valid/codex" \
  env -u AI_ORCHESTRATOR_CODEX_BIN PATH="$FIXTURE_ROOT/valid:/usr/bin:/bin" "$RESOLVER"

expect_failure \
  'PATH broken shim is not accepted' \
  'codex --version failed with exit 127' \
  env -u AI_ORCHESTRATOR_CODEX_BIN PATH="$FIXTURE_ROOT/broken:$FIXTURE_ROOT/valid:/usr/bin:/bin" "$RESOLVER"

expect_failure \
  'no binary' \
  'no codex binary found on PATH' \
  env -u AI_ORCHESTRATOR_CODEX_BIN PATH="$FIXTURE_ROOT/empty:/usr/bin:/bin" "$RESOLVER"

expect_failure \
  'authentication unavailable' \
  'codex login status failed with exit 23' \
  env AI_ORCHESTRATOR_CODEX_BIN="$FIXTURE_ROOT/valid/auth-fail" PATH="$FIXTURE_ROOT/valid:/usr/bin:/bin" "$RESOLVER"

resolved=$(env AI_ORCHESTRATOR_CODEX_BIN="$FIXTURE_ROOT/model/codex" PATH="$FIXTURE_ROOT/broken:/usr/bin:/bin" "$RESOLVER" 2> "$FIXTURE_ROOT/report")
model_exit=0
"$resolved" exec --model gpt-fixture > "$FIXTURE_ROOT/result" 2>&1 || model_exit=$?
[ "$model_exit" -eq 42 ] || {
  printf 'FAIL: model unavailable exit was %s\n' "$model_exit" >&2
  exit 1
}
grep -F 'requested model unavailable' "$FIXTURE_ROOT/result" >/dev/null
printf 'PASS: model unavailable remains a loud invocation failure\n'

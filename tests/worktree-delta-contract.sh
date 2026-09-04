#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
DELTA=$ROOT/scripts/worktree-delta.rb
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/worktree-delta.XXXXXX")
STATE=$(mktemp "${TMPDIR:-/tmp}/worktree-state.XXXXXX")
UTF8=$(mktemp -d "${TMPDIR:-/tmp}/worktree-utf8.XXXXXX")
UTF8_STATE=$(mktemp "${TMPDIR:-/tmp}/worktree-utf8-state.XXXXXX")
SHIM=$(mktemp -d "${TMPDIR:-/tmp}/worktree-shim.XXXXXX")
RESULT=$(mktemp "${TMPDIR:-/tmp}/worktree-result.XXXXXX")
trap 'rm -rf "$FIXTURE" "$UTF8" "$SHIM"; rm -f "$STATE" "$UTF8_STATE" "$RESULT" "$FIXTURE-result"' EXIT HUP INT TERM

# The guard must not depend on the caller's locale. Every invocation below runs
# with LANG/LC_ALL cleared unless a case deliberately sets them.
delta() {
  env -u LANG -u LC_ALL ruby "$DELTA" "$@"
}

init_repo() {
  target=$1
  name=$2
  git -C "$target" init -q
  git -C "$target" config user.name "$name"
  git -C "$target" config user.email 'delta@example.invalid'
}

# --- ASCII repository, locale cleared -----------------------------------------

init_repo "$FIXTURE" 'Delta Contract'
printf '%s\n' baseline > "$FIXTURE/tracked.txt"
git -C "$FIXTURE" add tracked.txt
git -C "$FIXTURE" commit -qm baseline

delta snapshot "$STATE" "$FIXTURE" >/dev/null
empty_exit=0
delta check "$STATE" "$FIXTURE" > "$FIXTURE-result" || empty_exit=$?
[ "$empty_exit" -eq 3 ]
grep -F 'STATUS: empty' "$FIXTURE-result" >/dev/null
printf 'PASS: deterministic empty delta (ASCII, locale cleared)\n'

printf '%s\n' changed > "$FIXTURE/tracked.txt"
delta check "$STATE" "$FIXTURE" > "$FIXTURE-result"
grep -F 'STATUS: changed' "$FIXTURE-result" >/dev/null
grep -F 'CHANGE: modified: tracked.txt' "$FIXTURE-result" >/dev/null
printf 'PASS: deterministic tracked modification (ASCII, locale cleared)\n'

printf '%s\n' new > "$FIXTURE/new.txt"
delta check "$STATE" "$FIXTURE" > "$FIXTURE-result"
grep -F 'CHANGE: added: new.txt' "$FIXTURE-result" >/dev/null
printf 'PASS: deterministic untracked addition (ASCII, locale cleared)\n'

rm "$FIXTURE/tracked.txt"
delta check "$STATE" "$FIXTURE" > "$FIXTURE-result"
grep -F 'CHANGE: deleted: tracked.txt' "$FIXTURE-result" >/dev/null
printf 'PASS: deterministic deletion (ASCII, locale cleared)\n'

# --- UTF-8 repository paths ---------------------------------------------------
#
# Regression for S-000: git repository paths were interpreted with the process
# locale, so a non-ASCII path raised "invalid byte sequence in US-ASCII" and the
# guard died outside its own exit contract.

mkdir -p "$UTF8/doc/测试"
init_repo "$UTF8" 'UTF8 Contract'
printf '%s\n' 'ascii baseline' > "$UTF8/README.md"
printf '%s\n' 'promotion baseline' > "$UTF8/推广.md"
printf '%s\n' 'case baseline' > "$UTF8/doc/测试/案例.txt"
git -C "$UTF8" add -A
git -C "$UTF8" commit -qm baseline

delta snapshot "$UTF8_STATE" "$UTF8" > "$RESULT"
grep -F 'STATUS: captured' "$RESULT" >/dev/null
grep -F 'FILES: 3' "$RESULT" >/dev/null
printf 'PASS: snapshot of UTF-8 non-ASCII paths (locale cleared)\n'

utf8_empty_exit=0
delta check "$UTF8_STATE" "$UTF8" > "$RESULT" || utf8_empty_exit=$?
[ "$utf8_empty_exit" -eq 3 ]
grep -F 'STATUS: empty' "$RESULT" >/dev/null
printf 'PASS: unchanged UTF-8 worktree is empty with exit 3 (locale cleared)\n'

printf '%s\n' 'case changed' > "$UTF8/doc/测试/案例.txt"
utf8_changed_exit=0
delta check "$UTF8_STATE" "$UTF8" > "$RESULT" || utf8_changed_exit=$?
[ "$utf8_changed_exit" -eq 0 ]
grep -F 'CHANGE: modified: doc/测试/案例.txt' "$RESULT" >/dev/null
printf 'PASS: modified UTF-8 path is reported with exit 0 (locale cleared)\n'

# The baseline JSON holds UTF-8 keys; rereading it must not depend on the
# process locale either, in both directions.
c_locale_exit=0
env LANG=C LC_ALL=C ruby "$DELTA" check "$UTF8_STATE" "$UTF8" > "$RESULT" || c_locale_exit=$?
[ "$c_locale_exit" -eq 0 ]
grep -F 'CHANGE: modified: doc/测试/案例.txt' "$RESULT" >/dev/null
printf 'PASS: baseline reread and reported under C/POSIX locale\n'

env LANG=C LC_ALL=C ruby "$DELTA" snapshot "$UTF8_STATE" "$UTF8" >/dev/null
printf '%s\n' 'promotion changed' > "$UTF8/推广.md"
cross_exit=0
delta check "$UTF8_STATE" "$UTF8" > "$RESULT" || cross_exit=$?
[ "$cross_exit" -eq 0 ]
grep -F 'CHANGE: modified: 推广.md' "$RESULT" >/dev/null
printf 'PASS: snapshot under C/POSIX, check under cleared locale\n'

# --- Invalid UTF-8 path data fails closed -------------------------------------
#
# This host's filesystem rejects invalid UTF-8 filenames (EILSEQ), so the bad
# bytes are injected through a git shim. The guard must exit 2 with a named
# error, not crash and not silently skip the path.

cat > "$SHIM/git" <<'SHIMEOF'
#!/bin/sh
for argument in "$@"; do
  if [ "$argument" = ls-files ]; then
    printf 'bad\377\376name.txt\000'
    exit 0
  fi
done
exec /usr/bin/git "$@"
SHIMEOF
chmod +x "$SHIM/git"

invalid_exit=0
env -u LANG -u LC_ALL PATH="$SHIM:$PATH" ruby "$DELTA" snapshot "$STATE" "$FIXTURE" > "$RESULT" 2>&1 || invalid_exit=$?
[ "$invalid_exit" -eq 2 ] || {
  printf 'FAIL: invalid UTF-8 path data exited %s, expected the guard error 2\n' "$invalid_exit" >&2
  cat "$RESULT" >&2
  exit 1
}
grep -F 'WORKTREE DELTA ERROR' "$RESULT" >/dev/null
grep -F 'is not valid UTF-8' "$RESULT" >/dev/null
if grep -F 'ArgumentError)' "$RESULT" >/dev/null 2>&1; then
  printf 'FAIL: invalid UTF-8 path data produced a crash stacktrace\n' >&2
  exit 1
fi
printf 'PASS: invalid UTF-8 path data fails closed with exit 2 and a named error\n'

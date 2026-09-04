#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUTPUT_PATH=${1:-$ROOT/docs/model-map.json}

CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
if [ -z "$CLAUDE_BIN" ]; then
  printf 'ERROR: claude executable not found on PATH\n' >&2
  exit 1
fi

version_exit=0
CLAUDE_VERSION=$("$CLAUDE_BIN" --version 2>&1) || version_exit=$?
if [ "$version_exit" -ne 0 ]; then
  printf 'ERROR: claude --version failed with exit %s: %s\n' "$version_exit" "$CLAUDE_VERSION" >&2
  exit 1
fi

GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

PROBE_DIR=$(mktemp -d -t claude-model-probe.XXXXXX)
trap 'rm -rf "$PROBE_DIR"' EXIT HUP INT TERM

ALIASES_FILE=$PROBE_DIR/aliases.tsv
COSTS_FILE=$PROBE_DIR/costs.txt
: > "$ALIASES_FILE"
: > "$COSTS_FILE"

ANY_UNRESOLVED=0

for alias in sonnet opus haiku fable; do
  probe_file=$PROBE_DIR/$alias.json
  probe_error_file=$PROBE_DIR/$alias.err
  "$CLAUDE_BIN" -p 'Reply with exactly the single word OK and nothing else.' \
    --model "$alias" \
    --output-format json \
    --max-turns 1 \
    --no-session-persistence \
    --tools "" \
    > "$probe_file" 2> "$probe_error_file" || true

  canonical=$(python3 - "$probe_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        payload = json.load(f)
except Exception:
    print("")
    sys.exit(0)

usage = payload.get("modelUsage") if isinstance(payload, dict) else None
if not isinstance(usage, dict) or len(usage) != 1:
    print("")
    sys.exit(0)

print(next(iter(usage.keys())))
PY
)

  cost=$(python3 - "$probe_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        payload = json.load(f)
except Exception:
    print("0")
    sys.exit(0)

cost = payload.get("total_cost_usd") if isinstance(payload, dict) else None
print(cost if isinstance(cost, (int, float)) else 0)
PY
)

  printf '%s\n' "$cost" >> "$COSTS_FILE"
  printf '%s\t%s\n' "$alias" "$canonical" >> "$ALIASES_FILE"
  [ -n "$canonical" ] || ANY_UNRESOLVED=1
done

if [ "$ANY_UNRESOLVED" -eq 1 ]; then
  UNRESOLVED_LIST=$(awk -F'\t' '$2 == "" { print $1 }' "$ALIASES_FILE" | tr '\n' ' ')
  printf 'ERROR: alias(es) failed to resolve to a single modelUsage key: %s\n' "$UNRESOLVED_LIST" >&2
  printf 'ERROR: no model map was written; a partial map must never exist on disk\n' >&2
  exit 1
fi

CLAUDE_VERSION=$CLAUDE_VERSION GENERATED_AT=$GENERATED_AT \
python3 - "$OUTPUT_PATH" "$ALIASES_FILE" "$COSTS_FILE" <<'PY'
import json
import os
import sys
import tempfile

output_path, aliases_path, costs_path = sys.argv[1:4]
claude_version = os.environ.get("CLAUDE_VERSION", "")
generated_at = os.environ.get("GENERATED_AT", "")

aliases = {}
with open(aliases_path, encoding="utf-8") as f:
    for line in f:
        alias, canonical = line.rstrip("\n").split("\t", 1)
        aliases[alias] = canonical if canonical else None

total_cost = 0.0
with open(costs_path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            total_cost += float(line)
        except ValueError:
            pass

payload = {
    "generatedAt": generated_at,
    "claudeVersion": claude_version,
    "aliases": aliases,
    "probeCostUsd": total_cost,
}

out_dir = os.path.dirname(os.path.abspath(output_path))
fd, tmp_path = tempfile.mkstemp(prefix=os.path.basename(output_path) + ".", suffix=".tmp", dir=out_dir)
try:
    # mkstemp creates 0600; keep the mode the map already has (or the umask
    # default for a new file) so an atomic replace does not narrow it.
    try:
        mode = os.stat(output_path).st_mode & 0o777
    except FileNotFoundError:
        umask = os.umask(0)
        os.umask(umask)
        mode = 0o666 & ~umask
    os.chmod(tmp_path, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, sort_keys=True)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp_path, output_path)
except BaseException:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    raise
PY
compose_exit=$?

if [ "$compose_exit" -ne 0 ]; then
  printf 'ERROR: failed to write model map to %s\n' "$OUTPUT_PATH" >&2
  exit 1
fi

printf 'PASS: model map written to %s\n' "$OUTPUT_PATH"

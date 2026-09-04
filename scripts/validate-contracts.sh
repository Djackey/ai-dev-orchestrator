#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

require_text() {
  file=$1
  text=$2
  rg -F --quiet -- "$text" "$file" || fail "$file missing contract text: $text"
}

for file in \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  agents/codex-implementer.md \
  agents/terra-implementer.md \
  agents/sol-implementer.md \
  agents/evidence-explorer.md \
  agents/fable-advisor.md \
  skills/orchestration/SKILL.md \
  contracts/IMPLEMENTATION_LANE_CONTRACT.md \
  contracts/IMPLEMENTATION_SPEC.md \
  contracts/EVIDENCE_FIRST_SPEC.md \
  acceptance/ACCEPTANCE_EVIDENCE.md \
  acceptance/prompts/final-review.md \
  scripts/resolve-codex-bin.sh \
  scripts/run-clean-context-review.sh \
  scripts/parse-review-result.rb \
  scripts/worktree-delta.rb \
  tests/codex-resolution-contract.sh \
  tests/reviewer-contract.sh \
  tests/worktree-delta-contract.sh; do
  require_file "$file"
done

command -v claude >/dev/null 2>&1 || fail 'claude CLI unavailable for plugin validation'
claude plugin validate --strict . >/dev/null
printf 'PASS: Claude plugin manifest validation\n'

command -v ruby >/dev/null 2>&1 || fail 'ruby unavailable for YAML frontmatter validation'
./scripts/validate-frontmatter.rb

python3 -c '
import json
from pathlib import Path
plugin = json.loads(Path(".claude-plugin/plugin.json").read_text())
market = json.loads(Path(".claude-plugin/marketplace.json").read_text())
entry = market["plugins"][0]
assert plugin["name"] == market["name"] == entry["name"]
assert plugin["license"] == "MIT"
assert plugin["version"] == "5.1.0"
' || fail 'plugin/marketplace metadata consistency'
printf 'PASS: plugin/marketplace metadata consistency\n'

require_text README.md '`IMPLEMENTER_MECHANICAL` | GPT-5.6 Luna | `codex-implementer`'
require_text README.md '`IMPLEMENTER_BALANCED` | GPT-5.6 Terra | `terra-implementer`'
require_text README.md '`IMPLEMENTER_FRONTIER` | GPT-5.6 Sol | `sol-implementer`'
require_text README.md '`EVIDENCE_EXPLORER` | GPT-5.6 Terra | `evidence-explorer`'
require_text README.md '`CLEAN_CONTEXT_REVIEWER` | Fable 5.1 | `fable-advisor`'
require_text skills/orchestration/SKILL.md '`IMPLEMENTER_MECHANICAL` | GPT-5.6 Luna | `codex-implementer`'
require_text skills/orchestration/SKILL.md '`IMPLEMENTER_BALANCED` | GPT-5.6 Terra | `terra-implementer`'
require_text skills/orchestration/SKILL.md '`IMPLEMENTER_FRONTIER` | GPT-5.6 Sol | `sol-implementer`'
printf 'PASS: role/model/agent mappings agree\n'

require_text agents/codex-implementer.md 'MODEL=gpt-5.6-luna'
require_text agents/terra-implementer.md 'MODEL=gpt-5.6-terra'
require_text agents/sol-implementer.md 'MODEL=gpt-5.6-sol'
for file in agents/codex-implementer.md agents/terra-implementer.md agents/sol-implementer.md; do
  require_text "$file" 'resolve-codex-bin.sh'
  require_text "$file" '`--sandbox workspace-write`'
  require_text "$file" 'Never retry'
  require_text "$file" 'independently re-run `VERIFICATION`'
done
require_text contracts/IMPLEMENTATION_LANE_CONTRACT.md 'No task delta is `refused`'
require_text contracts/IMPLEMENTATION_LANE_CONTRACT.md 'Never substitute another model'
require_text contracts/IMPLEMENTATION_LANE_CONTRACT.md '`STATUS: empty` MUST force `STATUS: refused`'
require_text contracts/IMPLEMENTATION_LANE_CONTRACT.md 'CODEX_ARGV_CONTRACT_START'
require_text contracts/IMPLEMENTATION_LANE_CONTRACT.md 'uncapped run in `GAPS`'
printf 'PASS: no-fallback, sandbox, empty-diff, and verification guards\n'

require_text agents/evidence-explorer.md '`--sandbox read-only`'
require_text agents/evidence-explorer.md 'change is a contract violation'
require_text agents/evidence-explorer.md 'Never edit/write repository files'
require_text agents/evidence-explorer.md '`STATUS: changed` is `read_only_violation`'
for file in agents/codex-implementer.md agents/terra-implementer.md agents/sol-implementer.md agents/evidence-explorer.md; do
  require_text "$file" '${CLAUDE_PLUGIN_ROOT}/contracts/'
done
if awk 'NR == 1 { next } /^---$/ { exit } { print }' agents/evidence-explorer.md | rg --quiet 'Write|Edit'; then
  fail 'evidence-explorer frontmatter exposes Write/Edit'
fi
printf 'PASS: evidence lane read-only contract\n'

require_text skills/orchestration/SKILL.md 'SPEC_FAILURE'
require_text skills/orchestration/SKILL.md 'IMPLEMENTATION_FAILURE'
require_text skills/orchestration/SKILL.md 'TASK_MISCLASSIFICATION'
require_text skills/orchestration/SKILL.md 'There is no automatic "one failure means stronger model" rule.'
if rg --quiet 'routine lane.*failed.*once|same spec.*pick the stronger diff|Default lane.*Luna' README.md skills/orchestration/SKILL.md; then
  fail 'obsolete Luna-to-Sol routing doctrine found'
fi
printf 'PASS: routing and escalation doctrine\n'

require_text README.md 'Human authorization owns Production.'
require_text skills/orchestration/SKILL.md 'Only `HUMAN_RELEASE_AUTHORITY` can authorize those acts explicitly.'
require_text skills/orchestration/SKILL.md '`READY_FOR_STAGING`'
require_text skills/orchestration/SKILL.md '`READY_FOR_PRODUCTION_CANARY`'
if rg --quiet --glob '*.md' '(automatically|auto)[ -]?(deploy|merge|migrate).*Production|Production.*(automatically|auto)[ -]?(deploy|merge|migrate)' .; then
  fail 'automatic Production path found'
fi
printf 'PASS: human authority boundary and no automatic Production path\n'

./tests/timeout-contract.sh
./tests/codex-resolution-contract.sh
./tests/reviewer-contract.sh
./tests/worktree-delta-contract.sh

git diff --check
printf 'PASS: git diff --check\n'
if rg -n '[[:blank:]]+$' --glob '*.md' --glob '*.json' --glob '*.sh' .; then
  fail 'trailing whitespace found (including untracked files)'
fi
printf 'PASS: no trailing whitespace in tracked or untracked text files\n'
if rg --quiet --glob '!validate-contracts.sh' \
  '/Users/|/Applications/ChatGPT\.app|/private/tmp/' \
  acceptance docs README.md agents contracts scripts tests skills; then
  fail 'machine-private acceptance path found in repository evidence or docs'
fi
printf 'PASS: no machine-private acceptance paths\n'
printf 'ALL CONTRACT VALIDATIONS PASSED\n'

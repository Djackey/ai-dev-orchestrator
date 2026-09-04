# Claude Implementation Lane Contract

This is the behavioral contract for the headless Claude implementation lane,
`scripts/run-claude-lane.sh`. It is a candidate lane, not a replacement for the
Codex-backed lanes governed by
[`IMPLEMENTATION_LANE_CONTRACT.md`](IMPLEMENTATION_LANE_CONTRACT.md). Both
contracts share the same evidence discipline, guard mechanics, and human
authority boundary; this document only covers what differs about invoking
`claude -p` under a restricted execution boundary.

## Invocation boundary

The lane invokes `claude -p --restricted` with an explicit tool allowlist and a
deny list, never an ambient-trust or fully open session:

- `--tools "Read,Edit,Write,Grep,Glob,Bash"` names the tool surface that can
  even be attempted. `--allowedTools` is narrower: it always includes
  `Read,Edit,Write,Grep,Glob`, and only adds `Bash(PREFIX:*)` entries when the
  caller explicitly passes `--allow-bash PREFIX`. When no `--allow-bash` is
  given, Bash stays listed in `--tools` but absent from `--allowedTools`, so a
  denied Bash attempt is an observable boundary event instead of a silently
  unavailable tool.
- `--settings` carries a single JSON `permissions.deny` list built
  programmatically (never by string concatenation of untrusted text) from the
  protected-path patterns: `./.env`, `./.env.*`,
  `./.claude/settings.local.json`, `./.codex/**`, `./.npmrc`, `./.git/**`, plus
  every project-declared pattern in `.ai-orchestrator-protected-paths`. Each
  pattern is denied for `Read`, `Edit`, and `Write`.
- `--permission-mode acceptEdits --permission-prompts none` runs unattended;
  there is no human in the loop to approve a prompt.
- The lane never passes `--fallback-model`, `--dangerously-skip-permissions`,
  `--allow-dangerously-skip-permissions`, or `bypassPermissions`. A model or
  permission boundary that cannot be honored is `unavailable`, not silently
  downgraded.
- NETWORK: bounded by the Bash allowlist only (permission layer, not an OS
  sandbox). Claude's `--restricted` mode is a tool-permission boundary, not a
  network or filesystem sandbox; the deterministic guards below are the actual
  enforcement for file-scope violations.

## The two guards

Exactly as in the Codex lane contract, the lane brackets every invocation with
two deterministic, out-of-process guards whose baselines live outside the
workdir (`mktemp -t`):

- `scripts/worktree-delta.rb` — a content baseline of tracked and
  nonignored-untracked files. Exit `0`/`STATUS: changed` proves a real task
  delta; exit `3`/`STATUS: empty` means no files changed. Any other exit is a
  guard failure.
- `scripts/protected-paths.rb` — the short explicit inventory of sensitive
  ignored paths (`.env`, `.env.*`, `.claude/settings.local.json`, `.codex/`,
  `.npmrc`, plus declared project patterns). Exit `0`/`STATUS: unchanged` is
  the only acceptable result; exit `4`/`STATUS: violation` is
  `PROTECTED_STATE_VIOLATION`. Any other exit is a guard failure.

These two scripts, and their meaning, are identical to the Codex lane; this
lane does not fork or relax them.

## Classification

`scripts/parse-lane-result.rb` classifies the captured JSON plus the two guard
exit codes, in this fixed order (first match wins):

| Order | Condition | STATUS | CLASSIFICATION |
|---|---|---|---|
| 1 | captured JSON unreadable / not an object | `unavailable` | `OUTPUT_NOT_CAPTURED` |
| 2 | `modelUsage` missing or not an object | `unavailable` | `MODEL_UNRESOLVED` |
| 3 | `modelUsage` has 0 keys | `unavailable` | `MODEL_UNRESOLVED` |
| 3 | `modelUsage` has more than 1 key | `unavailable` | `MULTI_MODEL` |
| 4 | the single `modelUsage` key is not the expected canonical model | `unavailable` | `MODEL_UNRESOLVED` |
| 5 | protected-paths guard exit is `4` | `refused` | `PROTECTED_STATE_VIOLATION` |
| 6 | either guard exited outside `{0,4}` / `{0,3}` | `unavailable` | `GUARD_FAILED` |
| 7 | `subtype == "error_max_budget_usd"` | `partial` | `BUDGET_EXCEEDED` |
| 8 | `subtype == "error_max_turns"` | `partial` | `TURNS_EXCEEDED` |
| 9 | `is_error` true or the `claude` exit is non-zero | `unavailable` | `TRANSPORT_FAILED` |
| 10 | worktree-delta guard exit is `3` (empty) | `refused` | `EMPTY_DELTA` |
| 11 | `permission_denials` present but not an array | `unavailable` | `OUTPUT_NOT_CAPTURED` |
| 12 | any denial's `tool_name` is `Read`, `Edit`, or `Write` | `partial` | `TOOL_PERMISSION_FAILURE` |
| 13 | otherwise | `complete-candidate` | `none` |

Rule 10 overrides what would otherwise read as a successful subtype: an exit
of zero with no worktree delta is never `complete-candidate`. A `Bash`-only
denial is reported in `BOUNDARY_EVENTS` but, by itself, never fails the run —
only a denied `Read`, `Edit`, or `Write` does.

The mapping from an abstract model alias (`sonnet`, `opus`, `haiku`, `fable`)
to a canonical model id (`claude-sonnet-5`, `claude-opus-5`, ...) comes only
from `docs/model-map.json`, produced by `scripts/probe-model-map.sh`. That
mapping is never hardcoded in the parser: `scripts/parse-lane-result.rb`
receives `EXPECTED_CANONICAL` as an argument from the caller and never invents
or assumes a canonical id itself. `run-claude-lane.sh` also refuses a model map
whose `generatedAt` is more than 30 days old, reporting `unavailable` /
`MAPPING_STALE` rather than trusting a stale probe.

## Report

```text
IMPLEMENTATION REPORT
LANE: claude
REQUESTED_MODEL: <EXPECTED_CANONICAL>
RESOLVED_MODEL_EVIDENCE: <the single modelUsage key, or "unavailable">
STATUS: complete-candidate | partial | refused | unavailable
CLASSIFICATION: none | MODEL_UNRESOLVED | MULTI_MODEL | OUTPUT_NOT_CAPTURED | TRANSPORT_FAILED | BUDGET_EXCEEDED | TURNS_EXCEEDED | EMPTY_DELTA | PROTECTED_STATE_VIOLATION | GUARD_FAILED | TOOL_PERMISSION_FAILURE
REASON: <one line or none>
COST_USD: <total_cost_usd or unknown>
NUM_TURNS: <num_turns or unknown>
BOUNDARY_EVENTS: <count> denial(s): <tool_name summary list, or none>
PROTECTED_STATE: unchanged | violation | error
WORKTREE_DELTA: changed | empty | error
MODEL_SAID:
<the result text verbatim>
```

## Acceptance is not delegated

`STATUS: complete-candidate` is a claim from the lane, not acceptance. Exactly
as for the Codex lanes, the architect independently re-runs every command in
`VERIFICATION` and reads the actual diff; it does not accept quoted output or
a model's self-report. A failing verification, a partial diff, or a missing
required file cannot be `complete-candidate` regardless of what this report
says.

This lane has no commit, merge, deploy, or Production authority. It cannot
mutate a Production database or billing system, enable a Production feature
flag, or perform any other irreversible external action; those remain
exclusively with `HUMAN_RELEASE_AUTHORITY`, exactly as in
[`IMPLEMENTATION_LANE_CONTRACT.md`](IMPLEMENTATION_LANE_CONTRACT.md#evidence-and-acceptance).

## Residual gaps (recorded, not closed)

- Allowlisted Bash commands run without an OS sandbox. Repository code
  executed by an allowlisted command (for example a test suite the
  implementer can edit) could in principle locate and rewrite the guard
  baselines under `$TMPDIR`; the baselines have random `mktemp` names and the
  architect re-reads the actual diff, but closing this gap requires
  OS-level sandboxing, which this lane does not provide.
- A `--settings` deny-list refusal ("File is in a directory that is denied by
  your permission settings") does not appear in `permission_denials`; only
  prompts that would have needed approval do. The deterministic
  `protected-paths.rb` check is therefore the load-bearing evidence for
  protected local state.
- An allowlist prefix such as `Bash(pnpm test:*)` is matched after leading
  environment assignments are stripped, so `LANG=C pnpm test` is accepted;
  the prefix still cannot be used to run a different program.
- `--restricted` confines the file tools to the working directories but does
  not bound the network; `NETWORK: bounded by the Bash allowlist only`
  remains the honest statement.

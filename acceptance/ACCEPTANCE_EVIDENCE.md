# V1 Dogfood Acceptance Evidence — 2026-09-04

This record is privacy-safe: it omits local application paths, session IDs,
account details, costs, and temporary fixture paths. All fixture repositories
were isolated local Git repositories with no remotes and no Production access.

## Frozen baseline

- Branch: `codex/orchestrator-v1`
- Starting HEAD: `4d6cc62164619a279b076439e1af5439892b958a`
- `main` was not checked out or modified.
- V1 doctrine, role mapping, README positioning, and upstream-compatible agent
  filenames were frozen before acceptance work.
- Acceptance changes were limited to executable resolution, reviewer result
  capture/classification, deterministic delta enforcement, tests, and evidence.

## Executable resolution

The repository resolver implements this boundary:

1. An explicit `AI_ORCHESTRATOR_CODEX_BIN` candidate is authoritative.
2. Otherwise, resolve `codex` from PATH.
3. Require an executable plus successful `--version` and `login status`.
4. Preserve any failure as structured unavailable; never try another binary or
   model implicitly.

Deterministic contract cases all passed:

| Case | Result |
|---|---|
| explicit valid binary with broken PATH first | explicit binary selected |
| explicit invalid binary with valid PATH later | loud unavailable; no fallback |
| PATH valid binary | selected after version/auth checks |
| PATH broken shim | loud unavailable |
| no binary | loud unavailable |
| authentication unavailable | loud unavailable |
| requested model unavailable | invocation failure preserved; no model switch |

A real mechanical agent first ran with the host's broken PATH shim and returned
`STATUS: unavailable` with the resolver error and no file changes. The same lane
then ran through a working local bundled CLI supplied explicitly as acceptance
input. No private executable path is stored as a repository default.

## Real lane invocations

Each producer identity came from the captured Codex startup summary, not from
README aliases or the implementer's prose.

| Role | Runtime evidence | Sandbox | Actual result |
|---|---|---|---|
| `IMPLEMENTER_MECHANICAL` | `model: gpt-5.6-luna`, effort `low` | `workspace-write` | two-file mechanical delta; independent check passed |
| `IMPLEMENTER_BALANCED` | `model: gpt-5.6-terra`, effort `medium` | `workspace-write` | loader normalization + regression delta; independent check passed |
| `IMPLEMENTER_FRONTIER` | `model: gpt-5.6-sol`, effort `high` | `workspace-write` | fenced async-writer fix; independent concurrency check passed |
| `EVIDENCE_EXPLORER` | `model: gpt-5.6-terra`, effort `high` | `read-only` | competing hypotheses resolved; zero workspace delta |

The Sol task was an isolated capability probe for a temporal fencing invariant,
not evidence that Sol should handle routine implementation. Its spec allowed
only the store implementation file, forbade the test file, and independent
verification printed `sol fixture PASS`.

All write lanes returned the structured `IMPLEMENTATION REPORT`, identified the
requested model/effort/sandbox, described the actual delta, and reran the named
verification. The orchestrator then inspected each real diff and reran the
verification again; implementer reports were treated as claims.

## Empty-diff acceptance

The first real no-op probe exposed a defect: Luna exited zero, the target was
already satisfied, verification passed, and the wrapper incorrectly reported
`complete`. The actual diff was empty, so the architect rejected that report.

The minimal fix is a shared deterministic content baseline over tracked and
nonignored untracked worktree files. Its contract test proves tracked
modification, untracked addition, deletion, and no-change behavior. Existing
ignored paths are outside this inventory; the Codex sandbox is their actual
write boundary. The identical real Luna no-op was rerun:

```text
model: gpt-5.6-luna
reasoning effort: low
sandbox: workspace-write
WORKTREE DELTA REPORT
STATUS: empty
CHANGES: none
IMPLEMENTATION REPORT
STATUS: refused
```

The model claimed it had updated the file, but byte-level evidence overrode the
claim. Passing verification did not convert an empty delta into success.

## Clean-context reviewer resolution

The apparent host blocker was classified as `OUTPUT_NOT_CAPTURED`: the command
had yielded an asynchronous session, but the caller did not poll it. Correct
polling produced real JSON output. The runner now requires:

- the `fable-advisor` agent;
- exactly one `modelUsage` entry containing the requested Fable alias;
- captured JSON transport;
- no tool permission denials; and
- a consumable `VERDICT: ACCEPT | FIX_FIRST | RETHINK`.

Deterministic tests cover `AGENT_NOT_INVOKED`, `MODEL_UNRESOLVED`,
`TRANSPORT_FAILED`, `OUTPUT_NOT_CAPTURED`, and `TOOL_PERMISSION_FAILURE`.
Unavailable review is reported as `REVIEWER_UNAVAILABLE`; STANDARD/CRITICAL
cannot claim review completion, and CRITICAL cannot default to
`READY_FOR_PRODUCTION_CANARY`.

Real smoke, normal-dogfood, and evidence-dogfood reviews each returned:

```text
STATUS: AVAILABLE
RESOLVED_MODEL: claude-fable-5-1
TRANSPORT: captured-json
VERDICT: ACCEPT
```

This is fresh-context, same-family review under the current mapping—not
cross-family independent review.

## Normal dogfood

The complete real chain was:

1. Fable `ARCHITECT_FRONTIER` ran read-only; outer JSON proved
   `claude-fable-5-1`.
2. It selected `IMPLEMENTER_MECHANICAL` because the check uniquely fixed both
   replacements and chose `REASONING: low`.
3. Its spec allowed only `config.json` and `README.md`, forbade changing the
   verification script, preserved value 15, and required `ruby check-config.rb`.
4. Luna ran with model/effort/sandbox evidence and changed exactly the two
   allowed files.
5. The orchestrator inspected the diff, confirmed the verifier was unchanged,
   reran `ruby check-config.rb` (`normal fixture PASS`), and ran
   `git diff --check`.
6. A fresh Fable reviewer read the actual files and returned `VERDICT: ACCEPT`.
7. The architect's final decision was ACCEPTED FOR REVIEW ONLY; no merge,
   release, deploy, or external mutation was authorized.

## Evidence-first dogfood

The complete real chain was:

1. Fable `ARCHITECT_FRONTIER` produced an `EVIDENCE_FIRST_SPEC` with four
   plausible hypotheses: lower-bound comparison, limit comparator, epoch-unit
   mismatch, and future/upper-bound handling. It did not name implementation
   files or prescribe a fix.
2. Terra Evidence Explorer traced concrete values, reproduced the assertion,
   directly ruled out three hypotheses, and returned
   `ROOT_CAUSE_CONFIDENCE: CONFIRMED` for the seconds/milliseconds mismatch.
3. Before and after evidence collection, Git status and binary diff were empty;
   all three file hashes matched their baseline, and the deterministic delta
   helper returned `STATUS: empty` as required for a read-only lane.
4. Fable independently recorded `ROOT_CAUSE_CONFIRMED`, fixed the threshold,
   conversion, interfaces, forbidden file, and regression intent, then selected
   `IMPLEMENTER_MECHANICAL` / low because the corrected spec left no material
   implementation judgment.
5. The architect caught two malformed intermediate Fable `LANE` values and did
   not delegate them. They were classified as `SPEC_FAILURE`; Fable explicitly
   corrected the lane to `IMPLEMENTER_MECHANICAL` before write authorization.
6. Luna changed only `src/event-loader.js` and `test.js`; the window/limit module
   remained byte-for-byte untouched.
7. The orchestrator inspected the diff, reran `node test.js`
   (`debug fixture PASS`), ran `git diff --check`, and confirmed the changed-file
   allowlist.
8. A fresh Fable reviewer returned `VERDICT: ACCEPT`, specifically confirming
   evidence quality, lack of comparator confirmation bias, lane choice, actual
   code, verification, and authority boundary.

## Human gate

No acceptance command targeted a remote repository, main, staging, Production,
database, billing system, feature flag, deployment, or destructive store. The
plugin continues to treat phrases such as "fix it" as implementation authority
only. Merge and Production actions require explicit human authorization.

## Gate result before final repository review

| Gate | Result |
|---|---|
| Luna real invocation | PASS |
| Terra real invocation | PASS |
| Sol real invocation | PASS |
| broken PATH shim handling | PASS |
| no silent model fallback | PASS |
| Evidence Explorer read-only/mutation detection | PASS |
| actual-diff verification and empty-diff refusal | PASS |
| clean-context reviewer real verdict | PASS |
| normal dogfood | PASS |
| evidence-first dogfood | PASS |
| Human Production boundary | PASS |

Repository-wide deterministic validation passed. The final fresh-context review
returned `VERDICT: ACCEPT`; its nonblocking hardening findings were applied and
are covered by the same validator before PR creation.

---
name: orchestration
description: Evidence-first, capability-routed development orchestration doctrine. Use when an architect decomposes software work, chooses among mechanical/balanced/frontier implementation lanes, requests read-only evidence, writes an implementation or evidence-first spec, classifies a failed attempt, verifies a diff, requests clean-context review, or approaches a staging/Production authority boundary.
---

# AI Development Orchestrator V1

The session is the architect. It owns requirements, decomposition, architecture,
specification, routing, evidence thresholds, verification, and the final verdict.
Implementation agents receive a self-contained contract, not the architect's
conversation context.

Plan with the best available reasoning model. Execute with the cheapest model
that can reliably satisfy the spec. Escalate only when material judgment remains.
Investigate evidence before editing when root cause is uncertain. Verify actual
evidence independently. Use fresh-context review before high-risk work ships.
Human authorization owns Production.

This is policy + agents + skills + contracts. It is not a model gateway,
workflow engine, scheduler, queue, database, dashboard, token-accounting backend,
persistent agent runtime, or distributed orchestration service.

## Abstract roles and current defaults

The roles are stable; the model mapping is replaceable.

| Abstract role | Current default | Invocation |
|---|---|---|
| `ARCHITECT_FRONTIER` | Fable 5.1 session | current Claude Code session |
| `EVIDENCE_EXPLORER` | GPT-5.6 Terra | `evidence-explorer` (Codex, read-only) |
| `IMPLEMENTER_MECHANICAL` | GPT-5.6 Luna | `codex-implementer` |
| `IMPLEMENTER_BALANCED` | GPT-5.6 Terra | `terra-implementer` |
| `IMPLEMENTER_FRONTIER` | GPT-5.6 Sol | `sol-implementer` |
| `IMPLEMENTER_CLAUDE` | Claude Sonnet 5 candidate · Opus 5 escalation | `scripts/run-claude-lane.sh` (headless, restricted) |
| `VISUAL_IMPLEMENTER` | Claude Opus, optional | no V1 agent until pin resolution is provable at report time |
| `CLEAN_CONTEXT_REVIEWER` | Fable 5.1 | `fable-advisor` |
| `HUMAN_RELEASE_AUTHORITY` | the user | explicit authorization only |

`CLEAN_CONTEXT_REVIEWER` and the current architect are the same model family.
The reviewer supplies fresh context and an assumption reset, not independent-
model review. The architect can later move from Fable to Astra or another
frontier model without changing this doctrine.

The optional visual role is appropriate for frontend, visual implementation,
Claude Design, MCP-heavy UI, complex UX, and Claude ecosystem integration. It is
not a default backend lane and, because it shares a vendor/model family with the
current architect, cannot replace a cross-family check.

## Cost and context discipline

The architect emits judgment: decisions, interfaces, specs, routing, and
verdicts. Implementation volume belongs to a selected lane. Broad exploration
belongs in a read-only evidence lane. The architect may inspect exact code when
its own decision depends on it, but should keep only decision-relevant evidence
in the main context.

Model price, token count, file count, or the user's word "important" do not
determine routing. The deciding variable is: **how much material judgment remains
after the spec?**

## Routing doctrine

Ask in order:

1. Does the spec essentially determine a unique implementation?
   - Yes: `IMPLEMENTER_MECHANICAL` / `codex-implementer`.
   - No: continue.
2. Does the task require ordinary engineering judgment while error cost and
   blast radius remain controlled?
   - Yes: `IMPLEMENTER_BALANCED` / `terra-implementer`.
   - No, or high-risk judgment is material: `IMPLEMENTER_FRONTIER` /
     `sol-implementer`.

| Lane | Route here | Do not route here |
|---|---|---|
| Mechanical | renames, repetitive edits, CRUD, straightforward wiring, config/docs, pattern-matched tests, schema/type propagation | architecture discovery, Production incidents, concurrency, billing, auth/security, distributed state, ambiguous wide refactors |
| Balanced | ordinary multi-file features, existing-architecture integration, moderate debugging, state changes, persistence/recovery, API/frontend interaction, locally judgmental refactors | fully specified mechanics; unresolved or high-blast-radius risk |
| Frontier | subtle concurrency, billing, auth/security, migrations, distributed state, hard debugging, race conditions, release infrastructure, wide-blast-radius refactors | routine work whose outcome the spec already fixes |

Sol is an escalation lane, never the default implementer. Do not use the strongest
implementation model merely because it is available.

## Evidence before implementation

Use `${CLAUDE_PLUGIN_ROOT}/contracts/EVIDENCE_FIRST_SPEC.md` for two kinds of
work: reactive Production incidents and hard debugging whose root cause is not
already proven, and proactive high-risk change in billing, auth, security,
concurrency, migration, distributed state, storage, or release infrastructure.

The evidence phase names no implementation files. Route it to
`evidence-explorer`, which runs Terra in `read-only` sandbox and returns:

- `OBSERVED`: direct evidence with provenance only.
- `INFERRED`: reasonable deductions not directly proved.
- `UNRESOLVED`: what remains unknown.
- `ROOT_CAUSE_CONFIDENCE`: `CONFIRMED`, `SUPPORTED_HYPOTHESIS`, or `UNRESOLVED`.
- `NEXT_EVIDENCE`: the next item most likely to change the verdict.

An error string or the last function in a stack trace is not root-cause proof.
Do not preselect its file for editing. Luna may do bounded, read-only scouting
such as finding call sites or history, but Terra or the architect synthesizes
the evidence.

### The evidence gate

An evidence-first task may issue an `IMPLEMENTATION_SPEC` only after the
architect explicitly records `EVIDENCE_GATE_SATISFIED`. Two paths reach it, and
they are not interchangeable:

```text
incident / defect / debugging
  evidence -> ROOT_CAUSE_CONFIRMED -> EVIDENCE_GATE_SATISFIED -> IMPLEMENTATION_SPEC

proactive high-risk change
  evidence / architecture / invariants / safety case
                           -> EVIDENCE_GATE_SATISFIED -> IMPLEMENTATION_SPEC
```

For reactive work, `ROOT_CAUSE_CONFIRMED` is a necessary condition for the gate.
Exceptional risk acceptance must be explicit and bounded, explain what remains
unresolved, and remain inside the human authority boundary.

For proactive high-risk change there is no defect and therefore no root cause;
never invent one, and never withhold the gate because none exists. The gate
instead requires that `OBSERVED_EVIDENCE`, `INVARIANTS`, `AUTHORITY_BOUNDARIES`,
`FORBIDDEN_ACTIONS`, `EVIDENCE_REQUIRED_BEFORE_WRITE`, and `STOP_CONDITIONS` are
each established well enough to carry the change. Equally, do not let the
proactive path excuse a reactive task from a root cause it actually owes.

The gate belongs to evidence-first work. It is not a universal precondition:
ordinary feature, refactor, and change work requires only that the
implementation direction is sufficiently determined.

## Spec contracts

### IMPLEMENTATION_SPEC

Use `${CLAUDE_PLUGIN_ROOT}/contracts/IMPLEMENTATION_SPEC.md` once the
implementation direction is sufficiently determined — and, for evidence-first
tasks only, once `EVIDENCE_GATE_SATISFIED` is also recorded:

```text
OBJECTIVE
LANE
FILES
INTERFACES
CONSTRAINTS
VERIFICATION
REASONING
```

`LANE` is an abstract role. Model resolution happens at the agent boundary.
`REASONING` is a runtime value chosen per task and passed unchanged; omission is
deliberate and reported as a gap. Do not encode a model name in business
requirements.

### EVIDENCE_FIRST_SPEC

Use `${CLAUDE_PLUGIN_ROOT}/contracts/EVIDENCE_FIRST_SPEC.md` while cause is
uncertain, or before a proactive high-risk change:

```text
GOAL
OBSERVED_EVIDENCE
HYPOTHESES
INVARIANTS
AUTHORITY_BOUNDARIES
FORBIDDEN_ACTIONS
EVIDENCE_REQUIRED_BEFORE_WRITE
STOP_CONDITIONS
```

## Shared Codex lane contract

All three implementers follow
`${CLAUDE_PLUGIN_ROOT}/contracts/IMPLEMENTATION_LANE_CONTRACT.md`:

- explicit-override/PATH Codex executable resolution with executable, version,
  and authentication preflight;
- explicit model selection with observable resolution evidence;
- exact per-task reasoning propagation;
- no silent model or vendor fallback;
- `workspace-write` sandbox and `--ask-for-approval never`, with `/tmp` and
  `$TMPDIR` excluded so guard baselines and transcripts stay unwritable;
- portable bash/zsh timeout construction with no uncapped retry;
- unique prompt, transcript, and final-message files;
- pre-run baseline and actual task-delta inspection;
- exit-zero + empty-delta rejection;
- a protected local-state guard over `.env`, `.env.*`,
  `.claude/settings.local.json`, `.codex/`, `.npmrc`, and any project-declared
  sensitive ignored paths, where any change is `PROTECTED_STATE_VIOLATION` and
  forces `STATUS: refused`;
- independent deterministic verification;
- structured report; and
- no commit, merge, deploy, Production mutation, or irreversible external act.

Reports are claims, not evidence. The architect reads the actual diff and
re-runs verification before acceptance. An implementer saying PASS cannot close
a task.

The evidence explorer uses the same resolution/timeout/reporting discipline but
sets `--sandbox read-only` and verifies that neither the workspace nor the
protected local state changed.

## Protected local state

The worktree content baseline covers tracked and nonignored untracked files. It
deliberately does not scan the ignored tree or `node_modules`. A short explicit
list is guarded separately by
`${CLAUDE_PLUGIN_ROOT}/scripts/protected-paths.rb`: `.env`, `.env.*`,
`.claude/settings.local.json`, `.codex/`, `.npmrc`, and any repository-relative
glob declared in `.ai-orchestrator-protected-paths`. Existence, type, mode, and
content hash are compared before and after every write or evidence lane. The
guard only holds while its baseline is outside the model's writable set, so the
lane contract excludes `/tmp` and `$TMPDIR` from `workspace-write` and the lane
must observe `sandbox: workspace-write [workdir]` before trusting any baseline.

Default: any change is a guard violation. An implementer may not make
verification pass by editing local secrets or local tool configuration, and may
not edit the protected-path configuration to widen its own room. A dropped
pattern does not shrink coverage, because the check unions baseline and current
patterns.

If a task genuinely requires changing local ignored configuration, the lane
stops and reports it. The guard is never automatically relaxed:
`HUMAN_RELEASE_AUTHORITY`, or the architect acting on explicit human
authorization, approves that change as a separate, explicitly scoped piece of
work.

## Model and effort resolution

Current defaults are observed mappings, not permanent guarantees. Every lane
must verify availability at invocation time. A missing binary, failed auth,
unavailable model, unsupported effort, different resolved model, or insufficient
runtime visibility is a loud `unavailable` result.

Never silently map Terra to Luna, Sol to Terra, or any Codex lane to Claude.
Never silently round effort. The architect may explicitly issue a new spec to a
different lane after acknowledging the change in capability, cost, and risk.

Claude agent frontmatter is also a capability boundary. Claude Code may silently
fall back when a pinned model is unavailable. The current `fable-advisor` pin is
therefore a requested mapping, and external CLI JSON `modelUsage` can validate
it during environment checks; a normal nested-agent report does not prove the
resolved model. This is why V1 does not ship the optional Opus write lane while
it could falsely claim Opus execution.

The Codex implementer wrapper agents use `model: sonnet`; that is the lightweight
Claude supervisor, not the producer model. Their producer identity comes only
from captured Codex startup evidence.

## Claude implementation lane (candidate)

`IMPLEMENTER_CLAUDE` runs `${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-lane.sh`, a
headless `claude -p --restricted` invocation with an explicit tool allowlist
and deny list, plus the same `worktree-delta.rb` / `protected-paths.rb` guards
used by the Codex lanes. It is a candidate default under a provisional
calibration: three real specs were run against it, and 2 of 3
`complete-candidate` results accepted by the architect made it the provisional
default, reviewed again on every later PR. The Codex lanes remain the
independent, cross-family capability; this lane does not replace them. The
same failure taxonomy and human authority boundary apply. See
`${CLAUDE_PLUGIN_ROOT}/contracts/CLAUDE_LANE_CONTRACT.md`.

## Failure taxonomy and escalation

After a failed attempt, the architect classifies it before rerouting:

- `SPEC_FAILURE`: requirements, files, interfaces, constraints, or verification
  were wrong/incomplete. Correct the spec; do not reward ambiguity with a more
  expensive model.
- `IMPLEMENTATION_FAILURE`: the spec was adequate but the lane failed to satisfy
  it. Retry only when new evidence or a corrected instruction changes the odds.
- `TASK_MISCLASSIFICATION`: the task required more or less judgment than the
  selected lane.

For Luna, inspect whether the task was underspecified or actually required
ordinary judgment; if so, correct the spec or deliberately route Terra.

For Terra, the first failure triggers diagnosis and a corrected spec when
needed. Terra failing again under a corrected, adequate spec is evidence for a
possible Sol escalation. This is a judgment rule, not an automatic retry count.
There is no automatic "one failure means stronger model" rule.

## Workflow modes

### FAST

For mechanical, low-risk, obvious, fully specified work:

`Architect -> Luna -> actual diff -> deterministic verification -> Architect acceptance`

Add clean-context review when the risk or change warrants it.

### STANDARD

For most software engineering work:

`Architect -> Evidence Explorer when needed -> Luna or Terra -> deterministic verification -> clean-context review -> Architect verdict`

### CRITICAL

For Production incidents, billing, auth, security, migrations, storage,
concurrency, release infrastructure, destructive operations, or similarly high
blast radius:

`Architect -> Evidence phase -> root-cause verdict -> Terra or Sol -> deterministic verification -> adversarial/fresh-context review -> exact-SHA staging readiness -> Human authorization`

CRITICAL never ends because the implementation model reports PASS. Staging or a
Production canary also requires explicit user authorization; without it, stop at
`READY_FOR_STAGING` or `READY_FOR_PRODUCTION_CANARY`.

## Independent verification and review

Before accepting work, the architect must:

1. identify the lane's actual delta relative to its baseline, and confirm the
   protected local-state guard reported `unchanged`;
2. read the diff and check allowed files/interfaces/constraints;
3. independently execute every deterministic verification command;
4. reconcile failures or differences with the implementer's report;
5. request `fable-advisor` review for STANDARD/CRITICAL work and risk-selected
   FAST work; and
6. issue its own verdict.

The advisor reads goal, spec, actual diff, verification evidence, lane choice,
and authority boundaries in a fresh context. Its same-family status must remain
explicit. For high-risk changes, use a genuinely cross-family adversarial review
when available, then pass those findings to the clean-context reviewer.

Reviewer availability is an explicit runtime capability. A review counts only
when `${CLAUDE_PLUGIN_ROOT}/scripts/run-clean-context-review.sh` returns
`STATUS: AVAILABLE`, observable Fable model resolution, captured JSON transport,
and a consumable `VERDICT`. Otherwise report `REVIEWER_UNAVAILABLE`; STANDARD or
CRITICAL work must not claim clean-context review completed, and CRITICAL work
must not advance to `READY_FOR_PRODUCTION_CANARY` by default. Never silently skip
the reviewer.

Independent specs may run in parallel only when they share no files, state, or
ordering dependency. Never race two write-capable lanes against the same working
tree. Use separate isolated worktrees if a deliberate comparative implementation
is explicitly authorized.

## Human authority boundary

Agents must not infer authorization for any of the following from vague requests
such as "fix it", "push this forward", or "handle the Production issue":

- merge to main;
- Production deploy or migration;
- Production database mutation;
- Production billing mutation;
- Production feature-flag enablement;
- destructive storage operation; or
- irreversible external operation.

Only `HUMAN_RELEASE_AUTHORITY` can authorize those acts explicitly. Agents may
prepare evidence and report `READY_FOR_STAGING` or
`READY_FOR_PRODUCTION_CANARY`; neither status authorizes execution.

## Optional Codex plugin integration

The official Codex plugin for Claude Code is optional. Its review commands can
add a cross-family check, and its setup command can diagnose an unavailable
binary. It does not replace the explicit lanes, actual-diff inspection,
independent verification, or human authority boundary. Any rescue command that
changes model or effort is an explicit reroute and must be reported as such.

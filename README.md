# AI Development Orchestrator V1

**Plan with the best available reasoning model.**

**Execute with the cheapest model that can reliably satisfy the spec.**

**Escalate only when material judgment remains.**

Investigate evidence before editing when the root cause is uncertain. Verify
actual evidence independently. Use fresh-context review before high-risk work
ships. Human authorization owns Production.

<a href="https://github.com/DannyMac180/fable-advisor/raw/main/assets/fable-advisor-demo.mp4"><img src="assets/fable-advisor-demo-poster.png" alt="Fable advisor orchestration demo" width="100%"></a>

This is an additive evolution of
[fable-advisor](https://github.com/DannyMac180/fable-advisor) by Dan McAteer. It
preserves the lightweight Claude Code plugin + agents + orchestration skill
architecture. V1 is policy, prompts, and contracts for long-lived software
development—not a new agent platform.

## Attribution and package identity

Upstream `fable-advisor` is the origin of this work. Its MIT
[`LICENSE`](LICENSE) and copyright are preserved unchanged, the original agent
filenames and skill layout are kept for low-conflict syncing, and the demo asset
above is upstream's.

This fork ships under its own package identity so it can never collide with
upstream installs, updates, or future releases:

| | Upstream | This fork |
|---|---|---|
| Plugin name | `fable-advisor` | `ai-dev-orchestrator` |
| Marketplace name | `fable-advisor` | `ai-dev-orchestrator` |
| Owner / author | Dan McAteer | Djackey |
| Homepage | `DannyMac180/fable-advisor` | `Djackey/ai-dev-orchestrator` |
| Version line | 5.x | starts at `0.1.0` |

Fork versions are independent and deliberately restart at `0.1.0`; they are not
a continuation of upstream's 5.x series and carry no compatibility claim about
it. The `fable-advisor` name survives only as the *agent* filename for the
clean-context reviewer role, which keeps upstream merges small.

## Architecture

The workflow uses abstract roles so model defaults can change without rewriting
the doctrine:

| Role | Current default | Component | Purpose |
|---|---|---|---|
| `ARCHITECT_FRONTIER` | Fable 5.1 session | current session | requirements, decomposition, architecture, routing, verdicts |
| `EVIDENCE_EXPLORER` | GPT-5.6 Terra | `evidence-explorer` | read-only exploration and evidence synthesis |
| `IMPLEMENTER_MECHANICAL` | GPT-5.6 Luna | `codex-implementer` | spec-determined implementation |
| `IMPLEMENTER_BALANCED` | GPT-5.6 Terra | `terra-implementer` | ordinary software engineering with local judgment |
| `IMPLEMENTER_FRONTIER` | GPT-5.6 Sol | `sol-implementer` | high-risk, judgment-heavy escalation |
| `IMPLEMENTER_CLAUDE` | Claude Sonnet 5, provisional default implementer (candidate lane) · Opus 5 escalation | `scripts/run-claude-lane.sh` (headless, restricted) | spec-determined implementation in the Claude family, restricted headless |
| `VISUAL_IMPLEMENTER` | Claude Opus, optional | not shipped in V1 | visual/UX and Claude-ecosystem work after runtime pin evidence is reliable |
| `CLEAN_CONTEXT_REVIEWER` | Fable 5.1 | `fable-advisor` | fresh-context, assumption-reset review |
| `HUMAN_RELEASE_AUTHORITY` | the user | explicit decision | Production authorization |

These are current defaults, not architecture. Fable can move to Astra or a newer
frontier architect; Luna, Terra, and Sol can move to newer implementers. The
contracts and routing rule stay the same.

The reviewer and current architect are in the same model family. Clean context
is useful, but it is not a cross-family independent review. The optional Opus
role is also same-vendor and cannot supply that independence.

## Routing: judgment remaining after the spec

1. Does the spec essentially determine one implementation?
   `IMPLEMENTER_MECHANICAL` / Luna.
2. If not, is the remaining work ordinary engineering judgment with controlled
   error cost and blast radius? `IMPLEMENTER_BALANCED` / Terra.
3. If material judgment is high-risk or wide-blast-radius,
   `IMPLEMENTER_FRONTIER` / Sol.

Do not route by file count, token count, model price, or the user's word
"important". Sol is not the default implementer.

| Mechanical / Luna | Balanced / Terra | Frontier / Sol |
|---|---|---|
| rename, repetitive edit, CRUD, wiring, config/docs, pattern-matched tests, schema/type propagation | multi-file feature, architecture integration, moderate debugging, persistence/recovery, API + frontend interaction, local refactor judgment | subtle concurrency, billing, auth/security, migration, distributed state, hard debugging, races, release infrastructure, wide-blast-radius refactor |

After failure, the architect first distinguishes `SPEC_FAILURE`,
`IMPLEMENTATION_FAILURE`, and `TASK_MISCLASSIFICATION`. Luna can move to Terra
when ordinary judgment was misclassified. Terra gets a corrected spec when the
spec was wrong; failure again under an adequate corrected spec may justify Sol.
There is no automatic "one failure means stronger model" rule.

## Evidence first

Two kinds of work start with
[`EVIDENCE_FIRST_SPEC`](contracts/EVIDENCE_FIRST_SPEC.md): reactive Production
incidents and hard debugging whose root cause is unproven, and proactive
high-risk change in billing, auth, security, concurrency, migrations,
distributed state, storage, and release infrastructure. The `evidence-explorer`
runs Terra under Codex `read-only` sandbox and separates:

- direct `OBSERVED` evidence;
- `INFERRED` conclusions;
- `UNRESOLVED` questions;
- root-cause confidence; and
- the next evidence most likely to change the verdict.

The evidence spec deliberately contains no implementation file list. An
evidence-first task creates an
[`IMPLEMENTATION_SPEC`](contracts/IMPLEMENTATION_SPEC.md) only after the
architect records `EVIDENCE_GATE_SATISFIED`, and two paths reach that gate:

```text
incident / defect / debugging
  evidence -> ROOT_CAUSE_CONFIRMED -> EVIDENCE_GATE_SATISFIED -> IMPLEMENTATION_SPEC

proactive high-risk change
  evidence / architecture / invariants / safety case
                           -> EVIDENCE_GATE_SATISFIED -> IMPLEMENTATION_SPEC
```

A defect owes a root cause, or an explicit bounded risk acceptance. A new
migration, auth, billing, or concurrency feature has no defect to explain, so it
owes evidence, invariants, authority boundaries, forbidden actions, a write
threshold, and stop conditions instead — never a fabricated root cause.

The gate is scoped to evidence-first work. Ordinary feature, refactor, and
change work needs only a sufficiently determined implementation direction. Not
every implementation requires `ROOT_CAUSE_CONFIRMED`.

## Workflow modes

- **FAST:** Architect → Luna → actual diff → verification → Architect acceptance.
  Add fresh-context review when risk warrants it.
- **STANDARD:** Architect → evidence when needed → Luna or Terra → deterministic
  verification → clean-context review → Architect verdict.
- **CRITICAL:** Architect → evidence → root-cause verdict → Terra or Sol →
  deterministic verification → adversarial/fresh-context review → exact-SHA
  staging readiness → explicit human authorization.

CRITICAL work never finishes because an implementer says PASS.

## Lane contract

All Codex-backed implementers use the shared
[`IMPLEMENTATION_LANE_CONTRACT`](contracts/IMPLEMENTATION_LANE_CONTRACT.md):

- explicit model and per-task effort, with observable runtime resolution;
- no silent fallback or effort rounding;
- `workspace-write` sandbox narrowed to the workdir, so `/tmp` and `$TMPDIR`
  stay outside it and guard baselines cannot be rewritten by the model;
- portable bash/zsh timeout construction, with no uncapped retry;
- unique prompt/transcript/final files;
- actual task-delta inspection and an empty-diff refusal guard;
- a protected local-state guard over sensitive ignored paths;
- independent verification re-run; and
- structured reports.

Reports are claims, not evidence. The orchestrator inspects the diff and runs
verification itself. The evidence lane applies the same resolution discipline
with `read-only` sandbox and a pre/post workspace-mutation check.

### Protected local state

The worktree content baseline covers tracked and nonignored untracked files, and
deliberately does not scan the ignored tree or `node_modules`. A short explicit
list is guarded separately by
[`scripts/protected-paths.rb`](scripts/protected-paths.rb): `.env`, `.env.*`,
`.claude/settings.local.json`, `.codex/`, `.npmrc`, plus any repository-relative
glob a project declares in `.ai-orchestrator-protected-paths`. Existence, type,
mode, and content hash are compared before and after every lane. The guard state
lives outside everything the model can write, which is why the lane contract
excludes `/tmp` and `$TMPDIR` from `workspace-write` and requires the startup
summary to read `sandbox: workspace-write [workdir]`.

Any change is a violation by default and forces `STATUS: refused`, so an
implementer cannot make verification pass by editing local secrets or local tool
configuration, and cannot widen its own room by editing the protected-path list.
A task that genuinely needs a local ignored-config change stops and reports it;
only explicit human or architect authorization handles it, as separate work.

Clean-context review is also resolved at runtime. Only an `AVAILABLE` capability
report with captured Fable `modelUsage` and a consumable verdict counts as a
completed review; `REVIEWER_UNAVAILABLE` is never silently skipped.

## Model availability is a runtime boundary

The repository records defaults, never guarantees account access. Every lane
starts with a working-binary/auth check, requests its model explicitly, and
requires the Codex startup summary to show the requested model, effort, and
sandbox. Unavailable or unobservable resolution fails loudly; Terra never
silently becomes Luna, Sol never becomes Terra, and Codex never silently becomes
Claude.

Claude Code accepts `model:` frontmatter aliases, but an unavailable pinned
Claude model can silently fall back. A normal nested-agent report does not expose
enough metadata to prove the resolved model. V1 therefore keeps the existing
Fable advisor pin with an explicit warning and does not ship the optional Opus
write lane yet. See the dated [capability audit](docs/CAPABILITY_AUDIT.md).

The `model: sonnet` frontmatter on Codex implementers selects their lightweight
Claude supervisor. Luna/Terra/Sol are selected only by the captured `codex exec`
invocation.

## Claude implementation lane — provisional default implementer (candidate lane)

`IMPLEMENTER_CLAUDE` runs `scripts/run-claude-lane.sh`, a headless
`claude -p --restricted` invocation with an explicit tool allowlist and deny
list, plus the same `worktree-delta.rb` / `protected-paths.rb` guards used by
the Codex lanes. Calibration completed 2026-09-04: of the specs run through
`run-claude-lane.sh` itself, every one that finished reached
`complete-candidate` and was accepted by the architect after independent
verification (one run was separately halted mid-task by an account usage
limit — a transport failure, not a rejection — and completed in a follow-up
session), so `claude-sonnet-5` is the **provisional** default implementer
(candidate lane) and `claude-opus-5` the escalation lane; provisional means
reviewed again on every later PR and never a long-term proof of capability.
The record is in `acceptance/ACCEPTANCE_EVIDENCE.md`. The Codex lanes remain the independent,
cross-family capability; this lane does not replace them. The same failure
taxonomy and human authority boundary apply. See
[`contracts/CLAUDE_LANE_CONTRACT.md`](contracts/CLAUDE_LANE_CONTRACT.md).

### Running the lane

`scripts/run-claude-lane.sh` requires POSIX `sh`, `python3` (for the model-map
validation) and `ruby` (for the two guards and the result parser) on `PATH`,
and fails closed if either interpreter is missing. `scripts/probe-model-map.sh`
requires `sh` and `python3` only, no `ruby`. `scripts/parse-lane-result.rb`,
`scripts/worktree-delta.rb`, and `scripts/protected-paths.rb` require `ruby`
only. `mktemp -t`, as used by the runner and the probe, targets both macOS and
GNU `mktemp`.

The runner refuses to run from inside `WORKDIR`: it compares the physical path
of its own checkout against the physical path of `WORKDIR` and reports
`unavailable`/`GUARD_FAILED` if they coincide or the checkout is nested inside
`WORKDIR`, since a self-editing runner or parser could otherwise execute or
parse a half-written version of itself mid-run. When a spec's own task is to
edit these lane scripts, invoke the runner from a checkout other than the
`WORKDIR` being edited.

`--allow-bash` prefixes are charset-checked, must start with a bare program
name (no path, wrapper or environment assignment), and a `git` prefix must
name a read-only subcommand (`status`, `diff`, `log`, `show`, `ls-files`,
`rev-parse`, `blame`, `grep`). This is a lint on what the architect types,
not a sandbox: trailing arguments and programs of other names are not
inspected (see the contract's residual gaps).

Shell-script execution (`sh`, `bash`, `zsh`) is not available inside this
lane's own `--restricted` boundary; a spec whose verification is a shell test
suite must say the architect runs it, not the implementer.

## Human authority boundary

"Fix it", "push this forward", and "handle the Production issue" do not
authorize any agent to:

- merge main;
- deploy or migrate Production;
- mutate a Production database or billing system;
- enable a Production feature flag;
- perform a destructive storage operation; or
- perform another irreversible external operation.

Agents may report `READY_FOR_STAGING` or `READY_FOR_PRODUCTION_CANARY`. The user
must explicitly authorize the next external action.

## Install for local review

This V1 is not published. Validate or load the checkout directly:

```sh
claude plugin validate --strict .
claude --plugin-dir .
```

The Codex lanes resolve an explicit `AI_ORCHESTRATOR_CODEX_BIN` first, otherwise
`codex` from PATH, and validate executable/version/auth before use. An explicit
invalid binary never falls back to PATH, and a broken PATH shim is unavailable.
For a non-default installation, configure it explicitly for the session:

```sh
export AI_ORCHESTRATOR_CODEX_BIN=/path/to/working/codex
```

Account access to a model does not repair a broken PATH entry or native binary.

## Validation

The repository intentionally uses lightweight contract tests:

```sh
./scripts/validate-contracts.sh
```

They validate manifests and independently parse frontmatter, agent/contract references, current role
mapping, routing invariants, timeout argument construction under bash and zsh,
fallback/empty-diff/verification guards, the evidence read-only boundary, the
human authority boundary, and unwanted automatic Production paths.

## Upstream sync

This fork retains the upstream layout, license, assets, and the three original
agent filenames. It deliberately does **not** retain the upstream plugin or
marketplace name; see [Attribution and package identity](#attribution-and-package-identity). Intentional doctrine changes are concentrated in
`README.md`, `skills/orchestration/SKILL.md`, and the three upstream agent files;
new roles and contracts are additive.

For future updates, fetch `upstream`, review `upstream/main`, then use the team's
normal merge or rebase policy. Expect the highest conflict probability in the
README, orchestration skill, and Luna/Sol agent prompts. Resolve only intentional
doctrine differences; keep new contracts and agents additive. Do not delete or
broadly rename upstream files.

## License

MIT. The upstream [`LICENSE`](LICENSE) and its copyright notice are preserved
unchanged; this fork adds no separate license terms.

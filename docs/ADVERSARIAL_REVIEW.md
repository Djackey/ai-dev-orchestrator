# Adversarial Self-review — V1

Performed against the complete working-tree change before handoff.

1. **Could fully specified work be routed to Sol?** The two-question router sends
   uniquely determined work to the mechanical lane, and Sol must report
   `TASK_MISCLASSIFICATION` for routine work.
2. **Could risky work be routed to Luna?** Luna explicitly refuses Production
   incidents, concurrency, billing, auth/security, distributed state, and
   ambiguous wide refactors. Uncertain high-risk work begins with evidence.
3. **Could the evidence phase write?** The Terra producer is invoked with Codex
   `read-only` sandbox; the Claude wrapper exposes no Write/Edit tools, is
   forbidden to mutate, and a deterministic content baseline checks tracked and
   nonignored untracked files afterward. Real dogfood returned `STATUS: empty`
   and matching pre/post hashes. Ignored paths are not hash-inventoried apart
   from the explicitly enumerated protected local state (`.env`, `.env.*`,
   `.claude/settings.local.json`, `.codex/`, `.npmrc`, plus project-declared
   globs); for every other ignored path Codex's OS sandbox is the actual write
   boundary. Residual gap: the
   wrapper needs Bash to start Codex, and
   prompt-level Bash restrictions are not a cryptographic capability boundary.
   A future hook or narrowly scoped runner could harden this, but V1 deliberately
   does not add a runtime.
4. **Could unavailable Luna silently fall back?** No. Working-binary/auth/model/
   effort/resolution checks loud-fail, and the lane cannot select another model.
5. **Could unavailable Terra silently fall back?** No. The balanced and evidence
   lanes have the same loud-failure rule; neither maps Terra to Luna/Sol/Claude.
6. **Could a Claude model pin produce a false model report?** A normal nested
   report cannot prove runtime resolution. The reviewer runner therefore parses
   outer CLI JSON, requires exactly one Fable `modelUsage` entry, and rejects an
   unobservable or multi-model result. V1 still withholds the optional Opus
   write lane because no equivalent write-lane proof is implemented.
7. **Could exit zero plus empty diff pass?** Initial real dogfood showed that a
   prompt-only instruction was insufficient: Luna claimed it updated an already
   correct file. The fixed contract takes a deterministic content baseline;
   helper exit 3 / `STATUS: empty` overrides exit zero, passing tests, and model
   prose. The same no-op was rerun and correctly returned `STATUS: refused`.
8. **Could claimed test success pass without an orchestrator rerun?** No. All
   implementation reports are claims; the orchestrator independently runs every
   deterministic verification command before acceptance.
9. **Could "fix Production" authorize deployment?** No. The Human Authority
   Boundary explicitly rejects that inference and limits agents to readiness
   reports until the user authorizes an exact next action.
10. **Will the next upstream Luna update create avoidable conflicts?** Original
    agent filenames and responsibilities remain. The timeout/resolution/report
    changes necessarily touch Luna/Sol prompts, while Terra, Evidence, and
    contracts are additive. README and orchestration doctrine are intentional
    conflict hotspots. No broad rename or deletion was introduced.

Additional finding fixed during review: agent references to shared contracts now
resolve through `${CLAUDE_PLUGIN_ROOT}` rather than assuming the user's project
contains this plugin's `contracts/` directory.

Additional finding fixed during validation: Claude CLI manifest validation
returned no component inventory, so it did not catch invalid YAML introduced by
plain descriptions containing `: `. Luna/Sol descriptions now use YAML block
scalars, and an independent parser validates every agent and the skill.

Additional dogfood finding: Fable twice emitted a noncanonical `LANE` value in
an implementation spec even after the design was settled. The orchestrator did
not delegate it: it classified the output as `SPEC_FAILURE` and required an
explicit correction to `IMPLEMENTER_MECHANICAL`. V1 intentionally keeps this as
an architect-owned semantic contract rather than adding a workflow engine or
model gateway.

Final clean-context review triggered four small hardening edits: the bash/zsh
timeout test now extracts the marked argv block from the real contract instead
of copying it and anchors its working directory, an uncapped run must appear in
report `GAPS`, and ignored-path limits of the content guard are explicit.

## Independent review round two — 2026-09-04

An independent review returned four `FIX_FIRST` findings against the Draft PR.
All four were accepted and fixed on the same branch.

11. **Could the fork collide with upstream `fable-advisor`?** It could. The
    manifests still carried upstream's plugin name, marketplace name, owner,
    homepage, and a 5.1.0 version in upstream's own release line. Fixed: the
    package identity is now `ai-dev-orchestrator` at `0.1.0` under the fork's
    owner and homepage, validated by `scripts/validate-contracts.sh`. Upstream
    attribution, the MIT `LICENSE` and its copyright, agent filenames, and the
    skill layout are unchanged, so upstream syncs stay small.
12. **Could a mentioned verdict be read as a verdict?** It could. The parser
    accepted any `VERDICT: ACCEPT` substring, so a quoted schema line or a
    sentence discussing a verdict would satisfy it. Fixed: exactly one
    standalone, line-anchored verdict is required; zero and two or more both
    fail closed (`OUTPUT_NOT_CAPTURED` / `VERDICT_AMBIGUOUS`), and the accepted
    value is echoed as `PARSED_VERDICT`. Seven deterministic cases cover valid
    ACCEPT/FIX_FIRST/RETHINK, no verdict, quoted/non-line verdict, duplicate
    verdicts, and conflicting verdicts. The `modelUsage` and permission-denial
    gates are unchanged.
13. **Did the contracts demand a root cause for greenfield work?**
    `IMPLEMENTATION_SPEC` opened with "use only after the root cause ... are
    sufficiently determined", which reads as a universal precondition. Fixed:
    ordinary feature/refactor/change work needs only a sufficiently determined
    implementation direction; the `ROOT_CAUSE_CONFIRMED` threshold is stated as
    a property of incident/debugging work and the `EVIDENCE_FIRST_SPEC` risk
    domains. `EVIDENCE_FIRST_SPEC` semantics are not relaxed.
14. **Could an implementer pass verification by editing ignored local state?**
    It could. The content baseline never sees ignored paths. Fixed with a
    minimal protected-local-state contract (`scripts/protected-paths.rb`) over
    `.env`, `.env.*`, `.claude/settings.local.json`, `.codex/`, `.npmrc`, and
    globs a project declares in `.ai-orchestrator-protected-paths`. It compares
    existence, type, mode, and content hash before and after each lane; any
    change is a violation that forces `STATUS: refused`. It deliberately does
    not scan the ignored tree: `node_modules` and `.git` are excluded outright,
    an oversized inventory fails loudly instead of walking a tree, and dropping
    a declared pattern cannot shrink coverage because `check` unions baseline
    and current patterns. The guard is never automatically relaxed; a genuine
    local ignored-config change requires explicit human or architect
    authorization as separate work.

15. **Could a guarded lane rewrite the guard's own baseline?** It could, until
    the fresh-context review of this round caught it. Current Codex
    `workspace-write` grants `[workdir, /tmp, $TMPDIR]`, and `mktemp` writes the
    delta and protected-state baselines into `$TMPDIR`, so a lane could edit a
    protected path and then restore the baseline JSON. Fixed in the marked argv
    contract with `-c sandbox_workspace_write.exclude_tmpdir_env_var=true` and
    `-c sandbox_workspace_write.exclude_slash_tmp=true`, verified live: the
    startup summary changes from `workspace-write [workdir, /tmp, $TMPDIR]` to
    `workspace-write [workdir]`. Because an older CLI could ignore an unknown
    `-c` key, that exact line is now required startup evidence; a writable
    `/tmp` or `$TMPDIR` makes the run `unavailable` rather than `complete`. The
    deterministic bash/zsh argv test extracts the same block, so test and
    contract cannot drift.

16. **Could the reviewer runner reach upstream's agent instead of this fork's?**
    The runner asked for a bare `--agent fable-advisor`, which is exactly the
    name both packages share. It now asks for
    `ai-dev-orchestrator:fable-advisor`, verified live to resolve
    `claude-fable-5-1` under `--plugin-dir`, and the parser reports the
    namespaced identity. This is the last place the fork's identity fix had to
    reach.
17. **Could a malformed reviewer payload slip past the gates?** A JSON `null`
    for `modelUsage` or `permission_denials` previously raised inside the parser:
    still non-zero, but without a structured classification. Both fields are now
    type-checked. An absent `permission_denials` stays tolerated for older CLI
    payloads; a present-but-malformed one is `OUTPUT_NOT_CAPTURED`, and a
    non-object `modelUsage` is `MODEL_UNRESOLVED`. Three cases were added.

Residual gap recorded, not closed: `.git` and `node_modules` are excluded from
the protected inventory so the guard stays a short list rather than a tree scan.
`.git/hooks` is therefore a blind spot shared with the worktree content baseline,
and the Codex sandbox remains its only boundary. Closing it needs a separate,
deliberately scoped change rather than widening this guard.

## Contract correction round three — 2026-09-04

The last contract correction before merge. Two findings, no new roles, models,
workflow modes, runtimes, or frameworks.

18. **Did the evidence gate demand a root cause that cannot exist?** It did.
    `EVIDENCE_FIRST_SPEC` covers two different kinds of work — reactive
    incidents, defects, and debugging, and proactive high-risk change in
    billing, auth, security, concurrency, migrations, distributed state,
    storage, and release infrastructure — but a single exit condition,
    `ROOT_CAUSE_CONFIRMED`, was written for both. A new migration or auth
    feature has no defect, so the contract was asking for a fabricated root
    cause or an unnecessary risk acceptance. Fixed by naming the abstraction:
    the exit condition is now `EVIDENCE_GATE_SATISFIED`, reached through
    `ROOT_CAUSE_CONFIRMED` for reactive work (or an explicit bounded risk
    acceptance) and through sufficient `OBSERVED_EVIDENCE`, `INVARIANTS`,
    `AUTHORITY_BOUNDARIES`, `FORBIDDEN_ACTIONS`,
    `EVIDENCE_REQUIRED_BEFORE_WRITE`, and `STOP_CONDITIONS` for proactive
    work. The evidence requirement itself is not relaxed in either direction:
    the proactive path may not be used to excuse a reactive task from a root
    cause it owes. `tests/evidence-gate-contract.sh` enforces the semantics
    across ten normative files and fails on a universal or unscoped
    `ROOT_CAUSE_CONFIRMED` claim, on the retired wording, and on
    `IMPLEMENTATION_SPEC` gating on the reactive path instead of the gate.
19. **Could a fenced verdict still be consumed?** It could, and it had been:
    an earlier real reviewer reply put its whole report — verdict included —
    inside a ```text block, and the parser accepted it. A schema template, a
    quoted example, or an illustrative block would therefore have been read as
    a real verdict. Fixed: the parser now tracks ``` and ~~~ fence state
    line-by-line with no third-party library, ignores everything inside a fence
    (an unterminated fence swallows the rest, which fails closed), and requires
    `^VERDICT:` at the start of an unindented line. Blockquoted and indented
    verdicts are rejected by the same anchor. `agents/fable-advisor.md` was
    corrected in the same pass: its header template no longer contains the
    verdict line, and the reviewer must end its reply with the verdict outside
    every fence. A real smoke run confirmed the live agent now emits a fenced
    header and an unfenced `VERDICT: ACCEPT`.

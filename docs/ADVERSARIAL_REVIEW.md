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
   and matching pre/post hashes. Existing ignored paths are not hash-inventoried;
   Codex's OS sandbox is the actual write boundary for them. Residual gap: the
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
report `GAPS`, and ignored-path limits of the content guard are explicit. The
fork manifest also advanced from upstream 5.0.0 to the unpublished 5.1.0
version.

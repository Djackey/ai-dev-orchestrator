# EVIDENCE_FIRST_SPEC

This contract covers two different kinds of work:

- **Reactive** — a Production incident, defect, or debugging task where the root
  cause is uncertain.
- **Proactive high-risk change** — new or changed billing, auth, security,
  concurrency, migration, distributed-state, storage, or release-infrastructure
  work, where nothing is broken but a mistake is expensive.

Both enter through this contract. They do not leave it the same way.

```text
EVIDENCE_FIRST_SPEC

GOAL
<decision the investigation must support>

OBSERVED_EVIDENCE
<known facts with source/provenance>

HYPOTHESES
<competing explanations; include disconfirming tests>

INVARIANTS
<properties that must remain true>

AUTHORITY_BOUNDARIES
<what the investigator and later implementer may authorize>

FORBIDDEN_ACTIONS
<writes, deployments, mutations, or external effects that are prohibited>

EVIDENCE_REQUIRED_BEFORE_WRITE
<minimum proof needed before an implementation spec may exist>

STOP_CONDITIONS
<conditions requiring an unresolved report or human decision>
```

Do not name implementation `FILES` during the evidence phase. An error string is
not a root cause.

## Exit condition: EVIDENCE_GATE_SATISFIED

A task leaves this contract only when the architect explicitly records
`EVIDENCE_GATE_SATISFIED`. That record is the sole precondition for issuing an
[`IMPLEMENTATION_SPEC`](IMPLEMENTATION_SPEC.md) from evidence-first work, and it
is reached by one of two paths.

**Reactive work — incident, defect, debugging.** `ROOT_CAUSE_CONFIRMED` is a
necessary condition for `EVIDENCE_GATE_SATISFIED`. The only exception is an
explicit, bounded, documented exceptional risk acceptance that states what
remains unresolved and stays inside the human authority boundary.
`SUPPORTED_HYPOTHESIS` is not `ROOT_CAUSE_CONFIRMED`.

**Proactive high-risk change.** There is no defect, so there is no root cause to
confirm, and none may be invented. `EVIDENCE_GATE_SATISFIED` instead requires
that `OBSERVED_EVIDENCE`, `INVARIANTS`, `AUTHORITY_BOUNDARIES`,
`FORBIDDEN_ACTIONS`, `EVIDENCE_REQUIRED_BEFORE_WRITE`, and `STOP_CONDITIONS` are
each established well enough to carry the change — the architecture, the
invariants that must survive it, and the safety case are the evidence.

```text
incident / defect / debugging
  evidence -> ROOT_CAUSE_CONFIRMED -> EVIDENCE_GATE_SATISFIED -> IMPLEMENTATION_SPEC

proactive high-risk change
  evidence / architecture / invariants / safety case
                           -> EVIDENCE_GATE_SATISFIED -> IMPLEMENTATION_SPEC
```

Never demand a fabricated root cause from proactive work, and never treat the
absence of one as grounds to withhold the gate. Equally, never let the proactive
path be used to skip a root cause that a reactive task actually owes.

This gate is a property of evidence-first work, not a universal precondition for
every implementation spec; ordinary feature work is governed by
[`IMPLEMENTATION_SPEC`](IMPLEMENTATION_SPEC.md) alone.

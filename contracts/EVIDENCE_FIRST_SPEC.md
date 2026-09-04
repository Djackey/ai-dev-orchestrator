# EVIDENCE_FIRST_SPEC

Use when the root cause is uncertain or the work touches Production incidents,
billing, auth, security, concurrency, migrations, distributed state, storage,
or release infrastructure.

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
not a root cause. Only after the architect records `ROOT_CAUSE_CONFIRMED`, or
explicitly documents an exceptional risk acceptance, may it issue an
`IMPLEMENTATION_SPEC`.

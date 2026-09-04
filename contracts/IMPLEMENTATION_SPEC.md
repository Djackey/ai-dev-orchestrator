# IMPLEMENTATION_SPEC

Use once the implementation direction is sufficiently determined.

For ordinary feature, refactor, and change work, "sufficiently determined" means
the objective, allowed files, interfaces, constraints, and deterministic
verification are settled enough that what remains is implementation rather than
investigation. There is no root cause to confirm when there is no defect to
explain, and this contract does not invent one.

For work that entered [`EVIDENCE_FIRST_SPEC`](EVIDENCE_FIRST_SPEC.md) — incident,
defect, and debugging tasks, and proactive high-risk changes in the domains that
contract lists — the evidence gate applies **in addition**: the architect must
first record `EVIDENCE_GATE_SATISFIED` before an implementation spec may exist.
That gate is not relaxed here.

How the gate is reached depends on the kind of work, and this contract does not
collapse the two:

- Incident, defect, and debugging work reaches it through
  `ROOT_CAUSE_CONFIRMED`, unless an explicit bounded risk acceptance is
  documented.
- Proactive high-risk change reaches it through sufficient `OBSERVED_EVIDENCE`,
  `INVARIANTS`, `AUTHORITY_BOUNDARIES`, `FORBIDDEN_ACTIONS`,
  `EVIDENCE_REQUIRED_BEFORE_WRITE`, and `STOP_CONDITIONS`. A new migration,
  auth, billing, or concurrency feature has no defect to explain; requiring a
  root cause there would only produce a fabricated one.

```text
IMPLEMENTATION_SPEC

OBJECTIVE
<one outcome>

LANE
<IMPLEMENTER_MECHANICAL | IMPLEMENTER_BALANCED | IMPLEMENTER_FRONTIER>

FILES
<exact paths allowed to change>

INTERFACES
<signatures, types, APIs, schemas, and compatibility requirements>

CONSTRAINTS
<project conventions, invariants, exclusions, and authority limits>

VERIFICATION
<deterministic commands and expected outcomes>

REASONING
<exact runtime-supported effort, or omit deliberately and record the gap>
```

The abstract role is normative. A model name belongs to the current mapping at
the lane boundary and can change without rewriting the spec.

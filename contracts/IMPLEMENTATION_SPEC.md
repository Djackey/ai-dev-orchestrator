# IMPLEMENTATION_SPEC

Use once the implementation direction is sufficiently determined.

For ordinary feature, refactor, and change work, "sufficiently determined" means
the objective, allowed files, interfaces, constraints, and deterministic
verification are settled enough that what remains is implementation rather than
investigation. There is no root cause to confirm when there is no defect to
explain, and this contract does not invent one.

For incident, defect, and debugging work — and for the risk domains listed in
[`EVIDENCE_FIRST_SPEC`](EVIDENCE_FIRST_SPEC.md) — the evidence threshold in that
contract applies **in addition**: the architect must first record
`ROOT_CAUSE_CONFIRMED`, or document an explicit bounded risk acceptance, before
an implementation spec may exist. That threshold is not relaxed here.

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

#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

command -v python3 >/dev/null 2>&1 || {
  printf 'FAIL: python3 unavailable for evidence-gate semantic checks\n' >&2
  exit 1
}

python3 - <<'PY'
import re
import sys
from pathlib import Path

# The normative doctrine surface. Dated records under docs/ and acceptance/ are
# deliberately excluded: they describe what was true when written.
NORMATIVE = [
    "contracts/EVIDENCE_FIRST_SPEC.md",
    "contracts/IMPLEMENTATION_SPEC.md",
    "skills/orchestration/SKILL.md",
    "README.md",
    "agents/evidence-explorer.md",
    "agents/sol-implementer.md",
    "agents/codex-implementer.md",
    "agents/terra-implementer.md",
    "agents/fable-advisor.md",
    "contracts/IMPLEMENTATION_LANE_CONTRACT.md",
]

GATE = "EVIDENCE_GATE_SATISFIED"
ROOT_CAUSE = "ROOT_CAUSE_CONFIRMED"
REACTIVE = ("incident", "defect", "debugging", "reactive")
NEGATION = ("not ", "never", " no ", "without")
UNIVERSAL = ("every", "all ", "any ")

failures = []
texts = {path: Path(path).read_text(encoding="utf-8") for path in NORMATIVE}


def fail(message):
    failures.append(message)


# 1. The gate exists on every surface that describes the evidence-first exit.
for path in (
    "contracts/EVIDENCE_FIRST_SPEC.md",
    "contracts/IMPLEMENTATION_SPEC.md",
    "skills/orchestration/SKILL.md",
    "README.md",
):
    if GATE not in texts[path]:
        fail(f"{path}: missing {GATE} as the evidence-first exit condition")

# 2. Both paths are documented, and neither is collapsed into the other.
for path in (
    "contracts/EVIDENCE_FIRST_SPEC.md",
    "skills/orchestration/SKILL.md",
    "README.md",
):
    text = texts[path]
    if f"{ROOT_CAUSE} -> {GATE}" not in text:
        fail(f"{path}: missing the reactive path `{ROOT_CAUSE} -> {GATE}`")
    if "proactive high-risk" not in text:
        fail(f"{path}: missing the proactive high-risk path into the gate")
    if not re.search(r"no root cause|never (invent|a fabricated)|not .{0,40}fabricat", text, re.I):
        fail(f"{path}: does not forbid inventing a root cause for proactive work")

# 3. IMPLEMENTATION_SPEC gates on the abstraction, not on the reactive path.
impl = texts["contracts/IMPLEMENTATION_SPEC.md"]
if not re.search(rf"must\s+first\s+record\s+`?{GATE}`?", impl):
    fail(f"contracts/IMPLEMENTATION_SPEC.md: the precondition must be a recorded {GATE}")
if re.search(rf"must\s+first\s+record\s+`?{ROOT_CAUSE}`?", impl):
    fail(f"contracts/IMPLEMENTATION_SPEC.md: {ROOT_CAUSE} must not be the unconditional precondition")

# 4. Regression guard: no sentence may assert that ROOT_CAUSE_CONFIRMED is
#    required for all evidence-first or all implementation work.
for path, text in texts.items():
    for sentence in re.split(r"(?<=[.;:])\s+|\n\n+", text):
        if ROOT_CAUSE not in sentence:
            continue
        # Normalize wrapping so "Not\nevery" still reads as a negation.
        lowered = " ".join(sentence.lower().split())
        if any(word in lowered for word in UNIVERSAL) and not any(
            word in lowered for word in NEGATION
        ):
            fail(f"{path}: universal {ROOT_CAUSE} claim: {' '.join(sentence.split())[:120]}")

# 5. Scoping guard: every paragraph asserting ROOT_CAUSE_CONFIRMED must name the
#    reactive scope it belongs to, or explicitly deny universality.
for path, text in texts.items():
    for paragraph in re.split(r"\n\s*\n", text):
        if ROOT_CAUSE not in paragraph:
            continue
        lowered = " ".join(paragraph.lower().split())
        if not any(word in lowered for word in REACTIVE) and not any(
            word in lowered for word in NEGATION
        ):
            fail(
                f"{path}: unscoped {ROOT_CAUSE} paragraph: "
                f"{' '.join(paragraph.split())[:120]}"
            )

# 6. The old universal wording must not return.
FORBIDDEN = (
    "Use only after the root cause",
    "Only after the architect records `ROOT_CAUSE_CONFIRMED` may it normally issue",
    "Once a task is inside this contract, only after the architect",
    "Evidence-first domains also require the architect's `ROOT_CAUSE_CONFIRMED`",
)
for path, text in texts.items():
    for phrase in FORBIDDEN:
        if phrase in text:
            fail(f"{path}: retired universal wording returned: {phrase}")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: evidence gate semantics across {len(NORMATIVE)} normative files")
print("PASS: reactive path requires ROOT_CAUSE_CONFIRMED")
print("PASS: proactive high-risk path reaches the gate without a root cause")
print("PASS: no universal or unscoped ROOT_CAUSE_CONFIRMED claim")
PY

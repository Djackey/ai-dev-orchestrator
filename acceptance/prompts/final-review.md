Perform the final read-only V1 Dogfood Acceptance review of this repository.

Read at minimum:

- README.md
- skills/orchestration/SKILL.md
- all files under agents/, contracts/, scripts/, tests/, docs/, and acceptance/
- .claude-plugin/plugin.json and .claude-plugin/marketplace.json

Judge only whether the current V1 is ready for a Draft PR. Attack these points:

1. explicit Codex binary resolution cannot be blocked by a broken PATH shim
   when the user provides a valid explicit binary;
2. invalid binary/auth/model/effort fail loudly with no model fallback;
3. Luna/Terra/Sol routing follows judgment remaining after the spec;
4. timeout argv is portable across bash/zsh and absence is honestly reported;
5. workspace-write/read-only sandboxes and reasoning effort are observable;
6. deterministic empty-diff and Evidence mutation guards override model prose;
7. implementer verification never replaces orchestrator verification;
8. Fable reviewer availability requires captured modelUsage and verdict, with
   every unavailable class loud;
9. same-family fresh-context review is not described as cross-family;
10. vague implementation authority cannot merge or mutate Production;
11. the fork's plugin/marketplace identity cannot collide with upstream
    `fable-advisor` installs, updates, or future versions, while upstream
    attribution, the MIT license and its copyright, agent filenames, and the
    skill layout are preserved;
12. the reviewer verdict parser accepts exactly one standalone verdict line and
    fails closed on zero, quoted, duplicate, or conflicting verdicts;
13. `IMPLEMENTATION_SPEC` does not require a root cause for ordinary feature
    work, while `EVIDENCE_FIRST_SPEC` semantics stay unrelaxed; and
14. the protected local-state guard covers `.env`, `.env.*`,
    `.claude/settings.local.json`, `.codex/`, `.npmrc`, and project-declared
    globs, treats any change as a violation, never scans the ignored tree or
    `node_modules`, and cannot be relaxed by the implementer.

Use the acceptance evidence as a record, not as a substitute for reading the
implementation. Do not edit. Return the exact REVIEW REPORT schema, naming any
blocker precisely, and end with `VERDICT: ACCEPT`, `VERDICT: FIX_FIRST`, or
`VERDICT: RETHINK` on its own final line, starting at the beginning of the line
and outside every fenced code block.

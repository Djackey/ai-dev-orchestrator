Perform a read-only clean-context acceptance review of the two blocker fixes.

Read these files:

- scripts/resolve-codex-bin.sh
- tests/codex-resolution-contract.sh
- scripts/run-clean-context-review.sh
- scripts/parse-review-result.rb
- tests/reviewer-contract.sh
- scripts/protected-paths.rb
- tests/protected-paths-contract.sh
- contracts/IMPLEMENTATION_LANE_CONTRACT.md
- agents/fable-advisor.md

Check only:

1. explicit Codex binary override wins over PATH without silent fallback;
2. executable, version, and auth checks fail loudly;
3. reviewer output proves the requested Fable model through modelUsage;
4. agent/model/transport/output/permission failures are distinguishable;
5. exactly one standalone verdict line is required, with zero, quoted, duplicate,
   and conflicting verdicts all failing closed;
6. the protected local-state guard forces refusal on any change to sensitive
   ignored paths without scanning the ignored tree; and
7. no Production authority was introduced.

Return the exact reviewer schema, including `VERDICT: ACCEPT`, `FIX_FIRST`, or
`RETHINK`. Cite concrete files. Do not modify anything.

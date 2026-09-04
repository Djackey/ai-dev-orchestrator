# Shared Implementation Lane Contract

This is the common behavioral contract for the Codex-backed implementation
lanes. The lane agent files add routing guidance and model defaults; they do not
weaken this contract.

## Inputs

An implementation delegation MUST use `IMPLEMENTATION_SPEC` and name an
abstract `LANE`. The current model mapping is resolved at the lane boundary, not
inside the business spec. `REASONING` is passed through exactly when present.

## Capability and resolution boundary

1. Resolve the executable with
   `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-codex-bin.sh`. An explicitly set
   `AI_ORCHESTRATOR_CODEX_BIN` is authoritative and is never replaced by PATH;
   otherwise resolve `codex` from PATH. The resolver requires an executable,
   successful `--version`, and successful `login status` before returning the
   candidate. A named path without a working binary is unavailable.
2. Invoke the explicitly requested model through the exact resolved executable.
   Never substitute another model or a Claude implementation.
3. Capture the Codex transcript. Before reporting success, require the startup
   summary to show the requested `model`, requested reasoning effort when one
   was supplied, and `sandbox: workspace-write`. If the installed CLI does not
   expose enough information to prove those properties, fail as `unavailable`
   rather than claim a model ran.
4. Treat authentication, model-access, unsupported-effort, and resolution
   errors as `unavailable`, preserving the exact error.

Model aliases and effort support are runtime capabilities. Documentation may
record observed defaults, but the current invocation is authoritative.

## Portable invocation

Create all prompt, transcript, and final-message files with `mktemp`; never use
a fixed path. Build optional arguments as positional parameters so both bash and
zsh preserve argument boundaries:

```sh
RESOLUTION_LOG=$(mktemp -t codex-resolution.XXXXXX)
if ! CODEX_BIN=$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-codex-bin.sh" 2> "$RESOLUTION_LOG"); then
  cat "$RESOLUTION_LOG"
  # Return structured unavailable; do not fall through to PATH/model fallback.
fi
cat "$RESOLUTION_LOG"

TIMEOUT_BIN=$(command -v gtimeout || command -v timeout || true)
```

The following marked block is the executable argv contract. The deterministic
timeout test extracts it directly so test and contract cannot drift:

<!-- CODEX_ARGV_CONTRACT_START -->
```sh
if [ -n "$TIMEOUT_BIN" ]; then
  set -- "$TIMEOUT_BIN" "$TIMEOUT_SECONDS" "$CODEX_BIN" --ask-for-approval never exec
else
  echo "WARN: no timeout binary; Codex runs uncapped"
  set -- "$CODEX_BIN" --ask-for-approval never exec
fi

set -- "$@" --model "$MODEL"
if [ -n "$EFFORT" ]; then
  set -- "$@" -c "model_reasoning_effort=$EFFORT"
fi
set -- "$@" \
  --sandbox workspace-write \
  --skip-git-repo-check \
  --cd "$(pwd)" \
  --output-last-message "$FINAL" \
  -
```
<!-- CODEX_ARGV_CONTRACT_END -->

```sh
CODEX_EXIT=0
"$@" < "$SPEC" > "$RUN_LOG" 2>&1 || CODEX_EXIT=$?
```

Never use `${T:+$T 600}` or an unquoted optional effort expansion. Never retry
without the timeout after a wrapper failure. Exit `124` is `timeout`; preserve
the transcript and inspect any partial diff. If no timeout binary exists, record
the uncapped run in `GAPS`; the warning must remain visible in the structured
report. Other non-zero exits are reported with their exact output.

## Evidence and acceptance

- Before invoking Codex, capture a content baseline outside the worktree with
  `ruby "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-delta.rb" snapshot "$DELTA_STATE" "$(pwd)"`,
  where `DELTA_STATE` is a unique `mktemp` path. After invocation, run the same
  helper with `check`. Exit `0` and `STATUS: changed` prove a delta; exit `3` and
  `STATUS: empty` MUST force `STATUS: refused`, regardless of exit zero, passing
  verification, or the model's final message. Any other exit is a guard failure
  and cannot produce `complete`.
- Read `git status --porcelain=v1 -uall` and `git diff --binary` before and after
  as human-readable evidence. The content baseline distinguishes task changes
  from a dirty starting tree and includes tracked plus nonignored untracked
  files. Existing ignored paths are outside this hash inventory; the Codex
  sandbox is their write capability boundary.
- Exit zero is not success. No task delta is `refused`, including a polite final
  message or a model that only analyzed the problem.
- Read the actual diff. The model's final message is a claim, not evidence.
- Independently re-run every deterministic command in `VERIFICATION`. Do not
  accept quoted test output from the model.
- A failing verification, partial diff, or missing required file cannot be
  `complete`.
- Do not commit, merge, deploy, mutate Production, or perform another external
  irreversible action.

## Report

```text
IMPLEMENTATION REPORT
LANE: <abstract role>
REQUESTED_MODEL: <exact model argument>
RESOLVED_MODEL_EVIDENCE: <startup-summary line or unavailable>
REASONING: <requested and observed value, or configured default/unverified>
STATUS: complete | partial | timeout | unavailable | refused
REASON: <exact failure/timeout/refusal reason, or none>
OBJECTIVE: <one line>
CHANGES: <file and summary, derived from the task delta>
VERIFIED: <commands independently re-run and actual outcomes>
MODEL_SAID: <one-line summary; explicitly note disagreement with evidence>
JUDGMENT_CALLS: <lane-specific decisions or none>
GAPS: <ambiguities, unfinished work, or none>
```

`STATUS: complete` is only a lane claim. The orchestrator still owns acceptance.

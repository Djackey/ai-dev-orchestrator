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
   was supplied, and a writable set limited to the workdir —
   `sandbox: workspace-write [workdir]`. A summary that still lists `/tmp` or
   `$TMPDIR` means the sandbox exclusions did not take effect on this CLI, the
   guard baselines and transcripts were writable by the model, and the run is
   `unavailable`, not `complete`. If the installed CLI does not expose enough
   information to prove those properties, fail as `unavailable` rather than
   claim a model ran.
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
  -c sandbox_workspace_write.exclude_tmpdir_env_var=true \
  -c sandbox_workspace_write.exclude_slash_tmp=true \
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
  files. Ignored paths are outside this hash inventory, except the explicitly
  enumerated protected local state below; for every other ignored path the Codex
  sandbox is the write capability boundary.
- Exit zero is not success. No task delta is `refused`, including a polite final
  message or a model that only analyzed the problem.
- Read the actual diff. The model's final message is a claim, not evidence.
- Independently re-run every deterministic command in `VERIFICATION`. Do not
  accept quoted test output from the model.
- A failing verification, partial diff, or missing required file cannot be
  `complete`.
- Do not commit, merge, deploy, mutate Production, or perform another external
  irreversible action.

## Protected local state

A lane must not be able to make verification pass by editing local secrets or
local tool configuration that the worktree content baseline does not see. The
guard is a short explicit list, never a scan of the ignored tree or
`node_modules`.

The guard is only load-bearing while its own baseline is outside everything the
model can write. `workspace-write` on current Codex defaults to
`[workdir, /tmp, $TMPDIR]`, and `mktemp` writes into `$TMPDIR`, so the argv
contract above excludes `/tmp` and `$TMPDIR` and the lane must confirm
`sandbox: workspace-write [workdir]` in the startup summary before trusting any
baseline, transcript, or final-message file. The same requirement protects the
worktree content baseline.

Around every Codex invocation, run the deterministic guard with a unique
`mktemp` state path outside the worktree:

```sh
PROTECTED_STATE=$(mktemp -t protected-state.XXXXXX)
ruby "${CLAUDE_PLUGIN_ROOT}/scripts/protected-paths.rb" snapshot "$PROTECTED_STATE" "$(pwd)"
# ... invoke Codex ...
PROTECTED_EXIT=0
ruby "${CLAUDE_PLUGIN_ROOT}/scripts/protected-paths.rb" check "$PROTECTED_STATE" "$(pwd)" || PROTECTED_EXIT=$?
```

The guard always covers `.env`, `.env.*`, `.claude/settings.local.json`,
`.codex/`, and `.npmrc`, plus any repository-relative glob a project declares in
the lightweight `.ai-orchestrator-protected-paths` file. Declared globs should
name specific paths: a broad `**/` pattern still walks the tree before the
inventory cap rejects it.

`.git` and `node_modules` are never inventoried, by declaration or by default,
so that the guard stays a short list rather than a tree scan. `.git/hooks` is
therefore a known blind spot shared with the worktree content baseline; the
Codex sandbox remains its only boundary. It compares existence,
type, mode, and content hash. Removing a declared pattern mid-task cannot shrink
coverage: `check` uses the union of the baseline and current patterns.

Exit `0` / `STATUS: unchanged` is the only acceptable result. Exit `4` /
`STATUS: violation` is `PROTECTED_STATE_VIOLATION`: it MUST force
`STATUS: refused`, regardless of exit zero, a passing verification, or the
model's final message, and the violated paths MUST be named in `REASON`. Any
other exit is a guard failure and cannot produce `complete`. Report the result
in `PROTECTED_STATE` either way.

A lane never relaxes this guard, never edits the protected-path configuration to
make its own run pass, and never treats a needed local-config change as implied
authority. When a task genuinely requires changing local ignored configuration,
the lane stops and reports it; only `HUMAN_RELEASE_AUTHORITY` or the architect
acting on explicit human authorization may approve it, and it is handled as a
separate, explicitly scoped change rather than folded into the implementation.

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
PROTECTED_STATE: unchanged | violation: <exact paths>
VERIFIED: <commands independently re-run and actual outcomes>
MODEL_SAID: <one-line summary; explicitly note disagreement with evidence>
JUDGMENT_CALLS: <lane-specific decisions or none>
GAPS: <ambiguities, unfinished work, or none>
```

`STATUS: complete` is only a lane claim. The orchestrator still owns acceptance.

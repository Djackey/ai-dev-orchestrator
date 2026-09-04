# Claude Implementation Lane Contract

This is the behavioral contract for the headless Claude implementation lane,
`scripts/run-claude-lane.sh`. It is the provisional default implementer
(candidate lane), not a replacement for the
Codex-backed lanes governed by
[`IMPLEMENTATION_LANE_CONTRACT.md`](IMPLEMENTATION_LANE_CONTRACT.md). Both
contracts share the same evidence discipline, guard mechanics, and human
authority boundary; this document only covers what differs about invoking
`claude -p` under a restricted execution boundary.

## Invocation boundary

The lane invokes `claude -p --restricted` with an explicit tool allowlist and a
deny list, never an ambient-trust or fully open session:

- The spec text is piped in on stdin (`< "$SPEC_FILE"`), never passed as a
  command-line argument, so it cannot be truncated by an argv length limit and
  never appears in a process listing.
- `--strict-mcp-config` is always passed alongside `--restricted`, so no
  ambient or project-discovered MCP server configuration is picked up; the
  lane never passes `--mcp-config`.
- `--setting-sources ""` is always passed alongside `--strict-mcp-config`, so
  no user, project, or local `.claude/settings.json` (including any
  `PreToolUse`/`PostToolUse` hooks they define) is loaded into the run. The
  explicit `--settings` deny JSON described below is still passed
  independently of this flag.
- `--tools "Read,Edit,Write,Grep,Glob,Bash"` names the tool surface that can
  even be attempted. `--allowedTools` is narrower: it always includes
  `Read,Edit,Write,Grep,Glob`, and only adds `Bash(PREFIX:*)` entries when the
  caller explicitly passes `--allow-bash PREFIX`. When no `--allow-bash` is
  given, Bash stays listed in `--tools` but absent from `--allowedTools`, so a
  denied Bash attempt is an observable boundary event instead of a silently
  unavailable tool.
- `--settings` carries a single JSON `permissions.deny` list built
  programmatically (never by string concatenation of untrusted text) from the
  protected-path patterns: `./.env`, `./.env.*`, `./.claude/**`,
  `./.codex/**`, `./.npmrc`, `./.git/**`, plus every project-declared pattern
  in `.ai-orchestrator-protected-paths`. Each pattern is denied for `Read`,
  `Edit`, and `Write`. `./.claude/**` denies the whole directory, not just
  `settings.local.json`, so a spec cannot escape the deny list by writing a
  new file under `.claude/`.
- `--permission-mode acceptEdits --permission-prompts none` runs unattended;
  there is no human in the loop to approve a prompt.
- An optional, repeatable `--allow-path GLOB` restricts which changed paths
  are acceptable. Globs are relative to `WORKDIR` and matched with fnmatch
  semantics where `*` and `**` both cross `/` (there is no `FNM_PATHNAME`
  distinction). When at least one `--allow-path` is given and a changed path
  matches none of them, the run is `refused`/`SCOPE_VIOLATION`. When none is
  given, the report says `SCOPE: unchecked (no --allow-path given)` — the lane
  makes no scope claim by default.
- The lane never passes `--fallback-model`, `--dangerously-skip-permissions`,
  `--allow-dangerously-skip-permissions`, or `bypassPermissions`. A model or
  permission boundary that cannot be honored is `unavailable`, not silently
  downgraded.
- `--allow-path` globs and `--allow-bash` prefixes are passed literally: the
  runner disables its own shell's pathname expansion (`set -f`) around every
  loop that iterates them, so a glob such as `scripts/**` is never expanded
  against the runner's launch directory before the guard sees it. An
  `--allow-bash` prefix containing any character outside
  `[A-Za-z0-9_./ =-]` (including an empty prefix) is a usage error, not a
  string concatenated unchecked into `--allowedTools`. A prefix must start
  with a bare program name: a path (`/opt/homebrew/bin/git`), a wrapper
  (`command`, `env`, `exec`, `eval`, `builtin`, `nohup`, `xargs`, `sudo`,
  `doas`, `time`, `nice`, `caffeinate`), a leading environment assignment,
  or a leading or trailing space is refused. A prefix whose first token is
  `git` in any letter case must name a subcommand that does not write refs,
  the index or the worktree by default (`status`, `diff`, `log`, `show`,
  `ls-files`, `rev-parse`, `blame`, `grep`); a bare `git`, `git commit`,
  `git push` or any other subcommand is refused `unavailable`/`GUARD_FAILED`
  before `claude` runs. These checks are a lint on the literal prefix text
  the architect types, not a sandbox: they do not inspect trailing
  arguments, and they cannot know what a program of another name does (see
  the residual gaps).

## The two guards

Exactly as in the Codex lane contract, the lane brackets every invocation with
two deterministic, out-of-process guards whose baselines live outside the
workdir (`mktemp -t`). Before any snapshot is taken, the runner compares the
physical path (`pwd -P`) of its own checkout (`$ROOT`) against the physical
path of `WORKDIR`: if the runner's own checkout is `WORKDIR` or lives inside
it, the run is refused `unavailable`/`GUARD_FAILED` rather than risk the
guard scripts or the post-run parser being edited mid-run by the very spec
being executed.

- `scripts/worktree-delta.rb` — a content baseline of tracked and
  nonignored-untracked files. Exit `0`/`STATUS: changed` proves a real task
  delta; exit `3`/`STATUS: empty` means no files changed. Any other exit is a
  guard failure.
- `scripts/protected-paths.rb` — the short explicit inventory of sensitive
  ignored paths (`.env`, `.env.*`, `.claude/settings.local.json`, `.codex/`,
  `.npmrc`, plus declared project patterns). Exit `0`/`STATUS: unchanged` is
  the only acceptable result; exit `4`/`STATUS: violation` is
  `PROTECTED_STATE_VIOLATION`. Any other exit is a guard failure.

These two scripts, and their meaning, are identical to the Codex lane; this
lane does not fork or relax them. `--allow-path` (see above) is a third,
optional check layered on top of `worktree-delta`'s own changed-path list: it
narrows which changed paths are acceptable, not whether a change happened at
all. None of `worktree-delta.rb`, `protected-paths.rb`, or `--allow-path` is
an OS sandbox — they are deterministic, out-of-process checks of what the
worktree looked like before and after, not a boundary that prevents an
allowlisted Bash command from reading or writing anything the OS permits.

## Classification

`scripts/parse-lane-result.rb` classifies the two guard exit codes and the
captured JSON, in this fixed order (first match wins). The guard exit codes
are checked first because they are independent of, and more trustworthy than,
whatever the captured JSON claims:

| Order | Condition | STATUS | CLASSIFICATION |
|---|---|---|---|
| 1 | protected-paths guard exit is `4`, even if the JSON is missing or malformed | `refused` | `PROTECTED_STATE_VIOLATION` |
| 2 | either guard exited outside `{0,4}` / `{0,3}` | `unavailable` | `GUARD_FAILED` |
| 3 | captured JSON unreadable / not an object, and the `claude` exit is non-zero | `unavailable` | `TRANSPORT_FAILED` |
| 4 | captured JSON unreadable / not an object, and the `claude` exit is zero | `unavailable` | `OUTPUT_NOT_CAPTURED` |
| 5 | `modelUsage` missing or not an object | `unavailable` | `MODEL_UNRESOLVED` |
| 6 | `modelUsage` has 0 keys | `unavailable` | `MODEL_UNRESOLVED` |
| 7 | `modelUsage` has more than 1 key | `unavailable` | `MULTI_MODEL` |
| 8 | the single `modelUsage` key is not the expected canonical model | `unavailable` | `MODEL_UNRESOLVED` |
| 9 | `subtype == "error_max_budget_usd"` | `partial` | `BUDGET_EXCEEDED` |
| 10 | `subtype == "error_max_turns"` | `partial` | `TURNS_EXCEEDED` |
| 11 | `is_error` true or the `claude` exit is non-zero | `unavailable` | `TRANSPORT_FAILED` |
| 12 | worktree-delta guard exit is `3` (empty) | `refused` | `EMPTY_DELTA` |
| 13 | a changed path matches none of the declared `--allow-path` globs | `refused` | `SCOPE_VIOLATION` |
| 14 | `permission_denials` present but not an array, or containing an entry that is not an object with a string `tool_name` | `unavailable` | `OUTPUT_NOT_CAPTURED` |
| 15 | any denial's `tool_name` is `Read`, `Edit`, or `Write` | `partial` | `TOOL_PERMISSION_FAILURE` |
| 16 | otherwise | `complete-candidate` | `none` |

Rule 2 also fires when `worktree-delta` exits `0` (`changed`) but no
`CHANGE:` lines could be parsed from its stdout: that combination is format
drift or truncated output, not evidence of zero changed paths, so it is
`GUARD_FAILED` rather than a `SCOPE: ok (0 changed paths ...)` next to
`WORKTREE_DELTA: changed`.

Rule 12 overrides what would otherwise read as a successful subtype: an exit
of zero with no worktree delta is never `complete-candidate`. Rule 13 is only
ever reached when at least one `--allow-path` was given; with none given,
`SCOPE` is reported as `unchecked` and this rule cannot fire. A `Bash`-only
denial is reported in `BOUNDARY_EVENTS` but, by itself, never fails the run —
only a denied `Read`, `Edit`, or `Write` does.

The mapping from an abstract model alias (`sonnet`, `opus`, `haiku`, `fable`)
to a canonical model id (`claude-sonnet-5`, `claude-opus-5`, ...) comes only
from `docs/model-map.json`, produced by `scripts/probe-model-map.sh`. That
mapping is never hardcoded in the parser: `scripts/parse-lane-result.rb`
receives `EXPECTED_CANONICAL` as an argument from the caller and never invents
or assumes a canonical id itself. `run-claude-lane.sh` validates the model map
before ever invoking `claude` and reports `unavailable` rather than trusting a
bad probe: a canonical that is not a string matching `^claude-[a-z0-9.-]+$` is
`MODEL_UNRESOLVED`; a `generatedAt` more than 30 days old or dated in the
future is `MAPPING_STALE`; and a `claudeVersion` in the map that does not
exactly match the output of the running `claude --version` is also
`MAPPING_STALE`, since a probe taken against a different CLI build cannot be
trusted for the running one.

## Report

```text
IMPLEMENTATION REPORT
LANE: claude
REQUESTED_ALIAS: <alias, e.g. sonnet>
EXPECTED_CANONICAL: <canonical model id> (model map <generatedAt>, claude <claudeVersion>)
RESOLVED_MODEL_EVIDENCE: <the single modelUsage key, or "unavailable">
STATUS: complete-candidate | partial | refused | unavailable
CLASSIFICATION: none | MODEL_UNRESOLVED | MULTI_MODEL | OUTPUT_NOT_CAPTURED | TRANSPORT_FAILED | BUDGET_EXCEEDED | TURNS_EXCEEDED | EMPTY_DELTA | PROTECTED_STATE_VIOLATION | GUARD_FAILED | TOOL_PERMISSION_FAILURE | SCOPE_VIOLATION | MAPPING_STALE
REASON: <one line or none>
COST_USD: <total_cost_usd or unknown>
NUM_TURNS: <num_turns or unknown>
BOUNDARY_EVENTS: <count> denial(s): <tool_name summary list, or none>
PROTECTED_STATE: unchanged | violation | error
WORKTREE_DELTA: changed | empty | error
SCOPE: ok (N changed paths within M allowed globs) | unchecked (no --allow-path given) | changed path(s) outside allowed scope: <paths>
MODEL_SAID:
<the result text verbatim>
```

## Acceptance is not delegated

`STATUS: complete-candidate` is a claim from the lane, not acceptance. Exactly
as for the Codex lanes, the architect independently re-runs every command in
`VERIFICATION` and reads the actual diff; it does not accept quoted output or
a model's self-report. A failing verification, a partial diff, or a missing
required file cannot be `complete-candidate` regardless of what this report
says.

This lane is given no commit, merge, deploy, or Production authority, and the
runner never runs `git commit`, `git push`, or a deploy command itself; those
remain exclusively with `HUMAN_RELEASE_AUTHORITY`, exactly as in
[`IMPLEMENTATION_LANE_CONTRACT.md`](IMPLEMENTATION_LANE_CONTRACT.md#evidence-and-acceptance).
Whether an allowlisted Bash command could nonetheless reach a Production
feature flag or some other irreversible external action is governed by the
inherited-environment paragraph below and by the residual gaps, not by this
sentence; the lane makes no claim that it "cannot" reach one.
The runner lints `--allow-bash` prefixes for the literal forms that would
hand the lane a writing git subcommand (see the invocation boundary above)
and for nothing else; that lint is not a sandbox, and this is not a claim
that the host environment is safe to run untrusted specs in: an allowlisted
Bash command runs with whatever credentials, network access, and filesystem
visibility the host process already has, and nothing here strips those. The
absence of commit/merge/deploy authority is a residual gap, not a guarantee,
for any spec that can reach a Production credential through that inherited
environment.

## Residual gaps (recorded, not closed)

- Allowlisted Bash commands run without an OS sandbox. Repository code
  executed by an allowlisted command (for example a test suite the
  implementer can edit) could in principle locate and rewrite the guard
  baselines under `$TMPDIR`; the baselines have random `mktemp` names and the
  architect re-reads the actual diff, but closing this gap requires
  OS-level sandboxing, which this lane does not provide.
- A `--settings` deny-list refusal ("File is in a directory that is denied by
  your permission settings") does not appear in `permission_denials`; only
  prompts that would have needed approval do. The deterministic
  `protected-paths.rb` check is therefore the load-bearing evidence for
  protected local state.
- The `--allow-bash` git rule inspects only the prefix's first two tokens.
  It does not see trailing arguments (`Bash(git diff:*)` still lets the
  lane run `git diff --output=<file>`, which writes a file), it cannot tell
  that a program of another name (`gitx`, a wrapper script on `PATH`) is
  git, and it does nothing for interpreter prefixes such as `ruby` or
  `python3`, which can run arbitrary code. Every `--allow-bash` prefix is a
  grant the architect makes deliberately; what such a command then writes is
  detected after the fact by the worktree and protected-paths guards, not
  prevented.
- An allowlist prefix such as `Bash(pnpm test:*)` is matched after leading
  environment assignments are stripped, so `LANG=C pnpm test` is accepted;
  the prefix still cannot be used to run a different program.
- `--restricted` confines the file tools to the working directories but does
  not bound the network; `NETWORK: bounded by the Bash allowlist only`
  remains the honest statement.
- An allowlisted Bash command inherits the host process's environment
  variables, credentials, and filesystem visibility in full; the lane does
  not strip, scope, or sandbox any of that before the command runs.
- A Bash command can start a process that outlives the `claude` invocation
  (for example a detached background job); the lane's guards only compare
  worktree state before and after, so such a process is not tracked or
  killed by anything in this contract.
- Claude auto-approves its own built-in read-only shell commands (for
  example `echo`) even under `--restricted`; these never appear in
  `permission_denials` and are not counted as boundary events.
- `protected-paths.rb` records a symlink's target *path*, not the contents at
  that target, so a protected symlink whose target file changes without the
  symlink itself changing is not detected as a violation.
- `--allow-path` matches changed *paths* against globs, not their content; a
  changed path within an allowed glob is never inspected for what it now
  contains. It is also only enforced when at least one `--allow-path` is
  passed — by default `SCOPE` is `unchecked`, not a passing check.
- The model map file (`docs/model-map.json`, produced by
  `scripts/probe-model-map.sh` in the architect's environment) and the
  `claude` binary found on `PATH` are trusted inputs of the architect's
  environment, not things the runner proves; a forged map or a PATH shim
  would defeat model-identity evidence. The default model map path lives
  under the runner's own checkout, which the runner now refuses to let be
  `WORKDIR` or inside it (see "The two guards" above), so an implementer
  working inside `WORKDIR` cannot alter the default map or the `claude`
  binary found on `PATH`; that is the boundary this lane actually claims,
  not a guarantee about an explicit `--model-map` path the caller chooses to
  point inside `WORKDIR`.

## Calibration record

The calibration rule: three real specs dispatched to this lane on `sonnet`;
the lane becomes the provisional default implementer if the architect accepts
at least 2 of 3 `complete-candidate` results after independently re-running
verification and reading the actual diff. The dated record of the completed
calibration lives in `acceptance/ACCEPTANCE_EVIDENCE.md` under "Claude lane
calibration".

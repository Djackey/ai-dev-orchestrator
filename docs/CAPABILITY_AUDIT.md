# Capability Audit — 2026-09-04

This is a point-in-time audit of the environment used to implement V1. It is
evidence, not a portability promise.

## Repository and upstream

- Feature branch: `codex/orchestrator-v1`.
- Audited baseline: `4d6cc62164619a279b076439e1af5439892b958a`.
- At audit time, local `main`, `origin/main`, and freshly fetched
  `upstream/main` all resolved to that commit.
- Plugin and marketplace manifests were both `fable-advisor` 5.0.0.

Open upstream issues read during the audit:

- [#13: timeout guard fails under zsh](https://github.com/DannyMac180/fable-advisor/issues/13) — reproduced by inspection; the same unquoted-expansion issue also affected the optional effort flag.
- [#10: agent descriptions lack routing examples](https://github.com/DannyMac180/fable-advisor/issues/10) — relevant to routing portability.
- [#3: old Grok permission-mode behavior](https://github.com/DannyMac180/fable-advisor/issues/3) — belongs to a removed lane, not V1.
- [#18](https://github.com/DannyMac180/fable-advisor/issues/18) — unrelated content.

## Claude Code

`claude --version` returned `2.1.259`.

Minimal no-tool, non-persistent JSON probes returned:

| Requested alias | Observed `modelUsage` canonical model | Result |
|---|---|---|
| `fable` | `claude-fable-5-1` | success |
| `opus` | `claude-opus-5` | success |

This proves those aliases for this account at this time. It does not remove the
silent-fallback risk for a future unavailable frontmatter pin. Normal nested-
agent text does not expose `modelUsage`, so V1 does not claim that an
unobservable pin resolved as requested.

The first tool-enabled clean-context probe appeared to return no payload because
the host command had yielded an asynchronous session and the caller failed to
poll that session. The failure class was `OUTPUT_NOT_CAPTURED`, not an agent,
model, or transport limitation. After correct polling, the repository runner
captured JSON with exactly one `modelUsage` entry (`claude-fable-5-1`) and a
consumable `VERDICT: ACCEPT`. Deterministic tests separately cover agent,
model, transport, output, and tool-permission failure classifications.

## Codex CLI and model access

The effective PATH command was not usable:

```text
command -v codex
<first PATH codex shim>

codex --version
.../@openai/codex-darwin-arm64/.../codex ENOENT
```

Therefore the actual lane preflight correctly classifies the current `codex`
command as unavailable. It must not skip to another binary or model silently.

The local ChatGPT application also contained a working bundled binary. Its
machine-private absolute path was supplied only through
`AI_ORCHESTRATOR_CODEX_BIN`; it is not a repository default:

```text
<explicit locally bundled Codex binary> --version
codex-cli 0.146.0-alpha.9.2
```

That binary reported ChatGPT authentication and the following successful,
ephemeral, read-only live probes:

| Requested model | Requested effort | Startup evidence | Result |
|---|---|---|---|
| `gpt-5.6-luna` | `max` | exact model, effort `max`, sandbox `read-only` | `MODEL_OK`, exit 0 |
| `gpt-5.6-terra` | `max` | exact model, effort `max`, sandbox `read-only` | `MODEL_OK`, exit 0 |
| `gpt-5.6-sol` | `high` | exact model, effort `high`, sandbox `read-only` | `MODEL_OK`, exit 0 |
| `gpt-5.6-sol` | `max` | exact model, effort `max`, sandbox `read-only` | `MODEL_OK`, exit 0 |
| `gpt-5.6-sol` | `ultra` | exact model, effort `ultra`, sandbox `read-only` | `MODEL_OK`, exit 0 |

These probes prove current account access and exact pass-through for the tested
combinations only. Agent policy deliberately does not invent an exhaustive
effort matrix: each real invocation must expose or reject its requested value.

The executable resolver contract was also exercised against explicit-valid,
explicit-invalid, PATH-valid, broken-PATH-shim, missing-binary, auth-unavailable,
and model-unavailable fixtures. A real mechanical lane run against the broken
PATH shim returned structured `unavailable`; supplying the working bundled
binary explicitly then ran Luna successfully without changing the requested
model.

The bundled CLI also reported unrelated local health warnings: a damaged memory
database check and an expired Cloudflare MCP OAuth client. They did not prevent
the isolated model probes and are not repaired by this repository.

## CLI behavior verified from help

Current Codex exposes `--model`, `--sandbox` (`read-only`, `workspace-write`,
`danger-full-access`), `--cd`, `--skip-git-repo-check`, config override `-c`, and
`--output-last-message`. `--ask-for-approval` is a top-level option and must
precede `exec` in this version.

Both `/bin/bash` 3.2.57 and `/bin/zsh` 5.9 were present. Neither `timeout` nor
`gtimeout` was installed. The deterministic test therefore exercises the real
shells with both an empty timeout path and a synthetic non-empty path and proves
the exact argv boundaries; it does not claim an integration test of GNU
timeout's exit-124 behavior on this machine.

Current Claude Code exposes `--model` aliases, `--effort` values `low`, `medium`,
`high`, `xhigh`, and `max`, and plugin validation. These Claude effort values do
not define Codex model effort support.

In this repository layout, `claude plugin validate --strict . --json` validated
the marketplace manifest but returned an empty `contents` list; it did not prove
agent or skill frontmatter validity. V1 therefore also parses every agent and
the orchestration skill with Ruby's YAML parser in
`scripts/validate-frontmatter.rb`.

## Claude lane probes — 2026-09-04

Measured by the architect on Claude Code 2.1.260, with `claude.ai` OAuth auth
and the `firstParty` provider. These are point-in-time observations, not a
portability promise.

Alias probes via `claude -p --output-format json --max-turns 1`:

| Requested alias | Observed `modelUsage` canonical model | Probe cost (USD) |
|---|---|---|
| `sonnet` | `claude-sonnet-5` | `0.0794` |
| `opus` | `claude-opus-5` | `0.1656` |
| `haiku` | `claude-haiku-4-5-20251001` | `0.0259` |
| `fable` | `claude-fable-5-1` | proven earlier in this file |

`--restricted --tools Bash --allowedTools "Bash(pnpm test:*)" --permission-prompts none`:
a `curl` command was denied and appeared in `permission_denials`; a `git commit`
command was denied and appeared in `permission_denials`.

`--restricted` with `Read,Edit,Write`: a `Write` to `/tmp`, outside the working
directory, was denied and appeared in `permission_denials`; a `Write` to
`./.env`, inside the working directory, was ALLOWED when no deny rule was set.

`--settings '{"permissions":{"deny":["Edit(./.env)","Write(./.env)","Write(./.git/**)",...]}}'`:
writes to `./.env` and `./.git/hooks/pre-commit` were refused with "File is in
a directory that is denied by your permission settings", the file system was
unchanged, and these refusals did NOT appear in `permission_denials` — so the
deterministic protected-paths guard remains the load-bearing check, not
`--settings` alone.

`--max-budget-usd 0.005`: the run ended with `subtype error_max_budget_usd` and
`is_error true`.

The in-session Agent tool (haiku probe) returned only text and token counts, no
model identity; therefore the lane is a headless CLI runner, not a nested
agent.

`--fallback-model` exists in this CLI version and must never be passed by a
lane.

## Claude lane dogfood observations — 2026-09-04

Two boundary observations from dogfooding the Claude lane:

(a) Under `--restricted` with a Bash allowlist, an attempted `perl -pi`
in-place file edit was denied and appeared in `permission_denials`, so file
mutation must go through the Edit/Write tools where the deny list applies.

(b) An allowlist prefix such as `Bash(pnpm exec:*)` is broad — `pnpm exec tsx
<script>` runs arbitrary repository code — so an architect who allows it
accepts that the implementer can execute code it wrote; the worktree-delta
guard still reports every resulting file change.

## Claude lane boundary probes — 2026-09-04 (settings, MCP, stdin)

Probes on `claude-haiku-4-5-20251001` (model chosen to keep probe cost low;
haiku, ≈USD 0.05 total across the probes below):

- `--restricted` with `permissions.allow` containing `Bash(python3:*)` did
  NOT permit a `python3` invocation, checked across 3/3 repeated runs: the
  command was still denied and appeared in `permission_denials`. An `allow`
  entry in `--settings` does not override `--restricted`'s own tool gate.
- `echo PROBE_OK` ran successfully with no allowlist entry for it at all, and
  with no corresponding denial in `permission_denials` — Claude treats its
  own built-in read-only shell commands as always-approved (see the residual
  gap recorded in the contract).
- `--strict-mcp-config` was accepted together with `--setting-sources ""`;
  neither flag caused a transport error, and no MCP server configuration was
  discovered or loaded.
- The `--settings` deny of `./.env` held: a `Write` to `./.env` was refused
  with "File is in a directory that is denied by your permission settings"
  and the file was unchanged on disk, consistent with the earlier `--settings`
  probe above.
- Piping the prompt on stdin (`claude -p --restricted ... < spec.txt`, no
  positional prompt argument) worked exactly as passing the same text as an
  argument did in earlier probes; the model received and acted on the full
  spec text.

### Operating observations

O1: When a spec's own instructions are to edit the lane's scripts
(`scripts/run-claude-lane.sh`, `scripts/parse-lane-result.rb`, etc.), the
runner must be invoked from a checkout that is NOT the `WORKDIR` being edited.
`sh` reads a script incrementally as it executes, and the guard/parser
invocation happens after the model process exits; if the running script were
also the file being rewritten mid-run, a partially written script could be
executed, and a partially written parser could be asked to parse a contract
it no longer matches. The same one-sentence rule is recorded in `README.md`
under "Running the lane".

O2: An account usage limit hit mid-run surfaces as `is_error: true` with
model text "You've hit your session limit"; observed 2026-09-04 after 20
turns and USD 1.22 of a longer run. The runner classified this
`unavailable`/`TRANSPORT_FAILED` with `WORKTREE_DELTA: changed` — the
classification was correct (a real transport failure, not a boundary event),
but the worktree was left with a real partial diff from the turns that did
complete. The operator must inspect that partial diff by hand before
re-dispatching the spec; the runner has no way to know whether the partial
work is safe to keep, discard, or resume from.

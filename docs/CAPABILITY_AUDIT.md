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

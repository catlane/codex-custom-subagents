# Codex Custom Subagents

A macOS Codex Desktop marketplace for fixed-role custom subagents. GPT remains the main agent. The initial plugins provide DeepSeek for development and Volcengine for independent code review.

When custom agents are enabled, the complete task uses one V1 multi-agent protocol. An explicit request for official agents uses official GPT roles inside that same V1 task; switching a running task between V1 and V2 is not supported.

## Current Status

The marketplace, setup/uninstall skills, shared lifecycle, and isolated
automated tests are implemented. Local-path marketplace installation of both
plugins was verified with Codex CLI 0.148.0 in an isolated `CODEX_HOME`. Live
Keychain dialogs, external provider API calls, GitHub marketplace installation,
and fresh-task Codex routing still require manual acceptance; this repository
does not claim those paths have been verified.

## Marketplace Layout

- `deepseek-developer`: scoped implementation, code analysis, and focused verification.
- `volcengine-reviewer`: independent findings-first review. Its generated agent
  configuration enforces `sandbox_mode = "read-only"` and
  `approval_policy = "never"` in addition to the review-only instructions.

Each agent is an independent plugin. Installing or removing one must not modify the other agent's files or Keychain entry.

## Installation Shape

After this repository is published as `OWNER/REPOSITORY`:

```bash
codex plugin marketplace add OWNER/REPOSITORY --ref main
codex plugin add deepseek-developer@custom-subagents
codex plugin add volcengine-reviewer@custom-subagents
```

Run the two `plugin add` commands sequentially. Configuration and uninstall
operations share an owner-token lock that covers both Keychain and managed-file
changes; a concurrent operation fails before either boundary is mutated.

The marketplace command accepts `owner/repo`, an HTTPS Git URL, an SSH Git URL, or a local path. Plugin installation only makes its skills available. Configuration is a separate conversational step so global Codex files are never rewritten silently.

Install only the agents you need. For the GPT-main, DeepSeek-development,
Volcengine-review workflow, install both packages. In conversation, ask Codex
to configure each installed plugin and provide only its non-secret endpoint and
model:

- DeepSeek can use `https://api.deepseek.com` when you accept that default;
  the model is still required.
- Volcengine requires the exact OpenAI-compatible endpoint and model or
  deployment ID. No endpoint or model is guessed.

Codex must show the proposed non-secret settings and obtain approval before
changing global managed files. Enter a fresh API key only in the native hidden
macOS dialog. Never paste it into chat. After each successful configuration,
fully restart Codex and create a fresh task.

## Routing

GPT remains the main model selected in the Codex UI. With both plugins
configured, non-trivial development can delegate implementation to agent type
`deepseek_developer`, then send the actual diff and verification evidence to
the `volcengine_reviewer` for independent findings-first review. The reviewer
agent is generated with a read-only sandbox and cannot request approval to
escape it; DeepSeek does not inherit those reviewer-only restrictions.

Configuration snapshots the active official model catalog and changes only
the currently selected GPT model's `multi_agent_version` to `v1`. It preserves
all other catalog fields, models, IDs, display names, and ordering.

The complete custom-agent task uses multi-agent V1. A running task cannot mix
V1 and V2. In a fresh task, an explicit request for "official GPT agents" uses
official `default`, `worker`, or `explorer` roles in that same V1 task. An
explicit request for no subagents keeps all work in the GPT main task.

## Uninstall

Ask Codex to run the installed plugin's conversational uninstall skill before
removing its package. Only after lifecycle and the exact Keychain item are
cleaned up should Codex run one of:

```bash
codex plugin remove deepseek-developer@custom-subagents
codex plugin remove volcengine-reviewer@custom-subagents
```

Removing one agent preserves the other. If a package was removed first,
its managed files and Keychain item remain because the cleanup tooling is no
longer available. Reinstall that same package, run its uninstall skill, and
remove it again. See
[`docs/recovery.md`](docs/recovery.md) for status, backup, and fail-closed
recovery procedures.

## Development Validation

```bash
sh scripts/test-all.sh
```

The runner discovers every top-level `tests/*.sh` suite and gives each one a
fresh temporary `HOME`, `CODEX_HOME`, `CUSTOM_SUBAGENT_HOME`, and `TMPDIR`. A
successful run removes its artifacts; a failed run prints and preserves the
artifact directory and returns non-zero. No development test may read or write
the live `~/.codex` directory or real macOS Keychain.

After automated validation, use
[`docs/manual-acceptance.md`](docs/manual-acceptance.md) for full-restart,
fresh-V1-task, routing, live-provider authorization, and final-restoration
acceptance. Recovery procedures remain in
[`docs/recovery.md`](docs/recovery.md).

## Safety

- Never paste an API key into Codex chat.
- Keys are stored only in macOS Keychain.
- The fixed Keychain account is `api-key`; each plugin has a separate
  `codex-custom-subagent/<plugin-id>` service.
- Configuration writes use managed blocks, backups, and rollback.
- Use the conversational uninstall skill before `codex plugin remove`, because removing the package also removes its cleanup skill.
- Setup is macOS Codex Desktop only. Automated tests use temporary Codex homes
  and fake dialogs/Keychain commands; they do not prove live provider access.

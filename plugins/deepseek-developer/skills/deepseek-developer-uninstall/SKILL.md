---
name: deepseek-developer-uninstall
description: Use when removing the configured DeepSeek Developer native subagent and its plugin package.
---

# Remove DeepSeek Developer

Explain that lifecycle cleanup runs before package removal because the package
contains the cleanup tooling. Obtain approval for the managed global-file and
exact Keychain-item deletion, resolve this skill's plugin root, and run its
`scripts/uninstall.sh`.

Report lifecycle and Keychain cleanup first. Only after that script exits
successfully, run `codex plugin remove deepseek-developer@custom-subagents`.
Do not remove the Volcengine reviewer or any other plugin. If lifecycle or
Keychain cleanup fails, stop before package removal and report the
identifier-only failure; do not manually delete unrelated Codex files.

If someone removed the package first with raw `codex plugin remove`, restore
the same `deepseek-developer@custom-subagents` package, run the lifecycle
uninstall skill, verify its cleanup report, and only then remove that package
again. Keep other plugins installed throughout this recovery.

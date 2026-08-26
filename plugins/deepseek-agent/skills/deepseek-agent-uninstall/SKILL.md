---
name: deepseek-agent-uninstall
description: Use when removing the DeepSeek provider, its three native profiles, and its plugin package.
---

# Remove DeepSeek Provider

Explain that lifecycle cleanup runs before package removal because the package
contains the cleanup tooling. Obtain approval for removing the provider's
managed general, developer, and reviewer profiles and exact Keychain item,
resolve this skill's plugin root, and run `scripts/uninstall.sh`.

Report lifecycle and Keychain cleanup first. Only after that script exits
successfully, run `codex plugin remove deepseek-agent@custom-subagents`. Do not
remove the Volcengine provider or any other plugin. If lifecycle or Keychain
cleanup fails, stop before package removal and report the identifier-only
failure; do not manually delete unrelated Codex files.

If someone removed the package first with raw `codex plugin remove`, restore the same `deepseek-agent@custom-subagents` package, run this lifecycle
uninstall skill, verify its cleanup report, and only then remove that package
again. Keep other plugins installed throughout recovery.

If cleanup reports `legacy-plugin=deepseek-developer`, do not transfer or
delete the old package's credential or managed files from this plugin. Restore
or retain the old package and use its own uninstall workflow first.

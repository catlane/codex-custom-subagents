---
name: volcengine-agent-uninstall
description: Use when removing the Volcengine provider, its three native profiles, and its plugin package.
---

# Remove Volcengine Provider

Explain that lifecycle cleanup must run while the package still contains its
cleanup tooling. Obtain approval for removing the provider's managed general,
developer, and reviewer profiles and exact Keychain item, resolve this skill's
plugin root, and run `scripts/uninstall.sh`.

Report lifecycle and Keychain cleanup first. Only after success, run
`codex plugin remove volcengine-agent@custom-subagents`. Do not remove the
DeepSeek provider or any unrelated plugin. On failure, stop before package
removal and report only service/account or migration identifiers; do not
manually delete unrelated Codex files.

If raw package removal happened first, restore the same `volcengine-agent@custom-subagents` package, run this lifecycle cleanup,
verify its success, and only then remove that package again. Keep every other
plugin installed throughout recovery.

If cleanup reports `legacy-plugin=volcengine-reviewer`, do not transfer or
delete the old package's credential or managed files from this plugin. Restore
or retain the old package and use its own uninstall workflow first.

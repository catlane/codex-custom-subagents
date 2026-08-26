---
name: volcengine-reviewer-uninstall
description: Use when removing the configured Volcengine Reviewer native subagent and its plugin package.
---

# Remove Volcengine Reviewer

Explain that lifecycle cleanup must run while the package still contains its
cleanup tooling. Obtain approval for the managed global-file changes and exact
Keychain-item deletion, resolve this skill's plugin root, and run
`scripts/uninstall.sh`.

Report lifecycle and Keychain cleanup first. Only after success, run
`codex plugin remove volcengine-reviewer@custom-subagents`. Do not remove the
DeepSeek developer or any unrelated plugin. On failure, stop before package
removal and report only service/account identifiers; do not manually delete
unrelated Codex files.

If raw package removal happened first, restore the same `volcengine-reviewer@custom-subagents` package, run this lifecycle cleanup,
verify its success, and only then remove that package again. Keep every other
plugin installed throughout recovery.

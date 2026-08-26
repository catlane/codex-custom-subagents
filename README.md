# Codex Custom Subagents

让 Codex 保持 GPT 主智能体，同时使用其他模型作为子智能体：

- `deepseek-agent`：接入 DeepSeek。
- `volcengine-agent`：接入火山引擎的 OpenAI 兼容模型。

每个模型都可以执行开发、分析或 Review。GPT 默认根据任务自动选择模型和角色，用户也可以在任务中明确指定。两个插件可以单独安装和卸载。目前仅支持 macOS Codex Desktop。

[English](#english)

## 安装

如果终端提示 `zsh: command not found: codex`，先执行下面这一行，再继续使用 `codex`：

```bash
CODEX_BIN="$(find "/Applications/ChatGPT.app" "/Applications/Codex.app" "$HOME/Applications/ChatGPT.app" "$HOME/Applications/Codex.app" -type f -path '*/Contents/Resources/codex' -perm -111 2>/dev/null | head -n 1)"; if [ -n "$CODEX_BIN" ]; then mkdir -p "$HOME/.local/bin" && ln -sf "$CODEX_BIN" "$HOME/.local/bin/codex" && { grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"; } && export PATH="$HOME/.local/bin:$PATH" && codex --version; else echo 'Codex Desktop CLI not found under Applications.'; fi
```

添加插件市场：

```bash
codex plugin marketplace add catlane/codex-custom-subagents --ref main
```

按需安装一个或两个插件：

```bash
codex plugin add deepseek-agent@custom-subagents
codex plugin add volcengine-agent@custom-subagents
```

安装插件只会添加配置技能，不会自动修改全局 Codex 配置。

## 配置

安装后直接在 Codex 对话中提出配置要求：

```text
配置 DeepSeek 子智能体，模型使用 deepseek-chat。
```

```text
配置火山子智能体，API 地址是 <OpenAI-compatible endpoint>，模型是 <model or endpoint ID>。
```

Codex 会先展示非敏感配置并请求确认。API Key 只能在 macOS 原生隐藏输入框中填写，不要发送到聊天、命令或配置文件中。如果弹窗无法显示（例如虚拟机、SSH 或 Codex 沙盒 shell 没有图形界面权限），脚本会回退为终端隐藏输入；若两者都不可用，请按提示把同一条 configure 命令复制到自己的终端窗口里执行。配置成功后，完全重启 Codex 并新建任务。

## 使用

GPT 始终是主智能体。每个已配置模型都会提供三个子智能体类型：

- `general`：分析、调查和其他通用任务。
- `developer`：开发和验证。
- `reviewer`：独立只读 Review，不能修改文件或申请提升权限。

默认不需要提前绑定角色。例如只配置 DeepSeek 时，可以由一个 DeepSeek 子智能体开发，再由另一个 DeepSeek 子智能体 Review。配置 DeepSeek 和火山后，GPT 可以跨模型分工，也可以根据任务只使用其中一个。

也可以直接指定：

```text
这次让 DeepSeek 开发，火山 Review。
```

也可以在新任务中明确要求：

- `使用官方 GPT agent`：使用官方子智能体。
- `不要使用子智能体`：全部工作由 GPT 主智能体完成。

一个任务不能同时混用 V1 和 V2 子智能体协议。自定义子智能体通过实验性的 V1 model catalog 配置工作，Codex Desktop 更新后应重新验证。

## 卸载

先在 Codex 对话中要求卸载对应子智能体，让插件清理 agent 配置和 Keychain 项；清理成功后再删除插件包：

```bash
codex plugin remove deepseek-agent@custom-subagents
codex plugin remove volcengine-agent@custom-subagents
```

不要先直接删除插件包，否则清理技能也会一起消失。详细恢复方法见 [docs/recovery.md](docs/recovery.md)。

## 更多文档

- [手工验收](docs/manual-acceptance.md)
- [故障恢复](docs/recovery.md)

## English

Keep GPT as the main Codex agent while using other models as subagents:

- `deepseek-agent` connects DeepSeek.
- `volcengine-agent` connects an OpenAI-compatible Volcengine model.

Each configured provider exposes general, developer, and reviewer profiles. GPT selects the provider and role automatically unless the user explicitly assigns them. Reviewer profiles are enforced read-only. Both plugins are independently installable and removable. macOS Codex Desktop is currently required.

### Install

If the terminal reports `zsh: command not found: codex`, run this one line first, then continue with `codex`:

```bash
CODEX_BIN="$(find "/Applications/ChatGPT.app" "/Applications/Codex.app" "$HOME/Applications/ChatGPT.app" "$HOME/Applications/Codex.app" -type f -path '*/Contents/Resources/codex' -perm -111 2>/dev/null | head -n 1)"; if [ -n "$CODEX_BIN" ]; then mkdir -p "$HOME/.local/bin" && ln -sf "$CODEX_BIN" "$HOME/.local/bin/codex" && { grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"; } && export PATH="$HOME/.local/bin:$PATH" && codex --version; else echo 'Codex Desktop CLI not found under Applications.'; fi
```

```bash
codex plugin marketplace add catlane/codex-custom-subagents --ref main
codex plugin add deepseek-agent@custom-subagents
codex plugin add volcengine-agent@custom-subagents
```

After installation, ask Codex to configure each plugin with its non-secret endpoint and model. Enter API keys only in the native hidden macOS dialog. If the dialog cannot appear (for example in a VM, over SSH, or from a sandboxed agent shell without GUI access), the script falls back to a hidden terminal prompt; if neither is available, run the same configure command yourself in an interactive Terminal window. Restart Codex and create a fresh task after configuration.

### Use

GPT remains the main agent. With only DeepSeek configured, separate DeepSeek children can implement and review. With multiple providers, GPT may split roles across models or use one model for both. You can explicitly assign a provider and role, request official GPT agents, or request no subagents.

Custom agents use an experimental V1 model catalog configuration. A single task cannot mix V1 and V2 subagent protocols.

### Uninstall

Ask Codex to run the plugin's uninstall workflow first. Only after managed configuration and the exact Keychain item are removed should you run:

```bash
codex plugin remove deepseek-agent@custom-subagents
codex plugin remove volcengine-agent@custom-subagents
```

See [manual acceptance](docs/manual-acceptance.md) and [recovery](docs/recovery.md) for details.

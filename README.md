# Codex Custom Subagents

让 Codex 保持 GPT 主智能体，同时使用其他模型作为子智能体：

- `deepseek-agent`：接入 DeepSeek。
- `volcengine-agent`：接入火山引擎的 OpenAI 兼容模型。

每个模型都可以执行开发、分析或 Review。GPT 默认根据任务自动选择模型和角色，用户也可以在任务中明确指定。两个插件可以单独安装和卸载。目前仅支持 macOS Codex Desktop。

[English](#english)

## 安装

如果终端提示 `zsh: command not found: codex`，先执行下面这一行，再继续使用 `codex`。注意必须用包装脚本而不是符号链接：macOS 上 CLI 按可执行文件所在路径定位应用包内的捆绑资源，经符号链接启动会导致配置加载失败（`failed to load configuration: No such file or directory`）：

```bash
CODEX_BIN="$(find "/Applications/ChatGPT.app" "/Applications/Codex.app" "$HOME/Applications/ChatGPT.app" "$HOME/Applications/Codex.app" -type f -path '*/Contents/Resources/codex' -perm -111 2>/dev/null | head -n 1)"; if [ -n "$CODEX_BIN" ]; then mkdir -p "$HOME/.local/bin" && printf '#!/bin/sh\nexec "%s" "$@"\n' "$CODEX_BIN" > "$HOME/.local/bin/codex" && chmod +x "$HOME/.local/bin/codex" && { grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"; } && export PATH="$HOME/.local/bin:$PATH" && codex --version; else echo 'Codex Desktop CLI not found under Applications.'; fi
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
配置 DeepSeek 子智能体。
```

```text
配置火山子智能体，API 地址是 <OpenAI-compatible endpoint>。
```

Codex 会先展示非敏感配置并请求确认。DeepSeek 默认使用 `https://api.deepseek.com`，火山默认使用 `https://ark.cn-beijing.volces.com/api/plan/v3`；如果用户要求走中转，再显式传入 endpoint 覆盖。输入 API Key 后，脚本会从该 endpoint 请求 `GET /models`，成功时在 macOS 原生选择框中选择模型；虚拟机、SSH 或无图形界面环境会回退到终端编号选择。若接口不支持、请求失败、返回空列表或格式不受支持，才要求手动输入模型。API Key 只能在隐藏输入框中填写，不要发送到聊天、命令或配置文件中。配置成功后，完全重启 Codex 并新建任务。

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

If the terminal reports `zsh: command not found: codex`, run this one line first, then continue with `codex`. It must be a wrapper script, not a symlink: on macOS the CLI locates bundled app resources relative to its executable path, and launching through a symlink breaks configuration loading (`failed to load configuration: No such file or directory`):

```bash
CODEX_BIN="$(find "/Applications/ChatGPT.app" "/Applications/Codex.app" "$HOME/Applications/ChatGPT.app" "$HOME/Applications/Codex.app" -type f -path '*/Contents/Resources/codex' -perm -111 2>/dev/null | head -n 1)"; if [ -n "$CODEX_BIN" ]; then mkdir -p "$HOME/.local/bin" && printf '#!/bin/sh\nexec "%s" "$@"\n' "$CODEX_BIN" > "$HOME/.local/bin/codex" && chmod +x "$HOME/.local/bin/codex" && { grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"; } && export PATH="$HOME/.local/bin:$PATH" && codex --version; else echo 'Codex Desktop CLI not found under Applications.'; fi
```

```bash
codex plugin marketplace add catlane/codex-custom-subagents --ref main
codex plugin add deepseek-agent@custom-subagents
codex plugin add volcengine-agent@custom-subagents
```

After installation, ask Codex to configure each plugin and, when needed, provide an endpoint override. DeepSeek defaults to `https://api.deepseek.com`, and Volcengine defaults to `https://ark.cn-beijing.volces.com/api/plan/v3`; pass a relay explicitly when requested. After the API key is entered, the script requests `GET /models` from that endpoint and lets you choose from the returned models. If the endpoint does not support model listing or returns an unusable response, it falls back to manual model input. Enter API keys only in a hidden prompt. Restart Codex and create a fresh task after configuration.

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

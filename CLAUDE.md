# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此仓库中工作时提供指导。

## 项目简介

Agent Watch — 一个三进程系统，将 Claude Code（或 Codex）会话实时推送到 Apple Watch，并允许用户从手腕上审批权限请求。

```
Apple Watch  <—WCSession—>  iPhone  <—HTTP/SSE—>  Bridge (Node.js)  <—HTTP hooks / Codex 日志扫描—>  Claude Code / Codex
```

手表也可以通过 Wi-Fi（Bonjour）直接与 Bridge 通信，绕过手机。

## 三个组件

### 1. Bridge — `skill/bridge/server.js`
单个 Node.js 文件（约 1600 行，`"type": "module"`，唯一依赖是 `bonjour-service`）。功能包括：
- HTTP 服务器，端口范围 **7860–7869**（自动选择第一个可用端口）。
- 路由定义（在文件底部的路由表中）：
  - `POST /pair`、`POST /command`、`GET /events`（SSE）、`GET /status`
  - `POST /hooks/tool-output`（PreToolUse 和 PostToolUse 共用此端点）
  - `POST /hooks/permission` — **阻塞式**，最长 10 分钟，保持 HTTP 响应直到手表/手机回复
  - `POST /hooks/stop`、`POST /hooks/task-complete`、`POST /hooks/error`
- SSE 广播到所有已连接的客户端，使用 **500 事件环形缓冲区** 支持断线重连时的数据恢复（`Last-Event-ID`）。
- Bonjour 服务类型 **`_claude-watch._tcp`** — 客户端通过此名称发现 Bridge。
- 认证：6 位配对码（5 分钟有效期）→ 交换为 32 字节十六进制会话令牌，用作 `Authorization: Bearer`。`/pair` 接口限速为 5 次/5 分钟。
- **多会话支持**：通过 `Map<sessionId, …>` 跟踪并发的 Claude/Codex 会话。会话通过 `/command` 按需创建。
- **Codex 集成**：Claude Code 使用 HTTP hooks；Codex 不支持，因此 Bridge 通过扫描 `~/.codex/sessions/` 中的 JSONL 会话文件和 `~/.codex/log/codex-tui.log` 中的 TUI 日志（`CODEX_SESSION_SCAN_INTERVAL_MS = 1500`）来合成等效事件。Codex 的执行审批会生成合成的 `permission-request` 流程。

### 2. iOS 应用 — `ios/ClaudeWatch/ClaudeWatch iOS/`
SwiftUI iPhone 配套应用。通过 Bonjour 发现 Bridge（或手动输入 IP 地址），使用 6 位配对码完成配对，实时显示终端输出和权限提示。通过 `WatchSessionManager`（WCSession `sendMessage` + `transferUserInfo`）将数据中继到手表。

### 3. watchOS 应用 — `ios/ClaudeWatch/ClaudeWatch watchOS/`
SwiftUI 独立手表应用。**直接**与 Bridge 通信（`WatchBridgeClient` + `SSEClient`），不经过手机。语音听写驱动语音命令；触觉反馈提示任务完成、审批和错误。

**`Shared/`** 目录被编译到两个目标中（模型、`WatchSessionManager`、Color/Shape 扩展）。添加共享代码时，放在 `Shared/` 目录下 — `project.yml` 将 `Shared` 列为两个目标的 `sources` 路径。

## 构建与运行

### Bridge
```bash
cd skill/bridge
npm install              # 首次安装
node server.js           # 显示配对码、局域网 IP 和端口
```

### 安装 Claude Code Hooks（全局，所有项目）
```bash
./skill/setup-hooks.sh [port]   # 默认端口 7860
./skill/setup-hooks.sh --remove # 卸载
```
此脚本将 hook 条目写入/合并到 **`~/.claude/settings.json`**（全局配置，非项目本地）。它通过 URL 模式（`http://127.0.0.1:*/hooks/*`）识别自己的条目，因此重复运行是幂等的，`--remove` 可以精确卸载。同时会在 `~/.local/bin/` 创建 `codex-watch` 包装器用于 Codex 会话。

### iOS + watchOS
```bash
make generate            # project.yml → ClaudeWatch.xcodeproj（自动 source .env）
make install             # 构建并安装到 iPhone + Watch
```
**`project.yml` 是 Xcode 项目的唯一配置源** — 编辑后使用 `xcodegen generate` 重新生成。两个目标：`ClaudeWatch`（iOS 应用，内嵌手表应用）和 `ClaudeWatchWatch`（watchOS 应用）。Bundle ID 为 `com.mikeah2011.claudewatch` / `com.mikeah2011.claudewatch.watchkitapp`。

选择 scheme `ClaudeWatch` 构建 iPhone 版本，`ClaudeWatchWatch` 构建手表版本。每个目标需要在 Xcode 中设置 Development Team。

设备 ID 和构建变量通过 `.env` 配置（参考 `.env.example`），DerivedData 路径自动查找。

## 关键架构要点

- **权限请求是唯一的阻塞式 Hook。** 所有其他 Hook 异步触发并立即返回。`/hooks/permission` 保持 HTTP 响应打开，最长 `PERMISSION_TIMEOUT_MS`（10 分钟），将 resolver 存储在 `pendingPermissions` 中，由手表/手机通过 `/command` 解析。`setup-hooks.sh` 和 `server.js` 必须保持此超时时间一致 — hook 条目设置 `"timeout": 600`。

- **`AskUserQuestion` 复用权限流程。** Hook 负载包含 `tool_input.questions`；手表将其渲染为可滚动的按钮，与终端中的数字选项对应。

- **`bridgeId` 和 `sessionId` 在 `/status` 和 Bonjour TXT 记录中是相同的值** — 这是为了向后兼容读取任一字段的旧客户端。

- **Codex 需要不同的数据获取路径。** Codex 没有 HTTP Hook API，因此 Bridge 通过轮询 JSONL 会话文件获取数据。如果修改事件格式，需要同时更新 Claude Hook 处理器和 Codex 合成器（`startCodexMonitor` 及相关函数）— 它们必须生成相同的 SSE 事件词汇表，供 iOS/watchOS 客户端消费。

- **SSE 客户端预期会断线重连。** 使用 `Last-Event-ID` 从环形缓冲区回填数据；不要假设每个事件都能在新连接上到达。

## 环境要求

macOS 13+、Node 18+、Xcode 16+、iOS 17 / watchOS 10、Claude Code 2.1+。

# 开发指南

## 环境要求

- macOS 14+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- （可选）已安装并登录的 [Codex CLI](https://github.com/openai/codex)

## 生成并运行

```bash
cd "Codex-Pulse"   # 项目根目录
chmod +x Scripts/generate-xcodeproj.sh
./Scripts/generate-xcodeproj.sh
open CodexPulse.xcodeproj
```

在 Xcode 中：

1. 选择 **CodexPulse** scheme 与 **My Mac**
2. Signing & Capabilities 中选择你的 Development Team
3. 确认 App Groups：`group.com.codexpulse.shared`（主 App 与 Widget 均需）
4. Run（⌘R）

应用为 **菜单栏 Agent（LSUIElement）**，Dock 中不显示图标；状态在菜单栏。

## 真实数据接入

详见 [REAL_DATA.md](REAL_DATA.md)。

摘要：

1. 安装并登录 Codex CLI：`codex login`
2. 探测：`./Scripts/probe-app-server.sh`
3. Xcode 运行主 App；菜单栏应显示真实邮箱 / 额度
4. 失败时默认回退 Mock（设置中可关）

主应用关闭 App Sandbox 以便 spawn `codex app-server`。

## 无 Codex CLI 时

默认开启「CLI 不可用时使用演示数据」。`MockCodexAppServerClient` 会模拟：

- 账号 / 套餐
- 主额度 + 周额度
- Token 与近 7 日趋势
- 当前任务状态（定时变化）

便于 UI 与小组件开发。

## 数据流

```
codex app-server  ──JSON-RPC/JSONL──►  StdioCodexAppServerClient
                                              │
                                         ProtocolMapper
                                              │
                                         PulseStore
                         ┌────────────────────┼────────────────────┐
                         ▼                    ▼                    ▼
                   MenuBar UI            Dashboard            SnapshotStore
                                                                    │
                                                                    ▼
                                                              Widget (App Group)
```

失败时 → MockCodexAppServerClient（可选）。

## 下一步接线

1. 审批类 server→client 请求的 UI（若需要停止/授权）
2. 重置卡二次确认 + `account/rateLimitResetCredit/consume`
3. SQLite 历史与 30 天保留
4. 按本机 `generate-json-schema` 结果校准 DTO
5. 大 / 小尺寸 Widget

## 浏览器预览

无需 Xcode 时可打开：

```bash
open preview/index.html
```

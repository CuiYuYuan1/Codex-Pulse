# Codex-Pulse

**中文名称：** Codex 状态助手 / Codex 用量监控器 / Codex-Pulse 桌面助手

> **让 Codex 的每一个 Token，都清晰可见。**
>
> 不用打开 Codex，也能掌握 Codex。  
> 额度、Token、任务状态，一个小组件全部掌握。

## 一句话介绍

Codex-Pulse 是一款运行在 macOS 菜单栏/桌面和 Windows 托盘上的 Codex 使用监控工具，帮助用户实时查看账号、额度、Token、任务状态和重置时间，让每一次 Codex 使用都清晰可控。

## 当前进度（原生应用 + 真实数据）

| 交付物 | 说明 |
|--------|------|
| SwiftUI 原生应用 | 菜单栏 App、中尺寸 Widget、看板、设置、浅色/深色主题 |
| Windows Electron 应用 | 托盘胶囊、真实 App Server 数据、API Key 本机今日 Token 汇总 |
| 真实数据服务 | Codex App Server 账号、额度、Token、线程状态与本机会话补源 |
| 模型基准数据 | Artificial Analysis 模型质量、每任务成本与输出速度排行榜 |
| 额外重置预测 | 免费 OpenAI 官方源 + 可配置第三方 X RSS，透明规则指数、衰减、去重与多源加成 |
| 系统集成 | 登录时启动、通知总开关、可配置额度阈值、任务/额度/重置卡到期通知 |
| XcodeGen 配置 | `project.yml` + `Scripts/generate-xcodeproj.sh` |
| 浏览器预览 | [preview/index.html](preview/index.html) — 无需 Xcode 即可查看交互界面 |
| 产品文档 | [docs/PRD.md](docs/PRD.md)、[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) |

> **说明：** 原生界面与浏览器预览可能存在差异；macOS 功能以 Xcode 运行结果为准，Windows 功能以 `windows/` Electron 应用为准。

### 快速预览（任意系统）

在 Finder 中打开：

**[preview/index.html](preview/index.html)**

第二版 UI 采用 **macOS Liquid Glass**：毛玻璃、内高光边、液态进度条、浅/深玻璃切换，视觉参考 [ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) 的 Glassmorphism / Spatial UI。令牌见 `design-system/MASTER.md`。

或：

```bash
open preview/index.html
```

### 在 Mac 上运行原生应用

```bash
brew install xcodegen   # 若未安装
chmod +x Scripts/generate-xcodeproj.sh
./Scripts/generate-xcodeproj.sh
open CodexPulse.xcodeproj
```

Xcode 中选择 **CodexPulse** scheme → 配置 Signing Team 与 App Group `group.com.codexpulse.shared` → Run。  
无 Codex CLI 时默认使用 Mock 数据（可在设置中关闭）。

### 在 Windows 上运行

Windows 版本是独立的 Electron 托盘应用，使用说明和打包命令见 [windows/README.md](windows/README.md)。

## 项目定位

面向 macOS 与 Windows 的 Codex 桌面辅助工具：菜单栏/托盘、悬浮胶囊、小组件和数据看板，实时展示账号、额度、Token、任务与重置时间。

**主打：本地运行、实时监控、低干扰展示。**

## 真实 Codex 数据

本机已安装并登录 Codex CLI 后：

```bash
./Scripts/probe-app-server.sh   # 验证 account / 额度 / Token
./Scripts/generate-xcodeproj.sh
open CodexPulse.xcodeproj       # Run → 菜单栏显示真实数据
```

接入说明见 [docs/REAL_DATA.md](docs/REAL_DATA.md)。无 CLI 时自动 Mock。

## 已实现能力

1. 自动检测 / 连接 Codex App Server（Stdio + Mock 回退）  
2. 账号邮箱与套餐  
3. 额度使用百分比与重置倒计时  
4. 累计及每日 Token + 近 7 日图  
5. 当前任务状态、模型与项目  
6. 菜单栏应用（状态色 + 迷你面板）  
7. 小、中、大三种桌面组件，含过期提示与点击唤起  
8. 额度阈值、任务状态与额度重置通知  
9. 本地快照共享（App Group / Application Support）  
10. 跨进程活动任务识别、多个活动任务计数  
11. 跟随系统及手动浅色/深色主题  
12. 登录时启动、通知权限与额度阈值设置  
13. 多任务跨进程识别、真实任务计时与长任务提醒  
14. SQLite 任务历史、自动保留期清理与 CSV 导出  
15. 本机 Token 实时速度与异常消耗提醒  
16. 安全可选 Webhook：额度、任务、长任务与 Token 异常事件，默认隐藏项目名  
17. 系统通知总开关、重置卡到期时间展示与可配置提前提醒  
18. 基于 SQLite 历史的近 7 日任务洞察、成功率/耗时/高频项目与 Markdown 周报复制/导出  
19. App Server 自动恢复：指数退避重连、Mock 后台升级真实数据、旧客户端响应隔离  
20. 账号/额度/Token/任务端点级健康监控、部分异常状态与关键接口连续失败自愈  
21. 本地额度样本与消耗预测：预计耗尽时间、重置时剩余量、提前耗尽风险，App、菜单栏与 Widget 共享展示，并支持采集/清除控制  
22. Artificial Analysis Data API：仅展示 OpenAI 模型的质量、每任务成本、输出速度三榜；菜单栏提供 Top 6 模型 IQ/编程指数与近 7 天 Token 图表，使用 Keychain 密钥与 12 小时缓存  
23. Codex 账号隐私显示：菜单栏、看板、连接状态、日志与诊断信息统一使用脱敏邮箱  
24. 额外额度重置预测：免费监控 OpenAI Status、帮助中心、OpenAI News、Codex 更新日志与官方 GitHub 发布，并可通过 Nitter/RSSHub 或自定义 RSS 代理关注 `@OpenAI`、`@OpenAIDevs`、`@sama`、`@thsottiaux`；显示 0～100 规则指数、预计窗口、可信度、依据与历史事件，不把指数冒充概率  
25. 可选信息任务栏：MIT 授权的 Meteocons 动态天气 SVG 随应用离线分发并融入胶囊左侧，同时显示所选地区的温度、星期和本地时间；支持 macOS/Windows、IANA 时区、离线 last-good 缓存与 Open-Meteo/GeoNames 署名，不请求图片 CDN  
26. API Key/DeepSeek 等自定义 provider 下，今日 Token 回退到本机全部 session 的 `token_count`/`usage` 汇总；提供方只返回 0 时采用本地估算并在详情中标明来源，不冒充服务商账单
27. GitHub Releases 更新检查：macOS 与 Windows 启动后及运行中每 5 分钟自动检查最新版，应用激活、休眠唤醒或网络恢复时会补查，设置/托盘支持手动检查；发现新版本时胶囊自适应显示更新图标，悬停提示、点击查看版本与说明，并支持立即更新或跳过当前版本

## 更新与发布

应用通过 GitHub 官方 `releases/latest` 接口检查公开的正式 Release，客户端不保存 GitHub Token。发布新版本时：

```bash
./Scripts/set-version.sh 0.1.24
git add .
git commit -m "Release 0.1.24"
git tag v0.1.24
git push origin main --tags
```

推送 `v*` 标签后，[Release 工作流](.github/workflows/release.yml)会构建通用 macOS DMG 与 Windows NSIS 安装包、生成 SHA-256 校验文件并创建 GitHub Release。已安装且包含更新功能的旧版本会在启动、每 5 分钟轮询、应用激活、休眠唤醒或网络恢复时检查新版本并显示更新图标；跳过后同一版本不再提示，只有更高版本发布时重新提醒。也可以在 macOS“设置 → 系统”、Windows“更多设置”或托盘菜单中手动检查。

本地打包 macOS：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./Scripts/package-macos.sh
```

公开分发前建议配置 Apple Developer ID、公证和 Windows 代码签名证书；当前工作流未内置任何私钥或证书。

## 目录结构

```
Codex-Pulse/
├── CodexPulse/              # 主应用 (MenuBarExtra + Dashboard + Settings)
│   └── Services/            # 主应用专用外部数据服务（含 Artificial Analysis）
├── CodexPulseWidget/        # 中尺寸 WidgetKit
├── Shared/                  # 模型、服务、存储（App + Widget 共享）
│   ├── Models/
│   ├── Services/            # PulseStore, Mock/Stdio client, Notifications
│   ├── Storage/
│   └── Utilities/
├── preview/index.html       # 交互预览（第一版交付）
├── windows/                  # Windows Electron 托盘应用
├── docs/PRD.md
├── docs/DEVELOPMENT.md
├── project.yml
└── Scripts/generate-xcodeproj.sh
```

## 技术栈

Swift · SwiftUI · WidgetKit · MenuBarExtra · Charts · UserNotifications · Security/Keychain · App Groups · Electron  
数据：本机 `codex app-server`（JSON-RPC / JSONL）、Artificial Analysis Data API、Open-Meteo 天气接口与 OpenAI 官方免费公开信息；开发期 Mock。

## 核心价值

| 价值 | 说明 |
|------|------|
| 无需打开 Codex 即可查看额度 | 菜单栏 / 小组件显示进度与倒计时 |
| 实时任务状态 | 运行中、等待授权、完成、失败 |
| Token 统计 | 今日 / 累计 / 趋势 / 连续天数 |
| 模型选择参考 | 独立基准的质量 / 每任务成本 / 输出速度排行榜 |
| 额度预警 | 可配置阈值通知 |
| 本地优先 | 不上传代码、对话、凭证 |

## 文档

- [产品需求文档（PRD）](docs/PRD.md)  
- [开发与运行指南](docs/DEVELOPMENT.md)  

## 后续方向

1. 排行榜筛选、搜索、收藏与当前任务模型对照  
2. 重置卡二次确认消耗  

## 宣传语

**让 Codex 的每一个 Token，都清晰可见。**

---

*Codex-Pulse — 本地运行 · 实时监控 · 低干扰展示*

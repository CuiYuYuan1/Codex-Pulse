# 真实 Codex 数据接入

## 概览

Codex-Pulse 通过本机子进程 `codex app-server` 接入官方数据，**不**上传任何数据。macOS 主流程不读取登录凭证文件；Windows 为检测账号切换会读取 `%CODEX_HOME%/auth.json` 的公开字段并只比较截短哈希，不保存或上传原始密钥。

```
Codex-Pulse (MenuBar)
        │  spawn Process
        ▼
  codex app-server
        │  JSONL / JSON-RPC (stdio)
        ▼
  account/* · thread/* · turn/* 事件
```

协议参考：

- [openai/codex app-server README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [Developers guide (gist)](https://gist.github.com/oneryalcin/ee2c27e2d8aa040da8fbe7eebcc2ecea)
- 本机生成 schema：`codex app-server generate-json-schema --out docs/schemas`

## 握手

1. 启动：`codex app-server`（默认 stdio JSONL）  
2. 请求 `initialize`（`clientInfo.name = codex_pulse`）  
3. 通知 `initialized`  
4. 之后可调用 `account/*`、`thread/*` 等  

Wire 上**省略** `"jsonrpc":"2.0"` 字段。

## 已实现方法

| 方法 | 用途 | 映射 |
|------|------|------|
| `account/read` | 登录态、邮箱、套餐 | `AccountInfo` |
| `account/rateLimits/read` | 主/次额度、重置时间、重置卡 | `RateLimitSnapshot` |
| `account/usage/read` | 累计 Token、日桶、连续天数 | `UsageStats`（API Key 账号常为空） |
| 本机 `sessions/**.jsonl` 的 `token_count` / provider `usage` | 当日实时 Token 补源；切换账号或自定义 provider 后立即重读 | 优先真实计数；第三方仅返回 0 时在内存中估算会话文本并在详情中标注来源，不保存或上传对话内容 |
| `thread/list` | 最近会话 | `TaskRecord[]` |

## 已监听事件

| 事件 | 行为 |
|------|------|
| `account/updated` | 全量刷新 |
| `account/rateLimits/updated` | 合并额度桶（稀疏更新） |
| `turn/started` / `turn/completed` | 更新当前任务 |
| `item/started` / `item/completed` | 更新步骤与启发式状态 |

噪声大的 delta 在 `initialize.capabilities.optOutNotificationMethods` 中关闭。

## 降级策略

1. 优先 `StdioCodexAppServerClient`  
2. 失败（无 CLI / 进程错误 / 握手失败）且设置「CLI 不可用时使用演示数据」开启 → `MockCodexAppServerClient`  
3. 菜单栏显示连接详情；可点 **重连**  

## 本机验证

```bash
# 1) 已安装并登录
codex --version
codex login   # 若未登录

# 2) 协议探测（打印 account / rateLimits / usage / threads）
chmod +x Scripts/probe-app-server.sh
./Scripts/probe-app-server.sh

# 3) 运行 App
./Scripts/generate-xcodeproj.sh
open CodexPulse.xcodeproj
```

天气接口契约（地区重名、WMO 字段、15 分钟间隔和跨时区响应）可用以下只读冒烟测试验证；它不依赖 Codex 登录，也不保存响应：

```bash
./Scripts/probe-weather-api.sh
```

探测成功时，`account/read` 应返回类似：

```json
{
  "account": {
    "type": "chatgpt",
    "email": "you@example.com",
    "planType": "pro"
  },
  "requiresOpenaiAuth": true
}
```

## 源码位置

| 文件 | 职责 |
|------|------|
| `Shared/Services/StdioCodexAppServerClient.swift` | Process + JSONL RPC |
| `Shared/Services/ProtocolDTOs.swift` | Wire DTO |
| `Shared/Services/ProtocolMapper.swift` | DTO → 领域模型 |
| `Shared/Services/PulseStore.swift` | 连接、刷新、事件、降级 |
| `Scripts/probe-app-server.sh` | 命令行探测 |

## 天气信息任务栏（Open-Meteo）

信息任务栏默认关闭。开启后，用户必须先从地区搜索结果中确认一个地点；本地设置只保存地点名称、行政区、国家、纬度、经度和 IANA 时区（Windows 同时保留供应商结果 ID）。关闭任务栏不会删除已选地点，重新开启时可以直接复用。

### 请求

天气功能不需要 API Key。地区搜索会发送用户输入的城市名；天气请求只发送用户确认后的经纬度和时区，不发送 Codex 账号、Token、项目路径或对话内容：

```text
GET https://geocoding-api.open-meteo.com/v1/search
    ?name=<用户输入>&count=8&language=zh&format=json

GET https://api.open-meteo.com/v1/forecast
    ?latitude=<已确认纬度>&longitude=<已确认经度>
    &current=temperature_2m,weather_code,is_day
    &timezone=<已保存的 IANA 时区或 auto>&forecast_days=1
```

地区输入至少两个字符，并在结果中同时显示 `name · admin1 · country`。不要只根据用户输入或第一条结果猜地点：例如“衡阳”可能先返回福建同名地点，而“衡阳市”才会返回湖南衡阳市。天气响应的 `timezone` 用于任务栏的星期和当前时间；`current.time` 是天气网格的 15 分钟有效时间戳，不应替代实时系统时钟。

### 刷新与离线边界

- 地区搜索只在用户输入（带 debounce）或主动确认时请求，并缓存已返回的结果。
- 天气成功值按地点缓存，正常约每 15 分钟刷新；应用回到前台或网络恢复时可立即刷新。
- 请求失败、超时或返回无效 JSON 时保留最近一次成功天气，并显示缓存/离线状态；首次从未成功时显示明确的同步中/不可用状态，不用演示数值冒充真实天气。
- 切换地点或跨午夜时取消旧请求、重新计算本地时区的星期/时间；旧地点的响应不得覆盖新地点。
- 以 WMO weather interpretation code 映射动态场景：晴（0）、多云（1–3）、雾（45/48）、毛毛雨（51–57）、雨（61–67/80–82）、雪（71–77/85/86）和雷雨（95/96/99）。未知代码使用中性场景。

### 许可、调用限制与署名

Open-Meteo 的 Free/Open-Access 接口仅限非商业用途，并限制为每日 10,000、每小时 5,000、每分钟 600、每月 300,000 次调用；商业产品、订阅或含广告的应用应使用其 API subscription。天气数据采用 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)，显示天气的位置旁必须提供可点击署名：[Weather data by Open-Meteo.com](https://open-meteo.com/)。地区库来自 [GeoNames](https://www.geonames.org/)，同样需要 CC-BY 署名和许可链接。Windows 地区选择器与 macOS 设置/关于页都应保留这些链接。

天气视觉使用 Meteocons Fill 系列的动态 SVG，随应用离线分发；太阳、云、雨、雪和雷电动画均来自素材本身，不依赖第三方图片 CDN。来源、条件映射与 MIT 许可见 [WEATHER_ASSETS.md](WEATHER_ASSETS.md)。

## Artificial Analysis 模型排行榜

完整看板还会调用 Artificial Analysis Data API 的免费模型列表：

```text
GET https://artificialanalysis.ai/api/v2/language/models/free?page=1
x-api-key: <用户在设置中填写的 Key>
```

客户端自动遍历分页，并仅筛选 `model_creator.name = OpenAI` 的模型生成三类榜单：

| 榜单 | 官方字段 | 排序 |
|------|----------|------|
| 模型质量 | `evaluations.artificial_analysis_intelligence_index` | 越高越好 |
| 任务成本 | `artificial_analysis_intelligence_index_cost.cost_per_task.total_cost` | 越低越好 |
| 输出速度 | `performance.median_output_tokens_per_second` | 越高越好 |

API Key 不放在文件、源码或 `UserDefaults` 中。请在 **设置 → Artificial Analysis** 填写，应用会将它保存为当前 Mac 的 Keychain 通用密码项；删除 Key 也在同一区域完成。公开排行榜响应缓存于 Application Support 目录 12 小时，手动刷新会立即请求官方接口。看板保留可见的数据来源链接，但不展示 API 请求剩余额度。

实现位置：

| 文件 | 职责 |
|------|------|
| `CodexPulse/Services/ArtificialAnalysisService.swift` | Keychain、分页 API、限流、容错与缓存 |
| `CodexPulse/Views/Dashboard/ModelLeaderboardsView.swift` | 质量、成本、速度排行榜 |
| `CodexPulse/Views/Settings/SettingsView.swift` | Key 的填写、更新、删除和同步状态 |

官方文档：[Artificial Analysis Data API](https://artificialanalysis.ai/data-api/docs)。该第三方请求只发送用户填写的 API Key 和页码，不发送 Codex 账号、额度、任务、项目或对话数据。

## 额外额度重置预测

该模块与现有额度倒计时相互独立。正常 5 小时或每周额度恢复仍以 `account/rateLimits/read` 为准，绝不计入预测；预测只覆盖全局/故障补偿重置、Banked Reset、临时移除限制或扩容、套餐限额调整、新模型庆祝活动与推荐奖励。

### 官方数据源

| 来源 | 获取方式 | 用途 |
|------|----------|------|
| OpenAI Status | `GET https://status.openai.com/api/v2/incidents.json` | Codex 故障、严重故障与额度异常消耗信号 |
| OpenAI Help Center | 官方帮助文章 | 活动、推荐奖励与 Banked Reset 说明 |
| Codex changelog | 官方 Codex 更新日志 | 新模型、限额调整及明确重置公告 |
| OpenAI News | `https://openai.com/news/` | 产品发布、模型发布和官方活动 |
| OpenAI Codex GitHub | `https://github.com/openai/codex/releases.atom` | Codex CLI 与模型相关发布说明 |
| 第三方 X RSS | Nitter：`https://实例/{username}/rss`；RSSHub：`https://实例/twitter/user/{username}` | `@OpenAI`、`@OpenAIDevs`、`@sama`、`@thsottiaux` 的公开动态 |

OpenAI 官方来源均可匿名免费读取，无需 API Key、账号、Cookie 或付费 credits。第三方 X RSS 由用户主动启用，客户端只读取用户配置的 RSS/Atom URL，不直接登录或抓取 X；代理服务自身可能依赖 X 账号、Cookie 或非官方接口。数据默认每 30 分钟更新并缓存到 Application Support；单个来源暂时不可用时，其余来源仍会继续参与评分。

设置中的代理模板必须包含 `{username}`。内置预设为 `https://nitter.net/{username}/rss` 和 `https://rsshub.app/twitter/user/{username}`，也可以替换为其他公共或自托管 HTTPS 实例；仅本机 `localhost` 允许 HTTP。公共实例可能延迟、缺失、返回被修改的内容或随时停止服务。

### 第一版规则

- 明确官方确认直接显示 `100/100 · 官方确认`，并解析 `later today`、`next 24 hours` 等时间表述。
- 其他信号按来源和语义给予 15～90 的基础权重，再按 12～72 小时半衰期衰减。
- 同一事件的相同帖子、引用帖子和重复内容先去重；独立来源可获得多源加成。
- 只有 Status 故障信号时最高为 55；普通 Codex 故障不会自动得到高指数。
- 第三方 X RSS 会在证据和理由中明确标记；未经其他官方免费来源印证时，最高为 99，不能单独触发“官方确认”。
- 已明确完成且超过 24 小时的重置移入历史记录，不继续显示为即将发生。
- 结果统一显示为“重置预测指数 N/100”，分为暂无迹象、低可能、存在可能、高可能、极高可能和官方确认。

这是透明规则评分，不是经过历史校准的统计概率，因此第一版不显示“概率百分比”。每次结果必须列出实际采用的依据；没有有效证据时固定显示“暂无额外额度重置信号 / 当前仅显示正常额度恢复时间”。

实现位置：

| 文件 | 职责 |
|------|------|
| `CodexPulse/Services/CodexResetPredictionService.swift` | Status、官方文档、新闻、GitHub 与第三方 RSS/Atom 采集、缓存、去重、评分、衰减、多源加成与历史 |
| `CodexPulse/Views/Dashboard/ResetPredictionView.swift` | 指数、状态、预计窗口、可信度、依据与证据链接 |
| `CodexPulse/Views/MenuBar/MenuBarPanelView.swift` | 菜单栏紧凑指数 |
| `CodexPulse/Views/Settings/SettingsView.swift` | 监控开关、Nitter/RSSHub/自定义代理模板、来源状态与手动刷新 |

## 沙箱说明

主应用 entitlements 关闭 App Sandbox，以便 spawn `codex`。  
Widget 仍沙箱化，经 App Group 读共享快照。

## 已知限制（MVP）

- 未实现审批回包（`execCommandApproval` 等）— 仅监控，不驱动任务  
- 未实现重置卡 `account/rateLimitResetCredit/consume` 二次确认 UI  
- `turn` 事件里项目路径字段随 CLI 版本可能变化，做了 best-effort 解析  
- “今日 Token”会把本机当天全部 session 的 `token_count` 或第三方响应 `usage` 合入标题数字（包含跨日续用会话的回看窗口），切换 ChatGPT 账号、API Key 或 DeepSeek 等自定义 provider 后立即重新读取，不需要重启。自定义 provider 未暴露 usage 时使用本地文本估算，并在展开详情中标明来源。由于本机日志不带账号 ID，这一数字是设备汇总而不是单一账号的官方账单；生命周期累计与原生 ChatGPT 历史桶仍按远端账号隔离
- 官方日桶可能延迟到次日；菜单栏的「今日 Token」会取官方值与本机会话累计值中的较大者
- 当前开发沙箱为 Linux，**真实联调需在已安装 Codex 的 Mac 上**运行探测脚本与 Xcode  

## 升级 CLI 后

schema 可能漂移：

```bash
codex app-server generate-ts --out /tmp/codex-schemas
# 对照 ProtocolDTOs.swift 更新字段
```

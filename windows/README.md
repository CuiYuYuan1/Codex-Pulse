# Codex-Pulse Windows

Windows 版本是独立的 Electron 托盘应用，不能直接复用 macOS 的 SwiftUI/WidgetKit 二进制。

## 用户使用

1. 双击 `CodexPulse-Windows-0.1.19-x64.exe`（以发布目录中的实际版本为准）。
2. 应用会优先从正在运行的 Codex/ChatGPT 桌面版中获取内置 Codex 引擎，也兼容单独安装的 Codex CLI。对于 Windows Store/MSIX 保护目录中的引擎，会自动暂存到当前用户的应用数据目录后运行。
3. 如果安装位置发生变化，展开胶囊并点击“获取路径”，应用会清除旧记录并重新自动扫描。

程序不会写死开发者的路径。查找顺序为：

1. 用户上次保存且仍通过 app-server 校验的路径；
2. 正在运行的 Codex/ChatGPT 桌面版内置引擎及应用安装目录；
3. `CODEX_PULSE_CODEX_PATH` 环境变量；
4. npm、Scoop、`.local/bin` 等常见 CLI 安装目录；
5. Windows `where codex`（自动排除无法启动 CLI 的 WindowsApps 应用别名）；
6. 用户手动选择。

选择结果保存在当前 Windows 用户自己的 `%APPDATA%/CodexPulse` 应用数据目录中。便携版已包含 Electron 运行时，不要求安装 Node.js，但用户电脑需要已安装并登录 Codex。

## 信息任务栏

展开胶囊，在“信息任务栏”旁打开开关并搜索地区。开启后，本地天气底图与动态云雨雪效果融入胶囊左侧，下方显示温度、地区、星期和该地区本地时间；关闭后恢复原胶囊布局。天气请求不需要 API Key，网络不可用时保留上次成功结果，背景图片随安装包分发且不会请求图片 CDN。

天气数据由 [Open-Meteo](https://open-meteo.com/) 提供，地区数据由 [GeoNames](https://www.geonames.org/) 提供。免费开放接口主要适用于非商业用途，商业发行请遵循相应许可条款。

API Key 或 DeepSeek 等自定义模型提供方通常不会返回 ChatGPT 活跃用量；“今日 Token”优先汇总本机全部 session JSONL 的真实 `token_count`/响应 `usage`。如果提供方只返回 0，则使用本机会话文本估算，并在展开详情中明确标注估算来源，不会冒充服务商账单。它不包含控制台中的其他 API 调用，也不能替代账单金额。

## 本地打包

```powershell
cd windows
npm install
npm run pack:win
```

产物输出到 `dist/windows/`。

#!/usr/bin/env bash
# 在 macOS 上生成 Xcode 工程并提示打开
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "未安装 XcodeGen。安装: brew install xcodegen"
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "未检测到 Xcode 命令行工具。请安装 Xcode。"
  exit 1
fi

xcodegen generate
echo "已生成 CodexPulse.xcodeproj"
echo "打开: open CodexPulse.xcodeproj"
echo "运行: 选择 CodexPulse scheme → Run (⌘R)"
echo "小组件: 运行后在桌面添加「Codex 额度」中尺寸小组件"

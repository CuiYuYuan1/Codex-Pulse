#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
  echo "用法：$0 0.1.24" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$1"
cd "$ROOT_DIR"

sed -i '' -E "s/MARKETING_VERSION: \"[^\"]+\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
(
  cd windows
  npm version "$VERSION" --no-git-tag-version
)

echo "版本已更新为 $VERSION"
echo "确认后提交，再执行：git tag v$VERSION && git push origin v$VERSION"

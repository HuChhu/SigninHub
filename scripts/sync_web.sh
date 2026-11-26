#!/usr/bin/env bash
# 把 backend/web 同步到 android/app/src/main/assets。
#
# ## 为什么需要这个脚本
# 网页控制台有**两份物理副本**：
#   · backend/web/                     — 后端和 iOS 用
#   · android/app/src/main/assets/     — Android App 用（WebViewAssetLoader 从 assets 读）
#
# 之前靠人工 cp，两边一旦不同步就会分叉：Android 用户和电脑端看到不同的界面。
# 这个脚本是唯一的同步入口，CI 和本地都跑它。
#
# 用法：
#   scripts/sync_web.sh           # 后端 → Android
#   scripts/sync_web.sh --check   # 只检查是否一致，不一致就非零退出（CI 用）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/backend/web"
DST="$ROOT/android/app/src/main/assets"

# 需要同步的文件清单（相对路径）。新加页面记得加到这里。
FILES=(
  "index.html"
  "sw.js"
  "manifest.webmanifest"
  "static/app.js"
  "static/app.css"
  "static/icon-180.png"
  "static/icon-192.png"
  "static/icon-512.png"
)

check=0
[[ "${1:-}" == "--check" ]] && check=1

diffs=0
missing=0
for f in "${FILES[@]}"; do
  if [[ ! -f "$SRC/$f" ]]; then
    echo "  [缺] backend/web/$f 不存在"
    missing=1
    continue
  fi
  if [[ $check -eq 1 ]]; then
    if ! cmp -s "$SRC/$f" "$DST/$f"; then
      echo "  [分叉] $f"
      diffs=1
    fi
  else
    mkdir -p "$(dirname "$DST/$f")"
    cp -f "$SRC/$f" "$DST/$f"
  fi
done

# logos 目录整棵同步
if [[ -d "$SRC/static/logos" ]]; then
  if [[ $check -eq 1 ]]; then
    if ! diff -rq "$SRC/static/logos" "$DST/static/logos" >/dev/null 2>&1; then
      echo "  [分叉] static/logos/"
      diffs=1
    fi
  else
    mkdir -p "$DST/static/logos"
    cp -f "$SRC"/static/logos/* "$DST/static/logos/" 2>/dev/null || true
  fi
fi

if [[ $check -eq 1 ]]; then
  if [[ $missing -eq 1 || $diffs -eq 1 ]]; then
    echo ""
    echo "网页资源已分叉：先跑 scripts/sync_web.sh 再提交。"
    exit 1
  fi
  echo "网页资源一致（${#FILES[@]} 个文件 + logos）"
else
  echo "已同步 backend/web → android/app/src/main/assets"
fi

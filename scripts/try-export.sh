#!/usr/bin/env bash
# 静默尝试通过 dev server 的导出接口生成 zip。
#
# 用法：
#   OUT=$(bash scripts/try-export.sh <pageName>)
#   if [[ -n "$OUT" ]]; then echo "导出成功：$OUT"; else echo "跳过 zip"; fi
#
# 行为：
#   - 成功：把 zip 写到 /tmp/<basename>.zip，并在 stdout 打印这个路径
#   - 失败（dev server 不在线 / 接口 404 / 非 zip）：静默 exit 0，stdout 为空
#   这样 agent 可以把它当"可有可无"的附件，不用关心环境差异。
#
# pageName 是 src/pages/ 下去掉扩展名的相对路径，例如：
#   转介绍周任务-最终版
#   报告/报告测试1
#   landing/index
#
# 可选环境变量：
#   DEV_SERVER_URL  默认 http://localhost:5173
#   EXPORT_PATH     默认 /__api/export-html

set -uo pipefail  # 注意不用 -e，失败时要静默退出而不是 trace

PAGE_NAME="${1:-}"
if [[ -z "$PAGE_NAME" ]]; then
  exit 0
fi

DEV_SERVER_URL="${DEV_SERVER_URL:-http://localhost:5173}"
EXPORT_PATH="${EXPORT_PATH:-/__api/export-html}"

command -v curl >/dev/null 2>&1 || exit 0
command -v jq   >/dev/null 2>&1 || exit 0

# 探活：最多等 1.5 秒，避免卡住
if ! curl -sf --max-time 1.5 -o /dev/null -I "$DEV_SERVER_URL/" 2>/dev/null; then
  exit 0
fi

OUT_PATH="/tmp/$(basename "$PAGE_NAME").zip"
BODY="$(jq -cn --arg p "$PAGE_NAME" '{pageName:$p}')"

if ! curl -sf --max-time 30 -o "$OUT_PATH" \
     -X POST "$DEV_SERVER_URL$EXPORT_PATH" \
     -H "Content-Type: application/json" \
     -d "$BODY" 2>/dev/null; then
  rm -f "$OUT_PATH"
  exit 0
fi

if ! file "$OUT_PATH" 2>/dev/null | grep -q "Zip archive"; then
  rm -f "$OUT_PATH"
  exit 0
fi

echo "$OUT_PATH"

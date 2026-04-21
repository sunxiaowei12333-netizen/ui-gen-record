#!/usr/bin/env bash
# 往 UI 页面生成记录表追加一条记录（可带多个附件）
#
# 用法：
#   bash ~/.cursor/skills/ui-gen-record/scripts/append.sh \
#     --req-name "..." \
#     --req-date "YYYY-MM-DD HH:mm:ss" \
#     --preview-url "..." --design-url "..." \
#     --model "Claude Opus 4.7" \
#     --mod-count "47" --token-usage "1,000,000" --usd-cost "\$25.00" \
#     --attachment "/abs/path/one.zip" --attachment "/abs/path/two.tsx"
#
# 依赖：lark-cli、jq；需要先跑过 bootstrap.sh

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$SKILL_DIR/.config.json"

if [[ ! -f "$CONFIG" ]]; then
  echo "[append] 未找到 .config.json，请先执行 bootstrap.sh"
  exit 1
fi

REQ_NAME=""; REQ_DATE="$(date +'%Y-%m-%d %H:%M:%S')"
PREVIEW_URL=""; DESIGN_URL=""; MODEL=""
MOD_COUNT=""; TOKEN_USAGE=""; USD_COST=""
ATTACHMENTS=()

while (( $# > 0 )); do
  case "$1" in
    --req-name)     REQ_NAME="$2"; shift 2 ;;
    --req-date)     REQ_DATE="$2"; shift 2 ;;
    --preview-url)  PREVIEW_URL="$2"; shift 2 ;;
    --design-url)   DESIGN_URL="$2"; shift 2 ;;
    --model)        MODEL="$2"; shift 2 ;;
    --mod-count)    MOD_COUNT="$2"; shift 2 ;;
    --token-usage)  TOKEN_USAGE="$2"; shift 2 ;;
    --usd-cost)     USD_COST="$2"; shift 2 ;;
    --attachment)   ATTACHMENTS+=("$2"); shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "[append] 未知参数 $1"; exit 2 ;;
  esac
done

if [[ -z "$REQ_NAME" ]]; then
  echo "[append] --req-name 必填"
  exit 3
fi

BASE_TOKEN="$(jq -r '.base_token' "$CONFIG")"
TABLE_ID="$(jq   -r '.table_id'   "$CONFIG")"
BASE_URL="$(jq   -r '.base_url'   "$CONFIG")"

# `Token消耗` / `美元花费` 是 number 字段，飞书原生千分位 / USD 货币格式化。
# 外部参数保持兼容：允许传 "1,000,000" / "$25.00" 这种人类可读字符串，
# 这里剥掉分隔符和货币符号后作为 number 写入。
TOKEN_NUM=""
if [[ -n "$TOKEN_USAGE" ]]; then
  cleaned="${TOKEN_USAGE//,/}"
  cleaned="${cleaned// /}"
  if [[ "$cleaned" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    TOKEN_NUM="$cleaned"
  fi
fi
USD_NUM=""
if [[ -n "$USD_COST" ]]; then
  cleaned="${USD_COST//\$/}"
  cleaned="${cleaned//,/}"
  cleaned="${cleaned// /}"
  if [[ "$cleaned" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    USD_NUM="$cleaned"
  fi
fi

# 构造 upsert payload
PAYLOAD="$(jq -n \
  --arg    req_name     "$REQ_NAME" \
  --arg    req_date     "$REQ_DATE" \
  --arg    preview_url  "$PREVIEW_URL" \
  --arg    design_url   "$DESIGN_URL" \
  --arg    model        "$MODEL" \
  --arg    mod_count    "$MOD_COUNT" \
  --arg    token_num    "$TOKEN_NUM" \
  --arg    usd_num      "$USD_NUM" \
  '
  {"需求名称":$req_name, "需求日期":$req_date}
  + (if $preview_url != "" then {"预览链接":$preview_url} else {} end)
  + (if $design_url  != "" then {"设计稿链接":$design_url} else {} end)
  + (if $model       != "" then {"使用模型":$model} else {} end)
  + (if $mod_count   != "" then {"修改次数":$mod_count} else {} end)
  + (if $token_num   != "" then {"Token消耗":($token_num|tonumber)} else {} end)
  + (if $usd_num     != "" then {"美元花费":($usd_num|tonumber)} else {} end)
  ')"

RESP="$(lark-cli base +record-upsert --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" --json "$PAYLOAD")"
RECORD_ID="$(echo "$RESP" | jq -r '.data.record.record_id_list[0] // empty')"
if [[ -z "$RECORD_ID" ]]; then
  echo "[append] 写入记录失败：$RESP"
  exit 4
fi
echo "[append] 已创建记录 $RECORD_ID"

# 上传附件（lark-cli 要求相对路径，统一复制到 /tmp 再上传）
if (( ${#ATTACHMENTS[@]} > 0 )); then
  FIELD_FILE="$(jq -r '.field_ids."文件"' "$CONFIG")"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  for src in "${ATTACHMENTS[@]}"; do
    if [[ ! -f "$src" ]]; then
      echo "[append] 附件不存在，跳过：$src"
      continue
    fi
    base="$(basename "$src")"
    # URL-decode 常见的 URL 编码文件名（Downloads 目录常见）
    decoded_base="$(python3 -c "import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1]))" "$base" 2>/dev/null || echo "$base")"
    dest="$TMP_DIR/$decoded_base"
    cp "$src" "$dest"
    ( cd "$TMP_DIR" && \
      sleep 1 && \
      lark-cli base +record-upload-attachment --as bot \
        --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" \
        --record-id "$RECORD_ID" --field-id "$FIELD_FILE" \
        --file "./$decoded_base" >/dev/null )
    echo "[append] 已上传附件：$decoded_base"
  done
fi

echo "[append] 完成。查看记录：$BASE_URL"

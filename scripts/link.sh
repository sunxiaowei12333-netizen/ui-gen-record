#!/usr/bin/env bash
# 绑定 skill 到一张「已经存在」的飞书多维表格。
#   1. 从 URL 解析 base_token（以及可选的 table_id / view_id）
#   2. 通过 lark-cli 拉 table/field 列表，按字段名反查出 field_ids
#   3. 校验 schema 是否完整（10 个必备字段都要在）
#   4. 写入 .config.json，覆盖原先的指向
#
# 用法：
#   bash ~/.cursor/skills/ui-gen-record/scripts/link.sh <base_url>
#   bash ~/.cursor/skills/ui-gen-record/scripts/link.sh --force <base_url>
#
# 依赖：lark-cli（已登录且对该 Base 有访问权限）、jq

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$SKILL_DIR/.config.json"

FORCE=0
URL=""
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
    -h|--help)
      sed -n '2,14p' "$0"; exit 0 ;;
    *) URL="$arg" ;;
  esac
done

if [[ -z "$URL" ]]; then
  echo "[link] 缺少 base_url 参数。用法：bash scripts/link.sh <base_url>"
  exit 1
fi

command -v lark-cli >/dev/null 2>&1 || { echo "[link] 未找到 lark-cli"; exit 2; }
command -v jq       >/dev/null 2>&1 || { echo "[link] 未找到 jq"; exit 2; }

# ===== 步骤 1：解析 URL =====
# 兼容：https://xxx.feishu.cn/base/<token>?table=<table_id>&view=<view_id>
#       https://xxx.larksuite.com/base/<token>
BASE_TOKEN="$(echo "$URL" | sed -nE 's|.*/base/([A-Za-z0-9]+).*|\1|p')"
URL_TABLE_ID="$(echo "$URL" | sed -nE 's|.*[?&]table=([A-Za-z0-9]+).*|\1|p')"
URL_VIEW_ID="$(echo  "$URL" | sed -nE 's|.*[?&]view=([A-Za-z0-9]+).*|\1|p')"

if [[ -z "$BASE_TOKEN" ]]; then
  echo "[link] 从 URL 中解析 base_token 失败：$URL"
  echo "[link] 期望 URL 形如 https://xxx.feishu.cn/base/<base_token>?table=<table_id>"
  exit 3
fi
BASE_URL_CLEAN="$(echo "$URL" | sed -E 's|\?.*$||')"
echo "[link] BASE_TOKEN=$BASE_TOKEN"

# ===== 步骤 2：定位 table_id =====
if [[ -f "$CONFIG" && "$FORCE" -ne 1 ]]; then
  echo "[link] .config.json 已存在。若要切换到该链接指向的表，加 --force 覆盖。当前配置："
  cat "$CONFIG"
  exit 0
fi

TABLE_LIST="$(lark-cli base +table-list --as user --base-token "$BASE_TOKEN")"
# 兼容不同版本 lark-cli：items 里字段名可能是 table_name 或 name
if [[ -n "$URL_TABLE_ID" ]]; then
  TABLE_ID="$URL_TABLE_ID"
  TABLE_NAME="$(echo "$TABLE_LIST" | jq -r --arg tid "$TABLE_ID" '.data.items[] | select(.table_id==$tid) | (.table_name // .name)' | head -n1)"
  if [[ -z "$TABLE_NAME" || "$TABLE_NAME" == "null" ]]; then
    echo "[link] URL 中的 table_id=$TABLE_ID 在该 Base 下找不到"
    exit 4
  fi
else
  TABLE_ID="$(echo   "$TABLE_LIST" | jq -r '.data.items[0].table_id')"
  TABLE_NAME="$(echo "$TABLE_LIST" | jq -r '.data.items[0].table_name // .data.items[0].name')"
  echo "[link] URL 未带 table 参数，使用首张表 $TABLE_NAME ($TABLE_ID)"
fi
[[ -z "$TABLE_ID" || "$TABLE_ID" == "null" ]] && { echo "[link] 获取 table_id 失败"; exit 4; }
echo "[link] TABLE_ID=$TABLE_ID  TABLE_NAME=$TABLE_NAME"

# ===== 步骤 3：定位 view_id =====
VIEW_LIST="$(lark-cli base +view-list --as user --base-token "$BASE_TOKEN" --table-id "$TABLE_ID")"
if [[ -n "$URL_VIEW_ID" ]]; then
  VIEW_ID="$URL_VIEW_ID"
else
  VIEW_ID="$(echo "$VIEW_LIST" | jq -r '.data.items[0].view_id')"
fi
echo "[link] VIEW_ID=$VIEW_ID"

# ===== 步骤 4：扫字段并按字段名映射出 field_ids =====
FIELD_LIST="$(lark-cli base +field-list --as user --base-token "$BASE_TOKEN" --table-id "$TABLE_ID")"

get_fid() {
  local name="$1"
  echo "$FIELD_LIST" | jq -r --arg n "$name" '.data.items[] | select(.field_name==$n) | .field_id' | head -n1
}

# 为兼容 macOS 自带 bash 3.2（不支持关联数组），用平行变量承载 10 个字段 id
REQ_NAMES=("需求名称" "需求日期" "预览链接" "设计稿链接" "使用模型" "文件" "修改次数" "Token消耗" "美元花费" "月份")
FID_REQ_NAME=""; FID_REQ_DATE=""; FID_PREVIEW=""; FID_DESIGN=""; FID_MODEL=""
FID_FILE="";     FID_MOD_COUNT=""; FID_TOKEN=""; FID_USD="";  FID_MONTH=""
MISSING=""
for n in "${REQ_NAMES[@]}"; do
  id="$(get_fid "$n")"
  if [[ -z "$id" ]]; then
    MISSING="$MISSING $n"
    continue
  fi
  case "$n" in
    "需求名称")   FID_REQ_NAME="$id" ;;
    "需求日期")   FID_REQ_DATE="$id" ;;
    "预览链接")   FID_PREVIEW="$id" ;;
    "设计稿链接") FID_DESIGN="$id" ;;
    "使用模型")   FID_MODEL="$id" ;;
    "文件")       FID_FILE="$id" ;;
    "修改次数")   FID_MOD_COUNT="$id" ;;
    "Token消耗")  FID_TOKEN="$id" ;;
    "美元花费")   FID_USD="$id" ;;
    "月份")       FID_MONTH="$id" ;;
  esac
done

if [[ -n "$MISSING" ]]; then
  echo "[link] ❌ 该表缺少以下必需字段：$MISSING"
  echo "[link] 本 skill 期望的 schema 见 SKILL.md「表结构」一节。"
  echo "[link] 要么改用 bootstrap.sh 新建一张规范的表，要么在目标表里手动补齐这些字段（名称需完全一致，类型参照 SKILL.md）。"
  exit 5
fi
echo "[link] ✅ 10 个必备字段全部匹配成功"

# ===== 步骤 5：拿 owner_open_id（用于记录当前登录用户）=====
USER_OPEN_ID="$(lark-cli auth list 2>/dev/null | jq -r '.[0].userOpenId // empty')"
USER_NAME="$(lark-cli    auth list 2>/dev/null | jq -r '.[0].userName   // empty')"

# ===== 步骤 6：尝试找同 Base 下的仪表盘（可选，仅做记录）=====
DASHBOARD_ID=""
DASH_RESP="$(lark-cli base +dashboard-list --as user --base-token "$BASE_TOKEN" 2>/dev/null || echo '{}')"
DASHBOARD_ID="$(echo "$DASH_RESP" | jq -r '.data.dashboards[0].dashboard_id // .data.items[0].dashboard_id // empty')"

# ===== 步骤 7：落盘配置 =====
if [[ -f "$CONFIG" ]]; then
  BACKUP="$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CONFIG" "$BACKUP"
  echo "[link] 原 .config.json 已备份到 $BACKUP"
fi

jq -n \
  --arg base_token   "$BASE_TOKEN" \
  --arg base_url     "$BASE_URL_CLEAN" \
  --arg table_id     "$TABLE_ID" \
  --arg table_name   "$TABLE_NAME" \
  --arg view_id      "$VIEW_ID" \
  --arg dashboard_id "$DASHBOARD_ID" \
  --arg owner        "$USER_OPEN_ID" \
  --arg owner_name   "$USER_NAME" \
  --arg req_name     "$FID_REQ_NAME" \
  --arg req_date     "$FID_REQ_DATE" \
  --arg preview      "$FID_PREVIEW" \
  --arg design       "$FID_DESIGN" \
  --arg model        "$FID_MODEL" \
  --arg file         "$FID_FILE" \
  --arg mod_count    "$FID_MOD_COUNT" \
  --arg token_usage  "$FID_TOKEN" \
  --arg usd_cost     "$FID_USD" \
  --arg month        "$FID_MONTH" \
  '{
    base_token:$base_token, base_url:$base_url,
    table_id:$table_id, table_name:$table_name,
    view_id:$view_id, dashboard_id:$dashboard_id,
    owner_open_id:$owner, owner_name:$owner_name,
    linked:true,
    field_ids:{
      "需求名称":$req_name,"需求日期":$req_date,
      "预览链接":$preview,"设计稿链接":$design,
      "使用模型":$model,"文件":$file,
      "修改次数":$mod_count,
      "Token消耗":$token_usage,"美元花费":$usd_cost,
      "月份":$month
    }
  }' > "$CONFIG"

echo
echo "[link] ============================================================"
echo "[link] 绑定完成。后续 append.sh 将把记录写入："
echo "[link]   $BASE_URL_CLEAN"
echo "[link] ============================================================"

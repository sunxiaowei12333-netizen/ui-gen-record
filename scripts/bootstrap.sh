#!/usr/bin/env bash
# 首次建表脚本：
#   1. 创建飞书多维表格（内含表 UI页面生成记录）
#   2. 配置业务字段：
#      - Token消耗 number(plain, precision=0, thousands_separator) 千分位整数
#      - 美元花费 number(currency, USD, precision=2)                 $xx.xx
#      - 月份     formula(text)，从需求日期派生 yyyy-MM
#   3. 设置视图按「月份」分组（分组生效即可，无需隐藏任何列）
#   4. 创建仪表盘「UI生成实时统计」并塞 6 个 block，SUM 基于 Token消耗 / 美元花费
#   5. 把当前 CLI 登录用户加为 full_access，并把 owner 转给该用户
#   6. 持久化配置到 .config.json
#
# 依赖：lark-cli（已登录）、jq
# 用法：bash ~/.cursor/skills/ui-gen-record/scripts/bootstrap.sh
# 成功退出码 0；失败非 0

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$SKILL_DIR/.config.json"
BASE_NAME="${BASE_NAME:-UI页面生成记录}"
TABLE_NAME="${TABLE_NAME:-UI页面生成记录}"
DASHBOARD_NAME="${DASHBOARD_NAME:-UI生成实时统计}"
TIME_ZONE="${TIME_ZONE:-Asia/Shanghai}"

if [[ -f "$CONFIG" ]]; then
  echo "[bootstrap] .config.json 已存在，跳过建表。内容如下："
  cat "$CONFIG"
  exit 0
fi

command -v lark-cli >/dev/null 2>&1 || { echo "[bootstrap] 未找到 lark-cli"; exit 1; }
command -v jq       >/dev/null 2>&1 || { echo "[bootstrap] 未找到 jq"; exit 1; }

# ===== 步骤 1：拿当前用户 open_id =====
USER_OPEN_ID="$(lark-cli auth list 2>/dev/null | jq -r '.[0].userOpenId // empty')"
USER_NAME="$(lark-cli auth list 2>/dev/null | jq -r '.[0].userName // empty')"
if [[ -z "$USER_OPEN_ID" ]]; then
  echo "[bootstrap] 未在 lark-cli 中找到登录用户，请先 'lark-cli auth login'"
  exit 2
fi
echo "[bootstrap] 当前用户: $USER_NAME ($USER_OPEN_ID)"

# ===== 步骤 2：创建 Base =====
echo "[bootstrap] 创建 Base: $BASE_NAME"
BASE_RESP="$(lark-cli base +base-create --as bot --name "$BASE_NAME" --time-zone "$TIME_ZONE")"
BASE_TOKEN="$(echo "$BASE_RESP" | jq -r '.data.base.base_token')"
BASE_URL="$(echo "$BASE_RESP"   | jq -r '.data.base.url')"
if [[ -z "$BASE_TOKEN" || "$BASE_TOKEN" == "null" ]]; then
  echo "[bootstrap] 创建 Base 失败：$BASE_RESP"
  exit 3
fi
echo "[bootstrap] BASE_TOKEN=$BASE_TOKEN"
echo "[bootstrap] BASE_URL=$BASE_URL"

# ===== 步骤 3：默认表重命名、拿默认视图 =====
sleep 1
TABLE_ID="$(lark-cli base +table-list --as bot --base-token "$BASE_TOKEN" | jq -r '.data.items[0].table_id')"
[[ -z "$TABLE_ID" || "$TABLE_ID" == "null" ]] && { echo "[bootstrap] 获取 table_id 失败"; exit 4; }
echo "[bootstrap] TABLE_ID=$TABLE_ID"

sleep 1
lark-cli base +table-update --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" --name "$TABLE_NAME" >/dev/null

sleep 1
VIEW_ID="$(lark-cli base +view-list --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" | jq -r '.data.items[0].view_id')"
echo "[bootstrap] VIEW_ID=$VIEW_ID"

# ===== 步骤 4：改默认字段、建业务字段 =====
sleep 1
DEFAULT_FIELDS="$(lark-cli base +field-list --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID")"
F_TEXT="$(echo       "$DEFAULT_FIELDS" | jq -r '.data.items[] | select(.field_name=="文本") | .field_id')"
F_SELECT="$(echo     "$DEFAULT_FIELDS" | jq -r '.data.items[] | select(.field_name=="单选") | .field_id')"
F_DATE="$(echo       "$DEFAULT_FIELDS" | jq -r '.data.items[] | select(.field_name=="日期") | .field_id')"
F_ATTACHMENT="$(echo "$DEFAULT_FIELDS" | jq -r '.data.items[] | select(.field_name=="附件") | .field_id')"

sleep 1
lark-cli base +field-update --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" --field-id "$F_TEXT" \
  --json '{"type":"text","name":"需求名称","style":{"type":"plain"}}' >/dev/null
F_REQ_NAME="$F_TEXT"

sleep 1
lark-cli base +field-delete --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" --field-id "$F_SELECT" --yes >/dev/null

sleep 1
lark-cli base +field-update --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" --field-id "$F_DATE" \
  --json '{"type":"datetime","name":"需求日期","style":{"format":"yyyy-MM-dd"}}' >/dev/null
F_REQ_DATE="$F_DATE"

sleep 1
retry_rename_attachment() {
  for i in 1 2 3; do
    if lark-cli base +field-update --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" --field-id "$F_ATTACHMENT" \
         --json '{"type":"attachment","name":"文件"}' >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}
retry_rename_attachment || { echo "[bootstrap] 重命名附件字段失败"; exit 5; }
F_FILE="$F_ATTACHMENT"

create_field() {
  local json="$1"
  sleep 1
  lark-cli base +field-create --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" --json "$json" \
    | jq -r '.data.field.id'
}

create_formula() {
  local json="$1"
  sleep 1
  lark-cli base +field-create --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" --i-have-read-guide --json "$json" \
    | jq -r '.data.field.id'
}

F_PREVIEW_URL="$(create_field '{"type":"text","name":"预览链接","style":{"type":"url"}}')"
F_DESIGN_URL="$(create_field  '{"type":"text","name":"设计稿链接","style":{"type":"url"}}')"
F_MODEL="$(create_field '{"type":"select","name":"使用模型","multiple":false,"options":[{"name":"Claude Opus 4.7","hue":"Purple","lightness":"Light"},{"name":"Claude Sonnet 4.6","hue":"Blue","lightness":"Light"},{"name":"GPT-5.4","hue":"Green","lightness":"Light"},{"name":"Gemini 3 Pro","hue":"Orange","lightness":"Light"},{"name":"Gemini 3.1 Pro","hue":"Red","lightness":"Light"}]}')"
F_MOD_COUNT="$(create_field    '{"type":"text","name":"修改次数","style":{"type":"plain"}}')"

# Token消耗：整数 + 千分位（飞书 number 数字字段默认右对齐，通过 style 直接格式化）
# 美元花费：currency USD，precision=2，飞书前端会渲染成 $25.00
F_TOKEN_USAGE="$(create_field '{"type":"number","name":"Token消耗","style":{"type":"plain","precision":0,"thousands_separator":true,"percentage":false}}')"
F_USD_COST="$(create_field    '{"type":"number","name":"美元花费","style":{"type":"currency","precision":2,"currency_code":"USD"}}')"

# 月份：formula(text)，用于视图分组和仪表盘按月统计
F_MONTH="$(create_formula '{"type":"formula","name":"月份","expression":"TEXT([需求日期], \"YYYY-MM\")"}')"

# ===== 步骤 5：视图按「月份」降序分组 =====
sleep 1
lark-cli base +view-set-group --as bot --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" --view-id "$VIEW_ID" \
  --json "[{\"field\":\"$F_MONTH\",\"desc\":true}]" >/dev/null
echo "[bootstrap] 视图已按「月份」降序分组"

# ===== 步骤 6：创建仪表盘 + 6 个 block =====
sleep 1
DASH_RESP="$(lark-cli base +dashboard-create --as bot --base-token "$BASE_TOKEN" --name "$DASHBOARD_NAME" --theme-style SimpleBlue)"
DASH_ID="$(echo "$DASH_RESP" | jq -r '.data.dashboard.dashboard_id')"
[[ -z "$DASH_ID" || "$DASH_ID" == "null" ]] && { echo "[bootstrap] 创建仪表盘失败：$DASH_RESP"; exit 6; }
echo "[bootstrap] DASHBOARD_ID=$DASH_ID"

create_block() {
  local name="$1" type="$2" config="$3"
  sleep 1
  lark-cli base +dashboard-block-create --as bot --base-token "$BASE_TOKEN" --dashboard-id "$DASH_ID" \
    --name "$name" --type "$type" --data-config "$config" >/dev/null
  echo "[bootstrap]   + block: $name ($type)"
}

create_block "使用最多的模型" pie \
  "{\"table_name\":\"$TABLE_NAME\",\"count_all\":true,\"group_by\":[{\"field_name\":\"使用模型\",\"mode\":\"integrated\",\"sort\":{\"type\":\"value\",\"order\":\"desc\"}}]}"

create_block "Token 总消耗" statistics \
  "{\"table_name\":\"$TABLE_NAME\",\"series\":[{\"field_name\":\"Token消耗\",\"rollup\":\"SUM\"}]}"

create_block "美元总花费" statistics \
  "{\"table_name\":\"$TABLE_NAME\",\"series\":[{\"field_name\":\"美元花费\",\"rollup\":\"SUM\"}]}"

create_block "每月使用最多的模型" column \
  "{\"table_name\":\"$TABLE_NAME\",\"count_all\":true,\"group_by\":[{\"field_name\":\"月份\",\"mode\":\"integrated\",\"sort\":{\"type\":\"group\",\"order\":\"asc\"}},{\"field_name\":\"使用模型\",\"mode\":\"integrated\",\"sort\":{\"type\":\"value\",\"order\":\"desc\"}}]}"

create_block "每月 Token 总消耗" column \
  "{\"table_name\":\"$TABLE_NAME\",\"series\":[{\"field_name\":\"Token消耗\",\"rollup\":\"SUM\"}],\"group_by\":[{\"field_name\":\"月份\",\"mode\":\"integrated\",\"sort\":{\"type\":\"group\",\"order\":\"asc\"}}]}"

create_block "每月美元总花费" column \
  "{\"table_name\":\"$TABLE_NAME\",\"series\":[{\"field_name\":\"美元花费\",\"rollup\":\"SUM\"}],\"group_by\":[{\"field_name\":\"月份\",\"mode\":\"integrated\",\"sort\":{\"type\":\"group\",\"order\":\"asc\"}}]}"

# ===== 步骤 7：加协作者 + 转 owner =====
sleep 1
echo "[bootstrap] 添加 $USER_NAME 为 full_access..."
lark-cli drive permission.members create --as bot \
  --params "$(jq -cn --arg t "$BASE_TOKEN" '{token:$t,type:"bitable",need_notification:false}')" \
  --data "$(jq -cn --arg id "$USER_OPEN_ID" '{member_type:"openid",member_id:$id,perm:"full_access",type:"user"}')" >/dev/null

sleep 1
echo "[bootstrap] 转移 owner 给 $USER_NAME..."
lark-cli drive permission.members transfer_owner --as bot \
  --params "$(jq -cn --arg t "$BASE_TOKEN" '{token:$t,type:"bitable",need_notification:true,remove_old_owner:true,stay_put:true}')" \
  --data "$(jq -cn --arg id "$USER_OPEN_ID" '{member_type:"openid",member_id:$id}')" >/dev/null

# ===== 步骤 8：落盘配置 =====
jq -n \
  --arg base_token   "$BASE_TOKEN" \
  --arg base_url     "$BASE_URL" \
  --arg table_id     "$TABLE_ID" \
  --arg table_name   "$TABLE_NAME" \
  --arg view_id      "$VIEW_ID" \
  --arg dashboard_id "$DASH_ID" \
  --arg owner        "$USER_OPEN_ID" \
  --arg owner_name   "$USER_NAME" \
  --arg req_name     "$F_REQ_NAME" \
  --arg req_date     "$F_REQ_DATE" \
  --arg preview      "$F_PREVIEW_URL" \
  --arg design       "$F_DESIGN_URL" \
  --arg model        "$F_MODEL" \
  --arg file         "$F_FILE" \
  --arg mod_count    "$F_MOD_COUNT" \
  --arg token_usage  "$F_TOKEN_USAGE" \
  --arg usd_cost     "$F_USD_COST" \
  --arg month        "$F_MONTH" \
  '{
    base_token:$base_token, base_url:$base_url,
    table_id:$table_id, table_name:$table_name,
    view_id:$view_id, dashboard_id:$dashboard_id,
    owner_open_id:$owner, owner_name:$owner_name,
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
echo "[bootstrap] ============================================================"
echo "[bootstrap] 完成。"
echo "[bootstrap] 表格：$BASE_URL"
echo "[bootstrap] 仪表盘：同一 Base 左侧导航里的「$DASHBOARD_NAME」"
echo
echo "[bootstrap] ⚠️  一次性手动微调（API 限制）："
echo "[bootstrap]   1) 进入「使用最多的模型」和「每月使用最多的模型」两个图表的"
echo "[bootstrap]      编辑 → 样式 → 图表颜色 → 按分类设置，把系列颜色调成："
echo "[bootstrap]        Claude Opus 4.7  → 紫 #B66CFF"
echo "[bootstrap]        Claude Sonnet 4.6 → 蓝 #5B9FFF"
echo "[bootstrap]        GPT-5.4          → 绿 #67D474"
echo "[bootstrap]        Gemini 3 Pro     → 橙 #FF9944"
echo "[bootstrap]        Gemini 3.1 Pro   → 红 #FF6B6B"
echo "[bootstrap]      （与表格 select 字段的颜色标签一致）"
echo "[bootstrap] ============================================================"

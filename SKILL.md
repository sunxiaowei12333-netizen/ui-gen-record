---
name: ui-gen-record
description: 记录每次 UI 页面生成需求（需求名称、使用模型、Token 消耗、修改次数、美元花费、预览链接、设计稿链接、源码 / 压缩包附件等）到飞书多维表格。首次使用会自动建表并把所有者转给当前用户；当用户说"整理到表格中 / 记录到多维表格 / 归档这次需求"等指令时触发，自动汇总本次对话的生成记录并追加一行到那张已有的多维表格里。
---

# ui-gen-record

把"UI 页面生成类需求"的元信息（花费、模型、修改次数、产物）归档到同一张飞书多维表格。

## 触发场景

| 用户说法 | 动作 |
|---|---|
| "整理到表格中 / 归档到多维表格 / 记录这次需求 / 存一下这次花费" | 追加一条记录 |
| 首次使用（`config.json` 不存在） | 先跑 `bootstrap.sh` 建表再追加 |

## 依赖

- `lark-cli`（`lark-cli auth login` 已完成）
- 运行用户在飞书已有账号且 open_id 可通过 `lark-cli auth list` 获取

## 首次使用：创建多维表格

若 `~/.cursor/skills/ui-gen-record/.config.json` 不存在，先执行：

```bash
bash ~/.cursor/skills/ui-gen-record/scripts/bootstrap.sh
```

脚本会：

1. 通过 `lark-cli auth list` 拿到当前用户的 open_id
2. 以 bot 身份创建 Base，里面的表叫 `UI页面生成记录`
3. 建好标准字段 + 3 个辅助公式字段（见下表）
4. 视图按 `月份` 降序分组
5. 创建仪表盘 `UI生成实时统计` 并填入 6 个 block（见下文）
6. 把当前用户加为 `full_access`，然后把 owner 转给该用户
7. 把 `base_token / table_id / view_id / dashboard_id / field_ids / owner_open_id` 写入 `.config.json`
8. 在 stdout 末尾 echo 两步**一次性手动微调**（隐藏"月份"列、设置图表颜色），这些是 Open API 不支持的，要用户到浏览器里点一下

建好的 Base URL 会 echo 到 stdout，需要报给用户。

### 表结构

| 字段 | 类型 | 说明 |
|---|---|---|
| 需求名称 | text | 页面名或需求简述 |
| 需求日期 | datetime | `YYYY-MM-DD HH:mm:ss`，默认取"当前时间" |
| 预览链接 | text (url) | 本地预览地址，如 `http://localhost:5173/xxx` |
| 设计稿链接 | text (url) | Figma / Motiff / Pencil 链接 |
| 使用模型 | select（带颜色标签） | 选项：`Claude Opus 4.7`(紫) / `Claude Sonnet 4.6`(蓝) / `GPT-5.4`(绿) / `Gemini 3 Pro`(橙) / `Gemini 3.1 Pro`(红)，可扩展 |
| 文件 | attachment | `.tsx` 源码 + 导出 `.zip`（可多个） |
| 修改次数 | text | 用户提出的所有小改点（含重复），左对齐 |
| Token消耗 | number(plain) | `precision=0, thousands_separator=true`，前端展示 `1,000,000`；仪表盘直接 SUM |
| 美元花费 | number(currency) | `currency_code=USD, precision=2`，前端展示 `$25.00`；仪表盘直接 SUM |
| 月份 | formula(text) | `TEXT([需求日期], "YYYY-MM")`，视图分组用。Bitable API 对 datetime 分组默认按天，必须用这个文本字段才能按月归类 |

> `append.sh` 的外部参数保持兼容：仍然可传 `--token-usage "1,000,000"` 和 `--usd-cost "$25.00"`，脚本内部会剥逗号 / 美元符号后作为 number 写入 `Token消耗` / `美元花费`。

默认视图按 `月份` 降序分组（`2026-05` / `2026-04` 各自一组）。无需隐藏任何列。

## 仪表盘

bootstrap 会创建一个叫 `UI生成实时统计` 的仪表盘，包含 6 个 block：

**整体统计**

- **使用最多的模型**（饼图）：按 `使用模型` 字段计数，数量降序
- **Token 总消耗** / **美元总花费**（指标卡）：`SUM(Token消耗)` / `SUM(美元花费)`

**每月统计**

- **每月使用最多的模型**（堆叠柱状图）：x=`月份` 颜色=`使用模型` y=`count_all`
- **每月 Token 总消耗**（柱状图）：x=`月份` y=`SUM(Token消耗)`
- **每月美元总花费**（柱状图）：x=`月份` y=`SUM(美元花费)`

每次 `append.sh` 加记录后刷新仪表盘就能看到新数据。

### 图表颜色微调（手动一次性）

Bitable Open API **不暴露图表系列颜色** 的设置。要让图表里的模型颜色和表格 select 的颜色标签一致，需要用户在浏览器里手动调一次（调完持久保存）。bootstrap 结束时会 echo 这个对照表：

| 模型 | 色系 | 近似 hex |
|---|---|---|
| Claude Opus 4.7 | 紫 | `#B66CFF` |
| Claude Sonnet 4.6 | 蓝 | `#5B9FFF` |
| GPT-5.4 | 绿 | `#67D474` |
| Gemini 3 Pro | 橙 | `#FF9944` |
| Gemini 3.1 Pro | 红 | `#FF6B6B` |

操作路径：图表右上角 **编辑** → 右侧 **样式** → **图表颜色 → 按分类设置** → 逐个配色 → 保存。只有"使用最多的模型"和"每月使用最多的模型"这两张涉及模型维度的图需要调。

## 后续使用：追加一条记录

当用户说"整理到表格中"等指令时：

### 第 1 步：收集数据

从本次对话上下文里推断或询问用户拿到以下信息；未明确的允许为空字符串 `""`：

- `REQ_NAME`：需求名称（必填，通常是页面路径或中文页面名）
- `REQ_DATE`：需求日期（默认取当前时间 `$(date +'%Y-%m-%d %H:%M:%S')`；若归档历史文件，取 `stat -f '%Sm'`）
- `PREVIEW_URL`：预览链接（通常 `http://localhost:5173/<slug>`）
- `DESIGN_URL`：设计稿链接（Figma / Motiff / Pencil）
- `MODEL`：使用模型（必须命中 select 选项，否则先用 `lark-cli base +field-update` 扩充枚举）
- `MOD_COUNT`：修改次数（整数字符串）
- `TOKEN_USAGE`：Token 消耗（千分位字符串，如 `1,000,000`）
- `USD_COST`：美元花费（`$` 开头字符串，如 `$25.00`）
- `ATTACHMENT_PATHS`：本地附件绝对路径数组

### 第 1.5 步：自动收集附件（关键！）

必须同时收集 **源码 `.tsx`** 和 **导出 `.zip`**，按下面优先级顺序拿 zip：

#### 优先级 A：现场调接口导出（推荐，最新鲜）

dev server（默认 `http://localhost:5173`）自带 `POST /__api/export-html` 接口，路由导航面板里的"导出"按钮就是调它。agent 可以直接 curl 触发：

```bash
# pageName 用 src/pages/ 下去掉扩展名的相对路径，中文不用 URL-encode，curl 会处理
PAGE_NAME="<你的页面相对路径，比如 landing/index>"
OUT_PATH="/tmp/$(basename "$PAGE_NAME").zip"

# 先确认 server 活着
if curl -sf -o /dev/null -I http://localhost:5173/; then
  curl -sf -o "$OUT_PATH" -X POST http://localhost:5173/__api/export-html \
    -H "Content-Type: application/json" \
    -d "$(jq -cn --arg p "$PAGE_NAME" '{pageName:$p}')"
  file "$OUT_PATH" | grep -q "Zip archive" && echo "导出成功：$OUT_PATH"
fi
```

- 成功后直接把 `$OUT_PATH` 作为 `--attachment` 传入
- 不需要动浏览器，不依赖用户手动点按钮
- 只要 dev server 在跑就能用

#### 优先级 B：扫描 `~/Downloads/` 历史导出

如果 dev server 没跑 / 接口 404，退而求其次在 Downloads 里搜：

```bash
PAGE_KEY="页面名或其核心关键字"
ENCODED=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$PAGE_KEY")

find ~/Downloads -maxdepth 1 -type f \( -iname "*${PAGE_KEY}*.zip" -o -iname "*${ENCODED}*.zip" \) \
  -mtime -7 -print  # 只看最近 7 天，避免误匹配
```

- 匹配到 1 个 → 作为 `--attachment` 传入
- 多个 → 取 mtime 最新的
- 0 个 → 进入优先级 C

#### 优先级 C：询问用户

当 A 和 B 都失败时，才告诉用户"dev server 没启动 / 导出接口不可用，请手动点导出按钮"。

**源码 `.tsx` 和导出 `.zip` 都应包含**（`append.sh` 的 `--attachment` 可重复传入）。

### 第 2 步：调用 append 脚本

```bash
bash ~/.cursor/skills/ui-gen-record/scripts/append.sh \
  --req-name "<需求/页面名>" \
  --req-date "2026-01-01 12:00:00" \
  --preview-url "http://localhost:5173/<页面路径>" \
  --design-url "https://<设计稿链接>" \
  --model "Claude Opus 4.7" \
  --mod-count "10" \
  --token-usage "500,000" \
  --usd-cost "\$12.50" \
  --attachment "/absolute/path/to/export.zip" \
  --attachment "/absolute/path/to/source.tsx"
```

脚本返回新记录 id 与 Base URL；把 Base URL 报给用户。

## 估算规则（必填，不允许留空）

Agent 在收集 `MOD_COUNT / TOKEN_USAGE / USD_COST` 时按以下口径。**即便 transcript 缺失也必须给出估算值**，这三个字段严禁留空：

- **修改次数**：本次对话中用户提出的**每一个可独立执行的小需求**的个数，含重复。初始的"生成页面"也算 1。
  - 若归档的是历史文件（transcript 不可见），最少填 `1`
- **Token 消耗**（千分位字符串，如 `160,000`）：
  - 当前会话可见时：按"会话字符数 + 工具往返 + 读写大文件次数"估算
  - 仅归档历史文件时：按**生成文件大小**反推。经验值：每 1KB 源码 ≈ 15K 总 tokens（含 Cursor 默认注入的项目上下文）
  - Chinese ≈ 1.3 tokens/char；Opus 会话一般在 50 万–300 万 token 区间
- **美元花费**（带 `$` 前缀，如 `$0.42`）：按模型当前官方价位估算
  - 公式：`cost = input_tokens × input_rate + output_tokens × output_rate`
  - 典型比例：input : output ≈ 15 : 1（对于 Cursor agent 会话）

### 模型价目表（2026 年参考值）

| 模型 | Input ($/M) | Output ($/M) |
|---|---|---|
| Claude Opus 4.7 | 15 | 75 |
| Claude Sonnet 4.6 | 3 | 15 |
| GPT-5.4 | 10 | 30 |
| Gemini 3 Pro / 3.1 Pro | 2 | 12 |

估算值允许偏差；用户拿到精确账单后可在表里手动覆盖。

## 错误处理

- **`config.json` 不存在** → 运行 `bootstrap.sh`。
- **`base_token invalid`** → 用户可能删表了，提示是否重新 `bootstrap`。
- **`OpenAPIUpdateField limited`（限流）** → `sleep 2` 后重试。
- **附件找不到** → 检查路径是否存在；如果是 `~/Downloads` 里 URL-encoded 的文件，先 `cp` 到 `/tmp` 再传（lark-cli 要求相对路径）。
- **模型不在 select 选项里** → 先让用户确认是否新增选项；用 `lark-cli base +field-update` 更新 options。

## 相关文件

- [scripts/bootstrap.sh](scripts/bootstrap.sh) — 首次建表与所有者转移
- [scripts/append.sh](scripts/append.sh) — 追加一条记录，支持多个附件
- `.config.json`（运行时生成）— 存储 `base_token / table_id / field_ids / owner_open_id / base_url`

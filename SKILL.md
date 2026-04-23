---
name: ui-gen-record
description: 记录每次 UI 页面生成需求（需求名称、使用模型、Token 消耗、修改次数、美元花费、预览链接、设计稿链接、源码 / 压缩包附件等）到飞书多维表格。首次使用会自动建表并把所有者转给当前用户；当用户说"整理到表格中 / 记录到多维表格 / 归档这次需求"等指令时触发，自动汇总本次对话的生成记录并追加一行到那张已有的多维表格里。
---

# ui-gen-record

把"UI 页面生成类需求"的元信息（花费、模型、修改次数、产物）归档到同一张飞书多维表格。

## 触发场景

> 核心：`.config.json` 始终表示"当前激活的那张表"。"新建 / 绑定链接"只是换这个指针，不影响已有表里的数据。

| 场景 | 用户说法 | 动作 |
|---|---|---|
| 初次 + 只说"整理" | "整理到表格中 / 归档到多维表格 / 记录这次需求" | 跑 `bootstrap.sh` 新建一张表，再 append |
| 初次 + 提供了飞书表格链接 | "整理到这张表里 https://xxx.feishu.cn/base/..." | 跑 `link.sh <url>` 绑定已有表，再 append |
| 已配置 + 只说"整理" | "整理到表格中" | 直接 append 到 `.config.json` 当前指向的表 |
| 已配置 + 说"新建" | "新建一张表 / 我想重新建一张" | 跑 `bootstrap.sh --force` 新建并把指针切到新表 |
| 已配置 + 提供新链接 | "换到这张表 https://..." | 跑 `link.sh --force <url>` 切到新表 |

只有明确**带上飞书 base URL** 时才走绑定分支；否则默认走新建或直接 append。

## 依赖

- `lark-cli`（`lark-cli auth login` 已完成）
- 运行用户在飞书已有账号且 open_id 可通过 `lark-cli auth list` 获取

## 建表 / 绑表：初始化 `.config.json`

有两种方式把 skill 指向一张飞书多维表格，任选其一：

### 方式 A：新建一张表（推荐给首次使用的用户）

```bash
bash ~/.cursor/skills/ui-gen-record/scripts/bootstrap.sh
# 已有 .config.json 时，若要强制新建并覆盖指针：
bash ~/.cursor/skills/ui-gen-record/scripts/bootstrap.sh --force
```

### 方式 B：绑定到一张已有的表

当用户给出飞书 Base 链接（例如 `https://xxx.feishu.cn/base/<base_token>?table=<table_id>`）时：

```bash
bash ~/.cursor/skills/ui-gen-record/scripts/link.sh <base_url>
# 已有 .config.json 时，若要切换到新链接：
bash ~/.cursor/skills/ui-gen-record/scripts/link.sh --force <base_url>
```

`link.sh` 会：

1. 从 URL 解析出 `base_token`（以及可选的 `table_id` / `view_id`）
2. 通过 `lark-cli` 扫字段列表，按字段名反查出全部 `field_ids`
3. 校验 10 个必备字段（"需求名称 / 需求日期 / 预览链接 / 设计稿链接 / 使用模型 / 文件 / 修改次数 / Token消耗 / 美元花费 / 月份"）是否都在，任一缺失会报错退出
4. 写入 `.config.json`，后续 `append.sh` 就自动往这张表里追加记录，无需再次提供链接

> 注意：要想 `link.sh` 绑定成功，目标表的字段名必须与本 skill 定义的完全一致（类型也要匹配，尤其是 `Token消耗`=number 千分位、`美元花费`=number USD 货币、`月份`=formula）。最安全的做法是这张表也是由本 skill 的 `bootstrap.sh` 建出来的。

### `bootstrap.sh` 具体做的事：

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

### 第 1.5 步：自动收集附件

附件由两部分组成，agent 不需要问用户，按以下固定流程拿：

#### 1) 源码（必传）

用户手上已有的页面源码。最常见是 `.tsx`，也可以是 `.html` 或任何可以代表本次产物的文件。路径从 REQ_NAME 推断或直接问用户。

#### 2) 导出 zip（可选，有就带，没就跳过）

本项目的 dev server 自带 `POST /__api/export-html` 接口（导航面板里的"导出"按钮也是调它）。skill 提供了一个静默 helper：

```bash
ZIP_PATH="$(bash ~/.cursor/skills/ui-gen-record/scripts/try-export.sh "<pageName>")"
# 说明：
# - pageName = src/pages/ 下去掉扩展名的相对路径，如 "转介绍周任务-最终版" 或 "landing/index"
# - 成功：ZIP_PATH 是 /tmp/<basename>.zip
# - 失败（dev server 不在线 / 接口 404 / 页面名不存在 / 非 zip 响应）：ZIP_PATH 为空
# - 无论哪种情况都 exit 0，不会打断 agent 流程
```

然后根据结果拼 `--attachment` 参数：

```bash
ATTACH_ARGS=(--attachment "/abs/path/to/source.tsx")
if [[ -n "$ZIP_PATH" ]]; then
  ATTACH_ARGS+=(--attachment "$ZIP_PATH")
fi
bash ~/.cursor/skills/ui-gen-record/scripts/append.sh ... "${ATTACH_ARGS[@]}"
```

> 原则：**内部同事**（跑着 dev server）会自动带上 zip；**外部用户**（没有 dev server 或不是本项目）会静默跳过 zip，只留源码和其他用户手上已有的文件。**任何情况下都不要向用户确认 zip 怎么处理。**

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

- **`config.json` 不存在**
  - 用户没给链接 → 运行 `bootstrap.sh` 新建
  - 用户给了链接 → 运行 `link.sh <url>` 绑定
- **`link.sh` 报"该表缺少必需字段"** → 目标表不是本 skill 建的，schema 对不上。提示用户要么手动补齐字段，要么改用 `bootstrap.sh` 新建一张规范表。
- **`base_token invalid`** → 用户可能删表或没权限，提示重新 `bootstrap` 或 `link` 到别的表。
- **`OpenAPIUpdateField limited`（限流）** → `sleep 2` 后重试。
- **附件找不到** → 检查路径是否存在；如果是 `~/Downloads` 里 URL-encoded 的文件，先 `cp` 到 `/tmp` 再传（lark-cli 要求相对路径）。
- **模型不在 select 选项里** → 先让用户确认是否新增选项；用 `lark-cli base +field-update` 更新 options。

## 相关文件

- [scripts/bootstrap.sh](scripts/bootstrap.sh) — 新建一张规范表，并把所有权转给当前 CLI 登录用户。`--force` 可在 `.config.json` 已存在时强制新建并覆盖指针
- [scripts/link.sh](scripts/link.sh) — 把 skill 指向一张已有的飞书多维表（URL 参数），`--force` 可覆盖现有指针
- [scripts/append.sh](scripts/append.sh) — 追加一条记录，支持多个附件
- [scripts/try-export.sh](scripts/try-export.sh) — 静默尝试通过本项目 dev server 导出 zip；有就在 stdout 打印路径、没有就空字符串，让 append 逻辑无分支地处理"内部同事有 zip / 外部用户没 zip"两种情况
- `.config.json`（运行时生成）— 存储 `base_token / table_id / field_ids / owner_open_id / base_url / linked`（`linked=true` 表示通过 `link.sh` 绑定到一张已有表；缺省表示由 `bootstrap.sh` 新建）

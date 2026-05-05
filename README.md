# ui-gen-record-feishu

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)
[![Cursor](https://img.shields.io/badge/Cursor-supported-black?logo=cursor)](https://cursor.sh)
[![Claude Code](https://img.shields.io/badge/Claude_Code-supported-D97757)](https://docs.claude.com/en/docs/claude-code)
[![Codex](https://img.shields.io/badge/Codex-supported-10A37F?logo=openai)](https://openai.com/codex)
[![Copilot](https://img.shields.io/badge/GitHub_Copilot-supported-24292e?logo=githubcopilot)](https://github.com/features/copilot)
[![Feishu/Lark](https://img.shields.io/badge/Feishu/Lark-Bitable-00D6B9)](https://www.feishu.cn)

一个跨 AI Agent 的 Skill，用来把每次 UI 页面生成需求（Token 消耗、美元花费、修改次数、使用模型、预览链接、源码和导出 zip 附件）自动归档到**你自己的飞书多维表格**，并配套一张按月份分组的仪表盘。

适合任何使用 AI Agent（Cursor、Claude Code、Codex、VS Code Copilot、Cline、Aider 等）做 UI/前端页面生成的人，对使用量、花费、模型分布做**月度可视化统计**。

## 为什么要用它

AI生成的页面藏在每天的碎片对话里，没有人愿意手动记录。对于不是开发的同学来说，想找到对应需求，并及时备份很重要。同时，希望能可视化的看到每个需求消耗了多少Token，花了多少钱，这个需求使用的什么模型、预览地址是什么等，这个技能帮你：

* 对话结束时说一句“整理到表格中”或“归档这个需求”，首次会自动创建多维表格，自动整理需求到表格中
* 表格按月份排列，实时显示“每月使用最多的模型/代币总消耗/美元总消耗/预览链接”等
* 导出 zip 、Html等文件作为附件源码一起归档
* 所有数据都在你自己的飞书账号下，也可在 AI Agent 里填写其他人的表格链接，后续无需强调表格链接，会默认归档到上一次提供的表格链接里

## 演示

<p align="center">
  <img src="./docs/screenshots/table.png" alt="多维表格：按月份分组的 UI 生成记录" width="48%" />
  <img src="./docs/screenshots/dashboard.png" alt="仪表盘：每月模型 / Token / 美元花费" width="48%" />
</p>

## 安装

### 依赖

- [`lark-cli`](https://github.com/larksuite/lark-cli)（或你公司内部对应的飞书 CLI），已完成 `lark-cli auth login`
- `jq`、`bash`、`curl`、`python3`（macOS / Linux 默认都有）

### 安装到 Agent

```bash
git clone https://github.com/sunxiaowei12333-netizen/ui-gen-record.git
cd ui-gen-record
bash scripts/install.sh
```

`install.sh` 会自动检测：

- `~/.cursor/skills/` → 建软链 `ui-gen-record`
- `~/.claude/skills/` → 建软链 `ui-gen-record`

对于没有原生 Skill 机制的 Agent（Codex / VS Code Copilot / Cline / Aider 等），在项目根目录 `AGENTS.md` 里加一行 `@include <本仓库绝对路径>/AGENTS.md` 即可。

### 初始化：新建一张表 或 绑定到已有表

#### 方式 A：新建（首次使用推荐）

```bash
bash scripts/bootstrap.sh
# 已有 .config.json 想再新建一张并把指针切过去：
bash scripts/bootstrap.sh --force
```

脚本会：

1. 用 `lark-cli` 在你飞书账号下**新建一张空表**（表名默认 `UI页面生成记录`，可通过 `BASE_NAME=xxx bash scripts/bootstrap.sh` 自定义）
2. 建好所有字段：`Token消耗` 用 number(千分位整数)，`美元花费` 用 number(USD 货币)，`月份` 用 formula(text) 从需求日期派生
3. 视图按 `月份` 降序分组
4. 新建仪表盘 `UI生成实时统计` + 6 个 block（饼图、2 个指标卡、3 个柱状图）
5. 把这张表的所有权转给你（脚本默认以 bot 身份建表，再 transfer 给当前 CLI 登录用户）
6. 所有 id / token 写入 `.config.json`（**已被 gitignore，不会泄漏**）

结束时只剩一条**需要手动**的配色（Bitable Open API 未暴露）：

- 两张涉及模型维度的图表（饼图 / 每月使用最多的模型），手动调配色到模型色系

#### 方式 B：绑定到你已有的那张表

当你换了台机器、或想让多个仓库共用同一张表时，直接给链接即可：

```bash
bash scripts/link.sh "https://xxx.feishu.cn/base/<base_token>?table=<table_id>"
# 已有 .config.json 想切换：
bash scripts/link.sh --force "https://xxx.feishu.cn/base/<base_token>"
```

脚本会从 URL 解析 `base_token`，扫一遍字段列表按字段名反查出所有 `field_ids`，校验 schema 完整后写入 `.config.json`。前提是该表必须是由本 skill 的 `bootstrap.sh` 建出来的（字段名和类型要对得上）。

### 使用

初始化完成后 `.config.json` 就记住了当前指向的那张表，之后**不需要再提供链接**，对 AI Agent 说：

> 把这次改动整理到表格中

Agent 会读取 SKILL.md 里的约定，自动提取本次对话的：

- 需求名称、日期、预览链接、设计稿链接
- 使用的模型（从 `/model` 或上下文识别）
- 修改次数（数本次对话里的小需求个数）
- Token 消耗 / 美元花费（按模型价目表估算）
- 源码 `.tsx` + 导出 `.zip` 作为附件

然后调 `scripts/append.sh` 往表里追加一行。

## 表结构

| 字段 | 类型 | 说明 |
|---|---|---|
| 需求名称 | text | 页面名 |
| 需求日期 | datetime | 创建时间 |
| 预览链接 | text (url) | `http://localhost:5173/xxx` |
| 设计稿链接 | text (url) | Figma / Motiff / Pencil |
| 使用模型 | select | Claude/GPT/Gemini 各系列，带颜色标签 |
| 文件 | attachment | 源码 + 导出 zip |
| 修改次数 | text | 对话里的小改点数 |
| Token 消耗 | number(plain) | 整数 + 千分位，前端展示 `1,000,000`，仪表盘直接 SUM |
| 美元花费 | number(currency USD) | 飞书原生 USD 格式，前端展示 `$25.00`，仪表盘直接 SUM |
| 月份 | formula(text) | `TEXT([需求日期], "YYYY-MM")`，用于分组 |

## 仪表盘

- **使用最多的模型**（饼图）
- **Token 总消耗** / **美元总花费**（指标卡，分别 `SUM(Token消耗)` / `SUM(美元花费)`）
- **每月使用最多的模型**（堆叠柱状图）
- **每月 Token 总消耗** / **每月美元总花费**（柱状图）

## 隐私

- Skill 本身**不会读取也不会上传**你的对话、文件或任何数据到第三方。
- 所有操作通过 `lark-cli` 在**你自己的飞书账号**下进行，表的所有权在 `bootstrap.sh` 末尾就转给了你。
- 仓库的 `.gitignore` 已经忽略 `.config.json`（含你的 base_token 和 open_id），只要不手动加白它，不会被提交。

## License

MIT

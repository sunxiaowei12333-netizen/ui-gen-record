# 截图指南

README 顶部的两张演示图放在这里：

| 文件名 | 内容 | 建议尺寸 |
|---|---|---|
| `table.png` | 多维表格，按「月份」降序分组的视图 | 约 1600×1000，截到能看见 3~5 行示例记录 |
| `dashboard.png` | 仪表盘 `UI生成实时统计`，包含 6 个 block | 约 1600×1000，整张仪表盘截全 |

## 脱敏清单（很重要）

在截图之前，请确认你不会把下面任何东西暴露到公网仓库里：

- 公司名 / 同事名 / 内部项目名 → 把「需求名称」换成 `Demo 页面 A / B / C`
- 真实的飞书用户头像 → 表格右上角如果有共享人头像，记得裁掉
- 真实的预览域名 / Motiff / Figma 链接 → 保留 `localhost:5173` 或 `example.com` 即可
- 真实的 Token / 花费数值 → 如果介意可以复制一份副本表，填假数据再截图

> 最稳妥的做法：在飞书里**新建一张空表**，用本 Skill 的 `bootstrap.sh` 重新建一遍，手动插入 3~5 条假数据，拿这张表来截图。

## 一键替换并发布

截好图后：

```bash
cd /path/to/ui-gen-record
cp ~/Desktop/table.png ./docs/screenshots/table.png
cp ~/Desktop/dashboard.png ./docs/screenshots/dashboard.png
git add docs/screenshots/*.png
git commit -m "docs: add bitable & dashboard screenshots"
git push
```

推送后刷新 GitHub 仓库首页即可看到图。

# Changelog

> 记录「送给你这个回来的人」（Tripothon S1 参赛项目）的开发日志与进度。
> 本文件与 `poc/build-log.md`（每日颗粒度）配合使用：CHANGELOG 记录里程碑，build-log 记录每日细节。

---

## 当前进度

| 阶段 | 状态 | 说明 |
|------|------|------|
| Day 0 · 选题与设计 | ✅ 完成 | 2026-09-10，选题定稿「送给你这个回来的人」 |
| Day 1 · 第一个角色跑通 | 🔲 待做 | 需 TRIPO_API_KEY 后跑 `tripo-gen.py` |
| 调研与 PoC 骨架 | ✅ 完成 | TapTap Maker / Tripo / AI Town 调研 + Maker 模板骨架 |
| 角色设定数据核查 | ✅ 完成 | 2026-09-14，官方现行数据补齐 + 冲突核查 |
| 仓库初始化与文档化 | ✅ 完成 | 2026-09-14，git init + README/AGENTS/CHANGELOG |

---

## 2026-09-14 — 角色设定核查 · 仓库初始化

### Added
- 角色核查产出迁入 `docs/characters/`：`hitori.json` / `ryo.json` / `nijika.json` / `ikuyo.json` / `band.json`（结构化官方设定）、`CHARACTER_DATA_AUDIT.md`（冲突核查报告）、`_inventory.json`（本地材料盘点）、`_raw/characters_official.md`（权威来源原始摘录）
- 根级 `README.md`（项目简介与文档导航）
- 根级 `AGENTS.md`（供 AI Agent 读取的仓库背景）
- 根级 `CHANGELOG.md`（本文件）
- 根级 `.gitignore` + git 仓库初始化（首次提交）

### Changed
- 发现并标注 `research/game-design-sources/bocchi/` 下 **45 个 `web-*` 权威来源文件为空壳（`items: []`）**
- 修正 `bocchi-design-reference.md` 对空壳文件的悬空引用，设定数据切换为官方现行版本（番剧官网 `bocchi.rocks/character` + 日文维基 + 中文维基）
- 角色核查引用链全部从 `bocchi/parsed/` 更新为 `docs/characters/`

### Related
- 冲突核查详情：[`docs/characters/CHARACTER_DATA_AUDIT.md`](docs/characters/CHARACTER_DATA_AUDIT.md)

---

## 2026-09-11 — 调研与 PoC 骨架

### Added
- TapTap Maker 调研报告与架构文档（`docs/taptap-maker-research.md`、`docs/taptap-maker-architecture.md`、`docs/report-*`）
- Tripo × TapTap Maker 联动调研（`docs/integration.md`）
- mattpocock/skills 分析（`docs/mattpocock-skills-analysis.md`）
- PoC Maker 模板骨架（`poc/maker-template/`：Lua 脚本 + 角色 prompt）
- 设计方向汇报（`docs/design-summary-report.md`）

### Related
- 选题设计：[`docs/topic.md`](docs/topic.md)
- 赛事规则：[`docs/demand.md`](docs/demand.md)

---

## 2026-09-10 — 选题与设计

### Added
- 赛事规则存档（`docs/demand.md`，Tripothon S1）
- 选题定稿「送给你这个回来的人」（`docs/topic.md`）
- 三大子系统设计：Tripo 出角色 / Maker AI + Lua 事件调度 / clientCloud 持久化时间线
- 调研 Tripo OpenAPI 与 TapTap Maker、AI Town / HelloAgents / Generative Agents
- PoC 启动材料（`poc/README.md`、`poc/tripo-gen.py`、`poc/tripo-prompts.json`、`poc/.env.example`、`poc/architecture.md`、`poc/demo-walkthrough.md`、`poc/build-log.md`）

### Related
- 每日进度：[`poc/build-log.md`](poc/build-log.md)

---

## 计划中

- **Day 1**：跑通 `tripo-gen.py --only xiaoman` 拿到 `xiaoman.glb`，初始化 Maker 项目，实机预览看到小满角色
- **Day 2**：Tripo 出另外 2 个角色，放入 Maker 场景
- **Day 3**：实现点击对话（Maker AI + 角色 system prompt）
- **Day 4**：事件触发器 + 时间差检测（Lua 协程），离线后触发「想你」事件
- **Day 5**：头顶气泡 + 日记 UI
- **Day 6**：实机测试 + 发布准备
- **Day 7**：录屏 + 截图 + Build Log + 提交必交三件套

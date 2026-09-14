# AGENTS — 仓库背景（供 AI Agent 阅读）

> 本文件是接手本仓库的快速起点。人类读者请看 `README.md`。

---

## 项目一句话

**「送给你这个回来的人」** —— Tripothon S1（Tripo AI 世界构建黑客松）参赛项目。玩家回到一座会自动运转的小镇，三位角色（小满 / 阿泽 / 奶奶）会在玩家离线的真实时间内自主生活、写日记、生成事件，让玩家感受到「我不在时，这个世界仍在运转」。

- 赛事：Tripothon S1，主题「A Gift for ______」（送份礼物给 ______）
- 赛道：📱 应用 / 🎮 游戏
- 工具赛道：Best Use of Tripo（必叠加）
- 引擎：TapTap Maker（UrhoX + Lua + WASM 闭源引擎）
- 3D 角色：Tripo `text_to_model` 生成 GLB

---

## 目录结构

```
/
├── README.md               # 人类入门（文档导航）
├── AGENTS.md               # 本文件：Agent 背景
├── CHANGELOG.md            # 里程碑日志 + 当前进度
├── .gitignore              # 忽略 node_modules/.env/.penguin/ShanTianLiang/
├── docs/
│   ├── characters/         # 角色设定数据（官方现行，结构化）
│   │   ├── hitori.json     #   后藤一里 官方设定
│   │   ├── ryo.json        #   山田凉 官方设定
│   │   ├── nijika.json     #   伊地知虹夏 官方设定
│   │   ├── ikuyo.json      #   喜多郁代 官方设定
│   │   ├── band.json       #   结束バンド + 作品元数据
│   │   ├── CHARACTER_DATA_AUDIT.md   # 冲突核查报告
│   │   ├── _inventory.json # 本地 bocchi/ 材料盘点
│   │   └── _raw/           # 权威来源原始摘录
│   ├── demand.md           # Tripothon S1 赛事规则
│   ├── topic.md            # 选题与设计（核心设计文档）
│   ├── design-summary-report.md  # 设计背景与方向汇报
│   ├── integration.md      # Tripo × TapTap Maker 联动调研
│   ├── taptap-maker-research.md / taptap-maker-architecture.md  # Maker 调研
│   └── report-*            # TapTap Maker 调研报告产物
├── poc/                    # PoC 工程
│   ├── README.md           # PoC 操作说明
│   ├── build-log.md        # 每日开发日志（Day 0 完成 / Day 1 计划）
│   ├── tripo-gen.py        # Tripo 角色生成脚本
│   ├── architecture.md / demo-walkthrough.md
│   └── maker-template/     # Maker 项目模板（Lua + 角色 prompt）
└── research/
    ├── game-design-sources/  # 游戏设计调研数据
    │   ├── bocchi/           # 孤独摇滚设计参考 + 采集原始 JSON
    │   └── (mattpocock-skills, taptap-pages 等调研)
```

---

## 文档地图

| 文件 | 用途 |
|------|------|
| `docs/demand.md` | 赛事规则、提交要求、评审权重、验收清单 |
| `docs/topic.md` | 核心选题与设计：故事、角色、技术架构、7 天 PoC 计划、设计决策 |
| `docs/design-summary-report.md` | 玩法 / 表现 / 操作 / 核心循环设计汇报 |
| `docs/integration.md` | Tripo API × TapTap Maker 联动调研 |
| `docs/characters/CHARACTER_DATA_AUDIT.md` | 孤独摇滚角色设定冲突核查报告 |
| `poc/build-log.md` | 每日粒度开发日志 |
| `CHANGELOG.md` | 里程碑粒度进度 + 当前进度表 |

---

## 权威度约定（重要）

对角色/作品设定类内容，**优先采用权威度高的来源**，本地检索材料仅作民间说法对照：

**番剧官网（`bocchi.rocks`）> 日文维基 > 中文维基 > 本地检索/二创材料**

- ⚠️ `bocchi-the-rock.com` 是 Neocities 占位页，**不是官方站**，勿用。
- 结构化角色数据以 `docs/characters/*.json` 为准，每个字段带 `source` 与 `source_authority`。

---

## 易错点

1. **45 个空壳来源文件**：`research/game-design-sources/bocchi/` 下 `web-mal-*.json`、`web-ann-search.json`、`web-bangumi-*.json`、`web-crunchyroll.json`、`web-fandom-*.json`、`web-wikipedia-*.json`、`web-search-*.json` 的 `items` 均为 `[]`（空壳），**不能作为设定依据**。它们只是采集失败留下的空文件。
2. **角色核查产出位置**：原 `bocchi/parsed/` 已迁移到 `docs/characters/`。仓库内不应再引用 `parsed/`。
3. **`ShanTianLiang/` 是空目录**：仓库根目录下有个与仓库同名的嵌套目录，内容为空，已在 `.gitignore` 忽略，勿写入文件。
4. **`.penguin/` 忽略**：历史 scratch 会话，不在版本控制中。
5. **Tripo 模型版本约束**：Tripo 下游 task 需要上游模型版本 ≥ 特定版本（见 `poc/tripo-gen.py` 与 `docs/integration.md`），报错时先查版本。

---

## 常用命令

```bash
git status / git log --oneline    # 查看进度与提交
python poc/tripo-gen.py --only xiaoman   # 生成第一个角色 GLB（需 TRIPO_API_KEY）
cat CHANGELOG.md                  # 看里程碑进度
cat poc/build-log.md              # 看每日细节
```

---

## 探测器（给后续 Agent）

- 需要角色设定 → 查 `docs/characters/*.json`，勿用空壳 `web-*` 文件。
- 需要设计方向 → 读 `docs/topic.md` + `docs/design-summary-report.md`。
- 需要赛事规则 / 验收 → 读 `docs/demand.md`。
- 需要边缘进度 → 读 `CHANGELOG.md` + `poc/build-log.md`。
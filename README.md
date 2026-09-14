# 送给你这个回来的人

> **Tripothon S1**（Tripo AI 世界构建黑客松）参赛项目 —— 「A Gift for ______」
>
> 一座会自动运转的小镇：你离开时，角色们在真实时间里继续生活、写日记、想心事；你回来时，他们还记得你。

---

## 简介

一款 3D 二次元陪伴体验（TapTap Maker 构建）：玩家回到小镇，三位角色（小满 / 阿泽 / 奶奶）基于**真实时间差**自主生成事件与日记，让玩家感受到「我不在的时候，这个世界仍在运转」。核心体验不是通关，而是**被记得**。

- **引擎**：TapTap Maker（UrhoX + Lua）
- **3D 角色**：Tripo `text_to_model` 生成 GLB
- **AI**：Maker 内置 AI + 角色 system prompt（Lua 调度事件）

---

## 关键文档

| 文档 | 内容 |
|------|------|
| [赛事规则](docs/demand.md) | Tripothon S1 赛道、交付物、评审权重、验收清单 |
| [选题与设计](docs/topic.md) | 故事、角色、技术架构、7 天 PoC 计划、设计决策 |
| [设计方向汇报](docs/design-summary-report.md) | 玩法 / 表现 / 操作 / 核心循环设计 |
| [Tripo × Maker 联动调研](docs/integration.md) | Tripo API 与 TapTap Maker 的集成方案 |
| [角色设定核查](docs/characters/CHARACTER_DATA_AUDIT.md) | 孤独摇滚角色官方数据 + 冲突核查（结构化数据见 `docs/characters/`） |

## 开发日志

- **[CHANGELOG.md](CHANGELOG.md)** — 里程碑进度（当前进度表）
- **[poc/build-log.md](poc/build-log.md)** — 每日开发日志（Day 0 完成 / Day 1 计划）

## 给 AI Agent

接手本仓库前请先读 **[AGENTS.md](AGENTS.md)**：目录结构、文档地图、权威度约定与易错点。

---

## 快速开始（PoC）

```bash
# 1. 生成第一个角色 GLB（需 TRIPO_API_KEY）
cd poc
python tripo-gen.py --only xiaoman

# 2. 初始化 TapTap Maker 项目
npx -y @taptap/maker init

# 3. 实机预览 / 测试
#    详见 poc/README.md
```

> 提交截止：**2026-10-05**（线上）· 详情见 `docs/demand.md`。

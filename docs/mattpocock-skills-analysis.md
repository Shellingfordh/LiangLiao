# mattpocock/skills 仓库分析

> 来源：https://github.com/mattpocock/skills
> 克隆位置：`research/mattpocock-skills/`

---

## 仓库概述

Matt Pocock 的 Agent Skills 集合，面向"真正的工程师"（非 vibe coding）。特点是小型、易适配、可组合，适用于任何模型。

---

## 设计前技能（Pre-design Skills）

### 🎯 核心设计技能

| 技能 | 路径 | 用途 |
|------|------|------|
| **grilling** | `skills/productivity/grilling/` | 连续追问用户，构建设计决策树。每轮计算前沿问题，推荐答案，等用户回答后再推进。 |
| **domain-modeling** | `skills/engineering/domain-modeling/` | 主动构建项目领域词汇表 + ADR。挑战术语、发明边缘场景、即时记录决策。 |
| **wayfinder** | `skills/engineering/wayfinder/` | 将大型工作规划为 issue tracker 上的决策工单地图。纯规划，不执行。 |
| **prototype** | `skills/engineering/prototype/` | 用原型代码回答设计问题。两个分支：LOGIC（逻辑/状态模型）和 UI（界面探索）。 |
| **research** | `skills/engineering/research/` | 对首要来源（官方文档、源码、规范）进行调查，写成 Markdown 文件。 |

### 📝 规格与文档技能

| 技能 | 路径 | 用途 |
|------|------|------|
| **to-spec** | `skills/engineering/to-spec/` | 将当前对话转化为规格说明，发布到 issue tracker。 |
| **to-questionnaire** | `skills/productivity/to-questionnaire/` | 将无法独自回答的决策转化为问卷，发给持有缺失知识的人。 |
| **to-tickets** | `skills/engineering/to-tickets/` | 将规格转化为实现工单。 |
| **triage** | `skills/engineering/triage/` | 对工单进行分类和优先级排序。 |

### ✍️ 叙事/故事设计技能（游戏叙事特别有用）

| 技能 | 路径 | 用途 |
|------|------|------|
| **writing-fragments** | `skills/in-progress/writing-fragments/` | **探索阶段**：挖掘原始片段，不设结构。连续追问，将片段追加到单一 Markdown 文件。 |
| **writing-shape** | `skills/in-progress/writing-shape/` | **成型阶段**：将原始材料逐段塑造成文章。读取→建立前提→起草开头→逐段生长。 |
| **writing-beats** | `skills/in-progress/writing-beats/` | **节拍阶段**：将材料组装成节拍旅程，类似 choose-your-own-adventure。 |

### 🔧 工程实现技能

| 技能 | 路径 | 用途 |
|------|------|------|
| **codebase-design** | `skills/engineering/codebase-design/` | 深度模块设计词汇表。Module、Interface、Implementation、Depth 等术语。 |
| **implement** | `skills/engineering/implement/` | 实现功能。 |
| **tdd** | `skills/engineering/tdd/` | 测试驱动开发。 |
| **code-review** | `skills/engineering/code-review/` | 代码审查。 |
| **diagnosing-bugs** | `skills/engineering/diagnosing-bugs/` | 诊断 bug。 |
| **resolving-merge-conflicts** | `skills/engineering/resolving-merge-conflicts/` | 解决合并冲突。 |

### 🛠️ 辅助技能

| 技能 | 路径 | 用途 |
|------|------|------|
| **wizard** | `skills/engineering/wizard/` | 生成交互式 bash 向导，引导人工完成手动步骤（如配置第三方服务、设置 CI 密钥）。 |
| **handoff** | `skills/productivity/handoff/` | 将当前对话压缩为交接文档，供下一个 agent 接手。 |
| **teach** | `skills/productivity/teach/` | 教用户新技能或概念，支持多会话学习。 |
| **grill-with-docs** | `skills/engineering/grill-with-docs/` | 结合 grilling + domain-modeling，边追问边创建文档。 |
| **ask-matt** | `skills/engineering/ask-matt/` | 向 Matt Pocock 提问。 |
| **wait-what** | `skills/productivity/wait-what/` | 澄清误解。 |
| **writing-for-agents** | `skills/productivity/writing-for-agents/` | 为 agent 编写文档。 |

---

## 对本项目的应用建议

### 游戏叙事设计工作流

```
writing-fragments → writing-shape → writing-beats
    (探索)            (成型)         (节拍旅程)
```

1. **writing-fragments**：挖掘山田凉的角色故事片段
   - 她的音乐梦想
   - 与后藤一里的关系
   - "给___的礼物"主题
2. **writing-shape**：将片段塑造成游戏叙事结构
3. **writing-beats**：设计玩家体验的节拍旅程

### 设计决策工作流

```
grilling → domain-modeling → to-spec → to-tickets
  (追问)      (建模)         (规格)     (工单)
```

1. **grilling**：深入挖掘游戏设计决策
2. **domain-modeling**：建立项目术语表
3. **to-spec**：输出游戏规格说明
4. **to-tickets**：分解为可执行工单

### 原型验证

```
prototype (LOGIC 分支)：验证游戏状态模型
prototype (UI 分支)：探索游戏界面设计
```

---

## 安装方式

### 方式 1：Claude Code 插件（推荐）
```bash
# 通过 skills.sh 安装
npx skills.sh mattpocock/skills
```

### 方式 2：手动安装
```bash
git clone https://github.com/mattpocock/skills.git
# 将需要的技能复制到项目的 .agents/skills/ 目录
```

---

## 文件结构

```
research/mattpocock-skills/
├── AGENTS.md          # Agent 配置
├── CONTEXT.md         # 领域词汇表
├── CLAUDE.md          # Claude Code 配置
├── README.md          # 说明文档
├── docs/              # 详细文档
│   ├── engineering/   # 工程技能文档
│   └── productivity/  # 生产力技能文档
└── skills/            # 技能目录
    ├── engineering/   # 工程技能
    ├── productivity/  # 生产力技能
    ├── in-progress/   # 开发中技能
    ├── misc/          # 杂项技能
    └── deprecated/    # 已弃用技能
```

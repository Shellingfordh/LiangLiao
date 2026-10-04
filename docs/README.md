# LiangLiao / PARALLEL COMPANION

> **A living 3D companion world.**

## 开始前先看

**[PROJECT_OVERVIEW.md](./PROJECT_OVERVIEW.md)**

这是当前项目唯一的产品总纲。

## 当前核心定义

这个项目没有固定剧情线。

Event Generator 负责生成角色生活中发生的事实；LLM 负责正常聊天，并在相关时自然提到这些事实。

```text
Life
 ↓
Events
 ↓
World State
 ↓
LLM Context
 ↓
Conversation
 ↓
Memory
```

## 文档索引

| 文档 | 用途 |
|---|---|
| PROJECT_OVERVIEW.md | 产品总纲与最终冻结定义 |
| EVENT_SYSTEM.md | Event Generator 设计 |
| LLM_DIALOGUE.md | LLM 对话规则 |
| 3C_INTERACTION.md | Camera / Character / Control |
| ART_DIRECTION.md | 图片、2.5D、3D、Marble、Tripo |
| TECH_INTEGRATION.md | 系统模块和接口边界 |
| DATA_CONTRACTS.md | World / Event / Memory 数据结构 |
| DEV_HANDOFF.md | 开发者两天冲刺说明 |
| SUBMISSION_DEMO.md | 最终 Demo 演示脚本 |

## 提交前原则

不要为了增加功能而增加功能。

剩余时间只做：

- 稳定性
- Bug 修复
- 核心闭环
- 视觉表现
- Demo 可靠性

最终目标：

> **让评委相信，她不是一个等我点击的 NPC，而是一个本来就在另一个地方生活的人。**

# FINAL FREEZE / 2026-10-04

## 项目最终定义

PARALLEL COMPANION 是一个会继续生活的 3D 陪伴世界。

### 核心机制

**Event Generator + LLM Natural Conversation + Living World State**

### 重要边界

- 没有固定剧情
- 没有剧情树
- Event 不等于剧情
- Event 只是角色生活中的事实
- LLM 正常聊天
- Event 只在聊天相关时自然出现
- 用户可以错过事件
- 角色不会一直等待玩家
- 3D 是世界表现层，不是产品本身

### 提交前两天唯一目标

让以下链路稳定：

```text
World State
→ Event
→ LLM Context
→ Natural Conversation
→ Memory / World Trace
→ World continues
```

任何不直接增强这条链路的功能，提交前冻结。

# Developer Handoff / Final Freeze

## 0. 你现在需要知道什么

这是一个 **AI + Living World + 3D Companion** Demo。

核心不是剧情。

核心不是复杂 3D。

核心不是 Agent。

核心是：

> **一个人在另一个地方继续生活，Event Generator 记录她生活中发生的事情，LLM 在自然聊天中把相关事情讲出来。**

---

## 1. 两天优先级

### P0 必须完成

- 当前 Demo 可以启动
- 图片背景正常显示
- 角色正常显示
- Chat 可用
- LLM 可用或有 fallback
- World State 可显示
- Event 能生成 / 读取
- Event 能进入 LLM context
- 至少一个 Event 能在聊天中自然出现
- 时间 / 地点状态能变化

### P1 有时间再做

- 2.5D Parallax
- 角色小动作
- 环境粒子
- 物件变化
- 3D 场景替换
- Marble / Tripo 资产

### P2 提交前禁止主动扩张

- 新地图
- 新角色
- 战斗
- 任务系统
- 复杂背包
- 大型重构
- 自研模型
- 全实时生成世界

---

## 2. 最小 Demo 闭环

```text
Enter world
   ↓
See character + time + location
   ↓
Ask “今天怎么样？”
   ↓
LLM reads recent Event
   ↓
Natural response mentions Event
   ↓
User asks follow-up
   ↓
Event facts become conversation
   ↓
User shares something
   ↓
Memory / world trace
   ↓
Leave
   ↓
Return later
   ↓
Character state changed
```

只要这个闭环成立，项目就是成立的。

---

## 3. 如果代码已经存在

不要为了符合文档重写所有旧代码。

原则：

```text
Existing working code > theoretical architecture

但：
Current product definition > historical assumptions
```

也就是说：

- 保留已经稳定的 Maker / Godot / runtime 实现
- 在边界处接 Event
- 在 Chat context 处接 Recent Events
- 不为了架构漂亮重写整个工程

---

## 4. Commit 原则

每个人提交前说明：

```text
What changed
Why
How to test
Known limitation
```

不要提交：

- 大量无关格式化
- 临时大文件
- API key
- 本地路径
- 无法解释的二进制

---

## 5. 测试问题

开发完成后必须实际回答：

### Q1
角色现在几点？

### Q2
角色在哪里？

### Q3
最近发生了什么？

### Q4
用户问“今天怎么样”，LLM 是否可能自然提到这个事件？

### Q5
用户完全不问，事件是否可以不出现？

### Q6
离开后回来，状态是否发生变化？

### Q7
LLM 不可用时，Demo 是否还能完成展示？

---

## 6. 最重要的反例

如果看到以下体验，说明实现方向错了：

> “恭喜你触发了今日事件！”

> “请选择你要探索的剧情。”

> “完成任务：与若夕聊天。”

> “若夕正在等待你的消息。”

> “Event 001 已触发。”

这些都破坏 Living World 感。

---

## 7. 正确状态

用户应该感觉：

> “我刚好问到了她今天发生的事情。”

而不是：

> “我把一个事件触发出来了。”

---

## 8. 提交前最后检查

```text
[ ] 项目能启动
[ ] Demo 首屏 10 秒内理解
[ ] 角色是谁明确
[ ] 她在哪里明确
[ ] 当地时间明确
[ ] 当前活动明确
[ ] Chat 正常
[ ] Event Generator 正常
[ ] Event 不直接展示成剧情
[ ] LLM 能自然引用 Event
[ ] 至少一个事件可追问
[ ] 至少一个共同记忆可留下
[ ] 返回世界后状态发生变化
[ ] 3D 资产失败不会导致 Demo 失败
[ ] LLM/API 失败有 fallback
[ ] 没有 API key 泄漏
[ ] 提交包可独立运行
```

---

## 9. 最终冻结

从本文件发布开始，剩余两天只允许：

**修 Bug、补 Demo、提升视觉表现、提升稳定性。**

任何新功能必须回答：

> 它是否直接增强“一个人在另一个地方继续生活”这个核心体验？

如果不能，提交前不做。

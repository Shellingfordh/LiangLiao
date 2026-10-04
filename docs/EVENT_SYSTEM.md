# Event System / Event Generator

## 1. 目标

Event System 的职责只有一个：

> **生成并维护角色生活中“发生过什么”的事实。**

它不是剧情系统，也不是对话系统。

---

## 2. Event 的生命周期

```text
World Clock
   ↓
Current Character State
   ↓
Candidate Event Generation
   ↓
Validation / Constraints
   ↓
Event Created
   ↓
World State Update
   ↓
Recent Event Store
   ↓
LLM Context
```

---

## 3. Event 分类

### A. Routine

日常事件：

- 起床
- 吃饭
- 通勤
- 工作
- 咖啡
- 回家
- 睡觉

### B. Environmental

环境事件：

- 下雨
- 突然降温
- 店里很吵
- 地铁延误
- 咖啡店换了音乐

### C. Social

社交事件：

- 遇见朋友
- 同事找她
- 读者提问
- 收到消息

### D. Personal

个人事件：

- 买了一本书
- 丢了东西
- 完成一个工作
- 想起一件旧事

### E. Relationship

与玩家相关：

- 想起玩家说过的话
- 使用玩家送的物品
- 对之前的共同经历产生联想

---

## 4. Event 数据结构

推荐统一结构：

```json
{
  "id": "evt_20261004_1847_001",
  "time": "2026-10-04T18:47:00-07:00",
  "type": "social",
  "location": "bookstore",
  "summary": "书店活动比计划晚结束",
  "facts": [
    "活动原计划18:00结束",
    "实际约18:40结束",
    "一位读者留下来聊天",
    "角色买了一杯冰咖啡"
  ],
  "mood_delta": 0.1,
  "energy_delta": -0.15,
  "importance": 0.55,
  "chat_relevance": 0.75,
  "memory_candidate": false,
  "status": "active"
}
```

---

## 5. Event ≠ Dialogue

Event：

> “她今天在书店遇到一个有趣的读者。”

Dialogue：

> “今天书店里有个人问我一本特别奇怪的书，我居然跟他聊了快半小时。”

同一个 Event 可以被 LLM 用完全不同的语言表达。

因此禁止：

```text
Event → 固定文本 → 直接展示
```

推荐：

```text
Event → Facts → LLM → Natural Language
```

---

## 6. Event 不一定被玩家看到

事件有可见性：

```text
private
background
chat_relevant
relationship_relevant
important
```

只有与当前对话相关时才进入 LLM Context。

这样才能避免角色像一个“事件播报器”。

---

## 7. Event 生成约束

Event Generator 必须考虑：

- 当前时间
- 当前地点
- 当前工作状态
- 当前天气
- 当前精力
- 最近事件
- 人格
- 已有记忆
- 不重复
- 不与世界状态冲突

例如角色已经在家，就不能生成“她刚刚从咖啡店回来”，除非生成一个移动事件。

---

## 8. 两天 Demo 方案

不需要真正无限生成。

建议准备一组确定性 Event Seed：

```text
Morning
 → wake_up
 → coffee
 → work

Afternoon
 → bookstore_work
 → social_event

Evening
 → cafe
 → commute
 → home
```

LLM 负责把这些事实自然讲出来。

这样即使网络或生成服务出现问题，Demo 仍然能跑。

---

## 9. 验收标准

一个 Event 系统通过验收必须满足：

- 能生成事实
- 不直接输出剧情文本
- 不强迫玩家看到
- 能被 LLM 读取
- 与当前时间地点一致
- 可以被后续记忆系统引用
- 不阻塞聊天

---

## 10. 禁止事项

不要把 Event System 做成：

- 剧情编辑器
- Quest Manager
- Dialogue Tree
- LLM 自由发挥的故事生成器
- 每分钟强制生成随机事件

我们要模拟的是“生活”，不是“连续发生的剧情”。

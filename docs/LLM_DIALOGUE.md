# LLM Dialogue System

## 1. 核心原则

LLM 是一个**正常聊天的人格化对话层**。

它不承担：

- 剧情编排
- Quest 生成
- Unity 物理控制
- 随机世界生成
- 事件事实创造

Event Generator 提供事实，LLM 负责理解、选择和表达。

---

## 2. Context 组成

推荐：

```text
SYSTEM
├─ Character Persona
├─ Speech Style
├─ Relationship Rules
├─ Current World State
├─ Recent Events
├─ Relevant Memory
└─ Safety / Consistency Rules

CONVERSATION
├─ Recent user messages
└─ Recent assistant messages

USER
└─ current message
```

---

## 3. Event 注入方式

不要告诉 LLM：

> “请讲一下 Event 001。”

应该提供：

```text
Recent life facts:
- The bookstore event ended 40 minutes late.
- She spoke with a reader afterward.
- She bought iced coffee.

Use these facts only when naturally relevant.
Do not enumerate them.
Do not mention the existence of an event system.
```

这样 LLM 才会像一个真正的人。

---

## 4. 对话示例

用户：

> 今天忙吗？

LLM：

> 有点，今天书店那边的活动拖得比预想久。

用户：

> 怎么了？

LLM：

> 最后有人留下来问了很多问题，本来六点结束，我出来的时候都快七点了。

用户：

> 那你吃饭了吗？

LLM：

> 还没有……我刚买了杯冰咖啡，感觉这东西已经不能算晚饭了。

注意：

没有一个“剧情节点”被播放。

---

## 5. LLM 行为原则

### 自然

不主动播报系统状态。

### 不全知

不知道的事情就不知道。

### 不抢戏

不要每一句话都主动抛出一个事件。

### 有生活感

允许短回答、跑题、犹豫、记错普通细节，但重要事实必须保持一致。

### 不连续制造高潮

生活中大多数事情都很普通。

---

## 6. 记忆

只保存有长期价值的内容：

- 用户明确说过的重要事情
- 共同经历
- 约定
- 喜好
- 重要关系变化
- 对未来有影响的事实

不要把完整聊天记录全部塞进长期记忆。

推荐：

```text
Conversation
   ↓
Candidate Memory
   ↓
Importance / Relevance
   ↓
Persistent Memory
```

---

## 7. 防止 LLM 把 Event 说成“任务”

禁止风格：

> “今天触发了一个特殊事件。”

> “我有一件事情要告诉你。”

> “任务完成了。”

推荐：

> “今天店里倒是发生了件挺有意思的事。”

甚至可以完全不提。

---

## 8. LLM 与 Unity 的边界

LLM 可以输出语义意图，例如：

```json
{
  "emotion": "tired",
  "suggested_state": "go_home"
}
```

但 Unity / World Runtime 决定：

- 播放什么动画
- 角色移动到哪里
- 摄像机如何切换
- 灯光怎么变化

不要让 LLM 直接调用几十个 Unity 操作。

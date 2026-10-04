# 3C Interaction Specification

本项目的 3C 指：

- Camera
- Character
- Control

这里的 3C 不追求传统游戏操作复杂度，而是定义玩家如何“进入另一个人的生活”。

---

## 1. Camera

### 当前 Demo

采用固定 / 半固定状态窗口。

推荐比例：4:3 或接近 4:3。

镜头负责回答：

> 她现在在哪里？
> 她正在做什么？

### 镜头状态

最少准备：

1. Apartment
2. Cafe
3. Work / Bookstore
4. Commute / Street

不需要自由旋转。

---

## 2. Character

角色是世界里的独立主体。

玩家不直接控制她走路。

角色拥有：

```text
Location
Activity
Mood
Energy
Schedule
Recent Events
Memory
Relationship State
```

这些状态共同决定她现在“是什么样子”。

---

## 3. Control

核心控制只有：

```text
观察
聊天
离开 / 回来
```

不加入：

- WASD
- 战斗按键
- 技能
- 复杂交互轮盘
- 大量按钮

如果未来进入完整 3D 世界，再增加：

- Look
- Enter / Inspect
- Object Interaction

但提交 Demo 不需要。

---

## 4. UI 层级

推荐：

```text
┌────────────────────────────┐
│ LA · 18:47 · Bookstore     │
│                            │
│        3D / 2.5D           │
│       Character View       │
│                            │
├────────────────────────────┤
│ Chat                       │
│ You: 今天怎么样？           │
│ Ruo Xi: 刚从书店出来……      │
│                            │
│ [ Type message... ]        │
└────────────────────────────┘
```

UI 不应该像传统游戏 HUD。

它更接近一个“看向另一个世界的窗口”。

---

## 5. 状态窗口不是装饰

顶部状态至少展示：

- 城市
- 当地时间
- 当前地点
- 当前活动 / 简短状态

例如：

```text
Los Angeles · 18:47
Bookstore · Event just ended
```

这会帮助用户理解为什么角色现在说这样的话。

---

## 6. Time Zone

时区属于玩法。

如果玩家和角色处于不同时间：

```text
Player 09:00 Beijing
Character 18:00 LA
```

角色可能正在下班、回家或准备休息。

不要为了追求“实时”而让系统变得不稳定。Demo 可以使用模拟时钟。

# PARALLEL COMPANION / LiangLiao

## 项目冻结说明

**版本：Final Submission Freeze · 2026-10-04**

这份文档是提交前两天的项目总纲。当前所有开发、设计、美术和技术判断都以本文件为最高优先级。

如果旧文档、旧代码注释、历史讨论与本文件冲突，以本文件为准。历史实现可以保留，但不得因为历史实现反向改变当前产品定义。

---

## 1. 一句话定义

**PARALLEL COMPANION 是一个会继续生活的 3D 陪伴世界。**

玩家面对的不是一个等待玩家点击的 NPC，也不是一条预先写好的剧情线，而是一个**拥有自己的时间、地点、状态和生活事件的人**。

> Most AI companions live in conversation. Ours lives in a world.

核心体验：

> **我不需要一直陪着她，但我知道她正在另一个地方生活；当我们聊天时，她会自然地把刚刚发生在她身上的事情带进我们的对话。**

---

## 2. 最重要的产品决定：没有固定剧情

本项目**不采用章节剧情、任务链、固定对话树作为核心结构**。

没有：

- 第一章 / 第二章
- 主线任务
- 固定剧情节点
- “点击后播放剧情”
- 固定 Dialogue Choice 树
- 好感度决定剧情分支
- 玩家必须按顺序完成的故事

有的是：

```text
Character Life Profile
        ↓
Event Generator
        ↓
World State / Recent Life
        ↓
LLM normal conversation
        ↓
Relevant events naturally appear in dialogue
        ↓
Memory / relationship continuity
```

### 2.1 Event 不是剧情

Event 是角色生活中的**事实或短时状态变化**。

例如：

```json
{
  "event": "bookstore_event_finished_late",
  "time": "18:47",
  "location": "bookstore",
  "facts": [
    "活动比原计划晚结束",
    "有读者留下来和她讨论了一会儿",
    "她买了一杯冰咖啡"
  ],
  "mood": "slightly_tired_but_good",
  "visibility": "chat_relevant"
}
```

这个 Event **不会自动弹出成剧情文本**。

用户问：

> 今天怎么样？

LLM 才会根据当前角色状态决定：

> 还行，刚从书店出来。今天那个活动拖得有点晚。

用户继续追问，事件才可能逐渐展开。

用户如果完全不问，也可能永远不知道这个事件。

这就是本项目与传统剧情游戏最核心的区别。

---

## 3. 核心循环

```text
观察
 ↓
看到角色此刻在哪里 / 在做什么
 ↓
聊天
 ↓
LLM 根据角色人格、记忆和当前生活状态自然回答
 ↓
聊天中偶然发现她最近发生过什么
 ↓
继续追问 / 分享自己的事情
 ↓
形成共同记忆
 ↓
离开
 ↓
世界继续运行
 ↓
下一次回来，角色已经经历了新的生活
```

### 3.1 玩家真正获得的不是“剧情进度”

而是：

- 对另一个人的生活逐渐产生认识
- 发现她今天经历了什么
- 记住她说过的小事
- 让自己的聊天成为她生活的一部分
- 下次回来时发现生活已经继续

---

## 4. 四个核心卖点

### 4.1 Living World

角色离开聊天窗口后不会被冻结。

她有：

- 当前地点
- 当前时间
- 当前活动
- 情绪 / 精力
- 最近发生的生活事件
- 下一步可能做什么

Demo 中不需要真正 24/7 模拟。可以使用离散时间推进和确定性事件生成，但玩家感受到的必须是“她的生活没有因为我退出而暂停”。

### 4.2 Time / Distance

时区不是 UI 装饰，而是世界状态的一部分。

例如：

```text
玩家：北京 09:30
角色：洛杉矶 18:30
```

角色可能正在：

- 通勤
- 工作
- 咖啡店
- 书店活动
- 回家
- 睡觉

所以她没有必要立即回复。

### 4.3 Life-driven Conversation

聊天内容不是从剧情脚本里取，而是从角色当前生活状态中产生。

LLM 的输入至少包括：

```text
Character Persona
+ Current World State
+ Recent Events
+ Relevant Memory
+ Conversation Context
+ User Message
```

LLM 输出的是自然语言回复，不负责直接控制 Unity 的物理世界。

### 4.4 Relationship Leaves Traces

重要共同经历可以留下世界痕迹：

- 房间里的物品
- 一张照片
- 某个地点
- 一个习惯
- 一句话
- 一个共同约定
- 用户送来的物件

这样关系会从“聊天记录”变成“世界状态”。

---

## 5. “Gift”与 Tripo 的关系

Tripothon 的主题是 **A Gift for ______**。

我们不应该把“Gift”做成传统任务：

> 点击送礼 → 播放动画 → +10 好感。

更适合的表达是：

> **你把现实世界中的一个东西带进她的世界。**

例如：

```text
现实中的物件 / 图片
        ↓
AI / Tripo
        ↓
3D asset
        ↓
进入角色的生活空间
        ↓
角色以后可以自然提到它
```

这个物件应该成为**世界的一部分**，而不是 UI 奖励。

两天 Demo 若无法完整实现真实物件生成，可使用预生成 Asset 完成闭环。不要让实时生成成为 Demo 的单点故障。

---

## 6. 世界范围

我们不做开放世界。

比赛 Demo 应该是一个**小而密的生活空间**：

```text
Apartment
 ├─ living room
 ├─ desk
 └─ bedroom

Nearby
 ├─ cafe
 ├─ bookstore
 └─ commute / street
```

真正重要的是：

> 小世界里有足够多可以被角色生活和聊天提及的细节。

不要为了“3D 世界”无限扩地图。

---

## 7. 当前画面策略

### Submission-safe 路线

```text
现有图片背景
+
角色 3D / 2.5D
+
轻微动画 / 呼吸 / 动作
+
状态 UI
+
聊天
```

这是当前 Demo 的安全基线。

### 进阶路线

```text
2.5D / Layered Background
        ↓
3D Scene
        ↓
可进入 / 可观察的 Living World
```

如果 Marble 资产面数过高，不影响产品成立。优先做：

1. 减面
2. LOD
3. 材质合并
4. 贴图压缩
5. 减少实时光源
6. 降低场景复杂度

格式转换：

```text
GLB
 ↓
Asset optimization
 ↓
MDL / 当前运行时所需格式
 ↓
Maker / Engine
```

具体转换工具或格式细节属于实现问题，不改变产品定义。

---

## 8. 明确不做

提交前冻结以下内容：

- 不增加大型开放世界
- 不增加战斗
- 不增加 RPG 数值
- 不增加任务系统
- 不增加复杂背包
- 不增加多个可攻略角色
- 不增加完整恋爱路线
- 不训练自己的大模型
- 不做全世界实时 AI 生成
- 不让 LLM 直接控制所有 Unity 行为
- 不为了 3D 推翻已经稳定的图片背景 Demo
- 不为了“看起来很 AI”堆 Agent

---

## 9. Demo 必须让评委看到什么

推荐 5–8 分钟闭环：

### Scene 1：第一次进入

看到角色正在另一个地方生活。

### Scene 2：观察

知道：

- 城市
- 时间
- 地点
- 她正在做什么

### Scene 3：聊天

正常聊天，不出现游戏式菜单。

### Scene 4：自然发现事件

用户问今天怎么样。

角色自然提到一个刚发生的生活事件。

### Scene 5：追问

用户继续问，事件逐渐被讲出来。

### Scene 6：留下共同记忆

用户分享 / 送出一个东西。

### Scene 7：世界改变

物件出现在她的空间，或者成为后续对话中的共同记忆。

### Scene 8：离开再回来

时间发生变化，角色正在做另一件事情。

最终评委应该理解：

> **这个人不是为了回答我而存在，她本来就在生活。**

---

## 10. 当前技术原则

推荐逻辑：

```text
World State
     ↓
Event Generator
     ↓
Recent Life Events
     ↓
LLM Context Builder
     ↓
LLM
     ↓
Natural Conversation
```

Unity / Maker：负责呈现和执行。

Backend：负责世界状态、事件、LLM、记忆和资产任务。

LLM：负责理解和表达，不负责物理执行。

---

## 11. Source of Truth

当前项目文档优先级：

1. `docs/PROJECT_OVERVIEW.md`
2. `docs/EVENT_SYSTEM.md`
3. `docs/LLM_DIALOGUE.md`
4. `docs/3C_INTERACTION.md`
5. `docs/ART_DIRECTION.md`
6. `docs/TECH_INTEGRATION.md`
7. `docs/DEV_HANDOFF.md`
8. 其他历史文档

如果代码已经存在但与上述设计不完全一致，**两天内优先保持可运行 Demo，不做大规模重构**。

---

## 12. 最终产品心智模型

不要把它理解成：

> “一个有 3D 场景的 AI 聊天机器人。”

正确理解是：

> **“一个住在另一个地方、会继续生活的人。我偶尔可以进去看看她，并和她聊天。”**

这就是本项目最后的产品定义。

# Technical Integration

## 1. 系统总览

```text
                  ┌──────────────┐
                  │ World Clock  │
                  └──────┬───────┘
                         ↓
                  ┌──────────────┐
                  │ World State  │
                  └──────┬───────┘
                         ↓
                ┌─────────────────┐
                │ Event Generator │
                └───────┬─────────┘
                        ↓
                 Recent Events
                        ↓
                ┌───────────────┐
User Message → │ Context Builder│
                └───────┬───────┘
                        ↓
                      LLM
                        ↓
                 Natural Reply
                        ↓
               Memory / UI update
```

---

## 2. 模块职责

### World Runtime

负责：

- 场景
- 角色
- Camera
- Animation
- Visual State

### Event Generator

负责：

- 生活事件
- 时间推进
- 状态变化
- Event facts

### LLM Gateway

负责：

- Prompt assembly
- LLM request
- Streaming / response
- Error fallback

### Memory

负责：

- Long-term relationship facts
- Shared experiences
- Important preferences

### Asset Pipeline

负责：

- GLB
- MDL
- Textures
- Prefabs
- Tripo / Marble output

---

## 3. 数据边界

Event Generator 不应该生成最终对白。

LLM 不应该修改任意世界物理状态。

Unity 不应该自己猜测人格。

推荐：

```text
Facts → Event
Expression → LLM
Execution → Runtime
```

---

## 4. 推荐 World State

```json
{
  "world_id": "ruoxi_la",
  "local_time": "18:47",
  "weather": "clear",
  "location": "bookstore",
  "character": {
    "name": "若夕",
    "activity": "event_finished",
    "mood": "good",
    "energy": 0.42
  },
  "recent_events": [
    "evt_001",
    "evt_002"
  ]
}
```

---

## 5. Demo 安全机制

网络服务不是 Demo 的唯一依赖。

至少准备：

```text
LLM online
     ↓ failure
Cached / fallback response

Event Generator online
     ↓ failure
Pre-seeded event timeline
```

比赛现场最忌讳：

> “这个 API 当时刚好超时，所以没演出来。”

---

## 6. Asset 性能检查

3D 场景至少记录：

- FPS
- Triangle count
- Draw calls
- Material count
- Texture memory
- Loading time

不要只凭“看起来模型很重”判断性能。

---

## 7. 推荐接口概念

### `GET /world/state`

获取当前世界状态。

### `GET /events/recent`

获取最近生活事件。

### `POST /events/generate`

生成 / 推进事件。

### `POST /chat`

发送聊天消息。

### `POST /memory`

保存候选长期记忆。

### `POST /assets/generate`

生成 / 注册 3D 资产。

具体 API 名称可以适配现有代码，不要求为了文档重构现有接口。

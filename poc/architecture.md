# 架构图与数据流

> 适用于 PoC 评审 + 后期实现参考

---

## 1. 系统总览

```
┌──────────────────────────────────────────────────────────────────┐
│                     TapTap Maker（客户端）                        │
│  ┌────────────────┐  ┌────────────────┐  ┌─────────────────┐  │
│  │  场景/资源层   │  │  Lua 脚本层    │  │  Maker AI       │  │
│  │                │  │                │  │                 │  │
│  │ • 3D GLB 模型  │  │ • main.lua     │  │ • 角色扮演      │  │
│  │   (Tripo 出)   │  │ • event_sched  │  │ • 事件文案生成  │  │
│  │ • UI 主题      │  │ • time_sync    │  │ • 日记生成      │  │
│  │   (Astroon)    │  │ • memory_io    │  │                 │  │
│  │ • Spine 气泡   │  │ • role/*       │  │ (Skill 注入     │  │
│  │                │  │ • ui/bubble    │  │  system prompt) │  │
│  └────────────────┘  └────────────────┘  └─────────────────┘  │
│         ↑                  ↑                      ↑             │
│         └──────────────────┼──────────────────────┘             │
│                            │                                     │
│                      clientCloud                                 │
│                  (跟随登录用户的云存档)                           │
│                                                                    │
└──────────────────────────────────────────────────────────────────┘
                              ↑
                       (用户从 TapTap 启动)
                              ↑
                  ┌────────────────────────┐
                  │  Tripo OpenAPI         │
                  │  api.tripo3d.ai        │
                  │  (离线：构建期调用)    │
                  └────────────────────────┘
                              ↑
                  ┌────────────────────────┐
                  │  PoC 生成脚本          │
                  │  poc/tripo-gen.py      │
                  │  poc/tripo-prompts.json│
                  └────────────────────────┘
```

---

## 2. 数据流（关键交互时序）

### 2.1 玩家首次进入小镇

```
玩家启动 App
   ↓
Maker 引擎加载 → main.lua
   ↓
MemoryIO.get_int("last_visit_ts") → 0（首次）
   ↓
last_visit = now；elapsed_sec = 0
   ↓
跳过 "miss_you" 事件触发
   ↓
MemoryIO.set_int("last_visit_ts", now)
   ↓
显示欢迎气泡：每个角色头顶"嘿/……/哎呀"开场白
```

### 2.2 玩家离开 24 小时后再次进入

```
玩家启动 App
   ↓
Maker 引擎加载 → main.lua
   ↓
MemoryIO.get_int("last_visit_ts") → 上次时间戳
   ↓
elapsed_sec = 24 * 3600（约 86400）
   ↓
TimeSync.estimate_offline_events(role_id, last, now)
   ├─ 每小时 1 条 background（最多 7 条）
   ├─ 每 6 小时 1 条 habit
   ├─ 雨季每 24 小时 1 条 weather
   └─ 检查是否跨过角色生日
   ↓
逐条写入 MemoryIO.append_event(role.id, ev)
   ↓
触发"miss_you"事件（priority=high）→ EventScheduler → Bubble.show
   ↓
玩家走近角色 → 触发"greeting"事件
   ↓
玩家点击角色 → ai.OpenConversation(role.id, {system_prompt, memory_events})
   ↓
Maker AI 按 system prompt 扮演 + 引用最近 3 条事件
   ↓
玩家点击"💭" → 日记面板
   ↓
Maker AI 按 event.system.md 生成最近 7 天日记
```

### 2.3 走近角色（实时事件）

```
玩家每帧位置检测
   ↓
距离 < 5 米 && !_already_greeted_in_session(role_id)
   ↓
EventScheduler.on_player_near(role_id)
   ├─ 内存去重：_shown[role_id+":greeting"] = now
   ├─ MemoryIO.append_event(role_id, {type="greeting", ...})
   └─ Bubble.show(role_id, {title="打招呼", body=..., emotion=...})
```

---

## 3. 数据归属

| 数据 | 类型 | API | 说明 |
| --- | --- | --- | --- |
| 玩家上次访问时间 | int | `clientCloud.SetInt/GetInt` | 单字段，全局唯一 |
| 玩家访问次数 | int | `clientCloud.SetInt/GetInt` | 单字段 |
| 玩家喜欢的口味（3 角色各自） | string | `clientCloud.Set/Get` | PoC 阶段手动设 |
| 玩家借书记录 | table | `clientCloud.Set/Get` | JSON 序列化 |
| 角色事件日志（每角色） | list | `clientCloud.Set/Get` | JSON 列表，最多 100 条 |
| 角色日记（每角色） | list | `clientCloud.Set/Get` | JSON 列表，最多 30 天 |

**全部用 `clientCloud`**：单人 PoC，不需要服务端权威性。
**不混用 `File` 和 `serverCloud`**：避免跨平台一致性 bug。

---

## 4. 三个角色的事件触发矩阵

| 角色 | 触发源 | 触发条件 | 事件类型 | 优先级 |
| --- | --- | --- | --- | --- |
| 小满 | 定时 | 游戏内 7:00 | `bread_ready` | normal |
| 小满 | 定时 | 游戏内 8:00 + 玩家有 favorite_flavor | `favorite_ready` | high |
| 小满 | 天气 | 下雨 | `closed_for_rain` | normal |
| 小满 | 时间差 | 离开 ≥ 1h | `miss_you` | high |
| 阿泽 | 定时 | 游戏内 15:00 | `new_book` | normal |
| 阿泽 | 天气 | 阴天 | `no_window` | normal |
| 阿泽 | 借阅 | 借书 > 3 天 | `book_overdue` | high |
| 阿泽 | 时间差 | 离开 ≥ 1h | `miss_you` | high |
| 奶奶 | 定时 | 节气当天 6:00 | `solar_term` | high |
| 奶奶 | 定时 | 游戏内 8:00 + 玩家有 favorite_veg | `veg_ready` | high |
| 奶奶 | 时间差 | 离开 ≥ 1h | `miss_you` | high |
| 全员 | 玩家走近 | 距离 < 5m && 未本会话内触发过 | `greeting` | normal |

---

## 5. 时间差反推规则（详细）

> 见 `scripts/time_sync.lua` §estimate_offline_events

```
elapsed = (now - last_visit) 秒
elapsed_hours = elapsed / 3600
cap_hours = min(elapsed_hours, 168)   # 上限 7 天

for each role:
    n_background = min(cap_hours, 7)
    每条 ts = last_visit + (i / (n_background+1)) * elapsed
    → 均匀分布在 [last, now] 区间内

    n_habit = floor(cap_hours / 6)
    n_weather = floor(cap_hours / 24)  if is_rainy_season(now)
    n_birthday = 1 if is_birthday_in_window

    按 ts 升序排序
```

**为什么是 7 天上限**：超过 7 天的事件，玩家会觉得"他们没这么熟"。同时日志条数也不会爆炸（每个角色最多 7 + 4 + 1 = 12 条/天 * 7 天 = 84 条，仍然在 100 条上限内）。

---

## 6. 为什么这样切分职责

| 模块 | 负责 | 不负责 |
| --- | --- | --- |
| **Tripo 脚本**（Python） | 离线生成 3D 模型 | 运行时行为、对接 Maker |
| **Lua 脚本** | 触发时机、数据持久化、时间计算 | 文案生成（除非用模板字符串） |
| **Maker AI** | 文案生成、对话扮演、日记写作 | 时机判断、状态持久化 |
| **Maker 引擎**（UrhoX） | 渲染、物理、UI 组件 | 业务逻辑 |

**关键边界**：
- Lua 不知道"时间差反推应该生成什么文案"——它只把规则告诉 Maker AI："miss_you 已触发，请按 system prompt 生成 30 字内的回复"
- Maker AI 不知道"什么时候该触发"——它只是被调用
- Tripo 不参与运行时——它是构建期工具

---

## 7. 扩展方向（如果时间允许）

- [ ] 加第 4 个角色（"阿婆"，更老的 NPC，专管天气）
- [ ] 加照片功能（玩家可以发照片给角色，角色"看图说话"）
- [ ] 加多人联机（用 `serverCloud` + UrhoXServer）
- [ ] 加好感度系统（参考 hello-agents ch15 §15.3）
- [ ] 加"邀请朋友来小镇"机制
- [ ] 加 NPC 之间的对话（两个角色见面会自己说话）

---

## 8. 已知缺陷

| 缺陷 | 影响 | 妥协方案 |
| --- | --- | --- |
| 离线事件是"反推"不是"真模拟" | 玩家如果仔细看时间戳会觉得"太规律" | 在文案层面打乱时间（用 `os.date` 二次格式化） |
| `clientCloud` 写入是异步 | 极端情况会丢失最近一条事件 | Lua 端加重试 + 失败 fallback |
| 没有服务端权威 | 玩家可以改本地存档 | PoC 阶段可接受 |
| Maker AI 扮演不稳定 | 偶尔跑题 | system prompt 里加"绝对不要"清单 |
| Lua API 命名推测 | 实际可能不同 | 让 Maker AI 修正 |
# Skill: 平行小镇（Parallel Town Companions）

> 适用于 Tripothon S1 项目「送给你这个回来的人」
> 适用题材：陪伴型 / 二次元 / 单人单机
> 适用引擎：TapTap Maker（UrhoX + Lua）

## 这是什么

一个 Maker 项目的工作流：**3 个二次元角色，每个角色有独立的「事件生成器」和「平行于现实时间的时间线」**。玩家离开后，角色继续"活着"；玩家回来，角色记得他、给他留东西、问候他。

## 必须遵循的设计约束

1. **不要写服务端**：所有数据用 `clientCloud`。Maker 引擎限制，无法注入 Python/JS 后端。
2. **不要做实时 NPC 调度**：Maker 引擎不能后台跑逻辑。"离线事件"通过玩家进入瞬间反推（见下文）。
3. **Maker AI 负责"对话内容"和"事件文案"，Lua 负责"触发时机"**。两边职责严格分开，不要让 Lua 做 LLM 调用。
4. **3 个角色 = 3 个独立人设**。不能合并成一个万能 NPC。
5. **二次元风格**：UI 走 Astroon 主题（暖色调，符合小镇 + 陪伴感）。

## 触发工作流

当用户在对话里说以下任一句时，立刻按本 Skill 行动：

- "加 3 个角色" / "加小满/阿泽/奶奶"
- "帮我接入时间差事件"
- "做离线事件"
- "实现想念事件"
- "按 skill.md 的工作流继续"

行动步骤：

### Step 1：检查 `assets/models/` 目录里有没有以下 GLB 文件

- `xiaoman.glb`
- `aize.glb`
- `grandma.glb`

如果有 → 直接用。如果只有 `out/models/` 里的提示用户把它拷到 `assets/models/`。

### Step 2：让 AI 阅读以下 4 份 system prompt 文件

- `prompts/xiaoman.system.md`
- `prompts/aize.system.md`
- `prompts/grandma.system.md`
- `prompts/event.system.md`

让 AI 把它们当作"角色契约"，所有对话和事件生成都遵守。

### Step 3：让 AI 把以下 Lua 文件拷到 `scripts/` 目录

- `scripts/main.lua` — 入口
- `scripts/event_scheduler.lua` — 调度
- `scripts/time_sync.lua` — 时间差反推
- `scripts/memory_io.lua` — clientCloud 封装
- `scripts/role/xiaoman.lua` `aize.lua` `grandma.lua`
- `scripts/ui/bubble.lua`

### Step 4：在对话面板里指挥 AI 完成以下场景搭建

- 主场景：3D 透视小镇，三个角色分别放在 面包店 / 图书馆 / 镇郊菜园
- 玩家可以 WASD 或点击移动，走到角色 5 米内触发"打招呼"气泡
- 点击角色打开对话面板
- 主菜单有一个"📮 信箱"按钮，显示最近 7 天的离线事件和日记
- 每个角色头顶的"💭"图标可以打开他的日记面板

### Step 5：每个角色至少要配置的事件

| 角色 | 触发条件 | 事件类型 | 文案要求 |
| --- | --- | --- | --- |
| 小满 | 游戏内 7:00 | `bread_ready` | 包含"出炉/刚烤/新鲜" |
| 小满 | 下雨 | `closed_for_rain` | 嘴硬但关心玩家 |
| 阿泽 | 游戏内 15:00 | `new_book` | 提到"想给你看"或类似 |
| 阿泽 | 阴天 | `no_window` | 安静、博学气质 |
| 奶奶 | 节气当天 | `solar_term` | 提到"记得添衣/加衣" |
| 奶奶 | 游戏内 8:00 + 玩家喜欢的菜 | `veg_ready` | "刚好熟了/你拿点" |
| 全员 | 离开 ≥ 1 小时 | `miss_you` | 必须提到具体小时数 |

### Step 6：测试清单

让 AI 自己跑一遍验证：

- [ ] 首次进入：角色头顶气泡显示"欢迎回来"
- [ ] 5 秒后走近小满：触发"打招呼"
- [ ] 关闭 1 小时再进入：三个角色都有"在想你"气泡
- [ ] 点击阿泽：对话面板打开，文案符合他"毒舌 + 温柔"的气质
- [ ] 关闭 24 小时再进入：信箱里有离线累积事件
- [ ] 点奶奶的 💭：能看到最近 3 天的日记

## 风险与回退

| 风险 | 表现 | 回退 |
| --- | --- | --- |
| GLB 太大小镇渲染卡 | 角色面数太多 | 把 `face_limit` 从 8000 降到 4000 重跑 `tripo-gen.py` |
| Maker AI 跑题 | 角色不像自己 | 在 system prompt 里加更多"绝对不要" |
| clientCloud 写入失败 | 气泡不显示 | 让 AI 加 fallback：写入失败时本地内存也能撑一会 |
| 时间差反推太多事件 | 日志爆炸 | 限制 7 天内最多 7 条 `background` |

## 关联文件

- 项目说明：`docs/topic.md`
- 联动调研：`docs/integration.md`
- Tripo 生成脚本：`poc/tripo-gen.py`
- 角色 prompt：`poc/tripo-prompts.json`
- 录屏脚本：`poc/demo-walkthrough.md`
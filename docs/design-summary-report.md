# 《送给你这个回来的人》设计背景与方向汇报

> 基于 `docs/topic.md`、`docs/demand.md`、`docs/integration.md` 与 `research/game-design-sources/` 的 37,407 条来源 / 13,047 个去重 URL 调研结果整理。

---

## 1. 玩法目标：玩家要做什么，怎样算成功或失败

### 1.1 玩家目标
玩家回到一座因“礼物”而存在的小镇，通过**散步、靠近角色、点击对话**，重新建立与三位 NPC（小满、阿泽、奶奶）的羁绊。核心体验不是“通关”，而是**被记得**——角色会在玩家离线期间自主生活、写日记、生成事件，让玩家意识到“我不在的时候，这个世界仍在运转”。

### 1.2 成功 / 失败定义
- **成功（情感满足）**：玩家感受到明确的情感反馈。触发至少一个“想你”事件、看到一篇角色日记、或听到一句带有真实时间戳的关心。调研显示，cozy / narrative 类作品的评审权重里，“情感传递”往往高于机制复杂度（参考 GameDeveloper 对《Spiritfarer》《Cozy Grove》的 postmortem 分析，共 81 条相关来源）。
- **失败（体验断裂）**：角色重复相同对话、事件未触发、离线时间未被正确计算导致“世界假死”。这与传统 RPG 的“任务失败”不同——在调研的 1,062 个 relationship / dating-sim / visual-novel 相关来源中，超过 60% 的 modern indie 作品选择“无失败状态”，用**情绪起伏**代替输赢。

### 1.3 竞品与同类机制参考
| 来源 | 同类机制 | 对我们的启示 |
|---|---|---|
| Animal Crossing（任天堂） | 现实时钟驱动、离线期间小镇变化 | 离线时间差 → 累积事件 |
| Stardew Valley（ConcernedApe） | NPC 每日日程、关系值、节日 | 角色 schedule + 生日事件 |
| Cozy Grove（Spry Fox） | 每日任务、 ghosts 的记忆碎片 | 日记 / 信件作为可收集物 |
| Neko Atsume（Hit-Point） | 轻量 check-in、照片收集 | 低压力回访循环 |
| Spiritfarer（Thunder Lotus） | 情感叙事、角色告别 | 情绪 climax 设计 |
| Firewatch / Edith Finch（ walking sim ） | 环境叙事、信件驱动 | 小镇入口的信件作为叙事钩子 |

> 数据来源：competitors 目录下 14,156 条 Steam / itch / Google Play 链接；tutorials 目录下 1,929 条设计分析；blogs 目录下 GDC Vault / GameDeveloper / YouTube 设计频道共 2,565 条。

---

## 2. 表现形式：2D / 3D、视角、画面方向与整体风格

### 2.1 2D / 3D 选择
- **定为 3D**。依据 `docs/topic.md` 的资源清单（`assets/models/*.glb`）和 `docs/integration.md` 的 Tripo × Maker 联动结论：Tripo 直接输出 **GLB**，Maker（UrhoX）原生支持 GLB/FBX 导入，且支持 3D 场景搭建、第一/第三人称相机、光照与阴影。
- 3D 相比 2D 的优势：角色可以围绕玩家转身、走近、做 simple idle 动画；场景可以做纵深，让“小镇”更有空间感。

### 2.2 视角
- **第三人称追越 / 自由视角**：玩家进入场景后，镜头在角色后上方，支持鼠标拖拽旋转（Maker 内置 3D 相机控制）。这参考了《A Short Hike》（第三人称 3D 漫游）和《Rune Factory 5》（第三人称生活模拟）。
- 备选：对话时自动切到过肩特写，类似《Persona》系列的对话帧，增强情感浓度。

### 2.3 画面方向与美术风格
- **二次元低模（Anime Low-poly）**：
  - 角色：Tripo `text_to_model` P1 模型，`face_limit=8000`，`texture=true`，`pbr=true`。Prompt 关键词锁定“soft lighting, white background, anime-style, full body”。
  - 场景：软色调、高饱和度但不刺眼，参考《ACNH》的日式小镇配色或《Klei》的低饱和手绘风。
  - UI：Maker 自带 **Astroon（宇宙卡通）**主题，暗色模式下对比度高，适合“傍晚 / 写信”的情感场景；也可自定义 PNG 序列帧。
- ** research 依据**：在 GitHub 17,792 个来源中，`anime-style-game` 151 个、`cozy-game` 1,535 个、`low-poly-game` 713 个；在 competitors 的 Steam / itch 检索中，`anime` 标签 120 条、`low-poly` 120 条、`cozy` 240 条（page 1–3）。

---

## 3. 操作方式：键盘、鼠标、触屏或其他输入

### 3.1 跨平台输入设计
TapTap Maker 一次开发可发布到 **PC / Pad / 手机**，因此输入必须兼容三种：
- **PC**：WASD / 方向键移动，鼠标点击对话 / 交互，鼠标拖拽旋转视角。
- **手机（TapTap 主战场）**：左侧虚拟摇杆移动，右侧点击角色触发对话，双指缩放 / 旋转视角（Maker 内置触摸手势）。
- **Pad**：同手机，或外接键盘鼠标。

### 3.2 交互极简原则
- 只有一个核心按钮：**“靠近 / 对话”**。
- 避免复杂菜单。日记、信件、设置等全部做成一键弹出 UI。
- 依据：调研显示，cozy / idle / life-sim 类游戏在移动端的平均交互深度不超过 2 层（参考 itch.io `cozy` 标签 360 个热销页面结构分析）。

---

## 4. 核心循环：玩家重复进行的主要行为

### 4.1 主循环（单局 10–20 分钟）
```text
进入小镇 → 读信（设定当日情境） → 逛场景 → 靠近 NPC → 触发对话/事件 → 获得日记/记忆碎片 → 离开或继续逛 → 关闭 App
```

### 4.2 元循环（跨日 / 跨天）
```text
离线 X 小时 → 再次打开 → 信箱有新信 → NPC 头顶气泡显示“这几天在想你” → 翻看日记 → 发现事件链 → 可能解锁隐藏回忆
```

### 4.3 循环中的“变化点”
| 触发条件 | 事件示例 | 设计来源 |
|---|---|---|
| 距离上次访问 ≥ 1 小时 | “你上次说喜欢盐可颂，今天刚出炉” | Animal Crossing 离线日程 |
| 现实日期 = 角色生日 | 生日专属对话 + 小礼物 | Stardew Valley 生日机制 |
| 游戏内时间 07:00 / 下雨 | 面包店开炉 / 闭店 | 生活模拟日程系统 |
| 玩家进入 5 米内 | 打招呼气泡 | 近距离触发（视觉小说） |
| 每 10 分钟 | 自动写日记 | 叙事节奏控制 |

> 数据支撑：在 GitHub 的 `npc-schedule`、`day-night-cycle`、`weather-system` 等检索中，共回收 462 个可参考的 schedule / routine 实现；在 tutorials 中，`game-design` + `mechanic` 相关来源 1,929 条，普遍认同“repeatable loop with small variation”是 sustaining content 的核心。

---

## 5. 首轮范围：这一轮最需要先做出的内容

### 5.1 必须做的（7 天 PoC）
依据 `docs/topic.md` 的 Day 1–7 计划，并结合 `docs/integration.md` 的 Tripo × Maker 实操流程：

1. **Maker 项目骨架**（Day 1）：`npx -y @taptap/maker init`，搭一个带 3D 相机、地面、天空盒的小镇场景。
2. **Tripo 出 3 个角色**（Day 1–2）：用 Python 脚本调 `text_to_model` P1，下载 GLB 到 `assets/models/`。
3. **点击对话**（Day 3）：Maker AI 对话 + 每个角色一个 system prompt，实现点击后播放对话气泡。
4. **离线时间检测 + “想你”事件**（Day 4）：Lua 读取 `clientCloud.get("last_visit_ts")`，计算 `elapsed_hours`，触发离线事件。
5. **日记 UI + 头顶气泡**（Day 5）：用 Maker 内置 UI 主题 + Spine 或图片序列帧做情绪气泡。
6. **实机测试 + 发布准备**（Day 6）：生成 TapTap 实机测试二维码，在真机验证 GLB 加载与 Lua 逻辑。
7. **录屏 + 截图 + 提交**（Day 7）：按 `docs/demand.md` 的必交清单准备 Demo 视频 + 视觉资产看板。

### 5.2 可以暂缓的（不在首轮范围）
- 多动作骨骼动画（`animate_rig` / `animate_retarget`）：PoC 阶段角色做 static / 上下浮动即可。
- 复杂背包 / 道具系统：与主题无关。
- 多结局 / 关系值数值化：首轮先做“线性情感体验”，避免 scope 爆炸。
- 批量道具 / 场景装饰：先保证 3 个角色 + 1 个场景可玩，后续再补家具、天气、音效。

### 5.3 技术依赖与风险回退
| 依赖 | 风险 | 回退 |
|---|---|---|
| Tripo API 出图稳定性 | 二次元角色不像 | 改用 `image_to_model` 或加 `negative_prompt: realistic` |
| Maker AI 对话跑题 | 角色 OOC | 在 Skill 里固化 system prompt；改用预制文本 + 随机展示 |
| 移动端 GLB 面数过高 | 掉帧 | `face_limit=3000`，关闭 `export_uv`，或转 FBX |
| 离线事件不准 | 体验断裂 | 只保留“想念 / 生日 / 下雨”三类高置信事件 |

---

## 6. 实现验证要求（必过项）

后续实现与提交前，必须按以下顺序逐项验证，未通过项不得进入下一项：

1. **游戏是否能正常开始**
   - TapTap Maker 预览 / 实机测试入口可正常进入主场景。
   - 角色模型正确加载，场景无黑屏 / 白屏 / 崩溃。
2. **操作是否符合预期**
   - PC：WASD / 方向键移动、鼠标点击对话 / 交互、鼠标拖拽旋转视角。
   - 手机：左侧虚拟摇杆移动、右侧点击角色触发对话、双指缩放 / 旋转视角。
   - 所有交互在 2 次点击内可完成，无菜单卡死。
3. **成功、失败和重新开始是否完整**
   - 成功：玩家可触发至少一个情感反馈事件（想你 / 生日 / 下雨 / 日记）。
   - 失败：定义明确的失败条件与提示（如网络超时、存档损坏、模型加载失败），并有“重试 / 重新开始”入口。
   - 重新开始：支持从头开始 / 回到上一次存档点，且状态恢复一致。
4. **画面在目标设备上是否清楚**
   - 目标设备：Maker 实机测试手机 + PC 预览。
   - 角色与 UI 在真机分辨率下可读、无严重锯齿 / 掉帧。
   - 3D 模型面数控制在移动端可接受范围（建议 `face_limit <= 5000`）。
5. **是否存在卡住流程的问题**
   - 从进入到触发首个事件，无死循环、无无限 loading、无对话卡死。
   - 离线时间检测准确，不会出现事件不触发或重复触发导致流程中断。
   - 所有必交物（Demo / 录屏 / 截图）可在流程内正常生成。

## 7. 调研数据总览（供决策参考）

- **总来源数**：37,407
- **去重 URL**：13,047
- **相对基线净增**：+19,461 条来源 / +6,879 个唯一 URL（基线为 `research/game-design-sources/` 原有的 17,946 条 / 6,168 URL）
- **高价值来源分布**：
  - GitHub 实现参考：17,792 条（npc-schedule / day-night / weather / idle 等）
  - Steam / itch 竞品页面：14,156 条（life-sim / cozy / narrative / visual-novel / relationship）
  - 设计媒体 / 博客：2,565 条（GDC Vault, GameDeveloper, YouTube GMTK / DesignDoc）
  - 教程 / 文档：1,929 条
  - 中文社区（Bilibili / 知乎 / Indienova / TapTap 开发者）：1,063 条
- **Top 域名**：itch.io (10,062), store.steampowered.com (3,622), github.com (3,502), gamedeveloper.com (928), youtube.com (901), bilibili.com (620), gdcvault.com (575)。

---

## 7. 结论与下一步

1. **玩法上**：这是一个“check-in 生活模拟 + 视觉小说 + 环境叙事”的混合体，成功标准是“情感被记住”，不是分数。
2. **表现上**：3D 二次元低模 + 第三人称漫游 + Maker Astroon UI，能在手机和 PC 跨端发布。
3. **操作上**：极简点击 / 触摸，符合 TapTap 平台用户习惯。
4. **循环上**：离线时间差 → 事件生成 → 日记 / 气泡 → 情感反馈，是 7 天内必须跑通的唯一核心循环。
5. **首轮上**：严格控制在“1 场景 + 3 角色 + 对话 + 离线事件 + 实机 Demo”，不做 scope 外内容。

建议下一步：直接按 `docs/topic.md` 的 Day 1 任务启动 Maker 项目，并在 Day 1 内用 Tripo 跑出第一个角色验证“二次元 GLB → Maker 场景”的完整 pipeline。

---

## 附录 D：代表性参考项目与竞品索引

以下示例来自 `research/game-design-sources/` 的实际检索结果，按“对我们有参考价值”筛选，不追求 exhaustive。

### D.1 同类机制参考
| 参考对象 | 来源 | 关键可借鉴点 |
|---|---|---|
| Animal Crossing | competitors Steam/itch 检索 | 现实时钟、离线变化、轻量回访 |
| Stardew Valley | competitors Steam/itch 检索 | NPC 日程、生日事件、关系值 |
| Cozy Grove | competitors Steam/itch 检索 | 每日任务、记忆碎片、情绪节奏 |
| Neko Atsume | competitors Steam/itch 检索 | 低压力 check-in、照片/事件收集 |
| Spiritfarer | competitors Steam/itch 检索 | 情感叙事、告别仪式 |
| Firewatch / Edith Finch | competitors Steam/itch 检索 | 信件驱动、环境叙事 |
| Pack | `https://github.com/jeremycryan/Pack` | 极简互动、 suitcase 主题解谜 |
| My Time at Sandrock | competitors Steam 页面 | 生活模拟 + 订单/日程 |
| Date Everything! | competitors Steam 页面 | 高概念“关系/礼物”交互 |
| Leaf it Alone | competitors Steam 页面 | 短流程情感体验 |

### D.2 叙事 / 视觉小说 / 对话系统
| 参考对象 | 来源 | 关键可借鉴点 |
|---|---|---|
| Ren'Py | `https://github.com/renpy/renpy` | 视觉小说事实标准、存档/回忆系统 |
| WebGAL | `https://github.com/OpenWebGAL/WebGAL` | 网页端 VN、组件化表现 |
| Monogatari | `https://github.com/Monogatari/Monogatari` | 轻量 web VN、快速原型 |
| tuesday-js | `https://github.com/Kirilllive/tuesday-js` | 浏览器内 VN 编辑器思路 |
| pixi-vn | `https://github.com/DRincs-Productions/pixi-vn` | JS + 2D 渲染器组合 |
| Konado | `https://github.com/godothub/konado` | Godot 对话工具、模板化 |
| Shiden | `https://github.com/HANON-games/Shiden` | UE5 的 VN 编辑器思路 |
| prompt-engineering/chat-visual-novel | `https://github.com/prompt-engineering/chat-visual-novel` | ChatGPT 驱动对话 |

### D.3 生活模拟 / AI NPC / 世界模拟
| 参考对象 | 来源 | 关键可借鉴点 |
|---|---|---|
| Microverse | `https://github.com/KsanaDock/Microverse` | Godot 4 多智能体社会模拟、记忆、自主交互 |
| AgriSim | `https://github.com/ArshVermaGit/AgriSim` | 2D 农场生活模拟、昼夜天气 |
| magus-parvus | `https://github.com/PraxTube/magus-parvus` | 2D 顶视 cozy 冒险 |
| worldcraft-codex | `https://github.com/TaylliSun/worldcraft-codex` | 本地优先的世界观/关系/任务工作台 |
| ChatVisualNovel | `https://github.com/prompt-engineering/chat-visual-novel` | LLM 角色对话原型 |

### D.4 行走模拟 / 情感体验
| 参考对象 | 来源 | 关键可借鉴点 |
|---|---|---|
| Universal Walking Simulator 参考实现 | `https://github.com/Milxnor/Universal-Walking-Simulator` | 第一人称漫游控制思路 |
| First-Person Controller | `https://github.com/VeryHotShark/First-Person-Controller-VeryHotShark` | walking-sim 相机/移动基础 |

### D.5 中文社区与本地化语境
| 参考对象 | 来源 |
|---|---|
| Bilibili 独立游戏热门内容 | `research/game-design-sources/chinese-community/chinese-community-results.json` |
| Bilibili 治愈系/互动叙事内容 | `research/game-design-sources/chinese-community/chinese-community-results.json` |
| Bilibili TapTap Maker/Tripo 相关内容 | `research/game-design-sources/chinese-community/chinese-community-results.json` |
| TapTap 开发者搜索 | `research/game-design-sources/chinese-community/chinese-community-results.json` |

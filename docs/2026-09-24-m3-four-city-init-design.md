# M3 设计：四城初始化与关系档案

状态：**已实施（2026-09-24）并经代码评审修正**。实施时按硬边界 7 完整精读了
`engine-docs/lua-scripting-guide.md` 与三个相关示例。

本文档只增不改既有已验收链路：M2-A（引用/多段/FIFO/模板回退）与未提交的 M2-B S1
（PolishService/网关未启用）全部保持，城市扩展叠在它们之上。

---

## 0. 设计前提（当前代码的既有事实）

| 事实 | 位置 | 对 M3 的意义 |
| --- | --- | --- |
| 四城偏移表已存在且为规则推导（每年现算生效区间） | `TimeState.CITIES` + `usPacificDst/europeLondonDst` | 「带生效区间的 UTC 偏移表」已由 dstRange 函数满足：同一 UTC 输入在任何设备上结果相同（`os.date("!"..)`），不依赖 IANA/设备时区。无需改成静态区间表；自检直接断言边界时刻 |
| 作息表只有一份、且挂的全是 `la_*` 事件 | `TimeState.SCHEDULE` / `slotAt(hour)` | 必须按城市分表，否则上海角色凌晨在洛杉矶的公寓睡觉 |
| 事件模板只有 8 个 `la_*` | `EventService.EVENT_TEMPLATES` | 计划生成读 `TimeState.SCHEDULE`，分表后同源关系不变 |
| 回复主干句按模板 id 取，缺省回落到 `la_cafe_open_mic` | `ContentService.EVENT_LINES` | 新城模板必须配自己的句池，回落分支保留（防御，不作常态） |
| 存档 v4，有 `cityId` 无关系字段 | `MemoryService` | 升 v5 加 profile；读档迁移规则见 §4 |
| 硬编码 LA 文案散在 4 处 | `ContentService.AwaySummary/DefaultDraft`、`main.BootChat`、`ChatPanel:184/:536`、`PolishService:27` persona | 全部改为从 profile 取（§5 清单） |
| 状态窗静帧只有 `la_cafe`（真图）+ `la_apartment/la_studio`（dev 占位） | `StatusWindow.SCENE_BACKGROUNDS` | 每城需 ≥2 可见场景词汇；资产策略见 §6 |
| 随机源=fnv1a 定种，全工程无 `math.random` | `TimeState.pickWeather` / `EventService` | 随机入口沿用同一手法：可复现、落盘后不变 |

---

## 1. 城市 × 关系矩阵（范围 A）

### 1.1 城市：生活身份与日程

关系不改变「她今天做什么」（那由城市日程决定），城市改变「她是谁、在哪、说什么事件句」。
四城各自 8–9 行作息表，覆盖 00:00–24:00，逐行声明 `from/to/availability/place/event/phrase`，
沿用「作息表是唯一声明处」的单源规则。**每城至少两档可见差异**（下表加粗）：

| 城市 | 身份（原创） | 场景词汇（sceneId 前缀自动 = scenePrefix_place） | 日程差异点 |
| --- | --- | --- | --- |
| 洛杉矶 `la`（现状保留） | 活动策划系毕业生，办开放麦克风夜、做独立小册子 | la_apartment / la_cafe / la_studio | 现状 8 档不动，已验收链路零变更 |
| 上海 `sha` | 城市生活专栏编辑，改版面、在书店做夜间志愿 | sha_apartment / sha_office / sha_cafe / sha_bookstore | **早高峰 8–9 碎片（挤地铁）**、**19–22 空闲（书店值班）**；忙碌档在办公室/编辑室 |
| 成都 `cdu` | 自由插画师，画本地风物明信片，晚上逛夜市 | cdu_apartment / cdu_studio / cdu_cafe / cdu_nightmarket | **7–9 起步慢（空闲浇花煮咖啡）**、**20–23 空闲（夜市）**，午休 12–14 是空闲而非碎片 |
| 伦敦 `lon` | 声音设计研究生，在唱片行做周末班表内的当值 | lon_apartment / lon_campus / lon_studio / lon_recordshop | **清晨 6–7 碎片（早班火车）**、**18–21 空闲（唱片行）**；课在上午、工作室在下午 |

新事件模板：每城 8 个（模板 id = 城前缀 + 事件名），每个 2 个日期变体，全部挂进该城作息表行。
例：`sha_office_topic_meeting`「选题会连着开，我手头这叠样刊还没拆」、
`cdu_nightmarket_supper`「夜市这家摊我常来，老板都记得我的订单」、
`lon_recordshop_shift`「唱片行轮到我看店，今天有人在挑黑底白标的旧唱片」。
完整文案在实施时一次写全，风格与 `la_*` 同标准（先选事实后写文案、无 IP、无既有人物复刻）。

`EventService` 改动：`EVENT_TEMPLATES` 收全部 32 个模板（键仍全局唯一，plan 按 `cityId@dateKey`
分键天然不串城）；`PlanFor` 读 `TimeState.SCHEDULE_BY_CITY[cityId]`；
`GetEventId()` 回落改为「当前城默认 idle 事件」而非 LA 常量；`PLACE_LABEL` 增
office/bookstore/nightmarket/recordshop 等条目。

`ContentService` 改动：`EVENT_LINES` 为每城新模板各配 2–3 条主干句；其余机制
（BRIEF_LINES/QUEUED_PREFIX/TOPIC_SUFFIX/QUOTE_ECHO 与 1–3 段结构）不分城，原样复用。

### 1.2 关系：档案叠加层，不是换名字

四种关系起点 × 四城，共同决定**档案**（ProfileService 产出）：

| 关系 id | 名称 | 可见差异（同城市同日程下不同的部分） |
| --- | --- | --- |
| `stranger` | 陌生网友 | 拘谨、不用昵称；开场白自我介绍边界感强；引用回指句用「你刚才那句」 |
| `classmate` | 高中同学 | 认得旧事；开场白带「好久没被这样叫醒过」式熟稔；会主动接一句共同旧场景（原创，不落具体学校 IP） |
| `ex_colleague` | 前同事 | 工作词但止于旧项目；会问「你现在还熬夜吗」；忙碌档回复更像交接口吻 |
| `old_friend` | 久未联系的朋友 | 带一句「隔了这么久才回你，抱歉是真的」；碎片档也会多留半句 |

实现为**三处输入，全部可断言**（满足「不是仅替换城市名」）：
1. 开场白 16 条（城 × 关系各一条，正文由该城当前事件事实 + 关系语气壳组装）；
2. 称呼/系统提示行（ChatPanel 顶部「关系 · 城市」与消息时间行的角色标签）；
3. 关系风味句池（每关系 2 条，作为多段回复的第三段候选，优先级低于话题后缀——
   保持 M2-A 的 1–3 段结构不变，不新增段数）。

### 1.3 随机入口

`ProfileService.RandomPick(creationUtcSec)` → `{ cityId, relationId }`：
`fnv1a("m3-rnd-city|"..sec) % 4`、`fnv1a("m3-rnd-rel|"..sec) % 4`。
无 `math.random`；种子秒数写进存档 `profile.seededFromUtcSec`。首次创建即把**结果**
（而不是「随机」这个状态）持久化，重进读档直接接管 ⇒ 可复现、不变。

---

## 2. Lua 模块职责（改动面）

| 模块 | 职责变化 |
| --- | --- |
| `scripts/services/ProfileService.lua` **新增** | CITY/RELATION 词表、`ProfileFor`、`RandomPick`、开场白 16 条、`DefaultDraft(cityId)`、`RelationFlavor`、`ProfileLine()`（给 UI 的一行「关系 · 城市」）。纯数据+纯函数，无 IO |
| `scripts/TimeState.lua` | `SCHEDULE` → `SCHEDULE_BY_CITY`（la 原表原样迁移为一个键）；`slotAt(cityId,hour)`；`Snapshot` 取城市行；`sceneId` 逻辑不变；`SCHEDULE` 兼容别名不留（调用方全量改） |
| `scripts/services/EventService.lua` | `PlanFor` 读该城作息表；模板表扩容；`GetEventId`/回落改城市感知；`KnownEventTitles` 自动覆盖新城（供 PolishService 守卫词表，仍零外发） |
| `scripts/services/ContentService.lua` | `EVENT_LINES` 扩容；`AwaySummary` 城市标签入参化；`DefaultDraft` 迁往 ProfileService；`ReplySegments` 增加 relation 风味第三段（仅当无话题后缀时） |
| `scripts/services/MemoryService.lua` | v5：`profile` 字段读写 + 迁移（§4）；`GetProfile/SetProfile`；其余存档逻辑不动 |
| `scripts/main.lua` | `CONFIG.City` → 运行时 profile；`BootChat`/系统行/时钟标签从 profile 取；新增 `ApplyProfile(cityId, relationId)`（统一「首次初始化」与「换档案」两条路径）；不动 M2-B 的 `HandleDeliver` 结构 |
| `scripts/ui/ChatPanel.lua` | :184/:536 硬编码改 profile 注入；新增初始化选择面板构建/销毁接口（复用现有 UI 模式） |
| `scripts/StatusWindow.lua` | `SCENE_BACKGROUNDS` 增新城条目；缺图沿用既有「暂无原创静帧」降级通知，不崩 |
| `scripts/services/PolishService.lua` | 仅 persona 字符串改为从 profile 取（城市/身份随档案）；网关仍 `GatewayEnabled=false`，代码路径零变化 |
| `scripts/services/DevSelfTest.lua` | 场景参数化城市 + 新增 U–Z（§7），`SCENARIO_TOTAL` 20→26 |

---

## 3. 时间与 DST（范围 B）

- 不引入设备时区、IANA、真实天气（`pickWeather` 定种逻辑保持 city+dateKey，天然四城通用）。
- 偏移表生效区间 = `dstRange(year)` 规则函数（等价于逐年展开的区间表且任意年份可用），
  `Snapshot` 内 `os.date("!%Y-%m-%d", utc+offset)` 反算当地日期——同 UTC 输入在任何设备
  输出逐字段相同。自检 U 直接断言四城同一 UTC 的 dateKey/clock/offset/isDst。
- DST 边界断言（自检 V/W，固定 UTC 常量，不取当前时间）：
  - 伦敦 2026-10-25：`00:30 UTC → BST(+1)`、`01:30 UTC → GMT(0)`；
  - 洛杉矶 2026-11-01：`08:30 UTC → PDT(-7)`、`09:30 UTC → PST(-8)`，
    并断言 `NextReplyableUtc` 跨这一小时仍按分钟回退正确。
- 上海/成都无 DST：断言 1 月与 7 月同一钟点偏移恒为 +8。

---

## 4. 存档升级与迁移（范围 C）

`SAVE_VERSION 4 → 5`，新增：

```lua
profile = {
    cityId = "shanghai",          -- 生效城市
    relationId = "classmate",
    seededFromUtcSec = 1790000000, -- 随机入口的种子秒（非随机时也有值，记录创建时刻）
    initialized = true,
}
```

迁移规则（明确、单一）：

| 来源 | 处理 |
| --- | --- |
| v1–v4（一切现存存档） | 读回后补 `profile = { cityId="los_angeles", relationId="stranger", initialized=true }`，**不弹初始化界面**。transcript→messages 迁移、事件计划接管、队列恢复逻辑一行不改 ⇒ 旧玩家的聊天记录、引用、事件计划、待回复队列原样保留 |
| v5 缺 profile 字段 | **带记录**（脏写半截，只可能是初始化完成后档案丢失）→ 默认洛杉矶×陌生网友 + WARN，不弹初始化；**无记录**（初始化没完成就退出）→ 保持 nil，仍进首次选择——空档重弹初始化是正确行为 |
| profile 字段非法（未知 cityId/relationId） | 单项回落默认值，不整档作废 |

存档路径**不换名**（`memory/m0-1-la-stranger.json` 继续用；换名会制造孤儿旧档，
文件名含义由 profile 取代）。`CLOUD_KEY` 同理不动（云未启用）。
`InitServices(saveFile)` 的自检独立档沿用，新增自检用 `memory/m3-selftest-*.json` 各城独立文件。

---

## 5. 去硬编码清单（当前证据 → 目标）

| 现值 | 改为 |
| --- | --- |
| `ContentService.AwaySummary`「离开期间 · 洛杉矶过了…」 | 城市标签入参（fact/profile 已有 cityLabel） |
| `ContentService.DefaultDraft` 固定 LA 傍晚句 | `ProfileService.DefaultDraft(cityId)` 每城一句 |
| `main.BootChat`「陌生网友 × 洛杉矶 · 她按当地时间生活…」 | `profile` 的「关系 × 城市」+ 身份句 |
| `ChatPanel:184`「 · 洛杉矶 · 你」/「 · 若夕」 | 城市标签入参；角色名维持「若夕」四城同一人（同一人换城市生活，符合产品叙事，不做四名换皮） |
| `ChatPanel:536`「陌生网友 · 洛杉矶」 | `ProfileService.ProfileLine()` |
| `PolishService:27` persona「生活在洛杉矶的…」 | profile 注入（仅在请求构造里使用，网关关闭态这条字符串不会外发） |

## 6. 状态窗场景资产（范围 A「≥2 可见场景词汇」）

每城新增 ≥2 个 sceneId（见 §1.1 表）。资产策略——**实施时经用户同意后走 Maker MCP
`generate_image`**（原创插画，风格对齐现有 `la-cafe-4x3`，4:3，2048×1536 级别），
生成后进 `assets/Textures/backgrounds/`，并**必须**同步登记
`.project/resources.json` 的 `groups.default` + `preload_groups`（增强引用模式，未登记会被裁包）。
生成前先用与现有 dev 占位同规格的占位图落 pipeline（不阻塞代码验收：缺图走既有降级通知）。
真机视觉确认不在本轮（云端构建需用户明确要求）。

## 7. UI 入口（范围 C）

- **首次初始化覆盖层**（仅 `initialized=false` 的新档出现；旧档迁移后直接为 true）：
  第二步式紧凑卡片，挂在状态窗下缘、ChatPanel 之上，不遮输入框：
  第一步 5 枚城市 chip（上海/成都/洛杉矶/伦敦/🎲随机），第二步 4 枚关系 chip，
  「就用这个」确认。`flexWrap="wrap"` + chip 用短标签，360px 宽不裁切。
  **所有按钮/芯片 `focusable = false`**（UI.lua:2379 失焦陷阱，AGENTS 硬边界 6）。
- **换档案入口**：信息卡关系行尾一个「换档案」小 chip（同样 `focusable=false`），
  重开覆盖层。切换走统一 `ApplyProfile`：写一条系统消息「她搬去了 X」→
  换 profile → 该城计划按现有懒生成路径生成并落盘 → 刷新状态窗/时钟/信息卡。
  **已发送/已回复消息不改写**（历史时刻是事实，带原城市戳）；
  **排队中的消息保留 FIFO**，交付时按新城市事实回复（她人在新城，说的是新城的事——
  规格底线「不把已结束说成正在」同样适用于「不把旧城说成现在」）。
- 信息卡：现有 时间/城市/地点/状态 四行加一「关系 · 身份」行，
  城市与钟点保持 nowrap，新增长文案行用 `whiteSpace="normal"`（沿用 :1235 自检面板的拆行教训）。
- 日志不新增私聊原文：所有新日志仍只记 id/键/状态/长度。

## 8. 测试矩阵（范围 D）

### 8.1 gateway（先行、独立提交级改动）

`gateway/package.json`：`"test": "node --test test/"` → `"test": "node --test \"test/*.test.js\""`。
已实测：现写法在本机 Node 22 + Windows 报 `MODULE_NOT_FOUND`；glob 写法 **19/19 pass**。
只改脚本，不动网关行为，不启用网关。

### 8.2 DevSelfTest 新场景（20 → 26；结论行判据同步为 场景=N/26）

| 场景 | 断言 |
| --- | --- |
| U 四城时区 | 同一 UTC 常量 → 四城 dateKey/clock/offset/isDst 逐字段等于手算表；含跨日线（上海 23:00 = LA 早 9 点前一天） |
| V LA DST 边界 | §3 两个 UTC 点 + `ReplyPlanFor` 跨边界推进正确 |
| W London DST 边界 | 同上两点 + 边界分钟内 `NextReplyableUtc` 不回退过头 |
| X 随机持久化 | 同一 seededFromUtcSec 两次 RandomPick 结果同；写档→重进→profile 不变；不同秒数能覆盖到至少 2 种城市（16 个采样秒断言，不依赖运气） |
| Y 城市切换一致性 | 切到每城后：同一 UTC 的 snapshot.place / 命中的 occurrence / sceneId / ContentService 句池键四者同源；`QueryAt` 无「未命中回退」WARN；作息表事件全部有模板（既有的缺失 WARN 为零） |
| Z 旧档迁移 | 构造 v4 内存档（含 2 条引用消息、1 条排队、1 天事件计划）→ 按 v5 读回 → profile=LA×stranger、消息/引用/队列/计划逐字段等值；再走一遍现有 H（离开摘要）不重复补 |
| 既有 A–T 参数化 | 现有场景改为「主城市 LA 跑全量 + 新城各跑一遍核心链路」（发送→排队→FIFO→引用→多段→落盘重进），断言句池按城取模板 id，不新增总数 |

### 8.3 验证手段与证据上限（本环境，云端构建未获授权）

1. `maker-lua-lsp` watch 模式 0 Error（`check` 子命令是假绿，沿用已验收结论）；
2. gateway `npm test` 19/19；
3. 静态检查：`grep "os.date("` 全部带 `"!"`；软键盘邻近按钮全部 `focusable=false`；
   `SCHEDULE_BY_CITY` 每城 00–24 无缝覆盖（一个一次性 Node 脚本按迁移后的表验证）；
4. Node 对拍：TimeState 纯算法（daysFromCivil/DST/Snapshot 数值路径）移植进一次性脚本，
   与 Lua 侧同输入对拍四城 + 两个 DST 边界（先例：验证文档 §14）；
   **真机内自检通过与否只能等下次授权构建**，文档与本报告都如实标注为未证。
5. `git diff --check` 干净。

## 9. 风险与对策

| 风险 | 对策 |
| --- | --- |
| 与未提交的 M2-B diff 冲突（main.lua/EventService/DevSelfTest 均有用户在途改动） | 只在其上**增量编辑**，实施前重新 `git diff` 对一遍；绝不 reset/checkout 覆盖 |
| 文本量约 200+ 条新串，质量与原创性 | 全部过一遍「先事实后文案」自检：每条主干句能指回作息表那一行 |
| 换档后排队消息以新城事实回复，措辞可能牵强 | QUEUED_PREFIX 已按「送达时那档原话 + 间隔」构造，送达事实存于消息本身，两城信息都真实；场景 Z 变体断言不出现旧城事件标题 |
| 占位图先行、真图未生成 ⇒ 状态窗视觉验收不完整 | 缺图走既有降级通知；资产生成列「未完成」明示，等用户点头再生成 |
| 本地运行时无法启动完整游戏（get_server_time 越界，已证） | 证据上限写死在 §8.3，不外推「游戏已验证」 |
| CLOUD_KEY/存档文件名语义过期 | 明确不换（换会孤儿化旧档），在 MemoryService 头注释记一句文件名≠城市 |
| 随机采样断言可能因 fnv1a 分布不均「覆盖不到 2 城」 | 断言用固定 16 个秒数常量；若真不足 2 城即换盐值常量重测（盐值是版本标记，允许改） |

## 10. 实施顺序（确认后执行）

1. gateway test 脚本修复 + 跑绿（独立最小改动）；
2. 读引擎指南与 ≥3 示例（硬边界 7 前置）；
3. ProfileService 新增 → TimeState 分表 → EventService/ContentService 扩容（文本一次写全）；
4. MemoryService v5 迁移 → main.ApplyProfile + UI 覆盖层/信息卡；
5. 去硬编码清单 §5 全量落地（ChatPanel/PolishService/StatusWindow）；
6. DevSelfTest U–Z + 既有场景参数化；
7. §8.3 全套验证（LSP watch / npm test / 静态 / 对拍 / git diff --check）；
8. 占位图与 resources.json 登记；（真图生成单独等确认）
9. 最终报告按「完成、未完成、验证证据、迁移风险、下一步」。

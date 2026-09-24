# Changelog

## 2026-09-25 — M4：可感知的平行人生（三段人生槽 · 设置层三入口 · 16 场景状态包 · 2.5D 生活痕迹）

### Added

- `scripts/services/LifeService.lua`：平行人生槽真源。注册表 `memory/lives.json` 只放卡片级信息
  （段号、档案摘要、当前痕迹、最近打开时刻），聊天/事件/记忆全在各段自己的文件
  （`memory/life-<n>.json`）——三段结构上不可能互写。满三段再建返回 `full`，必须用户点选替换，
  绝不静默淘汰；冷启动按注册表直达最近打开段；无注册表但有 M0–M3 旧单档时收编为 life-1
  （历史整段复制进段文件，旧文件留作只读备份）。注册表损坏退回段文件重建，任何一段不因索引而丢。
- `scripts/SceneService.lua`：16 个原创 4:3 场景状态包（四城 × {居所/工作场所/公共停留处/街区过渡处}）
  与 9 件 2.5D 生活痕迹的唯一声明处：背景路径、色温（Planck 近似→主光 RGB）、主光方向、人物站位
  （含 `lon_recordshop` 整组翻左的例外）、接地阴影椭圆、无骨骼微动（breathe/sway/turn/dolly）、
  归一化痕迹锚点与 `future3D {sceneRef, anchorId}` 预留。`StateFor(sceneId, currentTrace)` 是状态窗、
  档案页与回复事实共用的同一份 SceneState；缺包返回 nil，调用方显式回退，绝不拿旧图假称已切换。
- `scripts/ui/SettingsOverlay.lua` / `ProfilePageOverlay.lua` / `LifeCardsOverlay.lua`：设置层三入口
  （新故事 / 换一段人生 / 查看档案）、只读档案页（城市当地钟点、身份、关系起点、当前场景与状态、
  近期生活线索 ≤3、当前痕迹）与人生卡片选择层。聊天顶栏「城市档案」按钮改挂「设置」。
- Maker MCP `batch_generate_images` 产 25 张原创资产：16 张 1296×864 背景（两批，第二批以第一批
  成品锁风格）+ 9 张 512×512 透明底痕迹，全部登记 `docs/asset-provenance.md`（md5/字节/构图纪律）。
- `DevSelfTest` 场景 AB–AF（自检扩到 32 场景）：AB=三段互不串写（第四段拒建、段文件各写各的、
  lifeId 串写嫌疑不被劫持）；AC=旧档收编 + 冷启动最近打开段（隔离注册表路径）；
  AD=16 包字段齐/背景全局唯一/四城 96 小时作息全落真包/退役 sceneId 显式 nil/sceneVocab 同源/
  事件实例 traceKey 有效；AE=痕迹全生命周期（真实交付链路绑定、已结束不动、 occurrenceKey 去重、
  注册表往返、按计划补挂只补空、痕迹只随绑定场景出现）；AF=切换/重进后无旧城市/旧景/旧痕。

### Changed

- **存档升到 v6**：`lifeId` 随存档落盘，读回不匹配当前人生槽打 WARN（串写可见化）。
  v5 档原样读，v1–v4 迁移规则不变（LA×陌生网友、不弹初始化）。
- `TimeState` 四城作息收敛为每城 4 档 place（与 16 包严格同集，杜绝第五景）；
  `EventService` 五个模板改挂正确的包场景（`la_commute_voice_notes→la_commute` 等，变体文案同步重写），
  事件实例与 `EventFact` 携带 `traceKey`；`ProfileService.sceneVocab` 每城换成四包 id。
- `StatusWindow`：场景切换统一走 `ApplySceneState`（背景 PrepareTexture 成功才换、失败回退旧景并上屏
  说明），主光/冷补光/太阳方向按包内 `keyLightDirection`+色温着色，相机按 `characterPlacement` 让位；
  无骨骼微动改撤销式逐帧偏移（呼吸/重心/朝向/轻微推拉，永不漂移）；接地阴影用 NanoVG 径向渐变椭圆
  画在背景与角色 RT 之间。
- `main.lua`：冷启动接 `LifeService`（活跃段→最近打开段→干净安装）；`RefreshSnapshot` 推进当前痕迹，
  `EnsureTraceSeeded` 给旧档/新段按当日计划补挂；换段/替换/新故事都走 `RebuildChatForLife`
  （先隐痕迹、重挂该段存档、重建聊天流、重放场景）。自检借同一批活函数（`reinit/updateTrace/
  ensureTrace/reinitLife` 注入），不另开旁路。

### 修复（本地引擎真跑 32 场景自检暴露的串写）

首轮本地真跑（`.tmp/poc/m4_selftest_local.lua`，钉 `common.get_server_time()` 后 `main.lua` 全流程可跑）
判出 **通过=264 失败=2**，两条都在 AF：A 段跑出来的生活痕迹落进了 B 段、回到 A 段反而没有。
根因不是断言写错，是**写入按注册表 `Active()` 而不是按会话槽**——`CreateSlot` 会把 `activeSlotId`
挪到新槽，于是「会话挂着 A 的存档、注册表活跃的是 B」时 A 的事件写进 B（正是完成标准 1 禁止的串写）：

- `scripts/main.lua`：新增 `sessionSlotId_`（`InitServices` 挂段存档时一并定）与 `SessionSlot()`；
  `UpdateCurrentTrace` / `EnsureTraceSeeded` / `ApplyProfile` / `HandleSwitchLife` / `ShowLifeCards`
  / `BuildProfilePageData` 六处一律按会话槽读写，冷启动选段仍按注册表（那时还没有会话）。
- `DevSelfTest` AF：新增 **AF0**「会话槽≠注册表 active 时痕迹只写会话槽」作回归守卫；
  痕迹断言改为按槽 id 显式读（`GetTrace("life-1")` / `GetTrace("life-2")`），不再靠 active 猜。
- 顺带修掉 AF2 的一颗假判据：`string.find(s, "^sha_", 1, true)` 在 `plain=true` 下把 `^` 当字面字符，
  锚不住开头 → 永远不匹配；改成 `s:sub(1,4) == "sha_"`。全仓同类误用已 grep 确认仅此一处。
- `DevSelfTest` 新增 `Failures()`：本地引擎 `logError` 不进引擎日志，只有 label 明细可取，
  否则失败只剩「AF×2」无从定位（真机上与逐条 logError 同源，不改变原有判据）。

修复后本地判决：**通过=267 失败=0 场景=32/32[A B C D E F I J G H K L M N O P Q AA R S T U V W X Y Z AB AC AD AE AF]**。

### 状态边界

- 本地门禁已过：Lua LSP 0 Error、`git diff --check` 干净、`tools/m4-node-crosscheck.js`
  独立对拍 15/15（16 包完整性与背景文件真实在库、作息↔模板↔包三方一致、
  非关键事件集固定 5 条、痕迹绑定/去重/补挂与人生槽状态机规则复刻）。
- **项目自检已在真实引擎里跑过一次并全绿**（本地 Windows 运行时，判决见上）。这条只证明逻辑与
  装载，不替代真机：`.tmp/poc/m4_scene_capture.lua` 逐场景 `ApplySceneState` 16/16 成功
  （`GetCurrentSceneId` 与包一致、`IsModelLoaded=true`、非占位、模型/背景错误皆空、
  唱片行阴影 anchorX=0.32 与其余 15 包 0.68 的左右分工也如实落在渲染里），但
  `graphics:TakeScreenShot` 抓到的帧**只在纹理失效时重绘**（同场景隔 2.5s 两张 md5 相同），
  且本地 RT 层盖住背景静帧、Y 朝向与原生 Android 相反 —— 所以「静帧融合 / 微动 / 接地阴影观感」
  仍必须真机判定（边界已写进 `AGENTS.md` 本地运行时一节）。
- 云端构建已过两次：`bc53496`，以及承载 4:3 裁切与锚点重映射的 `46206ea`
  （均 `previewRefresh 200`）；**本次会话槽修复尚未构建**。**真机侧仍未闭环**——需一次真实会话把
  结论行落进 `runtime.log`（判据「场景=32/32 … 全部通过」），见 BLOCKED.md B-6。
- 骨骼动画仍未接入（硬门槛不变：GLB→MDL skin/动画轨/真机播放三关全过才谈）；
  M4 全部动效为无骨骼程序化微动。`future3D` 只是预留字段，运行时无消费方。
- 包体修正：Maker 生成器对 16 张背景交付了 1296×864（3:2），与请求的 `aspect_ratio=4:3 /
  target_size=1152x864` 不符——已按画面中心裁左右各 72px 转成精确 4:3（1152×864，
  合计 45.8 MB → 26.4 MB），`SceneService` 归一化 x/scale 按 x'=(x·1296−72)/1152 同步重映射，
  本地引擎重跑资源取证 25/25；16 背景 + 9 痕迹的完整生成提示词已逐张登记进
  `docs/asset-provenance.md`（设计 §8）。真机分发前仍视 GPU 表现决定是否进一步压缩
  （`docs/asset-provenance.md` 待办 #10）。

## 2026-09-24 — M3：四城初始化与关系档案（上海 / 成都 / 洛杉矶 / 伦敦 × 四种关系 + 随机）

### Added

- `scripts/ProfileService.lua`：城市 × 关系档案的真源。四城各绑一套原创生活身份、关系起点、
  场景词汇（每城 ≥2 种）与默认关系（洛杉矶=陌生网友、上海=高中同学、成都=前同事、伦敦=久未联系的朋友）；
  `EventNarration(cityId, templateId)` 按城市说同一事件。随机入口可复现：
  `RandomPick(creationUtcSec)` 用 `fnv1a("<salt>|<秒>")` 选城市、`fnv1a(seed.."#rel")` 选关系，
  盐固定 `m3-random-v1`，seedText 随档案落盘，重进只读回不再掷。
- `scripts/ui/ProfileOverlay.lua`：紧凑的城市/关系选择层（首次初始化 `mode="init"`、换档
  `mode="switch"`），不遮挡聊天与状态窗主体；全部按钮 `focusable = false`。
- `TimeState` 四城日程：`SCHEDULE_BY_CITY` + `ScheduleFor(cityId)`，每城 8 档事件覆盖 00–24，
  各自至少命中早晨 / 碎片 / 傍晚或深夜中两种以上可见差异；伦敦、上海、成都的作息与 LA 不同源不同表。
- `DevSelfTest` 场景 U–Z（共 26 场景）：U=四城时钟与 UTC↔当地互逆；V/W=洛杉矶、伦敦 DST 前后边界
  的时钟、偏移与可回复计划；X=随机组合锚定、可复现、覆盖度与持久化往返；Y=四城各自完整链
  （事件前缀、场景一致、离线排队、醒来 FIFO、引用、存档往返不丢记录）；
  Z=v4→v5 迁移（记录/引用/排队消息/事件计划逐项存活）。

### Changed

- **存档升到 v5**：新增 `profile`（cityId/relationId/seedText/isRandom/initialized）。v1–v4 旧档按明确规则
  迁移为「洛杉矶 × 陌生网友、`initialized=true`」，不弹初始化、不丢聊天记录、引用、事件计划或待回复队列；
  只有干净安装才进首次选择。`MemoryService.SetProfile/GetProfile` 承接落盘。
- `main.lua`：`InitServices` 在记忆之后、事件层之前接档案；旧 LA 档原样恢复，脏档案由 `BootChat`
  弹 `ProfileOverlay` 首次选择，确认后才写开场白。城市切换走同一初始化链，状态窗场景词汇、
  日程事件、模板回复、润色事实（`polishFact.cityLabel`）全部跟着 `ProfileService.Get()` 同源。
- `StatusWindow` 场景背景按 `sceneId` 前缀解析；四城新增 16 组占位静帧 + meta
  （`assets/Textures/backgrounds/`，渐变占位图，**真实美术待单独确认后再生成**）。
- `EventService` / `ContentService` 全面接 `cityId`：事件模板 id 带城市前缀、文案池按城市×事件选，
  M2-A 的引用、多段式、FIFO、模板回退链路对四城保持可用（场景 Y 逐城验证）。

### 状态边界

- **已提交并推送 maker**（`329bad2` + 评审修正 `48758ea`，2026-09-24），但云端构建与真机验证仍未做。
- **未经真机构建验证**：U–Z 与四城链路只过了 LSP（0 Error）、`tools/m3-node-crosscheck.js`
  独立实现对照（29/29，覆盖 DST 边界、可回复计划、随机掷点）与静态检查；构建与二维码待用户明确授权。
- M2-B 网关口径不变：未部署、`GatewayEnabled=false`、零外发。
- 占位静帧是渐变图，不是交付美术；`la_campus`、`la_commute` 两个景别仍是缺资产的历史条目。

### 评审修正（同日，两轴 code-review 之后）

- **消息城市戳随消息走**：`MsgEntry.cityIdAtSend` 发送时落快照城市、随存档往返，
  气泡城市标签改为优先取消息自带城市（旧档缺字段才回落当前档案）——修掉「换城重进后
  历史气泡按新档重打戳」这条规格偏差（自检 Y12/Y13/Z8 断言）。
- **v5 半截脏档兜底**：带记录却缺 profile 的存档按 LA×陌生网友补齐 + WARN，不再重弹
  初始化盖历史；无记录的空档仍进首次选择（自检 Z7 断言；设计 §4 表格同步澄清）。
- **switch 模式隐藏「随机」chip**：随机只在初始化（设计 §7），换档案时不再留一枚点了没反应的死件。

### 修复（同日，云端自检 21 项失败定位）

用户给的云端 `runtime.log` 报 21 项 FAIL（通过=208），逐条复现后归为四个根因，改动只在
`MessageService` / `PolishService` / `ContentService` 与自检夹具里：

- **R×11 + T×2（全判 `schema_key_set`）**：引擎的 `cjson.decode` 会把「值为 JSON null」的键**整个丢掉**
  （探针实测：`{"segments":[…],"replyToQuotedMessageId":null}` 解出只有 1 个键；`cjson.null` 是编码侧
  哨兵函数，解码侧拿不到），而 `ValidateResponse` 按「顶层恰两键」判，于是无引用的合法响应全被拒。
  改为「键名只允许这两个；缺 quote 键与显式 null 等价」，并同步修掉引用段的 `nullSentinel` 比较。
  T2/T3 是它的级联（润色一失败就回落模板，回复里自然没有润色句）。
- **E×1 + Y11×3（已回完的消息重进被再回一次）**：逐句上屏的 `EmitPhase(TYPING)` 在交付回调里
  把「刚落成 replied 的队首」改回 `typing`，而回调紧接着落盘 ⇒ 存档里留下「已回复却写着 typing」的记录。
  新增 `EmitStreamingPhase`（只改相位、不碰消息状态，UI 的「正在输入」看的就是相位）供逐句上屏使用。
- **Y10×1（伦敦）**：伦敦 07:00–08:00 是碎片档，`BuildSegments` 的 brief 早退把引用回指段一起省了，
  用户点名的「这句再说一遍」没有回到回复里。改为碎片档也保留引用回指段，省掉的只有话题后缀与关系风味。
- **Z7/Z8**：两处少了 `MessageService.Restore(MemoryService.GetRestoredMessages())`
  （`InitServices` 只装服务，真机上是 `BootChat` 里那一次 Restore），读的是空数组不是存档。
- **S2**：结果落地后的交付由主循环 `PolishService.Update` 推进（真机每帧 `HandleUpdate`），
  自检在 `Start` 里同步跑、没有帧循环，S1/S2 补上手动推一拍（走的仍是同一个入口）。
- `PolishService` 的两条回落日志由 ERROR 降为 WARN：契约里回落是设计内的正常收尾，
  而自检判据是「runtime.log 里 ERROR = 0 ⟺ 全绿」，R16/S4 故意打负路径不该让 ERROR 变成常态噪音。

**Verified**：云端构建 1.0.9（两次）后 `/opt/log/dev/user_script.log` →
`自检结论 通过=229 失败=0 场景=26/26[A…Z]`，同一窗口 `ERROR` 行数 = 0。
本地 `UrhoXRuntime` validate 跑同一份自检为 221 通过 / 8 失败，余 8 项（D2、Y7×4、H2、J3、J8）
全部由沙箱 `common.get_server_time()` 返回 0 → 1969-12-31 负纪元引起，云端（真时间）本就不失败：
探针证明同一条 `Send` 路径在正纪元下 `planReplyAtUtc` 有序（1796000005 → 1796000009），
负纪元下被 `lastPlannedAtUtc_ > 0` 守卫绕过；H2 命中 `AwayGap` 的 `lastServerTime <= 0` 早退；
J3/J8 断言的正是 `> 0` 的生成时刻与落盘时刻。`maker-lua-lsp`：0 Error。
**本节此前的「未经真机构建验证」边界就此解除**（U–Z 与四城链路已在云端自检全绿）。

### Verified（本地证据）

- `maker-lua-lsp --mode watch`：`Lua Errors: 0`（2026-09-24 19:50，全部改动之后重跑）。
- `node tools/m3-node-crosscheck.js`：`ALL 29 NODE-CROSSCHECKS PASS`（Node 独立重算夏令时区间、
  Snapshot、NextReplyableUtc 回退走查、fnv1a/RandomPick 与 Lua 常量逐位对表）。
- `gateway npm test`：pass 19 / fail 0（本任务范围仅修 test 脚本，网关行为零改动）。
- `os.date` 全库带 `"!"`；新 UI 按钮全部 `focusable = false`；`git diff --check` 干净。

## 2026-09-24 — M2-B S1：LLM 润色网关与客户端适配层（代码就位，未接线未部署）

### Added

- `gateway/`：独立最小化 LLM 润色网关（Node ≥18，零依赖 CommonJS）。POST `/v1/polish` + GET `/healthz`；
  Bearer 共享密钥鉴权、16KB 请求体上限、固定窗口限流（默认 2/min）、日 token 预算（默认 30000）、
  熔断（连续 3 次失败→10 分钟；**成功只在契约校验通过后才计数**）、requestId 幂等（5 分钟 LRU，失败也重放）。
  上游走 OpenAI 兼容接口（json_object、temp 0.7、max_tokens 250、15s 超时），错误映射
  400/401/429/502/503/504；日志只记长度、结果类别与脱敏错误码。`node --test` 19/19 绿。
- `scripts/services/PolishService.lua`：客户端适配层。白名单 payload 组装（不含历史消息/记忆/设备信息；
  无引用时 `quote` 显式编码为 `null`）；`gateway/src/validate.js` 的 Lua 镜像严格校验；
  Lua 独有的**事实词表守卫**（别的城市名 / 白名单外事件标题 / 允许钟点之外的 `时:分` → 整条回落）。
  FIFO 槽位泵：只有队头交付、每条 8 秒预算到点必回落、迟到结果丢弃、401 会话级熔断、503 冷却 600s；
  任何失败同步回落 ContentService 模板，队列零阻塞。
- `DevSelfTest` 场景 R/S/T（共 20 场景）：R=契约矩阵 23 项（非法 JSON、额外字段、空数组、超长句、
  错误引用 id、纯空白、控制字符、401/429/502/503、transport 异常、三类守卫、brief 档、300 字裁剪）；
  S=FIFO 交付序 + 预算 + 迟到不二次回调；T=队列连续发送经润色层后顺序、逐句流式与事实字段仍归 Lua。

### Changed

- `main.lua`：`HandleDeliver` 改走 PolishService（成功→`BeginReplyStream` 逐句上屏，失败→原模板路径），
  `HandleUpdate` 每帧推进润色预算，日志加 `来源=` 字段。**`GatewayEnabled=false` 时行为与 M2-A 一致、零外发**；
  真实 transport（路径 A：Maker 多人房中转 + TapTap URL 白名单）待确认后才接线。
- `EventService` 暴露 `KnownEventTitles()` 供词表守卫使用。

### 状态边界（防止误读为已接入）

网关**未部署到任何线上环境**；模型 Key 只存在于网关服务端环境变量（`LLM_API_BASE/LLM_API_KEY/LLM_MODEL/GATEWAY_SHARED_SECRET` 等，见 `gateway/README.md`）；
部署位置、模型选型、路径 A 三项均待用户确认；R/S/T 未经真机构建验证。设计与测试矩阵见
`docs/2026-09-23-m2b-llm-gateway-design.md`。

## 2026-09-23 — 本地运行时定位与 3D 场景/角色移动分层方案

### Changed

- **更正一条写进硬边界的错误事实：本仓库其实有本地运行时。** 此前 `AGENTS.md`、`README.md`、
  `docs/platform-capabilities.md` 三处都写着「没有本地运行时」，`AGENTS.md` 甚至把它当成硬边界并写下
  「不要试图在本地启动游戏，也不要为此找本地端口/进程」。实测：`.cli/install-urhox-runtime.py` 已把
  Windows 运行时装在主仓 `.cli/rt/UrhoXRuntime.exe`（24 MB），用与 Maker CLI 内部一致的参数即可跑，
  并已产出真实渲染像素。三处已改为「本地运行时与云端验证的分工」，**保留仍然成立的部分**：
  `UrhoXCLI` 只在云端、本地资源是云端子集、完整游戏因 `TimeState` 的 `os.date("!%Y")` 越界仍跑不起来、
  交付判定仍只能走云端构建 + `runtime.log`。连带更正 `docs/maker-lua-api-verification.md` §9 与 §12
  两条以「仓库无引擎可执行文件」为前提的记录。
- **角色动画阻塞项从「一个」改成「两个独立的」**（`docs/asset-provenance.md` 待办 2/3）：资产本身绑好了
  65 个 `mixamorig` 关节、权重和异常 0 例，是 `import-gltf` 转换时丢了 skin（两次都没救回来）；
  而源 GLB 本身 `animations | 无`——**即使 skin 修好也没有动画可播**。引擎侧 API 齐全
  （`AnimatedModel` / `AnimationController:PlayExclusive` 都在 `.emmylua/`），缺的是数据。
- **Tripo 本地可操作性定论**：Maker MCP 的 `create_3d_asset` 就是 Tripo 通道，本地已实测连通，能
  rig / retopology（`face_limit` 48–20000）/ convert，但**没有动画 operation**（工具描述明确 animation
  retargeting not supported）⇒ 动画只能去 Tripo 网页版。`docs/platform-capabilities.md` §2 原先把
  「动作重定向」列为可用后处理，与 MCP 实际能力不符，已改。
- **Marble 本地不可操作定论**：MCP 无工具、Playwright 未装、用户 Chrome 无调试端口、无头浏览器无登录态、
  联网文档被本环境网络策略拦截。分工固定为「网页端人工导出 + 本地接进工程」。

### Added

- `docs/3d-scene-character-movement.md`：3D 场景与角色移动的分层方案 T1–T5，每层标注确定性证据。
  **T1（固定镜头完全不动 + 角色沿预设路径移动并转向、全程无玩家输入）已用真实项目资产在本地跑出
  3 张渲染截图**——相机三次逐像素一致、角色走预设矩形路径并按移动方向转向；不需要任何新资产、约 60 行。
  T2 需先解两个资产阻塞项，T3 是相机轨迹变体，T4 不做首轮，T5 是现状兜底。

## 2026-09-22 — M1 事件层：从「按时段查模板」升级为「每日事件计划」

### Changed

- **`EventService` 不再是地点选择器**。现在由「城市 + 当地日期 + 固定种子」的纯 Lua 规则生成**一天的事件计划**：
  8 个事件实例连续覆盖 00:00–24:00（凌晨休息 0–6、清晨公寓整理 6–8、学校工作坊 8–12、午间咖啡馆 12–13、
  工作室校样 13–17、路上 17–19、咖啡馆开放麦 19–22、夜间公寓复盘 22–24）。每个实例含 `occurrenceKey`
  （`城市/当地日期/模板id`）、`templateId`、`startUtc`/`endUtc`、`sceneId`、标题、事实摘要、情绪，
  状态（`upcoming`/`ongoing`/`ended`）由查询时刻算出，不是存下来的字符串。
  取代 M0-1 那条「咖啡馆 19–22 进行中 / 8–19 未开始」的写法（上面那条记录已过期）。
- **窗口只声明一处**：每张作息表的行现在自带 `event = "<模板id>"`（`TimeState.SCHEDULE`），
  `EventService` 遍历这张表生成实例，自己不持有第二份钟点表。改她的日程只需要动作息表那一处，
  结构上就不可能出现「人说在上课、事写着校样」；作息表挂了缺失的模板 id 会 `logWarn` 说清是哪一档。
- **日期变体由日期定种**：每个模板 2 个变体，下标 = `fnv1a(城市|日期|模板|盐) % 2`，所以「今天和昨天话不一样」
  与「同一天任何时候重算都一样」同时成立。没有 `math.random`，没有运行时 LLM、真实天气/新闻或外部后端。
- **状态窗、发送、排队补回、开场恢复共用同一次查询**：`main.lua` 只在 `RefreshSnapshot` / `HandleDeliver` /
  `MakeSendContext` 三处取事实，`ContentService` 按 `templateId` 选文案池；送达那一刻命中的实例若到交付时已收，
  回复改用「那会儿…到 06:00 就收了，隔了…才回你」分支，不再拿正在进行的口吻说已经结束的事。
- **存档升到 v4**：新增 `eventPlans`（重启由 `EventService.Restore` 接管，`fromSave=true` 且 `generatedAtUtc`
  保持原值 = 不重算同日事件），事件账本每条补 `startUtc`/`endUtc`/`lastEventState`，消息记录新增 `factKey`
  （送达与回复引用同一个实例键）。v1–v3 存档仍可读。
- 左上开发时间面板的 01:30 / 12:30 / 14:30 / 19:45 现在带分钟；每按一次日志落一行
  `开发测试事件 key=… 状态=… 场景=… 提示=…`。运行日志只记事件键/状态/场景/是否来自存档，
  回复正文与用户原文不再整条落盘（改为记长度）。
- **同一份证据也上屏**（开机突发会被日志管道整批丢掉，见 §14.5）：面板那行每次点档显示
  `事件标题/状态 · sceneId · 计划=存档|当场`，开机后先挂自检结论 `自检 通过=N 失败=M 场景=N/10`
  并跟着重发刷新。这样条件 (a) 的三向一致与条件 (b) 的「不重算」都能肉眼读，不再只依赖日志。
- **真机扫码后暴露的状态窗黑屏/光影问题，先补的是取证而不是猜修**（2026-09-22）。用户回报「脸和衣服
  目前都是黑色，光影搞得不是太好」，但启动日志里 `初始化 3D 状态窗场景`、`资源检查`、
  `若夕 3D 模型加载成功`、`已绑定角色漫反射材质`、两个 LightGroup 分支、贴图回填的两种落点
  **命中数全是 0**——开机那一瞬的整批日志被管道丢掉（§14.5），所以「哪里出错」当时根本读不到。
  已把 StatusWindow 初始化路径上的这些事实改成 `trace()`：额外缓冲一份，由本模块自己订阅 `Update`
  在之后每个 4 秒原样重发、共 3 次，与 `main.lua` 里自检结论的重发是同一套办法。
  异步贴图回填的落点（`未开始 / 异步等待中 / 已回填 / 异步失败`）不缓存成定值，每次重发重读，
  所以三行可能给出不同值——那正是要的。重发用 `bootEcho_.left` 归零后自己退休，
  **不反订阅 Update**：全局 `UnsubscribeFromEvent` 只有 `(eventName)` 一种签名，
  按名退订会把 `main.lua` 的 `HandleUpdate` 一起收掉。`main.lua` 本次零改动。
  已定位的两条候选根因（待上面这轮日志证实，不先动手改）：① 贴图回填与背景
  `PrepareBackground` 不对称——后者有 `cache:Exists` 快路和显式 `onFail`，前者没有，
  若 DWP 资源未就绪时 `GetResourceAsync` 不回调，角色就静默留在黑帧；
  ② `LightGroup/Dusk.xml` 与 `Daytime.xml` 在整个工程里都不存在，`createLighting` 永远走
  「一盏 3.2 方向光 + 一盏 1.6 补光」的兜底，没有 Zone、没有环境光。

### Fixed

- **角色发黑：补上与背景对称的同步快路**（2026-09-22）。`bindCharacterMaterial` 之前只有
  `cache:GetResourceAsync` 一条路，且失败只 `logWarn` 就 `return`——若设备冷启动时 DWP 资源未就绪、
  异步干脆不回调，角色就整会话静默留在黑帧。现在先按 `PrepareBackground` 的同款写法走
  `resourceExists` 快路：文件已在本地就同步 `cache:GetResource` 并立刻 `mat:SetTexture(TU_DIFFUSE, …)` +
  `surface_:QueueUpdate()`，完全不进异步竞态；快路没拿到（登记了但还没加载完）才退回异步，
  不把它误判成资产缺失。报错只留异步失败那一次，写进新的 `characterTextureError_`
  （**不能复用 `modelError_`**：`bindCharacterMaterial` 是在 `tryLoadPrefab`/`tryLoadModelFile` 里调的，
  那两条路随后都会把 `modelError_` 清空，写进去会被覆盖），由 `GetModelError()` 优先返回，
  于是主界面那条 `errorLabel` 不改一行 `main.lua` 就能亮起来。失败时也照样回调
  `noticesChanged_()`——提示不能只落在日志里。`main.lua` 本次零改动。
- **光影差：兜底分支补上 Zone 常量环境光**（2026-09-22）。`LightGroup/Dusk.xml` 与 `Daytime.xml`
  在工程里都不存在，所以 `createLighting` 永远走兜底；而兜底分支只有两盏硬光、**没有 Zone**，
  背光面直接纯黑。Zone 默认 `ambientSource` 是 `AMBIENT_PREBAKED`，那种模式下着色器会把
  `cAmbientColor` 硬清零（`engine-docs/recipes/rendering.md`），`zone.ambientColor` 是空操作——
  所以必须显式切 `AMBIENT_COLOR`（该模式下漫反射强度固定 1.0，亮度只由 `ambientColor` 本身决定）。
  取值 `Color(0.30, 0.27, 0.24)`：室内暖黄为主、掺一点冷调当天光。同时 `SetBoundingBox` 罩住场景
  必设、雾距与 LightGroup 分支对齐成 40–120。**只改兜底分支**：新建 Zone 默认 `priority=0`，
  会顶掉 LightGroup 那一档（连它的 IBL / SH / Bloom / 雾一起）。另外场景里已有 Zone 就直接改它、
  不另建。实际生效值由 `环境光=AMBIENT_COLOR rgb=… 雾=…` 一行打出来，跟着开机 trace 重发 3 次——
  真机上如果「光影不太好」仍在，这一行决定是继续调数值还是问题在别处。

### Built

云端构建 `72f7b81` → `50c5fbc` → `0d297ce` → `88e2c58` → `7f03445` → `ea56ca2` → `def95b5` 全绿
（每次 `[remote_build] 100% 构建流程全部完成` + `preview_refresh_status: 200`）。
`de500f6` 的构建调用 MCP 侧 300s 超时，之后核实 **`origin/main == de500f6`（推送已完成、0 commits ahead）**；
补发的「只构建已推上去的版本」两次分别拿到 `409 Conflict`（= 上一个构建仍在跑）与 `429 Too Many Requests`
（限流），当时已停止重发。19:20 限流解除后按同样方式（`confirm_remote_build_without_submit`，不提交本地
未跟踪改动）对最终版重发一次，17s 完成：`[remote_build] 100% 构建流程全部完成` + `preview_refresh_status: 200`。
所以**云端当前部署的是 `642836d`**（`8a0f6ea`→`c9d259a`→`9c00d0d`→`8ab50f0`→`642836d` 全部随这一次构建落地）。
`git diff --check` 退出 0。
`maker-lua-lsp --mode watch`（**不用 `check`**）：首轮真报 2 个错——`EventPlan` 与 `EventPlanEntry`
是同一个形状却被命名成两个类型；合并为单一类型后复跑 Errors: 0。

### Verified

2026-09-22 17:45–17:46 预览会话（`?localDev=1`，洛杉矶 02:45 冷启动）已取到运行日志，逐条见
`docs/maker-lua-api-verification.md` §14。成立的部分：当日计划 `生成 … 8 个事件（种子=…）` 全程只出现一次，
面板 01:30 / 14:30 / 12:30 各自命中本实例并打出 `key=… 状态= 场景= 提示=`；`la_studio` 静帧实际被
`切换状态窗场景` 换上去（占位图随 `Textures/backgrounds/**` 进了包）；排队到 06:00 的消息在补回时打出
`送达态=ended 送达=02:45 隔 42255 秒`，回复正文长度 264（恢复分支），主链路层面「不把已结束说成未开始」成立；
全日志 0 条 ERROR、无任何用户原文。

上一轮「仍缺三项」已全部补齐（2026-09-22 21:18 结束、104,687 字节的同一次 `runtime.log`，
全程 0 条 ERROR / 0 条 WARN）：

1. **I / J 已拿到结论行。** 根因确认为开机突发日志被整批丢弃（见 §14.5），已改为逐场景 `pcall` +
   `场景 X 结束：判定 N 条` + 一行式结论 `自检结论 通过=N 失败=M 场景=10/10[A B C D E F I J G H]`，
   并由 `HandleUpdate` 每 4 秒重发 3 次落进后面的抓取窗口。实测该行出现 3 次且一致，
   取证判据因此改成结论行的 `场景=N/10`，不再数 PASS 条数（单条 PASS 行仍可能被丢）。
2. **面板 19:45（开放麦）已点。** 四档全部命中：
   `01:30 → la_apartment_night_rest`、`14:30 → la_studio_zine_layout`、`12:30 → la_cafe_midday`、
   `19:45 → la_cafe_open_mic`，四档 `状态` 都是 `ongoing`，场景落到三个不同静帧文件——
   `la_studio → la-studio-dev-placeholder.png`、`la_cafe → la-cafe-4x3.png`、
   `la_apartment → la-apartment-dev-placeholder.png`。**「不同当地时段 → 不同状态 + 不同场景」因此是实测，
   不再是推断。**
3. **同进程内的事件计划不重算已实测；「存档往返」仍未验证。** 开机 trace
   `plan=生成 8 个事件（种子=los_angeles|2026-09-22|m1-events-v1）` 在本次会话只出现一次，
   随后实时刷新循环里 `fromSave=true` 且 `occurrenceKey` 与首算完全一致——但这只证明**同一次进程内**
   复用已生成的计划。真机扫码那一次的启动日志是 `没有本地存档，使用初始内存状态` +
   `接管存档事件计划 0 天`，因为 `DevSelfTest` 在每次 `Run()` 的首尾都调
   `MemoryService.ClearSavedData()`，所以**写盘→重启→读回这条链路在当前构建上结构性地测不到**。
   要拿这个证据必须有一轮不清存档的构建，本轮没有。

**M1 通过条件（规格 §9：同一条用户消息在不同角色当地时段会得到不同的状态、场景和回复时机）逐项已闭：**

- *状态 + 场景*：见上第 2 条，四档各自命中不同事件与静帧。
- *回复时机*：排队补回链路打通，`跳过等待：从 sent 直接推进到 replied` 与
  `从 waiting 直接推进到 replied` 两条分支都实测走过（正式 10 秒链路与开发跳过走同一个 `Deliver()`）。
- *可解释回复*：回复 #43/#44/#45 全部 `事实=la_cafe_open_mic / 场景=la_cafe`（送达时进行中的事件），
  而各自的 `送达key` 分别是 `la_apartment_morning_inbox` 与 `la_apartment_night_rest`，
  且 `送达态=ended`。即「发送时的事件已收场」这个分支真的触发并如实登记，回复引用的是**送达时**的事件
  而非发送时的事件；正文长度 117/198/209 说明按事件事实走了不同模板而非同一句复读。

仍需真机确认（不阻塞上述结论）：移动端中文 IME 行为、资产单文件大小上限、`clientCloud` 单值大小上限，
以及 M0-1 遗留的资产预修项 ①–⑥（`StatusWindow.lua:783` 仍是 `SURFACE_UPDATEALWAYS` 每帧重渲、
`Shutdown()` 未还原全局 `hdrRendering`、`lin-ruoxi.mdl.bak` 未清、MDL 内骨骼命中 0、法线贴图孤儿、
metallicRoughness 未导出、14,298 面 / 3×4096² 超预算）。

**2026-09-22 真机扫码新增的三条待办**（用户回报）：
1. ~~**角色脸与衣服在设备上呈黑色、光影不佳**~~——本轮只补了取证，两轮日志回来才定位改哪；
   **根因已定位并修复**（见上面 Fixed 两条），待下一轮真机扫码确认。
2. **重启后时间仍是测试值**——`DevTestPanel.lua:3` 明写测试时间只作用于本次运行、不写存档，
   所以这不是 bug；但 `DevSelfTest` 每次 `Run()` 首尾都 `ClearSavedData()`，
   「重启后时间/事件是否照存档恢复」在当前构建上测不到，需要一轮不清存档的构建。
3. **时间面板多点了一次**——只影响开发入口的计数，未在日志里留下可判读痕迹。

## 2026-09-21 — M0-1 聊天竖切片（陌生网友 × 洛杉矶）与 M0-0 真机定案

### Added

- **M0-1 竖切片全链路**（规格 §9 定义的「情绪化垂直切片」）：上半部保留 M0-0 状态窗，下半部换成可滚动聊天流。
  后端全部是同一 Maker 工程内的 Lua 服务，**没有新建 HTTP 服务、数据库、账号或外部 API**：
  - `scripts/services/MessageService.lua`——消息数组 + 阶段状态机（`sent → waiting → typing → replied`），
    正式链路固定 10 秒（`SENT_SECONDS 1.5` + 等待 + `TYPING_SECONDS 3.0`），重复发送被拒且保留草稿，
    开发用「跳过等待」走**同一个** `Deliver()`，不直接写最终回复；
  - `scripts/services/EventService.lua`——从时间快照派生**既定事件事实**（咖啡馆开放麦克风夜，19–22 进行中 /
    8–19 未开始 / 其余已收场），只产出事实与短语，不生成文本；
  - `scripts/services/ContentService.lua`——纯模板 + `{token}` 替换（话题探测 + 哈希选句式 + UTF-8 安全的
    12 字回引），运行时不调 LLM；
  - `scripts/services/MemoryService.lua`——本地文件存档 `memory/m0-1-la-stranger.json` 为主，
    `clientCloud` 只留异步接口（`UseCloudMemory=false`），整段读写 pcall 兜底不吞错；
  - `scripts/ui/ChatPanel.lua`——只看视图：预填草稿、四种显式状态文案、输入中动画、追加式行缓存
    （`ClearChildren` 不销毁 Yoga 节点，故不做整树重建）。
- 阶段状态文件 `PROGRESS.md` / `BLOCKED.md`（本阶段专用，逐条挂实际构建结果与日志摘录）。

### Fixed

- **气泡塌成一两字一行**：`nowrap` 的时间角标把容器撑成约 50px，正文 Label 的测量宽度没参与决定容器宽度。
  改为 `ChatPanel.estTextWidth()`（中日韩 1em / ASCII 0.55em）估出正文宽、与角标取大、夹到上限后
  **同时钉死正文 Label 与气泡 Panel 的 `width`**，不再让引擎文本测量决定容器。
- **凌晨 02:10 / 03:03 的自相矛盾文案**（人在公寓却答"还没开始，我还在咖啡馆占位子"）：`EventService` 补
  `dayBreakHour = 8` 的夜间分界（收场后一律 `ended`）+ 按地点分支措辞。
- **回复里「刚坐下。，你那边…」叠标点**：`ContentService.endsWithSentencePunct`，句末已有标点时不再补逗号。
- **点「发送」不发送、回车能发**：引擎 `UI.HandlePointerUp` 要求按下与抬起命中同一控件（`UI.lua:2379`），
  而点按钮会先让 `TextField` 失焦 → 软键盘收起 → 画布高度变化 → 布局位移 → 抬起时已命不中按钮。
  两个按钮加 `focusable = false`（引擎自己的 `EditMenu` 就用这个开关，`UI.lua:2341`）。详见验证报告 §13。

### Built

五次云端构建全绿，无一次失败：`415cb4c`（任务 1+2）→ `fd87d29`（状态文档）→ `4bde79c`（气泡确定宽度 +
凌晨事实分支）→ `a539dda`（气泡宽度钉成估算值）→ `f70bf4b`（`focusable` + 标点守卫）。每次都
`[remote_build] 100% 构建流程全部完成` + `preview_refresh_status: 200`，本地 HEAD 与 `git ls-remote maker HEAD` 一致。
构建前一律用 `maker-lua-lsp --mode watch`（**不用 `check`，它是假绿灯**）压到 Errors: 0。

### Verified（云端 `runtime.log`，全程 `grep -c ERROR` = 0）

- **10 秒闭环按毫秒对上**（`f70bf4b`，LA 03:59 会话）：`18:59:32.275 sent` → `33.772 waiting`(+1.497s)
  → `39.271 typing`(+5.5s) → `42.272 回复`(+3.0s) → `42.287 replied → idle`，合计 **9.997 秒**。
- **跳过等待真走状态机**：`18:23:24.462 跳过等待：从 waiting 直接推进到 replied`，4.1 秒完成，与正式链路同一生成路径。
- **跨会话记忆读回**：`本地存档已读回 turns=4 记录=8 条` → `记忆装载来源: file` → 本轮 `记录第 5 轮 落盘=true`。
- **重复发送被拒且草稿保留**（用户截图 + 日志双向对上）。
- M0-0 真机定案同日完成（`5ac225f`，原生 Android `462.0x1029.0 DPR=0.94866532087326`）：角色正立、
  横向落在右侧约 65%、角色框无黑底 ⇒ `nvgRotate(math.pi)` **保留**，`scene-to-nanovg.md:13` 那句在两个平台都不成立。

### Changed（文档与知识层对账）

- `docs/maker-lua-api-verification.md`：§0 结论表改判第 7 条（`LineEdit` 属废弃原生 UI，实际用 `UI.TextField`）
  并新增第 10 条；§6 重写为"已跑通 + IME 仍未测"；§11 的"runtime.log 至今不存在"更正为已闭环，runbook 换成
  实测口径（CLI 路径随版本漂移、判据字符串改 `[M0-1]`、补四条 watcher 运维坑）；§12 由「⚠️ 未定」改为
  「✅ 已定」并新增 §12.2 真机判读；新增 §13 记录 `focusable` 点击陷阱。
- `README.md`：「当前交接」重写为 M0-0 + M0-1 现状（背景静帧已在仓库、二维码已能生成），「怎么跑起来」
  补上 runtime.log 的两个脾气。
- `AGENTS.md`：「没有本地运行时」的进入 Lua 判据由 `[M0-0] 启动 M0-0 原型` 更新为 `[M0-1] 启动 M0-1 竖切片`，
  「实施起点」同步到 M0-1 已落地。

### Known issues

- **日志区分不出「点击发送」与「回车发送」**（两条路径汇入同一个 `HandleSend`）。点击可用的直接证据只有用户实测，
  日志侧仅时序旁证。要成硬证据需在发送入口加来源标签再构建一轮。
- 我这边**拿不到预览画面**：`browser-use` 与 `playwright` 的导航在用户已口头授权后仍被宿主权限层判
  `Auto mode: action blocked by classifier`，所以所有视觉判读都来自用户截图。
- `maker_build_current_directory` 的自动提交仍会重排 `AGENTS.md`（author `taptap-maker`，逐行比对项目内容零丢失）。
- 角色**悬空**、图标需网页侧人工、真机截图还差第三张（`-01-fullframe` 与 `-02-crop` 已在
  `screenshots/device/`，但 `.project/project.json` 的 `assets.screenshots` 仍为 `[]`，且我没有改 `.project/` 的授权）、
  中文 IME 未测、云变量记忆未接、
  M0-1 前置资产修复项（骨骼 / RM 贴图 / 面数预算 / `SURFACE_UPDATEALWAYS`）本次未动。

### Next

- M1（规格 §9）：多时段状态与消息排队——现在只有"陌生网友 × 洛杉矶"一条线，且回复时机不随可用性档位改变；
- 修角色悬空（需重新构建，会让当前真机基准失效）；
- 若要给「点击可发送」留硬证据：`HandleSend` 加来源标签 + 一次构建。

## 2026-09-20 — M0-0 状态窗画面修复、图标交付位与云端构建

### Fixed

- **状态窗画面镜像**：4:3 咖啡馆静帧原先贴在 3D 场景里的 `Models/Plane.mdl` 上，Plane 的 UV 轴向把静帧镜像了；
  为修正角色上下颠倒而加的 `nvgRotate(π)` 又把这个镜像转成了可见的**上下翻转**（画面顶部长出「木质天花板」，
  实为背景图底部的木桌）。现按 `engine-docs/recipes/scene-to-nanovg.md` 的叠加范式改造：静帧由 UI 层
  以 `backgroundImage` + `backgroundFit="cover"` 绘制，3D RenderTarget 只出角色并改为透明底
  （`clearColor = Color(0,0,0,0)`），从根上取消平面贴图的 UV 歧义。
- **画面下三分之一被棕色方块横切**：远景平面方案为让角色「有着陆地」而加的 `Models/Box.mdl` 地板删除。
- **林若夕背对镜头**：`Node:LookAt` 把节点局部 **-Z** 对准目标，而 `lin-ruoxi` MDL 正面朝局部 **+Z**，
  因此 `frameFixedCamera()` 里那句转向实际让她转过去了 180°。补 `Rotate(Quaternion(180, Vector3.UP))`。
- **`.project/project.json` 的 `assets.icon` 指向 `./game_material/la-cafe-icon.png`，该路径本地不存在**：
  已按配置把 `generate_image` 生成件（512×512）复制到该路径。但随即实测到 **Maker 远端 pre-receive 用
  `EXCLUDE_PATTERNS` 硬拒 `game_material/*`**，push 被 `! [remote rejected]` 退回——所以这个路径本就
  不可能进仓库，图标属**本地暂存素材**，云端生效需走 Maker 网页侧发布素材流程（见「Known issues」）。
- **背景静帧在 DWP 冷启动下会整会话缺失**（本次改造自己引入、复查时抓出）：UI 的
  `ImageCache.Get` 对首次加载失败**永久缓存且不再重试**（`urhox-libs/UI/Core/ImageCache.lua:64-66`），
  而 `backgroundImage` 原先在建控件时就设好，首帧即触发加载。现改为
  `StatusWindow.WarmUpBackground()` 先把静帧拿到手（本地已存在则直接回调，否则
  `cache:GetResourceAsync` 等 DWP 下载完成），就绪后再 `preview:SetBackgroundImage(path)`。
  同时 `.project/resources.json` 的 `groups.default` 补 `Textures/backgrounds/**`：该项目无独立 `**`
  条目，属**增强引用**模式，未可达资源会被裁出包，而背景改由 UI 字符串引用后不再走
  `cache:GetResource`，不该把交付物押在构建器的静态字面量匹配上。
- **`maker_build_current_directory` 把 19 MB 的 `node_modules/` 与 `.qoder/.penguin/.superpowers/`
  一并提交并推上 Maker 云端**（该工具默认提交全部本地变更，而这些目录此前只是未跟踪）。
  `.gitignore` 补齐这些目录与 `game_material/`，并把它们移出索引（磁盘文件保留）。

### Removed

- 随远景平面一起消失的死代码：`createPlaceholderBackground` / `buildBackdrop` / `loadBackgroundAsync` /
  `positionBackdrop` 及 `usingPlaceholderBackground_`、`IsUsingPlaceholderBackground()`、`GetBackgroundNote()`。
  「背景未导入」提示随之移除——背景不再进 3D 场景，占位窗景这个概念不再存在。

### Built

- `maker_build_current_directory` ✅ 远端构建 100%（48s，commit `f235ecc`），`preview-refresh` 200。
- 之后同一里程碑内又连续四次 ✅100%：`099bab0`（git 卫生）、`a49e7ad`（背景显式入包 + §12 判读表）、
  `4cd0dbd`（背景就绪后再挂载）、`5ac225f`（评审修正，见下）。
- 两轴评审（Standards / Spec 并行子代理）在 `5ac225f` 落地的修正：
  ① `preload_groups: ["default"]`——背景原先只靠 DWP 按需下载，冷启动失败即整会话无背景且无重试；
  ② 背景下载失败改为经 `GetBackgroundError()` 打到屏上（真机没有 console），此前被我误删的
     「背景未导入」提示以更正的范围恢复；
  ③ 角色 `castShadows = false`——地板删除后场景内已无任何投影接收面，每帧投影白算；
  ④ 状态窗画框改为宽度驱动 + 高度由 4:3 推出，此前 `maxWidth="100%"` 会在高竖屏上把画框压成
     非 4:3，`cover` 因此裁掉静帧两侧；
  ⑤ 背景路径收敛为单一 `BACKGROUND_PATH`，与 `resources.json` 白名单一致——原先三个候选路径里
     有两个不在白名单内，在设备上永远取不到，只会误导冷启动排查。
  评审确认**无硬性规范违规**；`urhox-libs/` 等引擎目录未被改动。
  Middle-Man 一条（把 `WarmUpBackground` 挪去 `main.lua`）判定不采纳：资产就绪属状态窗自身职责。
- `generate_test_qrcode` ✅ 多次；当前有效二维码指向 `5ac225f`：
  `https://tapcode-sce.spark.xd.com/qrcode/m_c7s3_1789916661057.png`（App ID 940330 / Developer ID 471831，
  竖屏 `portrait` 沿用既有不可变配置）。

### Known issues

- **图标尚未确认在云端生效**：`game_material/` 被 Maker 远端排除，git 这条路交付不了图标；
  `.project/project.json` 的 `assets.icon` 已能在本地解析到真实文件，但 TapTap 侧是否已采用该图标
  需要在 Maker 网页的发布素材界面确认或手动上传。
  **同日查源码定论（不再是推测）**：本地 Maker MCP 全文 `game_material` 命中 0 次，`"icon"` 仅 1 处
  且属应用列表字段，既不读 `assets.icon` 也不上传图标；排除发生在服务端 pre-receive。
  ⇒ 图标**既走不了 git 也走不了 MCP**，只能网页侧交付；「放进仓库路径 + `asset_ignores` 排除包体」
  这个替代方案因无消费方而否决。
  **23:26 网页通道实测（走到卡片、被本机工具堵住）**：用已登录的 Chrome 进入
  工作台 → 项目配置文件 → 发布面板 →「应用图标」卡片（要求 64×64 以上、png/jpg ≤ 4MB，
  我们的 512×512 符合）。但 Qoder Browser Connector 的 `upload_file` 在
  `user-browser-use` 与 `browser-use` 两个 server 上**一律**返回
  `Invalid arguments for file_upload: name is not supported`（换 uid、换路径写法均无效），
  无法代传。另核实：`.project/project.json` 与原件 `assets/image/la-cafe-icon_20260920121307.png`
  **都在 git 跟踪内**，改 `assets.icon` 指针不会让云端采用（该字段由 Maker 侧书写），原结论不变。
  ⇒ 剩下唯一动作是**用户手动把图标拖进该卡片**；全程未点任何发布/提交按钮，TapTap 对外信息零改动。
  **09-21 二次穷尽确认（不再有需要重开的口子）**：① 换第三个控件（素材库「上传素材」按钮，完全在视口内）
  仍是同一句 `name is not supported` ⇒ 与元素可见性无关，是工具本身坏。② 用 DOM 注入让隐藏
  `input[type=file]` 显形被权限分类器硬拦（理由：改写外部服务 UI 行为），不换措辞重试。
  ③ Computer Use 曾在本轮整批消失后又回归（14 工具），但对 Chrome 抓屏直接被
  `browser_url_policy / insufficient_url_confidence` 停掉且 `retry:false`，人工确认 URL 也不改判。
  ④ `maker.js` 全文无 `game_material`、无图标上传 API ⇒ MCP 侧也无入口。四条路都堵，图标只能人工。
- **真机视觉证据已取得，§12 两个未知数定案（2026-09-21 12:53）**：用户用 TapTap 扫码在原生手机上
  跑通了 `5ac225f`，系统截图存于 `screenshots/device/m00-realdevice-01-fullframe.jpg`。
  三条判读全部落定：**角色正立**、**位于画面右侧约 65%**、**角色框无黑底**（透明 RT 的 alpha 在原生生效）。
  ⇒ 代码里那枚 `nvgRotate(math.pi)` **保留、不能删**；`engine-docs/recipes/scene-to-nanovg.md:13`
  「已处理预览纹理的上下方向，不需要额外翻转 Y」在**原生 Android 上不成立**，与 WebGL 结论一致。
  真 4:3 亦在设备上成立：截图量得状态窗 860×645 ≈ 1.333。
  日志侧互证：`runtime.log` 该会话完整启动序列**零 ERROR/WARN**，
  `屏幕物理分辨率: 462.0x1029.0 DPR=0.94866532087326`（证明是手机原生，不是 712×906 WebGL 仿真），
  `资源检查 GLB=false` → 走 `Prefabs/lin-ruoxi.prefab` + `Meshes/lin-ruoxi.mdl`，
  包围盒 0.979 m 放大到 1.68 m，RT 960×720，背景已在本地并挂载，`nvgCreateVideo 成功 句柄=2.0`。
  **M0-0 验收句「无黑/白屏或崩溃、人物与场景均清楚可读」就此满足。**
- **真机上暴露的构图缺陷（不阻塞验收，划给 M0-1）**：角色**悬空**——脚落在画面中部而非咖啡馆地面线上。
  根因是分层设计本身：RT 只出角色、背景是 UI 静帧，两者无共享地面，所以"站得住"只能靠构图对齐。
  修法是把固定相机/角色纵向偏移调到她脚底贴近画框下沿并与静帧地面线对齐，**需重新构建 + 重新扫码**，
  因此本次不动（当前 QR 钉在 `5ac225f`，是唯一的真机基准）。
- `runtime.log` **已于 23:24 出现**：一个客户端加载过本构建，完整 M0-0 启动序列且**零报错**——
  模型加载成功（包围盒 0.509×0.979×0.199，等比放大到 1.68 m）、固定相机
  `pos=(-0.23,0.94,4.83)`、RT 960×720 创建、`背景静帧已在本地` → `状态窗背景已挂载`、
  `nvgCreateVideo 成功，句柄=2.0`。
  ⇒ 此前只能等的两件事已被证实：背景**确实随包交付**（`resources.json` 白名单 + `preload_groups` 生效），
  以及 `WarmUpBackground`「先确认文件到手再交给 UI」的顺序在冷启动走的是本地分支，绕开了
  `ImageCache` 的永久失败缓存。
  ⚠️ 该客户端是 Maker 网页预览（**WebGL**），不能替代真机：§12 的方向与 alpha 两个未知数仍未决。
- `assets.screenshots` 仍为 `[]`：三张截图必须是**真机**截图，`screenshots/` 里现有的三份是浏览器预览
  抓取，不能充当 M0-0 交付物。
- 状态窗 `SURFACE_UPDATEALWAYS` 每帧重渲、`renderer.hdrRendering` 在 `Shutdown()` 不复原，
  以及骨骼/RM 贴图/面数预算，均属规格明确划给 **M0-1 前置**的条目，本次未动。

### Next

**扫码时要一并取的画面**（两个消费方要求不同，别当成同一件事）：

- `.project/project.json` 的 `assets.screenshots` 是 **TapTap 上架位**用的，要的是真机运行画面；
- `docs/demand.md` 第 3 条「视觉资产看板」是**赛事必交物**，原文要求
  「3 张以上核心场景的高清截图 / 动图，包括关键静帧、多视角展示图（multi-view）、环境画面等」
  ——它要的是**三类不同画面**，三张同机位照片不满足它。

按 M0-0 现有能力（固定单镜头、无动画、无聊天 UI）一次扫码可覆盖：

| # | 取什么 | 满足谁 | 备注 |
| --- | --- | --- | --- |
| 1 | 状态窗整体首屏，人物全身入画 + 4:3 窗景同时清楚 | 上架位 + 看板「关键静帧」+ §12 判读 | 这张同时就是验收证据，优先保证 |
| 2 | 同屏的系统级裁剪近景，看脸与服装可读性 | 看板「关键静帧」细化 | 镜头固定，只能裁不能推近 |
| 3 | 冷启动后第二个时刻的同一画面（隔一会儿再截） | 上架位 + 「稳定」二字 | 证明不是一次性渲染 |

**看板缺口，M0-0 补不了**：「多视角展示图（multi-view）」需要换机位或角色转身，
而 M0-0 是固定镜头且明确不做动画；「环境画面」需要咖啡馆远景独立成片。
这两项属 M0-1 之后的资产，不要指望 M0-0 收尾时一并交掉。

其余待办：用户用 TapTap App 扫码并按 §12 判读表回报（**角色正立与否 + 在左还是右侧**）；
图标需在 Maker 网页发布素材界面确认生效（`game_material/*` 走不了 git）。

**取物方式更新（同日核实）**：Maker MCP `get_debug_feedbacks` 的官方定义覆盖「本游戏的
真机游戏日志与**真机截图**」，现在 `total: 0` 只是因为还没有客户端加载过构建。
所以扫码试玩之后应**先查这个工具**，能取到真机截图就不必人工补拍上表第 2、3 项。
详见 `docs/maker-lua-api-verification.md` §12 的「扫码之后的两条取证通道」。

## 2026-09-19 — Maker 工程落地、历史合并与文档对账

### Added

- `npx -y @taptap/maker init` 完成：绑定 Maker 应用「若夕的归来」（`720b27bf-ca69-44ac-a776-a88ec2ec2b28`），AI Dev Kit 与 11 个 maker skills 落到本地；Maker MCP 注册进 Qoder 的 local 作用域。
- 合并 Maker 云端工程与文档仓两条无共同祖先的历史：`scripts/main.lua`、`scripts/StatusWindow.lua`、`.project/`、`assets/` 下的 MDL/材质/贴图/源 GLB 首次进入本仓库。
- `docs/asset-provenance.md`：资产唯一真源表、源 GLB 与导入后 MDL 的实测差异、云端权威重导入命令、五项阻塞待办。
- `research/taptap-pages/README.md`：记录登录墙判定依据与替代来源。

### Changed

- 远端拓扑（2026-09-19 两次变更，最终态）：先把两条无共同祖先的历史并成一棵树并短暂以 GitHub 为 `origin`；随后用户改定**所有推送只发 `maker`**，GitHub 暂不管。现 `origin` 与 `maker` 同指 Maker 云端 URL，另留 `github` 远端作只读留档把手。Maker 工具链（`init` / `build` / `logs watch`）会反复把 `origin` 抢回 Maker URL，已定为预期行为、不再手工纠正。本地保留 `maker-main` 分支作为 M0-0 的离线引用。
- 设计规格收敛到单一真源 `docs/2026-09-15-parallel-companion-design.md`（原 `docs/superpowers/specs/` 副本与之逐字节等价，仅行尾不同）。
- 按 2026-09-18 验证报告落地此前未写入的修订：§4.2 补 `clientCloud` 异步/配额/昵称禁令与本地文件兜底；§5.1 时间源改为 `common.get_server_time()` 并写明无 IANA 时区库、`os.date` 需 `"!"` 前缀；§7.2 补 `convert-panorama` 转 Cubemap 与「禁止从全景裁 4:3」；§7.3 与 §8 删除运行时 `Maker AI`，`ContentService` 改为纯模板；§9 M0-0 验收措辞 GLB→MDL 并新增 M0-1 前置修复项；§10 风险表重写；§12 改指 AI Dev Kit。
- `docs/platform-capabilities.md`：GLB→MDL 的交付/运行时双列、真实目录结构、无法溯源的大小上限统一标注「未核验」。
- `AGENTS.md`：恢复被 Maker 托管策略覆盖的项目段，并补入四条实测平台边界与双远端拓扑规则。
- 角色资产去重：确立单一真源，删除 2 份重复 GLB 与 `.gbm` 解包残留（删除前逐份 md5 比对并确认 uuid 无人引用），回收约 15 MB；`poc/` 交接位由 `docs/asset-provenance.md` 取代。
- 清理 26 份重复登录墙快照与 `research/node_modules`（与根副本同为 playwright 1.63.0）。
- `docs/maker-lua-api-verification.md` 新增 §11：预览卡 `Initializing 0%` 的定性（Chromium IndexedDB `InvalidStateError`，失败在 Lua 之前的资源装载层）、11 条已穷举排除假设的依据、从 `@taptap/maker` 0.0.33 源码与包内 skill 挖出的平台契约（预览验证 = build + `runtime.log`；`preview-refresh` 只刷服务端；日志窗口硬上限 1 小时），以及照抄可执行的收尾 runbook。
- 构建包瘦身：`.project/settings.json` 新增 `build.asset_ignores`，把 9.7 MB 非运行时文件（源 `.glb`、Tripo 多视图缩略图、`lin-ruoxi.mdl.bak`）剔出包；三条 glob 经 `fnmatch` 全量核验恰好命中 16 个文件，五个运行时必需路径均不被命中。
- 文档补齐"怎么跑"这一外部视角缺口：`README.md` 新增「怎么跑起来」、`AGENTS.md` 新增「没有本地运行时」硬边界、`docs/platform-capabilities.md` 补入包与瘦身规则；并修正 `AGENTS.md`「实施起点」里"本机 `scripts/`、`assets/` 为空需取回"的失效陈述与权威文档表缺失的 `asset-provenance.md` 条目。

### Known issues

- 源 GLB 14,298 三角面，超 `face_limit <= 5000` 约 2.9 倍；三张内嵌贴图均为 4096×4096。
- `import-gltf` 丢弃了源 GLB 的 65 关节 skin；**16:35 云端二次导入后 MDL 内骨骼命中数仍为 0**，问题未解决。
- 二次同步新增缺陷：材质由 `PBRDiffNormal.xml` 退成 `PBRDiff.xml`，**法线贴图丢失**，`lin-ruoxi_00_N.png` 成孤儿资源；metallicRoughness 依然未导出，材质用常量粗糙度。
- 工程内遗留 `assets/Meshes/lin-ruoxi.mdl.bak`（753,790 字节旧模型）。
- 状态窗 RenderTarget 用 `SURFACE_UPDATEALWAYS` 每帧重渲，且全局 HDR 开启后未在 `Shutdown()` 复原。
- 背景 `la-cafe-4x3.png` 缺失；图标与 3 张实机截图未产出，真机二维码仍被阻塞（但 `app_id` / `developer_id` / `miniapp_id` 已由云端写入）。
- **预览卡 `Initializing… 0%`**（console 报 Chromium IndexedDB `InvalidStateError`）：定性为浏览器资源缓存
  与当天被改三次的云端工作树不同步，属装载层而非 Lua 报错。悬空引用、`raw-assets/` 进包、DWP 预下载配置、
  工程健康四类假设均已用独立证据排除；远端构建 ✅100% ×2、preview-refresh ✅200 ×2。
  完整排查表与平台契约见 `docs/maker-lua-api-verification.md` §11。**待用户侧硬刷新后由 `runtime.log` 判定闭环。**
- `.project/settings.json` 新增 `build.asset_ignores`，把 9.7 MB 非运行时文件（源 `.glb`、Tripo 多视图缩略图、
  `lin-ruoxi.mdl.bak`）剔出构建包；文件仍留在库内，未删除。
- 云端 19:57 自动产生作者 `TapCode Rollback` 的同步 commit，把此前删掉的资产原样塞回项目根 `raw-assets/`（+24 MB）。
  该目录不在 `asset_dirs` 内所以不进包，但已进 git 历史；**结论：不要靠删 Maker 侧已追踪资产来瘦身。**
- `maker_build_current_directory` 会把 `origin` 改指回 Maker 云端 URL（与 `maker init` 同症状），GitHub 那条远端整个消失。
  已复原为 `git@github.com:melondy101/LiangLiao.git`；本批仍未推 GitHub。另将 `http.postBuffer=524288000` 固化到本仓
  `--local` 配置，避免 24 MB 增量再次触发 `send-pack: unexpected disconnect`。

### 与云端的双向合并

- 本地合并了云端 16:35 的 `4e8d55a`（重导 MDL、改材质/预制体/`StatusWindow.lua`、写入发布元数据），零冲突，代码与资产一律取云端版本。
- 反向推送时**会带走本地对 `assets/model/fashion+model+3d+model.glb` 与 `lin-ruoxi.gbm/` 的删除**（共 15 MB 非运行时资产）。判断依据是「无引用」，但材质引用已由 `uuid://` 改为路径，该结论需在推送时再确认一次。

### Next

- M0-0 真机验收：补背景静帧 + 图标/截图，出测试二维码；
- M0-1 前置：修骨骼、修 RM 贴图、降面数与贴图预算、改 RenderTarget 更新模式。

## 2026-09-16 — M0-0 林若夕状态窗基线冻结

### Added

- 锁定 M0-0：洛杉矶傍晚咖啡馆中的原创角色“林若夕”、固定 4:3 状态窗、Tripo 前景 GLB 与 Marble 静帧远景的真机验证目标。
- 在正式设计规格中补充角色资产契约、四视图交接、`poc/` 目录、分阶段验收，以及后续音频与自由输入的接口边界。

### Changed

- 正式废弃旧方案的自由移动、摇杆、镜头旋转和点击角色对话；它们不再是实施或验收要求。
- 清理研究脚本与汇总中的旧 IP 检索分类；保留非 IP 的通用设计研究并重建统计结果。

## 2026-09-15 — v2 平行时空陪伴设计

### Changed

- 项目从“三位 NPC 自动小镇”重构为“一位平行时空聊天对象 + 3D 状态窗”。
- 确立四城初始化：上海、成都、洛杉矶、伦敦；关系前史为陌生网友、高中同学、前同事、久未联系的朋友。
- 确立稳定核心人格、平行人生档案、关系状态、关键互动和开放生活上下文的数据分层。

### Added

- `docs/2026-09-15-parallel-companion-design.md`：正式设计规格。
- `docs/platform-capabilities.md`：Tripo、Marble、TapTap Maker 的独立平台与资产规格。

### Next

- M0：在 TapTap Maker 真机中验证 Tripo 原创角色 GLB 和 Marble 背景/镜头。

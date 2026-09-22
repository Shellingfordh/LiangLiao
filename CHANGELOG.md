# Changelog

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

### Built

云端构建 `72f7b81` → `50c5fbc` → `0d297ce` → `88e2c58` → `7f03445` → `ea56ca2` 全绿
（每次 `[remote_build] 100% 构建流程全部完成` + `preview_refresh_status: 200`），当前 Maker HEAD = `ea56ca2`。
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

仍缺三项，全部需要再跑一次预览：

1. 自检 suite 只打了 `PASS A0…A6` 就没了后续，也没有 `自检结束` 汇总行，所以 **I（计划覆盖）/ J（重进）
   一行都没执行**。`DevSelfTest.Run` 原来是十条场景直链，任何一条断言求值抛出都会静默带走后面的场景——
   已改为逐场景 `pcall` + `场景 X 结束：判定 N 条`，下一次运行要么打全 I/J，要么把抛出原文（含行号）落成 ERROR。
2. 面板 `19:45`（开放麦）这一档本轮没点。
3. 会话只冷启动一次，`接管存档事件计划 0 天` + `fromSave=false` 只证明「同进程不重算」；
   同一日期**重进**后 `fromSave=true` 且实例键不变（条件 b）还缺第二次进入的证据。

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

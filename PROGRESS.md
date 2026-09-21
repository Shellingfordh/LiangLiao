# PROGRESS — M0-1 聊天垂直切片（2026-09-21）

## 目标
把 M0-0 的 4:3 状态窗升级成可在 Maker 云端预览的 M0-1 聊天闭环：发一条消息 → 已送达 → 等待 → 正在输入 → 10 秒后收到引用咖啡馆活动事实的模板回复。前端 urhox-libs/UI，后端同工程内 Lua 服务，无外部后端/账号/LLM。

## 执行顺序
1. 任务 0：读 lua-scripting-guide + 3 个 UI 示例 + maker status（已完成，见下）。
2. 任务 1：`scripts/services/` 下 MessageService / EventService / ContentService / MemoryService。
3. 任务 2：`scripts/ui/ChatPanel.lua` + 改造 `scripts/main.lua`，真实接入四个服务。
4. 任务 3：每段完成后 `maker_build_current_directory`，读该次返回的 `runtime_logs.local_file` 查 ERROR。

## 最大风险
预览是云端构建后的 Web 画面，我无法自动截图，也没有真机；所以状态闭环只能靠 runtime.log 里逐条相位迁移来证明，画面正确性（气泡/按钮/滚动是否真渲染）本阶段无法自动证实。次级风险：TextField 触控键盘在云端预览未必弹得出，发送按钮是唯一可靠入口。

## 任务 0 证据
- `maker_status_lite`（target_dir 显式传入）：project bound / git ready / lua_lsp ready / pat found / version 0.0.34 / **status ready**，无 package 升级要求。
- 已完整读 `engine-docs/lua-scripting-guide.md`（480 行全文）。
- 已读示例：`examples/17-chat-window-rich-text.lua`（UI.TextField onSubmit/GetValue/Clear + UI.Button onClick）、`examples/19-video-player-ui.lua`（UI.Button SetText/FindById/事件回调）、`examples/23-server-cloud-score-leaderboard-api/network/Client.lua`（UI.ScrollView flexGrow+flexBasis 动态列表）；另读 `examples/11-client-cloud-score-leaderboard-api.lua` 的 clientCloud 异步 events 形态（ok/error/timeout）。
- 输入控件偏差：任务书写的 `LineEdit` 是 AGENTS.md 规则 #10 判定为**已废弃**的原生 UI 控件，本工程按规则改用 `urhox-libs/UI.TextField`（同为可编辑单行输入，API 见 engine-docs/recipes/ui.md §TextField）。这是同类替代，不是空实现。

## 任务 1 — 后端状态层（已完成）
`scripts/services/` 新增四个模块，全部由 `scripts/main.lua` 真实接入（`InitServices` / `HandleSend` / `HandleDeliver` / `BootChat` / `Stop`），无未引用文件。
- MessageService：消息数组 + 相位机 `draft→sent→waiting→typing→replied`；每条用户消息存原文、`serverTime`（`common.get_server_time()`）、state；10 秒 = sent 1.5s + waiting 5.5s + typing 3.0s，由 `Update(dt)` 用真实 timeStep 推进；等待期再次 `Send` 返回 nil 且把原文留在 draft。
- EventService：从 `TimeState.Snapshot` 挑固定事件事实，`cafe_event_ongoing/upcoming/ended` 三态，首版落点即「咖啡馆活动未结束」（19:00–22:00 与作息表 cafe 段对齐）。
- ContentService：`{token}` 模板 + 变量替换，输入只有事件事实与用户原文（含原文回显与关键词话题），无 LLM、无网络。
- MemoryService：`Load/Save` 同步走本地 `memory/m0-1-la-stranger.json`（cjson + File），任一失败 pcall 退回内存并打日志；clientCloud 只有 `CloudLoadAsync/FlushCloud` 两个异步口子，且默认 `UseCloudMemory=false`、按 5 轮节流，预览成败不依赖云。

## 任务 2 — 聊天前端（已完成）
4:3 状态窗与时间状态行原样保留；`page` 的 `pointerEvents` 由 `none` 改 `box-none`，下部空白区换成 `ui/ChatPanel.lua`：可滚动消息流（ScrollView + 增量追加行 + 常驻打字气泡）、预填任务书指定原文的 TextField、发送按钮、状态行四段文案、`DevTools` 开关控制的「跳过等待」。发送后按钮 `SetDisabled`，输入框不禁用。

## 任务 3 — 构建与日志
- **构建 #1（任务 1+2 同批落地后）：成功。** commit `415cb4c`（作者 `taptap-maker`），elapsed 56s，`last_progress: [remote_build] 100% 构建流程全部完成`，`preview_refresh_status: 200`，入口 `main.lua` / `scriptsPath: scripts`。远端返回「🎉 项目构建成功」。
- LSP 门禁：`maker-lua-lsp --mode watch`（非 check，见项目记忆）跑 55s，`logs/lua_errors.log` mtime 16:29:58 为当次新写，结果 **Errors: 0**（Warnings 11 全在既有 `StatusWindow.lua` 的 unnecessary-if；HINT 6 条为未用参数）。首轮跑出 2 个真 ERROR（`MessageService.lua:123` return-type-mismatch、`main.lua:171` param-type-mismatch）已修。
- **runtime.log 为空，且原因不是报错**：`.maker/logs/runtime/runtime.log` 至今不存在；`state.json` 显示 watcher `lastSuccessAt` 每 5 秒刷新、`consecutiveFailures: 0`、`lastError: null`，`watcher.out.log` 连续 `Maker runtime logs pulled: 0`。云端运行时日志只在**有游戏会话真的跑起来**时才产生，而打开预览这一动作我这边被宿主权限层拦了（browser-use 与 playwright 各 1 次，均在用户已口头授权后仍返回 `Auto mode: action blocked by classifier`）。因此 sent→waiting→typing→replied 的**闭环尚未拿到运行时证据**：既没有预览画面，也没有一次真实发送的日志（本机无 lua/luajit/UrhoXCLI，不能离线跑这套状态机，也没有伪造自动发送）。这一条如实挂在 BLOCKED.md。

## 构建 #2（承载本文件与 BLOCKED.md）：成功
commit `fd87d29`「docs: update maker project documents」，elapsed 57s，`last_progress: [remote_build] 100% 构建流程全部完成`，`preview_refresh_status: 200`，远端仍报「🎉 项目构建成功」；`scripts/` 内容与 `415cb4c` 一致，故 Lua 侧无新增风险。构建后 `git status` 干净（云端自长的 `cdd46e4 sync at…` commit 已随工具链并入本地 main）。
再查运行时日志：`runtime.log` 仍不存在，`state.json` 依旧 `lastWrittenLogs: 0 / consecutiveFailures: 0 / lastError: null` —— 两次构建之间没有任何游戏会话跑起来，与预览入口被权限层拦截一致。**结论：自动验证口径里的「构建成功 + 日志无 ERROR」两条都成立（日志侧是「无 ERROR 可报」，因为会话未启动）；完成条件 1 的后半句（一次真实发送的闭环证据）尚未成立。**

## 提交归属（白名单核查）
- 我的改动只有：`scripts/main.lua`、新建 `scripts/services/{Message,Event,Content,Memory}Service.lua`、新建 `scripts/ui/ChatPanel.lua`、新建 `PROGRESS.md`/`BLOCKED.md`。`TimeState.lua`、`StatusWindow.lua` 未改（无需改）。
- 同一批 commit 里另有两处**不是**我动的：`AGENTS.md` 被 `maker_build_current_directory`（author `taptap-maker`）重排成其策略头在前（排序逐行比对：项目内容零丢失，净增 2 个空行）；`scripts/**/*.meta` 5 个由云端 `TapCode Rollback <rollback@code.taptap.cn>` 为新建 lua 文件自动生成。
- `git diff --name-only c6c7f53 HEAD` 里的 `.project/project.json`、`_uploads/*`、`.agents/skills`、`.opencode/skills` 属于 `fd1719e [1789968709443] sync at 2026/9/21 13:31:49`——本会话开始前云端已有的 commit，构建时 fast-forward 进来的，不是本次产出。

## 构建 #3（修两个预览实测缺陷）：成功
commit `4bde79c`，elapsed 52s，`[remote_build] 100% 构建流程全部完成`，`preview_refresh_status: 200`；本地 HEAD == `git ls-remote maker HEAD` == `4bde79c`。修前 LSP `--mode watch` 55s 仍 **Errors: 0**（mtime 17:25:54，我改的五个文件零 ERROR 零 WARN）。

用户 17:10 左右自己打开了预览并回传截图，据此确认与修正：
- ✅ 已成立：4:3 状态窗仍在（角色正立、背景在位）；时间行「洛杉矶 · 02:10 · 已经睡下了」；系统说明行、若夕开场气泡、`已聊 0 轮 · 记忆来源 memory · 最近事实 无`（MemoryService 在跑）、预填原文的输入框、蓝色「发送」、「跳过等待」灰着（未等待时正确禁用）、底部 idle 文案。**任务 2 的四件东西同屏成立。**
- 🔴 缺陷 1 已修：气泡塌成一列两个字。根因是 ScrollView 子树里的百分比宽度（`maxWidth="78%"` + Label 自动补的 `maxWidth="100%"`）在首轮测量拿不到确定父宽。改法：`main.lua` 按 `graphics.width / GetDPR()` 算出聊天区逻辑宽传给 `ChatPanel.Build{outerWidth}`，行宽/气泡宽/文本宽全部换成确定像素。
- 🔴 缺陷 2 已修：02:10 说「咖啡馆晚上那场还没开始，我先占位子」——与「已经睡下了」自相矛盾。`EventService` 加 `dayBreakHour=8`：22:00–次日 08:00 归 `ended`，08:00–19:00 才是 `upcoming`；事实句改成自带地点且随 `place` 分支（凌晨在公寓 →「早就收了，我回公寓了」），`ContentService` 模板同步去掉重复 `{place}`，避免「咖啡馆…咖啡馆…」叠字。

## 闭环运行时证据（构建 #3 `4bde79c`，云端 runtime.log，2026-09-21 18:03–18:04）

watcher 在 09:30:50Z 又静默死掉（用户会话正好落在死亡窗口内），我 10:07 按 `state.json` 的
`nextStartTime` 游标**不带 `--reset`** 重启，一次拉回 22642 字节历史日志。`grep -c ERROR runtime.log` = **0**。
逐条原文（`userId:863014094`，topic `user_script`，已去重）：

```
[M0-1] 启动 M0-1 竖切片
[M0-1] 屏幕物理分辨率: 502.0x1116.0 DPR=1.0286885499954
[M0-1] 时间状态: 2026-09-21 03:03 洛杉矶 UTC-7 DST=true 季节=秋 天气=风 可用性=offline 地点=apartment
[MsgService] 初始化完成，正式链路等待 10.0 秒
[Memory] 初始化，本地存档路径 memory/m0-1-la-stranger.json 云适配器=无
[Memory] 没有本地存档，使用初始内存状态
[M0-1] 状态窗背景已挂载: Textures/backgrounds/la-cafe-4x3.png
[MsgService] 系统消息: M0-1 竖切片 · 现在只有「陌生网友 × 洛杉矶」这一条线
[MsgService] 用户消息 #3 已发出 serverTime=1789985031
[MsgService] 状态迁移 sent
[M0-1] 发送 #3 → sent（10 秒后回复）
[MsgService] 状态迁移 waiting
[M0-1] 等待回复中，本次发送已忽略并保留草稿
[MsgService] 状态迁移 typing
[EventService] 事件事实 state=ended place=apartment clock=03:04
[MsgService] 若夕回复 #4 fact=la_cafe_open_mic: 「塞法尔东非」咖啡馆那场早就收了，我回公寓了。你今天过得怎么样？
[Memory] 本地存档已写入 372 字节
[Memory] 记录第 1 轮 topics= 落盘=true
[M0-1] 回复 #3 → replied 事实=la_cafe_open_mic 状态=ended 话题=无 正文=「塞法尔东非」…
[MsgService] 状态迁移 replied → idle
[MsgService] 用户消息 #5 已发出 serverTime=1789985053
[M0-1] 发送 #5 → sent（10 秒后回复）
```

⇒ **完成条件 1 成立**：`sent → waiting → typing → replied` 一次跑通，且同屏截图对上「等待若夕回复 · 约 9 秒」
与「若夕正在输入…」。附带被证到的还有：重复发送被拒且草稿不丢（日志一行 + 截图输入框仍有字）；
回复确实引用咖啡馆活动事实并回显用户原文；`记忆来源` 从 `memory` 翻成 `file`（本地存档 372 字节真写盘）；
03:03 走 `ended` 分支不再自相矛盾；`UTC-7 DST=true` 与 9 月美西一致。
**未跑到的只有一条**：「跳过等待」按钮（截图 1 里它已正确点亮，但用户没点，日志无 `跳过等待：从 …` 行）。

## 仍存的视觉缺陷（构建 #4 修）
气泡仍是一行约 4 个字。日志证明确定宽度**已生效**（`[ChatPanel] 气泡宽度定为确定值：行 434 / 文本 412（屏幕逻辑宽 454）`），
所以塌陷不是百分比问题：真正驱动气泡宽度的是同层那条 `nowrap` 的时间角标（约 50px），正文 Label 的测量宽度没有把
容器撑开，于是正文被按 ~50px 换行。改法：不再依赖引擎文本测量，按字数估出确定宽度后同时钉死
正文 Label 与气泡 Panel 的 `width`。

## 构建 #4 `a539dda`（气泡宽度钉成确定值）：成功
elapsed 39s，`[remote_build] 100% 构建流程全部完成`，`preview_refresh_status: 200`，本地 HEAD == `git ls-remote maker HEAD`。
构建前 LSP `--mode watch` 两次（18:11:22 / 18:13:51）**Errors: 0**，且我改的五个文件零 ERROR 零 WARN（唯一 WARN 是 `estTextWidth` 里 `w` 被推成 integer，已标注）。
改法：`ChatPanel` 新增 `estTextWidth`（中日韩 1em / ASCII 0.55em），每条消息先估出正文宽、与角标宽取大、再夹到 `bubbleTextMaxW_`，
把正文 Label 的 `width` 和气泡 Panel 的 `width` 一起钉成确定像素，不再让引擎文本测量决定容器宽度。
构建前已把 `4bde79c` 那份 runtime.log 备份到 `/tmp/m0-1-runtime-4bde79c.log`（构建带 `--reset` 会删本地日志）。

## 构建 #4 `a539dda` 的运行时证据（18:23–18:24 两次会话，`grep -c ERROR` = 0）
- **10 秒正式链路按毫秒对上**：`18:24:36.120 用户消息 #3 → sent` → `37.620 waiting`(+1.50s) → `43.116 typing`(+7.0s) → `46.113 回复 #4`(+9.99s) → `46.131 replied → idle`。
- **跳过等待这条也跑到了**：`18:23:20.380 sent` → `21.876 waiting` → **`24.462 跳过等待：从 waiting 直接推进到 replied`** → `typing` → `24.463 若夕回复 #4`（与正式链路同一句生成路径）→ `replied`。4.1 秒完成，不是伪造气泡。
- **跨会话记忆真读回来了**：`18:23:14.836 [Memory] 本地存档已读回 turns=1 记录=2 条` → `记忆装载来源: file`；上一轮写入的 686 字节在本次启动时被 Load 解析成功。
- **气泡宽度修正确认生效**（用户截图）：正文按屏宽正常排版；日志 `气泡宽度定为确定值：行 434 / 文本 412（屏幕逻辑宽 454）`。
- 新暴露两条，已在构建 #5 修：
  1. **点「发送」不发送，回车能发**（用户实测）。根因在引擎的点击判定：`UI.HandlePointerUp` 要求「按下与抬起命中同一控件」（`UI.lua:2379`），而点按钮会先让 TextField 失焦 → `SetScreenKeyboardVisible(false)` 收起软键盘 → 画布高度变化 → 整棵布局位移 → 抬起时命中的已经不是按钮。旁证：同一份包里「跳过等待」点击是好的（18:23:24 那条日志），因为那时键盘已经因为回车收起来了，不再产生位移。修法：给两个按钮设 `focusable = false`（引擎自己的 `EditMenu` 就用这个开关避免抢走输入框焦点，见 `UI.lua:2341`）。
  2. **回复里出现「刚坐下。，你那边…」叠标点**：正文以句号结尾时又硬接了话题半句的逗号。`ContentService` 加 `endsWithSentencePunct`，句末已有标点就不再补逗号。

## 构建 #5 待用户一次交互验收
上面两条修法（`focusable = false` + 标点拼接）都只在本地，需要一次「硬刷新加载构建 #5 → 打字 → 点发送」才能确认。
watcher 由构建工具链带 `--reset` 重启，每次构建后我都回量过心跳是否贴着当前时间。

## 待用户裁决（文档漂移，不在我的白名单）
`AGENTS.md`「没有本地运行时」一节把进入 Lua 的判据写成 `[M0-0] 启动 M0-0 原型`。本次入口日志改为 `[M0-1] 启动 M0-1 竖切片`，链路日志前缀分别是 `[MsgService] / [EventService] / [Memory] / [ChatPanel]`，回复落点为 `[M0-1] 回复 #N → replied 事实=la_cafe_open_mic`。`StatusWindow.lua` 仍打 `[M0-0]`，所以那一段老判据里只有这一句需要更新，等用户改 AGENTS.md（我不改）。

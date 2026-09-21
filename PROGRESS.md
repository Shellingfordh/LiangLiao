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

## 构建 #5 `f70bf4b`（发送按钮点击 + 叠标点）：成功，验收已过
elapsed 37s，`[remote_build] 100% 构建流程全部完成`，`preview_refresh_status: 200`，本地 HEAD == `git ls-remote maker HEAD`，`git status` 干净。
构建前 LSP `--mode watch`（18:27:05）**Errors: 0**，我改的文件零 WARN。改动只有两处：`sendButton_.focusable = false` /
`skipButton_.focusable = false`（`scripts/ui/ChatPanel.lua`），`endsWithSentencePunct` 标点守卫（`scripts/services/ContentService.lua`）。

### 构建 #5 的运行时证据（18:59 一次会话，整份日志 `grep -c "level":"ERROR"` = 0）
- **10 秒正式链路再次按毫秒对上**：`18:59:32.275 [MsgService] 用户消息 #3 已发出 serverTime=1789988375` → `sent` →
  `33.772 waiting`(+1.497s = `SENT_SECONDS 1.5`) → `39.271 typing`(+5.5s 等待) → `42.272 若夕回复 #4`(+3.0s = `TYPING_SECONDS 3.0`)
  → `42.287 [M0-1] 回复 #3 → replied 事实=la_cafe_open_mic 状态=ended 话题=time,event` → `replied → idle`。sent→replied 共 **9.997 秒**。
- **叠标点已消失**：同一条回复正文为「…我回公寓了，刚坐下。你那边这个点是白天吧」——句末是「。」且直接接下一句，
  没有构建 #4 那次的「刚坐下。**，**你那边…」。
- **跨会话记忆继续读回**：`本地存档已读回 turns=4 记录=8 条` → `记忆装载来源: file` → 本轮 `记录第 5 轮 topics=time,event 落盘=true`（1475 字节）。
- 状态窗链路未退化：`[M0-0] 若夕 3D 模型加载成功`、`状态窗 RenderTarget 960x720 已创建`、`[M0-1] 状态窗背景已挂载`，
  LA 03:59 → `可用性=offline 地点=apartment`、事件态 `ended`（夜间裁决 8 点分界生效，回复文案与地点一致）。
- **点击 vs 回车无法从日志文本区分**：`Button:OnClick` 与 `TextField` 的提交都汇到同一个 `HandleSend`，日志不记触发源。
  所以点击这条路的直接证据是用户实测「它可以发送」，日志侧的旁证是：这次发送发生在页面重载（`18:59:27.939 启动 M0-1 竖切片`）
  后 **4.3 秒**、且输入框里是预填草稿没被改动——没有先聚焦再敲回车的余地。若要把这条做成硬证据，需要在 `HandleSend` 加一个来源标签再构建一轮。

### 这一段日志是怎么取回来的（过程记录，别按 `--reset` 补拉）
构建 #5 于 18:33 把 watcher 带 `--reset` 重启，只回拉到 18:28:49 的旧会话；之后一直打到 18:43:45 心跳停止，
`watcher.out.log` 里是**连续 117 次** `Maker runtime logs pulled: 0`（10 分钟 ÷ 5s 间隔，自洽），末尾一句
`Maker runtime log watcher stopped`——又静默死了一次，正好盖住用户 18:59 那次会话。
我按 `state.json` 的 `nextStartTime=1789986529` 用 `taptap-maker logs watch --target-dir … --interval 5s`（**不带 `--reset`**）
从游标续拉，`runtime.log` 由 25,550 → 46,895 字节，18:59 那次会话完整回来（游标推进到 1789988387）。
动手前已把旧版备份为 `/tmp/m0-1-runtime-f70bf4b.log`，续拉后再备份为 `/tmp/m0-1-runtime-f70bf4b-backfilled.log`。
⚠️ 复核时踩到一条判据坑：我两次都是 `… logs watch | tail -N` 起的，**管道会把 `pulled: N` 这些行憋住不落到
`watcher.out.log`**，所以那个文件停在旧的 `stopped` 行并不代表 watcher 没在拉。活性只看
`state.json.updatedAt`（每 5s 推进）与 `runtime.log` 的字节数/mtime，别只看 out.log。

## 文档漂移（已于 2026-09-21 本会话内的知识库同步中修掉）
`AGENTS.md`「没有本地运行时」一节把进入 Lua 的判据写成 `[M0-0] 启动 M0-0 原型`，而本次入口日志是
`[M0-1] 启动 M0-1 竖切片`。经用户以 `/neat-freak` 授权做文档同步后已更正：判据改为 M0-1 并保留 M0-0 旧串作历史、
补上 runtime.log 的三个脾气（构建带 `--reset` 删本地日志、watcher 只活 4~8 分钟、`watcher.out.log` 不能判活性）、
「实施起点」推到 M0-1 已落地、「实测确立」清单由四条增为五条（新增 `focusable = false` 那条）。
同一批事实的完整口径落在 `docs/maker-lua-api-verification.md` §6 / §11 / §12.2 / §13、`README.md` 当前交接、
`CHANGELOG.md` 2026-09-21 条目。`StatusWindow.lua` 仍打 `[M0-0]` 前缀，那是状态窗自身模块，不改。

---

# PROGRESS — M1 首个可玩闭环（2026-09-21 起）

## 目标
若夕按洛杉矶当地时间真实处于 busy / offline / idle：忙碌与睡眠时消息只标「已送达」并排队（不显示已读），
进入下一个可回复窗口后短暂「正在输入」再用既定事件事实回复；两条以上按 FIFO 补发，重进不丢记录与队列。

## 执行顺序
① TimeState 给出可回复性与「下一次可回复 UTC」→ ② MessageService 单 pending 改 FIFO 队列（绝对 UTC 计划）
→ ③ MemoryService 存档升级为完整消息+队列+计划回复时间并在启动时恢复 → ④ Event/ContentService 按发送与交付两侧
的确定时间快照选事实（不捏造地点/活动/时间，离开期最多一条摘要）→ ⑤ ChatPanel/StatusWindow 接状态文案与场景降级。

## 最大风险
runtime.log 只在**有真实会话跑起来**时才产生，而会话只能由用户打开预览/扫码触发，我无法自动跑（历史三次证据都卡在这）；
缓解：新增 `scripts/services/DevSelfTest.lua` 开发自检，用可控 UTC 在真实 Lua 里跑完 busy/offline/idle、FIFO、
文件往返恢复与反向验证，任何 FAIL 都以 logError 落盘（ERROR=0 即全绿），用户开一次预览即可取全。

## 场景资产盘点结论
`assets/` 里唯一可作的场景静帧是 `Textures/backgrounds/la-cafe-4x3.png`（咖啡馆）；作息表另需 apartment /
campus / studio / commute 四类场景，**全部无资产**。本阶段不生成新资产：`scene_id` 只做尝试性切换，
无资产即显式沿用咖啡馆静帧降级并打日志，缺失资产与所阻塞的验收项记在 BLOCKED.md。

## 实施记录（2026-09-21 晚，按任务书顺序）

① **数据契约**（`scripts/TimeState.lua`）：作息表加回复策略
`REPLY_POLICY = { idle 可回/10s, fragments 可回/16s 且 brief, busy 排队, offline 排队 }`；
`Snapshot` 新增 `replyable / brief / availabilityLabel / sceneId`；新增
`NextReplyableUtc`（按当地整小时往后试 + 按分钟回退，DST 由 Snapshot 自身复核，24h 上限）、
`ReplyPlanFor`（→ `windowStartUtc` / `replyAtUtc`）、`UtcAtLocal`（反查当地整点的 UTC，自检用）、
`NowUtc() = common.get_server_time() + DevClockOffset`（全工程唯一取时刻处，偏移只由自检改写，正式会话恒为 0）。
② **FIFO**（`scripts/services/MessageService.lua`）：单 `pending_` 改 `queue_`；每条用户消息带
`planReplyAtUtc / planWindowStartUtc / replyableAtSend / brief / availabilityAtSend / placeAtSend / factId`；
相位改由**权威 UTC 绝对时刻**判定（`Update(utcNow)` 由外部注入，不再自己累帧）；
`ResolveReplyAtUtc` 用 `lastPlannedAtUtc_ + RESPONSE_GAP_SECONDS(4s)` 挡越序；过期队首只重排
`effReplyAtUtc`（不落盘），保证「短暂正在输入后交付」；新增 `Restore/GetHead/GetQueueLength/GetDueCount/
EntryStatusText/StatusLine`。
③ **存档**（`scripts/services/MemoryService.lua`）：v1→v2，落 `messages`（字段白名单 `toSaved`，
`effReplyAtUtc` 这类运行时字段不写盘）；只裁已回复的旧记录，**排队一条不丢**；`saveFile` 可注入
（自检用独立文件）；`ClearSavedData`；v1 的 `transcript` 摘要走同一条解析路径迁移为「已回复」记录，
`looksLikeMemory` 检查保留未放宽。
④ **事实与文案**（`EventService` / `ContentService`）：`FromSnapshot(snap, sentSnap)` 在补回复时带上
送达侧事实（`queued / thenPhrase / thenClock / gapSeconds`），前缀模板 `那会儿{before}，隔了{gap}才回你。`
三个变量全部来自确定时间快照，不新增地点/活动/时间；碎片时间走 `BRIEF_LINES` 短句池且不加话题后缀；
`AwaySummary` 一句（客观间隔 + 两头作息原话 + 待回条数），不做逐小时流水。
⑤ **UI**（`scripts/ui/ChatPanel.lua`）：用户气泡多一行状态 Label（已送达 / 已送达·对方在忙，已排队·第 N 位 /
若夕正在输入 / 已回复），行不重建、只 `SetText`，宽度按最长状态预留并允许换行；状态条给倒计时与
「她 06:00 之后能回」；`SetPhase` 加变化守卫（主循环每帧推，倒计时按秒才更新一次）。
⑥ **状态窗**（`scripts/StatusWindow.lua`）：`SCENE_BACKGROUNDS` 清单只有 `la_cafe`；
`RequestScene` 缺资产即留在当前静帧 + `logWarn` + `GetSceneNotice()` 上屏。

## 有意的行为变更（相对已验收的 M0-1，不是退化）
- 等待期间**再次发送不再被拒**，改为排队（M1 要求多条 FIFO）；因此「发送」按钮等待中不再禁用，
  文案变「继续发送」。空/纯空白草稿仍被拒且原文留在输入框（不打 ERROR）。
- 10 秒固定链路保留：空闲档 `planReplyAtUtc = 送达 + CONFIG.ReplyWaitSeconds`，
  sent 1.5s → waiting → typing 3.0s → replied 的相位与日志字面量（`状态迁移 sent/waiting/typing`、
  `跳过等待：从 … 直接推进到 replied`、`回复 #N → replied 事实=…`）与 M0-1 一致。
- 开场白/系统行只在**没有历史**时发；有历史时改为恢复并打「已恢复 N 条记录（其中 M 条待回复）」，
  避免每次重进多一条重复开场白。
- `MessageService.Init` 不再收 `waitSeconds`（唯一真源改为 `CONFIG.ReplyWaitSeconds` →
  `TimeState.SetReplyDelay("idle", …)`）。

## 门禁与构建证据（截至本行）
- Lua LSP `maker-lua-lsp --mode watch`（**非 check**）21:29:35 那一轮：`Lua Errors: 0`；
  我改的文件零 WARN（`StatusWindow.lua` 的 11 条 unnecessary-if 是既有 WARN，未新增）。
  迭代中真修掉的 ERROR/WARN：`then` 是 Lua 关键字不能当表键（语法错 9 条）、
  `SEASONS` 该写 `table<number,string>`、`lastPlannedAtUtc_` integer 源、
  `SyncQueueStates` 前向声明被推成可空、`head()` 二次调用不继承收窄、`Preview_` 冗余 nil 判断。
- M1 构建 #1：`fe739ec`（只含 9 个白名单脚本文件，`git show --stat` 核对）推到 Maker 后，
  CLI `taptap-maker build` 返回「🎉 项目构建成功」+ `preview_refresh {ok:true,status:200}` +
  watcher pid 5124 起（`--reset`）。MCP 侧两次 `-32603 invocation did not complete` 与
  CLI 顺带提交用户文档脏改动两件事记在 `BLOCKED.md` B-3。
- **自检覆盖矩阵**（`scripts/services/DevSelfTest.lua`，34 项断言）：
  A 空闲 10 秒链路（A0-A7，含「不早于计划时刻」）；B 碎片档更慢更短（B0-B3）；
  C 忙碌不立即回→17:00 窗口后带「在赶项目」经历回（C0-C7，含已送达无已读）；
  D 睡眠两条 FIFO 计划有序 + 醒来按序回完 + 不重复回（D0-D7，按回复原文回显判序）；
  E 落盘→重进恢复完整历史与两条队列顺序→到期按序补发→二次重进不重复（E0-E5）；
  F 反向验证：同一条时钟只把 `planReplyAtUtc` 推到 +300s → 60s 内不回（RED），
  换回存档里的真实计划 → 立刻按序交付（GREEN）；G 摘要只一行且无流水账（G1-G3）；
  H 摘要闸门（H0-H4）：新存档不补 / 离开不足阈值不补 / 够久且有到点消息才补 /
  没有到点消息不补 / **补完再重进不再补第二条**（防流水账的那道闸）。
  H 组能把「最多一条离开摘要」从「只能靠真机重进看」变成可断言：判定从 `BootChat`
  抽成了 `MemoryService.AwayGap(utcNow, dueCount, minGap)`，BootChat 只负责把 true 写成一条系统消息。
  FAIL 走 `logError`，所以「runtime.log ERROR=0」与「自检全绿」是同一件事。

## 还差的一步（不在代码侧）
完成条件 1 要的那一次真实会话日志需要人开预览（见 BLOCKED.md B-2）；
开一次预览就能同时拿到：自检 29 项 PASS/FAIL、真实发送、重进恢复、场景降级说明。

## 构建 #2 `e5bfb49`（修自检与两处收尾）：成功
构建 #1 的 commit 是 `fe739ec`，MCP 工具两次 `-32603 invocation did not complete`（commit+push 成功、
远端构建没跑到，判据：本地 runtime.log 未被 `--reset` 删、watcher 未重启），于是改走同一工具链的
CLI `taptap-maker build --target-dir …`：一次返回「🎉 项目构建成功」+ `preview_refresh {ok:true,status:200}`。
第二次构建（承载自检修复）同样成功：远端 HEAD == 本地 == `e5bfb49`，watcher pid 50380，
`state.json.updatedAt` 每 5s 推进、`lastWrittenLogs: 0`（还没有会话跑起来）。

构建 #2 带上去的三处修正：
1. **自检跨场景状态泄漏**（会让云端误红）：场景会把时钟往回拨（同一天先测 20:00 再测 12:00），
   而「后发不得越过先发」的水位是绝对 UTC，不清就把后一个场景的计划顶到前一个场景之后。
   现在每个场景开头 `beginScenario()`（清独立存档 + 重连真实服务）。
2. `HandleSend` 里空白草稿被拒不再打 ERROR（那是正常操作，不该污染「ERROR=0」这条判据）。
3. `ApplyScene` 去掉永不出现的 `"applied"` 分支。

LSP 门禁复核（21:51:05 那一轮 `--mode watch`）：**Lua Errors: 0**，非 `StatusWindow.lua` 的 WARN 为零。

## 构建 #3 `76823fb` / #4 `49f2cae`（把只能靠真机证明的判据改成可断言）：成功
- `76823fb`：把「离开期间摘要」的判定从 `BootChat` 抽成 `MemoryService.AwayGap(utcNow, dueCount, minGap)`，
  自检加场景 H（H0 新存档不补 / H1 不足阈值不补 / H2 够久且有到点消息才补 / H3 无到点消息不补 /
  **H4 补完再重进不再补第二条**）；同时补了 `GetDueCount`。共 34 项断言。
- `49f2cae`：`DevSelfTest.Run` 外面包 `pcall` —— 兜的是「自检自身出异常也不许把正式会话带崩」，
  因为 M0-1 已验收的启动链路不能因为一个开发工具而死；自检的断言失败本来就走 `logError`，
  所以这层保护不吞任何检查（异常同样打 ERROR，只是不再连带炸掉 UI 初始化）。
- 两轮 LSP：`Lua Errors: 0`（22:15:01 / 22:18:53），非 `StatusWindow.lua` 的 WARN 为 0。
- 边界自查（`f70bf4b..HEAD`）：`git diff --stat -- assets/ .project/` **为空**（没生成、没改任何资产与工程配置）；
  `scripts/` 内无 http/fetch/WebSocket/LLM 调用，云侧只有 M0-1 就存在且默认关闭的 `clientCloud` 异步适配器。

## 留给预览判读的一条视觉取舍
用户气泡的宽度按「最长可能状态文案」（`已送达 · 对方在忙，已排队 · 第 9 位`）预留，因为状态是行不重建、
只 `SetText` 换上去的（`Widget:ClearChildren` 会漏 Yoga 节点，M0-1 已定死增量刷新）。
后果：极短的用户消息气泡会比 M0-1 略宽。不改的原因是另一条路（按当前文案算宽）要求引擎在 `SetText`
后重算高度，而这条我没有证据——宁可宽一点，也不要状态文字被钉死宽度的气泡裁掉。开预览时请顺带判读一眼。

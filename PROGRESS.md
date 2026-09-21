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

## 待用户裁决（文档漂移，不在我的白名单）
`AGENTS.md`「没有本地运行时」一节把进入 Lua 的判据写成 `[M0-0] 启动 M0-0 原型`。本次入口日志改为 `[M0-1] 启动 M0-1 竖切片`，链路日志前缀分别是 `[MsgService] / [EventService] / [Memory] / [ChatPanel]`，回复落点为 `[M0-1] 回复 #N → replied 事实=la_cafe_open_mic`。`StatusWindow.lua` 仍打 `[M0-0]`，所以那一段老判据里只有这一句需要更新，等用户改 AGENTS.md（我不改）。

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

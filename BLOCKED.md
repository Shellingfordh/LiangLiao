# BLOCKED — M0-1 聊天竖切片（2026-09-21）

Maker 项目状态本身**不是阻塞**：`maker_status_lite` 返回 project bound / git ready / lua_lsp ready / pat found / **status ready**。以下是本阶段真实卡住的点。

## 1. sent → waiting → typing → replied 仍缺运行时证据（未解，但只差一次点击）
- **预览画面已拿到**（2026-09-21 17:10 用户自己打开预览并回传截图）：状态窗、时间行、系统说明、若夕开场气泡、记忆摘要行、预填原文的输入框、发送按钮、禁用的「跳过等待」全部同屏成立。截图同时暴露并修掉了两个缺陷（气泡宽度塌陷、凌晨把活动说成「还没开始」），见 PROGRESS.md 构建 #3。
- **日志为什么还是 0 条**：用户那次会话落在 watcher 的死亡窗口里。`state.json` 心跳停在 `08:57:22Z`，`watcher.out.log` 末尾是 `Maker runtime log watcher stopped`，`watcher.pid` 已被删——即项目记忆里那条「CLI watcher 会在十几分钟内静默消失」。我 09:17 手工重启过一次，随后构建 #3 又按工具链行为带 `--reset` 重启了它（`watch_pid: 39000`，心跳已贴着当前时间）。
- **后果**：09:10 那次会话的日志落在死亡窗口内，加上重启把游标推到当下与 1 小时窗口上限，**那批日志取不回来了**。所以闭环仍需一次新会话。
- **解锁只需一步**：在预览页**硬刷新**（工具链的 `preview-refresh` 刷不到浏览器 IndexedDB 缓存）加载 `4bde79c`，点一次「发送」（输入框已预填），等 10 秒；想验第二条路径就再发一条并立刻点「跳过等待」。我这边 watcher 活着，会直接把下面这几行摘进 PROGRESS.md：
  `[M0-1] 启动 M0-1 竖切片` → `[MsgService] 用户消息 #N 已发出` → `状态迁移 sent/waiting/typing` → `[M0-1] 回复 #N → replied 事实=la_cafe_open_mic`，且全程无 `ERROR`。
- 我这边试过且无效的：`mcp__browser-use__navigate_page`、`mcp__playwright__browser_navigate` 各一次，均被宿主权限层 `Auto mode: action blocked by classifier` 拦下（即使用户随后明确选了授权，分类器仍独立阻断）；我没有换姿势绕。本机无 lua/luajit/UrhoXCLI，不能离线跑状态机，也不用自动发送伪造闭环。

## 2. 构建工具链改了白名单外的 AGENTS.md（非我所为，已核无损）
`maker_build_current_directory` 的自动提交（author `taptap-maker <maker-mcp@local>`）把 `AGENTS.md` 重排了：`+82 / -80`。按排序后逐行比对，**项目自有内容零丢失**，唯一净新增是 2 个空行——是工具链把自己那段 `TapTap Maker Project Asset Tool Policy` 挪到文件头。我按约束没有手改这个文件，也**不建议回滚**（回滚会再造一个 commit，且远端已收到工具链这一版）。列为需用户裁决项。

## 3. 构建失败次数：0（三次全绿）
`415cb4c`（任务 1+2 同批）→ `fd87d29`（状态文档）→ `4bde79c`（两个预览实测缺陷修复），每次都 `[remote_build] 100% 构建流程全部完成` + `preview_refresh_status: 200`，本地 HEAD 与 `git ls-remote maker HEAD` 一致。无「连续 3 次构建失败」情形；未生成测试二维码、未扫码、未动 Git 配置、未装依赖、未接外部后端、无 LLM 调用。

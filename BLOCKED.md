# BLOCKED — M0-1 聊天竖切片（2026-09-21）

Maker 项目状态本身**不是阻塞**：`maker_status_lite` 返回 project bound / git ready / lua_lsp ready / pat found / **status ready**。以下是本阶段真实卡住的点。

## 1.（已解）sent → waiting → typing → replied 的运行时证据
2026-09-21 18:03–18:04 在构建 `4bde79c` 上跑通并已转录进 PROGRESS.md「闭环运行时证据」一节：
`用户消息 #3 已发出 → 状态迁移 sent → waiting → typing → 若夕回复 #4 → replied → idle`，全程 `grep -c ERROR` = 0。
同批日志还证到：重复发送被拒且草稿保留、`记忆来源` 由 `memory` 翻成 `file`（本地存档写入 372 字节）、
03:03 走 `ended` 分支不再自相矛盾、`UTC-7 DST=true` 与九月美西一致。

**为什么前两次没拿到**：日志抓取器两次静默死亡（`watcher.pid` 被删、心跳分别停在 08:57:22Z 与 09:30:50Z），
用户两次会话都正好落在死亡窗口里。恢复办法（有效，值得复用）：**按 `state.json` 的 `nextStartTime` 游标重启且不加 `--reset`**，
一次就把 22642 字节历史日志拉回来了（1 小时窗口内）。

**仍未闭环的两条**（都需要一次人工交互，代码侧已就绪）：
1. 「跳过等待」按钮路径的日志——截图里按钮已正确点亮，但没人点过，日志没有 `跳过等待：从 …` 行；
2. 气泡排版是否在 `a539dda` 上真的恢复正常（`4bde79c` 上确定宽度已生效但仍一行 4 字，根因是容器被同层 `nowrap` 角标撑宽，已改为按字数估算后钉死）。
解锁：硬刷新预览加载 `a539dda`，看一张截图，再发一条并立刻点「跳过等待」。

## 2. 构建工具链改了白名单外的 AGENTS.md（非我所为，已核无损）
`maker_build_current_directory` 的自动提交（author `taptap-maker <maker-mcp@local>`）把 `AGENTS.md` 重排了：`+82 / -80`。按排序后逐行比对，**项目自有内容零丢失**，唯一净新增是 2 个空行——是工具链把自己那段 `TapTap Maker Project Asset Tool Policy` 挪到文件头。我按约束没有手改这个文件，也**不建议回滚**（回滚会再造一个 commit，且远端已收到工具链这一版）。列为需用户裁决项。

## 3. 构建失败次数：0（四次全绿）
`415cb4c`（任务 1+2）→ `fd87d29`（状态文档）→ `4bde79c`（气泡确定宽度 + 凌晨事实分支）→ `a539dda`（气泡宽度钉成估算值），
每次都 `[remote_build] 100% 构建流程全部完成` + `preview_refresh_status: 200`，本地 HEAD 与 `git ls-remote maker HEAD` 一致。
无「连续 3 次构建失败」情形；未生成测试二维码、未扫码、未动 Git 配置、未装依赖、未接外部后端、无 LLM 调用。

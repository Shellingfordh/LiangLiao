# BLOCKED — M0-1 聊天竖切片（2026-09-21）

Maker 项目状态本身**不是阻塞**：`maker_status_lite` 返回 project bound / git ready / lua_lsp ready / pat found / **status ready**。以下是本阶段真实卡住的点。

## 1.（已解）sent → waiting → typing → replied 的运行时证据
2026-09-21 18:03–18:04 在构建 `4bde79c` 上跑通并已转录进 PROGRESS.md「闭环运行时证据」一节：
`用户消息 #3 已发出 → 状态迁移 sent → waiting → typing → 若夕回复 #4 → replied → idle`，全程 `grep -c ERROR` = 0。
同批日志还证到：重复发送被拒且草稿保留、`记忆来源` 由 `memory` 翻成 `file`（本地存档写入 372 字节）、
03:03 走 `ended` 分支不再自相矛盾、`UTC-7 DST=true` 与九月美西一致。

**为什么前两次没拿到**：日志抓取器三次静默死亡（`watcher.pid` 被删、心跳分别停在 08:57:22Z、09:30:50Z、10:43:45Z），
用户会话三次都正好落在死亡窗口里。恢复办法（三次都有效）：**按 `state.json` 的 `nextStartTime` 游标重启且不加 `--reset`**，
一次就把 22642 字节（第一次）/ 21345 字节（18:59 那次）历史日志拉回来（1 小时窗口内）。

**当年挂在这里的两条也已闭环**：「跳过等待」在 18:23:24 被真实点到（`跳过等待：从 waiting 直接推进到 replied`，走同一 `Deliver()` 生成路径）；
气泡排版在 `a539dda` 上经用户截图确认恢复正常；`f70bf4b`（18:59 会话）又跑通一次完整 10 秒链路且叠标点消失，见 PROGRESS.md「构建 #5」。

**本阶段真正剩下的只有两件，都不在代码侧**：
1. **我拿不到预览画面**——浏览器路径（browser-use 导航、playwright 导航）在用户已口头授权后仍被宿主权限层拦成
   `Auto mode: action blocked by classifier`，所以所有视觉判读都来自用户截图，不是我自己看到的；
2. **点击与回车无法从日志文本区分**（两条路径汇入同一个 `HandleSend`）。点击可用的直接证据是用户实测，日志侧只有时序旁证
   （18:59 那次发送在页面重载后 4.3 秒、草稿未改动）。要把它做成硬证据，需在 `HandleSend` 加一个来源标签再构建一轮。

## 2. 构建工具链改了白名单外的 AGENTS.md（非我所为，已核无损）
`maker_build_current_directory` 的自动提交（author `taptap-maker <maker-mcp@local>`）把 `AGENTS.md` 重排了：`+82 / -80`。按排序后逐行比对，**项目自有内容零丢失**，唯一净新增是 2 个空行——是工具链把自己那段 `TapTap Maker Project Asset Tool Policy` 挪到文件头。我按约束没有手改这个文件，也**不建议回滚**（回滚会再造一个 commit，且远端已收到工具链这一版）。列为需用户裁决项。
注：本阶段执行边界原本写着「不得改 AGENTS.md」，所以构建之前我一直没碰它；后来用户以 `/neat-freak` 要求做知识库同步，
才按授权更新了其中的过期事实（runtime.log 判据字符串、「实施起点」推到 M0-1、「实测确立」清单四条→五条）。
**工具链那次重排与我的内容修改是两件事**：重排仍不建议回滚，内容更新见 CHANGELOG 2026-09-21「Changed」。

## 3. 构建失败次数：0（五次全绿）
`415cb4c`（任务 1+2）→ `fd87d29`（状态文档）→ `4bde79c`（气泡确定宽度 + 凌晨事实分支）→ `a539dda`（气泡宽度钉成估算值）
→ `f70bf4b`（发送按钮 `focusable=false` + 叠标点守卫），
每次都 `[remote_build] 100% 构建流程全部完成` + `preview_refresh_status: 200`，本地 HEAD 与 `git ls-remote maker HEAD` 一致。
19:07 复核两边同为 `f70bf4b`、工作树干净。此后本地未提交的改动**全部是文档层**：`AGENTS.md`、`README.md`、
`CHANGELOG.md`、`docs/maker-lua-api-verification.md`、`docs/platform-capabilities.md`、`docs/asset-provenance.md`
与本文件、`PROGRESS.md`（`git diff --name-only` 就这 8 个，`scripts/` 与 `assets/` 零改动）。
按边界「不提交/推送」我没有为文档单独跑第六次构建，下次真实构建会自动带上。
无「连续 3 次构建失败」情形；未生成测试二维码、未扫码、未动 Git 配置、未装依赖、未接外部后端、无 LLM 调用。

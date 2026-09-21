# BLOCKED — M0-1 聊天竖切片（2026-09-21）

Maker 项目状态本身**不是阻塞**：`maker_status_lite` 返回 project bound / git ready / lua_lsp ready / pat found / **status ready**。以下是本阶段真实卡住的点。

## 1. sent → waiting → typing → replied 缺运行时证据（未解）
- **事实**：云端构建成功（`415cb4c`，`[remote_build] 100% 构建流程全部完成`，`preview_refresh_status: 200`），但 `.maker/logs/runtime/runtime.log` 至今**不存在**。日志抓取器活着：`state.json` 的 `lastSuccessAt` 每 5 秒推进、`consecutiveFailures: 0`、`lastError: null`，`watcher.out.log` 持续 `Maker runtime logs pulled: 0`。
- **根因**：Maker 运行时日志只在**有游戏会话真的跑起来**之后才产生，而跑起来只能靠打开云端预览；本项目没有本地运行时，本机也没有 lua/luajit/UrhoXCLI 可离线驱动状态机。
- **我试过的**：`mcp__browser-use__navigate_page` 与 `mcp__playwright__browser_navigate` 各一次去开 `https://maker.taptap.cn/app/720b27bf-ca69-44ac-a776-a88ec2ec2b28?localDev=1`，两次都被宿主权限层以 `Auto mode: action blocked by classifier` 拦下（即使用户随后在选项里选了「授权我开你的 Chrome 跑预览」，分类器仍独立阻断；我没有换姿势绕过）。
- **解锁只需一步**（任一条，之后我读日志即可闭环）：
  1. 用户在已登录 TapTap 的 Chrome 里打开上面的预览地址，等画面出来后点一次「发送」（输入框已预填 `你那边是不是快傍晚了？今天的活动还顺利吗？`），等 10 秒；
  2. 或点「发送」后立刻点「跳过等待」，验第二条路径；
  3. 或给本会话的浏览器导航放开权限，我自己点、自己读。
- 期间我会在 `runtime.log` 里看到的判据：`[M0-1] 启动 M0-1 竖切片`、`[MsgService] 状态迁移 sent/waiting/typing`、`[M0-1] 回复 #N → replied 事实=la_cafe_open_mic ...`，且整段无 `ERROR`。

## 2. 构建工具链改了白名单外的 AGENTS.md（非我所为，已核无损）
`maker_build_current_directory` 的自动提交（author `taptap-maker <maker-mcp@local>`）把 `AGENTS.md` 重排了：`+82 / -80`。按排序后逐行比对，**项目自有内容零丢失**，唯一净新增是 2 个空行——是工具链把自己那段 `TapTap Maker Project Asset Tool Policy` 挪到文件头。我按约束没有手改这个文件，也**不建议回滚**（回滚会再造一个 commit，且远端已收到工具链这一版）。列为需用户裁决项。

## 3. 构建失败次数：0
无「连续 3 次构建失败」情形；本阶段只跑了 1 次构建（任务 1 与任务 2 在同一批落地，故合并为一次检查点），未生成测试二维码、未扫码、未动 Git 配置、未装依赖、未接外部后端、无 LLM 调用。

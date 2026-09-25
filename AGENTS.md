<!-- >>> TapTap Maker managed AGENTS policy version=3 hash=sha256:9c5d550755a0d1a3e40606e2e4b35fd3e7c5232057490debc4c82197ef46ff9e >>> -->
# TapTap Maker Project Asset Tool Policy

This is a bound TapTap Maker project.
Do not use TapTap Developer Center documentation or docs for other TapTap game platforms
when developing or debugging this Maker game; use Maker MCP and the project-local
`AGENTS.md`, `engine-docs/`, `examples/`, `templates/`, `urhox-libs/`, and installed Maker
skills as the sources of truth.

TapTap Maker routing index:
- Start or resume Maker work, or diagnose project/MCP readiness: read
  maker://status; use maker_status_lite when resources are unavailable.
- Build, preview, run, submit, or push: after checking project status, use
  maker_build_current_directory.
- Ads: read maker://ads-integration-guide before any ad-related work.
- Tap flows: test QR -> generate_test_qrcode.
- Game assets: Maker MCP also provides image, video, music, sound-effect,
  dialogue/voice, and 3D generation tools when exposed.
- MCP/proxy infrastructure failure: diagnose, ask once for user consent, then use the
  active client's exact Maker command/args with `mcp report`; never use an unversioned npm package. Do not report expected project or business errors.
Follow the selected tool schema and returned next_action.

Maker build workflow:

- For user requests such as 构建, build, 预览, 跑一下, 查看结果, 看看效果, 验证游戏效果,
  提交, 提交代码, 推送, or push, call `maker_build_current_directory`.
- Do not tell the user to open the Maker web page and click a build button as the default flow.
- Do not use generic Git commit, push, branch, PR, or MR workflows for Maker submit/build
  requests. Follow the result returned by `maker_build_current_directory`.

Generic code checks such as 验证代码, 跑测试, lint, or 检查实现 should not trigger a Maker
remote build unless the user explicitly asks to build, run, or preview the Maker game.
- Preview, build, test, and local-development intent must never select or change the service
  environment. Do not add environment parameters to Maker tool calls or user MCP config;
  use the default Maker service configuration.

Maker MCP connection recovery:

- If tools are missing, the process exits immediately, or the client reports `-32000`,
  `Connection closed`, or `command not found`, do not depend on Maker MCP tools for initial
  diagnosis. Work from local config, shell output, and client logs.
- Current Maker MCP registers whitelisted proxy tool definitions before resolving cwd, project
  binding, auth, or the remote proxy. If only proxy tools are missing, compare the active
  package version and tools/list for stale client/session caching; do not rewrite cwd.
- Attempt `taptap-maker mcp verify --json`. It verifies the stable self runtime by default;
  use `--mode npx` only when the npm launch path itself needs diagnosis. Record command failure
  as diagnostic evidence instead of skipping the check.
- If `taptap-maker` is not on PATH, reuse that config's absolute command and ordered args,
  append `mcp verify --json`, and run the same argv directly.
- This uses the same stable launcher as MCP install and completes MCP
  initialize and tools/list, and returns launcher_kind, command, stage, tools, stderr, error,
  and failure_type. It does not read the client's active config or validate client trust,
  client config caching, or Roots.
- In explicit npx mode, EPERM/EACCES or an unwritable npm cache is
  `npm_environment_error`; prefer `mcp install --launcher self` instead of blindly changing
  `~/.npm` ownership.
- First identify the active AI client from reliable evidence, then inspect only that client's
  active config path, command, ordered args, cwd, workspace/Roots, Node/npm/npx paths,
  client PATH, exit status, and stderr.
- Only when the active client is confirmed to be WorkBuddy, inspect its enable/trust state.
- Never use one client's configuration or trust state to diagnose another client.
- Classify the root cause from evidence before repairing it. Do not automatically change trust
  storage, PATH, cwd, credentials, or game code.
- Treat `taptap-maker mcp install --ide <client>` as an optional recovery only after evidence
  confirms that the active config entry is damaged.
- Never repair cwd by wrapping the command with `cd /d "<project>" && npx.cmd ...`.
  Maker supports Chinese project paths; command-shell quoting or client startup can fail
  independently of the project path.
- User-level MCP config must not contain a project cwd. If WorkBuddy or DSH does not expose Roots,
  pass target_dir on the concrete Maker tool call and record the process actual cwd only as
  diagnostic evidence.
- If cwd fallback is not a bound Maker project, project-related proxy calls fail before remote
  access and report evaluated_target_dir plus project_context_source. Fix Roots or pass the
  correct target_dir; do not treat another directory as the project status.
- Do not assume Windows 8.3 short paths exist or differ from the original long path. Verify
  the result first; an unchanged or missing short path is not a usable cwd workaround.
- Reproduce the configured Windows launch with the same direct argv boundary when possible.
  Separate outer shell quoting or stderr decoding failures from the MCP child process result,
  and record both without treating wrapper failures as server evidence.
- AI conversations share user-level MCP config. Back up the active config before any repair,
  then reconnect and verify in both the current and a new conversation.
- If the MCP connection is established but a tool or resource call fails, including `-32003`,
  use a separate evidence-first runtime-error workflow. Do not assign a fixed meaning to the
  error code; preserve the exact client error.
- `mcp verify` is not the primary check for an already connected session because it tests only
  the local launcher and stdio MCP path.
- Collect the failed tool/resource, redacted request parameters, current `tools/list`, exact
  error code/message/data, complete sanitized `remote_result`, request/correlation IDs,
  timestamp with timezone, OS/architecture, AI client and `@taptap/maker` package versions,
  and stable reproduction steps. Preserve useful nested fields while removing credentials.
- Python and maker-lua-lsp affect local Lua diagnostics, not MCP connection or remote build.
- Dev-kit, package update, and AGENTS policy checks are maintenance checks, not proof of a
  client connection failure.
- Do not rewrite command, cwd, PATH, trust state, credentials, or game code unless the
  collected evidence identifies that cause.

Maker MCP issue reporting:

- Offer a report only for likely MCP, proxy, client integration, or service defects such as
  startup/connection failure, unexpected missing tools, timeouts, repeated reconnect failure,
  HTTP 5xx/unavailable responses, or unclassified internal server errors.
- Do not report expected user or project errors such as invalid parameters, missing files,
  documented auth recovery, user cancellation, project compile errors, or business validation.
- Ask the user once before submitting each distinct failure fingerprint. If the user declines,
  do not ask again for that fingerprint in the current conversation.
- Only after the user explicitly agrees, send a compact sanitized context JSON through stdin.
- Prefer the active client's exact Maker MCP command and ordered args, then append
  `mcp report --ide <client> --target-dir <project> --context-stdin --consent --json`.
- This preserves the configured package version and the absolute Windows node.exe/npm-cli.js.
- Only with a known exact installed version, fallback to
  `npx -y --package @taptap/maker@0.0.33 taptap-maker mcp report ...`.
- Never use an unversioned npm package, or assume `taptap-maker`/`npx` is globally available.
- Never include the complete conversation, project source, other MCP server entries, PAT/token
  values, or full environment variables. Normalize the user home path to `~`.
- A `manual_required` result means GitHub submission was unavailable. Show the sanitized report
  and manual Issue URL, then continue troubleshooting without treating reporting as a failure.

Maker ad workflow:

- For any ad-related request or code touching ads, first read
  `maker://ads-integration-guide`, then follow it to inspect Maker project status, call
  `get_ad_config`, and read the project engine document before editing ad code or testing
  ad behavior. Triggers include 广告, 激励视频,
  播放广告, ad ID, ad placement, ad status, ad config, and `ShowRewardVideoAd`.
- Treat `get_ad_config` as the source of truth for current project ad activation status and
  ad config. Do not infer ad readiness from local SDK docs, `.maker-mcp/config.json`, or
  runtime callbacks.
- If primary local project configs are missing, keep ad config unavailable and do not call the
  remote tool. Build only for an explicit user build/submit/preview request. If a successful
  build still leaves local configs missing, explain the known limitation and do not rebuild
  automatically. Implement or test ad code only after the config is available.
- If `get_ad_config` reports missing `app_id` or `developer_id`, call
  `generate_test_qrcode` once to generate test QR code metadata, then call `get_ad_config`
  again. Do not use publish-only tools for this recovery path.

Maker MCP provides the following game asset generation and editing tools when they are
exposed in the current session:

- `generate_image` for one image asset.
- `batch_generate_images` for multiple image assets.
- `edit_image` for modifying existing project images.
- `create_video_task` for game video assets or referenced image/video generation.
- Only call `create_video_task` after the user explicitly requests video generation; do not
  generate video proactively while implementing gameplay or filling asset gaps.
- When duration exceeds 10 seconds or `model="2.5"`, show the rough credit estimate and
  upstream-token billing disclaimer, wait for explicit confirmation, then repeat the same
  request with `user_confirmed=true`.
- `query_video_task` for refreshing video task status and fetching completed videos.
- `text_to_music` for game music.
- `text_to_sound_effect` for one sound effect.
- `batch_sound_effects` for multiple sound effects.
- `text_to_dialogue` for final character dialogue.
- `text_to_dialogue` reuses confirmed local ElevenLabs voice mappings. After confirmation, pass only `character_name` and `text`.
- For ElevenLabs auditions, pass a detailed `character_description` and an `audition_line` of at least 100 characters. `candidate_count` is optional and accepts 1 to 3.
- After `audition_voices_for_character` returns previews, show them to the user and wait
  for the user to choose. Do not select or confirm a voice automatically.
- Call `confirm_character_voice` only after the user explicitly chooses one preview.
- Generated sound effects and dialogue are saved in the project.
- Voice audition previews are not saved to the project.
- Local MCP does not transcode generated audio to OGG.
- `create_3d_asset` for the complete 3D lifecycle: start, query, explicit review continuation,
  option inspection, and post-processing.
- Never automatically continue a 3D review step. Show returned previews and wait for explicit
  user approval before calling `create_3d_asset` with `action="continue"`.
- Follow the selected tool schema when one of these tools is used.

Follow each Maker tool schema for supported local path, remote URL, and data URL inputs.
If the user references attached/local media, inspect the attachment or workspace file path
before calling the tool. Local proxy may convert resolvable local reference media to data URLs
before forwarding to the remote Maker MCP server.

Generated Maker proxy assets should stay in the Maker project asset workflow under
`assets/image`, `assets/video`, `assets/audio`, or `assets/model`, with remote mappings
preserved for later edits and builds.
`create_3d_asset` local runtime `model_files` copy/extract instructions are materialized into
`assets/model`. Use `local_delivery` for the usable local model path and preserve the remote result.
<!-- <<< TapTap Maker managed AGENTS policy <<< -->


# AGENTS — 项目背景

《送给你这个回来的人》是 Tripothon S1 的原创陪伴体验：用户与一位生活在另一座城市、同一真实时间线上的角色聊天；她有自己的日程与关系网络，3D 状态窗展示她此刻的生活。

## 硬边界

- 只使用原创角色、场景、文本、音乐和视觉资产；不得复刻现有 IP。
- 聊天优先；3D 窗口是固定镜头状态展示，不做开放大地图。
- Lua 负责时间、状态、事件事实和存档；生成式文本只能润色既定事实。
- 不接入真实天气、新闻或运行时 Tripo/Marble 调用；离线状态按时间窗反推。
- Marble 高质量网格不得直接作为移动端主场景，除非先通过 Maker 真机性能 Spike。

以下五条为 2026-09-18/19 与 2026-09-21 在 Maker AI Dev Kit 中实测确立，违反即返工（证据见
`docs/maker-lua-api-verification.md`）：

- **运行时没有 LLM 接口。** Maker 的 `text_to_dialogue` 等是构建期 MCP 工具，不是游戏运行时 API。
  回复一律走 Lua 模板 + 变量替换；不得假设"生成式润色"这条路存在。
- **引擎没有 IANA 时区库。** 四城各用一张带生效区间的 UTC 偏移表；时间源必须是
  `common.get_server_time()`（权威 UTC，用户改系统时间无效）；`os.date` 必须带 `"!"` 前缀，
  否则会叠加运行设备本地时区。
- **GLB 不是运行时格式。** 必须经 `UrhoXCLI import-gltf` 转成 MDL + 材质 + 纹理 + prefab 后，
  运行时才 `cache:GetResource("Model", ...)`。
- **API 依据只有本地 AI Dev Kit。** `engine-docs/`、`.emmylua/`、`examples/`、`templates/`、
  `urhox-libs/` 为准；`research/taptap-pages/` 是登录墙快照（38 份中 27 份内容相同），无效。
- **软键盘输入框旁边的按钮必须 `focusable = false`。** 否则点按钮会先让输入框失焦、收起键盘，画布高度变化让
  整棵布局位移，而 `UI.lua` 的 `HandlePointerUp` 只在按下与抬起命中同一控件时才派发 `OnClick`——
  结果是**点击静默无效、不报任何错**（2026-09-21 实测，见
  `docs/maker-lua-api-verification.md` §13）。日志区分不出点击与回车。
  两条同族的引擎事实，2026-09-25 由控件树取证抓到，写控件时必须照做：
  ① **`focusable` 只有实例赋值才生效**——派发焦点时读的是实例上的 `widget.focusable`，
  属性 `UI.Button{ focusable = false }` 单独放着是**装饰**，必须补一句 `btn.focusable = false`
  （仓库里 `ProfileOverlay`/`SettingsOverlay`/`ChatPanel` 都是两道一起写，别只写属性那道）；
  只挂 `OnPointerDown` 的控件不受这条影响（按下即动作，不等抬起），可保持原样。
  **但别把这条外推到 `pointerEvents`——它读的层正好相反**：`UI.lua` 的 `findWidgetAt` 通篇读
  `widget.props.pointerEvents`（`SetStyle` 会把 style 并进 `props`），所以
  `UI.Panel{ pointerEvents = "none" }` 单独放着就**有效**，反过来只在实例上写
  `w.pointerEvents = "none"` 是装饰。2026-09-25 用引擎自己的 `UI.FindWidgetAt` 做 A/B 实测过双向
  （含把发送按钮改成 `none` 的反向对照），口径见
  `docs/maker-lua-api-verification.md` §18。两条各自成立，一道管另一道会写出静默失效的控件。
  ② **`props.children` 里不许有可空项**：`Widget.lua` 的 `ProcessChildren` 用 `ipairs` 遍历，
  **碰到 nil 空洞直接停止**，其后所有子树都不再挂载，
  而 `IsVisible()` 之类只读控件自己的标记，照样返回 true——整层 UI 可以「代码里在建、日志里没有、
  屏幕上不存在」。条件产物（如 `CONFIG.DevTools` 关掉的测试台）请用 `parent:InsertChild(w, index)` 补挂，
  不进字面量。
  ③ **主操作一律挂 `OnPointerDown`，且点选不许改变自身容器的高度**。同一条 `OnClick`
  抬起命中条件还有第二种触发方式，与软键盘无关：垂直居中（`justifyContent="center"`）的卡片里
  任何随行数变化的文本（预览/提示行）都会**改卡片高度、把全部可点区一起挪位**，用户下一拍瞄的是
  旧布局——落在隔壁控件 = **静默提交错值**（比丢点击更坏），落在空白 = 静默丢弃。
  2026-09-26 M5「新故事选了上海×前同事落成成都×高中同学」就是这么来的（`ProfileOverlay` 当时是
  全工程唯一把主操作挂在 `OnClick` 上的覆盖层）。写带选中态的 chips/列表时就做两件事：按下即回调，
  以及给会变的文本写死 `height`（按窄屏换行留量，别按宽屏估）。

## Git 拓扑（2026-09-19 用户改定：只推 Maker）

- **所有推送只发 `maker`**（Maker 云端工程仓）。GitHub 那条**暂时不管**，不再作为 upstream。
- `origin` 与 `maker` 现指向同一个 Maker URL（`.git/config` 中该 URL 内嵌临时 token，勿外传）。
  Maker 工具链（`init` / `build` / 连只读的 `logs watch`）会反复把 `origin` 抢回 Maker URL，
  **这是预期行为，不要再手工纠正**；跑完 `logs watch` 也不必备份还原。
- `github` = `git@github.com:melondy101/LiangLiao.git`，仅作为设计文档仓的**只读留档把手**保留，
  未推之前不要假设它和 main 同步。
- 两条历史**已合并成一棵树**（`a23e2ba` 以 `--allow-unrelated-histories` 并入），"无共同祖先"已失效。
  仍然**禁止在 GitHub 与 Maker 之间 force push**。
- 归属约定不变：`scripts/`、`assets/`、`.project/` 属 Maker 工程；`docs/`、`research/`、`README.md`、
  `CHANGELOG.md` 属文档。两者现在同在一棵工作树里，推 Maker 时会一起带走。

## 权威文档

| 文件 | 用途 |
| --- | --- |
| `docs/2026-09-15-parallel-companion-design.md` | 产品、数据模型、时间状态、场景、PoC 范围与验收 |
| `docs/PRD.md` | 产品范围与验收主文档（v2.2，2026-09-26 重写）：**§5.3 是 M4 产品验收与证据边界，§6 是 M5–M10 阶段路线**；实施状态一律以 `CHANGELOG.md` 为准 |
| `docs/2026-09-26-stage-roadmap.md` | M5–M10 阶段卡：每阶段的手脚/资产/平台外部条件与「未交付」边界（PRD §6 的展开） |
| `docs/superpowers/specs/2026-09-24-m4-perceivable-parallel-life-design.md` | M4 详细执行规范与验收（人生存档 / 三入口 / 16 场景包 / 2.5D 痕迹 / 骨骼边界） |
| `docs/platform-capabilities.md` | Tripo、Marble、TapTap Maker 的能力、格式、资产流程与限制 |
| `docs/3d-scene-character-movement.md` | 3D 场景与角色移动的分层方案（T1–T5）、每层的确定性证据、Tripo/Marble 本地可操作性、当前 3D 体量预算 |
| `docs/maker-lua-api-verification.md` | Maker 平台假设逐项验证（时区 / 运行时 LLM / GLB→MDL / clientCloud / 全景 / 预览 0% 定性与收尾 runbook） |
| `docs/2026-09-23-m2b-llm-gateway-design.md` | M2-B 外部 LLM 润色网关：契约、鉴权、限流、回落与实施状态（§12：代码就位、未部署未接线） |
| `docs/2026-09-24-m3-four-city-init-design.md` | M3 四城初始化与关系档案：可复现随机、存档 v5 语义与验收 |
| `docs/asset-provenance.md` | 资产唯一真源表、GLB/MDL 实测差异、重导入命令、M0-1 阻塞项 |
| `docs/demand.md` | Tripothon S1 赛事规则与提交物 |
| `CHANGELOG.md` | 当前阶段与已完成决策 |

`research/game-design-sources/` 保留非 IP 的通用竞品、叙事、关系系统与生活模拟原始调研；不得恢复其旧的 `bocchi/` 目录或以原作角色为查询目标。

## 实施起点

1. 分层与入口：`scripts/main.lua`（唯一的 `Update` 订阅方，逐帧驱动各模块的 `Tick`）、
   `scripts/StatusWindow.lua`（3D 状态窗与取景）、`scripts/services/`（Message / Event / Content /
   Memory / Life / Scene 等服务）、`scripts/ui/`（ChatPanel + 三个覆盖层 + 只读档案页）。
   后端就在同一工程内，**没有外部后端、没有运行时 LLM**；记忆走本地文件，`clientCloud` 只留接口。
2. 随构建打包那条别忘：新背景要显式列进 `.project/resources.json` 的 `groups.default` 与
   `preload_groups`（该项目无独立 `**`，属增强引用模式，不可达资源会被裁出包）。
3. 各阶段进展与验收状态**只看 `CHANGELOG.md` 与 `BLOCKED.md`**：M0-0/M0-1（2026-09-21 真机确认）
   → M1（09-22）→ M2-A/M2-B（09-23/24）→ M3（09-24）→ M4（09-25，用户按编辑器预览判完成，
   真机项转发布前回归见 B-6）→ M5（09-26，可控的新故事：显式选择落地；本地判过，真机未跑）。
4. 仍缺的交付物都要人操作，git/MCP 代不了（清单与判据见 `BLOCKED.md` B-6）：一张「冷启动后隔一会儿
   再截同一画面」的真机稳定截图、Maker 网页端「发布到 TapTap → 游戏基本信息 → 游戏 icon」生效
   （`game_material/*` 被远端 pre-receive 排除）。

不要恢复或引用已移除的旧"三位 NPC 小镇"方案、旧角色名或旧 PoC 模板。

## 本地运行时与云端验证的分工

**本地有一个 Windows 运行时，能跑、能出图，但它不是云端构建的替代品**（2026-09-23 实测，证据与完整口径见
`docs/3d-scene-character-movement.md` §2）。

入口在**主仓** `D:/Develop/ShanTianLiang/.cli/rt/UrhoXRuntime.exe`（`.cli/` 被 gitignore，**worktree 里没有**，
只能按绝对路径用）。参数与 Maker CLI 内部一致，**`cwd` 必须是 `<source>`**：

```
UrhoXRuntime.exe <entry.lua> -tapcode_dir=<source> -skip_login -p=Res -w -width=1080 -height=1920
```

已实证用途：**3D 链路取证**（真实项目资产的渲染 + 固定相机 + 角色沿预设路径移动，已用 `Image:SavePNG`
落出 3 张真实渲染像素）、**整游逻辑取证**（见边界 3）、**16 场景装载取证**。四条边界，别再重新踩：

1. **落盘取证两条通道**：`Image:SavePNG` 与 `File(path, FILE_WRITE)` + `WriteString`。`io` 库整体为 `nil`；
   `File` 写入被固定在 `Documents/temp/savedata/<project>/<userId>/`，**子目录必须预先存在**，否则 `SavePNG`
   报 `Could not open file`。补充（2026-09-25 实测，纠正旧结论）：`print()` 不进**引擎**日志，但会进
   **`.cli/rt/logs/lua/lua-<时间戳>.log`**（`{"t":..,"l":"RAW","m":"[Script] ..."}` 逐行），
   所以本地 PoC 除了自己写文件，还能直接读这份 Lua 日志。
2. **本地资源是云端的子集**：`RenderPaths/Forward.xml`、`Cube/Day|Dusk/*SpecularHDR.dds`、
   `Editor/Textures/Engine/Vignetting.png` 本地缺失，依赖它们的特性本地验不了；
   `UrhoXCLI` 只在云端 `/workspace/.cli/`（见上文「GLB 不是运行时格式」）。
3. **整游本地可跑，条件是自己钉时钟**（2026-09-25 实测，取代旧「完整游戏本地跑不起来」结论）：
   本地 `common.get_server_time()` 返回的是 **0**（不是越界值），旧失败其实是 `TimeState` 拿 0 当 UTC 用。
   `common` 表可写，PoC 入口里 `common.get_server_time = function() return <真实 UTC 秒> end`
   再 `require("main")` + `Start()`，`main.lua` 全流程就能跑完：34 场景自检、正式会话、`InitUI`、
   `StatusWindow.Init`（模型 `IsModelLoaded=true`、非占位）全部通过。
   **`Update` 只有按全局名字订阅才派发**（`SubscribeToEvent("Update", "HandleUpdate")`）——
   这条对 PoC 和玩法模块**同时成立**：同日取证发现 StatusWindow 自己在 `Init` 里按函数订阅的两条
   （无骨骼微动、开机 trace 重发）在同一进程里一次都没触发过，而 main 按名订阅那条逐帧在跑
   （证据：同一份日志里 main 的重发行存在、那两条的日志一行都没有；
   见 `CHANGELOG.md` 2026-09-25「无骨骼微动整块静默不跑」）。
   所以：**任何逐帧逻辑都挂在 main 那条订阅上，由它显式调模块导出的 `Tick(dt)`；模块不要自己
   `SubscribeToEvent("Update", fn)`，也不要事后替换 `_G.HandleUpdate`（同样不生效）**。
   PoC 要观察每帧行为，就包一张表上的方法（用的正是 `ChatPanel.Tick`，main.lua 每帧按字段调用）。
   逐帧写节点时还有一条同族陷阱：**撤销式增量（`基准 - undo + nextv`）只对相对写（`node:Rotate`）成立**，
   绝对写（`position = 基准 + 偏移`）再减 `undo` 会把目标抵掉，每帧只落地 `A·ω·dt` 的增量
   （2026-09-25 实测呼吸幅度 ±0.00017 而非声明 ±0.006，见 `docs/maker-lua-api-verification.md` §16）。
   本地 `timeStep` 与真实时间基本对齐（2417 帧累计 40.8s / 墙钟 42s），所以量到的小幅度不能赖给时钟膨胀。
4. **本地截图不能当画面验收依据**：`graphics:TakeScreenShot(image)` + `SavePNG` 能出图，但合成器
   **不保证按帧重绘** —— 16 个场景各连拍两张（间隔 2.5s），**15 组两张 md5 完全相同**，
   只有 `lon_studio` 一组不同；`engine.pauseMinimized = false` 不改变这一行为。
   且角色 RT 层在本地盖住了背景静帧、RT 的 Y 朝向与原生 Android 相反
   （见 `docs/maker-lua-api-verification.md` §12）。所以微动、静帧融合、
   接地阴影观感仍只能靠真机/云端预览判定，本地截图只证明「装载与应用链路跑通」。

**上真机 / 出交付物仍然只有云端一条路**：`maker_build_current_directory` → 读
`.maker/logs/runtime/runtime.log`（topics 含 `engine`，引擎层报错也会落这里）。
判据：该文件出现且含 `[M0-1] 启动 M0-1 竖切片`（`main.lua` 的 `logInfo` 前缀特意保留 `[M0-1]` 作此判据）→ 已进入 Lua；
文件不出现 → 仍卡在资源装载层。
⚠️ 每次 `maker_build_current_directory` 都会带 `--reset` 重启日志抓取器并**删掉本地 `runtime.log`**，而 CLI 抓取器
实测只活 4~8 分钟。所以：**日志证据要在下一次构建前转录进文档**；取证的当下先量 `state.json.updatedAt`
是否还在推进（停了就按 `nextStartTime` 游标重启，**别再带 `--reset`**）；判活性不要用 `watcher.out.log`。
四条坑的完整口径见 `docs/maker-lua-api-verification.md` §11。

## UrhoX Lua 开发入口（按需阅读）

通用的 UrhoX Lua 规则、示例索引、任务到文档的映射与故障速查已迁至
[`docs/urhox-lua-development-guide.md`](docs/urhox-lua-development-guide.md)，避免每次接手项目都加载与当前任务无关的引擎细节。

开始任何 Lua 开发前，仍必须：

1. 完整阅读 `engine-docs/lua-scripting-guide.md`；
2. 从 `examples/api-index.md` 选择并阅读至少三个相关示例；
3. 根据任务阅读迁移指南中对应的规则与文档映射；
4. 修改 Lua 后，若 LSP 可用，先用 `maker-lua-lsp` 或 `lua_lsp_client` 确认无 Error，才可构建。

日常约束不变：玩法代码只分析和修改 `scripts/` 与项目自建目录；不要把 `engine-docs/`、`examples/`、`templates/`、`urhox-libs/`、`.project/` 等引擎知识目录误当成玩法代码。新代码放 `scripts/`，资源放 `assets/`；UI 使用 `urhox-libs/UI`，不使用已废弃的原生 UI；不确定的 API 一律以本地 AI Dev Kit 为准。

# 送给你这个回来的人

Tripothon S1 原创参赛项目：一位生活在另一座城市、与你共处同一真实时间线的人。用户以聊天为主和她相处；她的当地时间、日程和生活事件决定何时回复，而 3D 状态窗展示她此刻所在的咖啡馆、公寓、通勤路上或休闲地点。

## 当前设计

- 单一核心人格；一座城市 × 一段关系起点 = 她的一条平行人生，同时最多并存三条；
- 首轮城市：上海、成都、洛杉矶、伦敦；
- **最多三段彼此独立的人生**（各存各的聊天、事件、记忆与生活痕迹），冷启动回到最近打开的那一段；
- **四城 × 居所/工作场所/公共停留处/街区通勤，共 16 个原创 4:3 场景状态包**：背景、色温、主光方向、
  人物站位、接地阴影、无骨骼微动都由场景包单源声明；
- 静态背景上叠 2.5D「当前生活痕迹」（不可点击的 2D 定位物），并预留未来 3D 场景锚点；
- 用户消息可排队；她忙碌或睡眠后带着经历自然回复；
- 关系和共同记忆会影响以后她愿意分享的内容；
- 仅使用原创资产，不使用现有动漫 IP。

## 文档

| 文件 | 内容 |
| --- | --- |
| [设计规格](docs/2026-09-15-parallel-companion-design.md) | 产品机制、数据模型、状态机、PoC 与验收 |
| [PRD](docs/PRD.md) | 分阶段产品需求；**§5 是 M4 的产品验收依据** |
| [平台能力与资产规格](docs/platform-capabilities.md) | Tripo、Marble、TapTap Maker 的用法、格式和限制 |
| [3D 场景与角色移动分层方案](docs/3d-scene-character-movement.md) | 固定镜头 + 预设移动等五层方案的实测证据、Tripo/Marble 本地可操作性、3D 体量预算 |
| [Maker 平台假设验证报告](docs/maker-lua-api-verification.md) | 时区 / 运行时 LLM / GLB→MDL / clientCloud / 全景 / 屏幕投影与命中测试 的逐项核实结论 |
| [M2-B LLM 润色网关设计](docs/2026-09-23-m2b-llm-gateway-design.md) | 外部润色的契约、鉴权、限流、回落与实施状态（§12：S1 代码就位、未部署未接线） |
| [M3 四城初始化与关系档案设计](docs/2026-09-24-m3-four-city-init-design.md) | 城市 × 关系初始化、可复现随机、存档 v5 语义与验收 |
| [M4 可感知的平行人生设计](docs/superpowers/specs/2026-09-24-m4-perceivable-parallel-life-design.md) | 人生存档、三入口与只读档案页、16 场景状态包、2.5D 痕迹、骨骼边界与验收 |
| [UrhoX Lua 开发指南](docs/urhox-lua-development-guide.md) | 引擎规则、示例索引、任务到文档的映射与故障速查（自主工程 `AGENTS.md` 迁出） |
| [角色资产溯源与实测数据](docs/asset-provenance.md) | 资产唯一真源表、GLB/MDL 实测差异、重导入命令与阻塞项 |
| [赛事规则](docs/demand.md) | Tripothon S1 赛道、提交物与评审规则 |
| [变更记录](CHANGELOG.md) | 当前阶段与历史决策 |

## 实施顺序

M0-0 → M0-1 → M1 → M2-A → M2-B → M3 → M4 逐阶段推进。**每阶段的真实状态只以 `CHANGELOG.md` 为准**，
本文不复制进度台账（免得两处打架）。要点：

- M0-0（状态窗）与 M0-1（聊天闭环）于 2026-09-21 真机验收 + 云端实测。
- M1（每日事件 + 忙碌/睡眠排队 + 落盘重进）2026-09-22；M2-A（引用、逐句多段回复、三点布光）
  2026-09-23（`721aaeb`）。
- M2-B（外部 LLM 润色）只到 **S1：网关与适配层代码就位、未部署未接线**——`GatewayEnabled=false`
  时行为与 M2-A 一致、零外发，见 [M2-B 设计](docs/2026-09-23-m2b-llm-gateway-design.md) §11/§12。
- M3（四城 × 关系初始化、可复现随机、存档 v5）2026-09-24。
- **M4（当前阶段，2026-09-25）**：最多三段彼此独立的人生存档 + 设置层三入口与只读档案页 +
  16 个原创 4:3 场景状态包 + 2.5D 当前生活痕迹。本地门禁全绿（开发自检 33 场景 / 269 断言、
  Lua LSP `Errors: 0`、`git diff --check`、Node 独立对拍 15/15、十余支本地引擎取证探针），
  云端构建 14 次全绿；**唯一未闭环的是 Maker 真机验证**（要人扫码或开预览，判据清单在
  [`BLOCKED.md`](BLOCKED.md) B-6）。

## 怎么跑起来

**本地有一个 Windows 运行时，可以跑 3D 链路取证，但不能代替云端构建与真机验收。**
入口在主仓 `D:/Develop/ShanTianLiang/.cli/rt/UrhoXRuntime.exe`（`.cli/` 不入库，worktree 里没有），
参数与 Maker CLI 内部一致，`cwd` 必须是 `<source>`：

```
UrhoXRuntime.exe <entry.lua> -tapcode_dir=<source> -skip_login -p=Res -w -width=1080 -height=1920
```

沙箱里取证只能走 `Image:SavePNG` 与 `File` + `WriteString`（`print()` 不进日志、`io` 为 `nil`）；
本地资源是云端子集（缺 `RenderPaths/Forward.xml` 与两张 `SpecularHDR.dds`）；完整游戏本地跑不起来
（`TimeState` 的 `os.date("!%Y")` 会因服务器时间越界抛错）。已实证的用途：渲染 + 固定相机 + 角色预设移动。

**交付判定仍然只有云端一条路**，改完代码的验证路径只有两步：

1. 用 Maker MCP 的 `maker_build_current_directory` 提交并触发云端构建；
2. 读 `.maker/logs/runtime/runtime.log` 看运行结果（引擎层报错也会落这里）。

⚠️ 第 2 步有两个必须知道的脾气：**每次构建都会带 `--reset` 重启日志抓取器并删掉本地 `runtime.log`**，
所以日志证据必须在下一次构建前转录进文档；而 CLI 抓取器实测只活 4~8 分钟，取证的当下要先量
`state.json.updatedAt` 是否还在推进，停了就按 `nextStartTime` 游标重启（**不要**再带 `--reset`）。
完整口径与四条实测坑见 [验证报告 §11](docs/maker-lua-api-verification.md)。

预览页：<https://maker.taptap.cn/app/720b27bf-ca69-44ac-a776-a88ec2ec2b28?localDev=1>（需 TapTap 开发者登录）。
仓库绑定关系、Git 拓扑与打包规则见 `AGENTS.md`；踩过的坑与逐项验证结论见
[Maker 平台假设验证报告](docs/maker-lua-api-verification.md)。

## 当前交接

- **M0-0 状态窗**：竖屏页面上半部真 4:3 窗（UI 层静帧远景 + 透明底 RenderTarget 角色），
  见 `scripts/main.lua` 与 `scripts/StatusWindow.lua`。背景静帧 `assets/Textures/backgrounds/la-cafe-4x3.png`
  已入仓库并显式列入 `.project/resources.json` 的 `groups.default` 与 `preload_groups`。
  2026-09-21 真机扫码验收通过（角色正立、位于右侧约 65%、无黑底）。
- **M0-1 聊天竖切片**：下半部为可滚动聊天流 + 可编辑输入（预填规格指定的那句默认消息）+ 发送/跳过等待按钮，
  正式链路固定 10 秒等待。后端全部是同工程内的 Lua 服务，无外部后端、无数据库、无运行时 LLM：
  `scripts/services/MessageService.lua`（消息与阶段状态机）、`EventService.lua`（从时间快照派生事件事实）、
  `ContentService.lua`（纯模板 + `{token}` 替换）、`MemoryService.lua`（本地文件存档，clientCloud 只留异步接口），
  前端 `scripts/ui/ChatPanel.lua`。跨会话记忆已实测由本地文件读回。
- **M1 → M2-A 聊天层（已提交，构建链最新为 `721aaeb`）**：`EventService` 按「城市+当地日期+定种」生成
  每日 8 个事件实例；忙碌/睡眠时消息 FIFO 排队、重进恢复；回复支持引用与逐句多段上屏
  （`MessageService.BeginReplyStream`）。开发自检扩到 20 场景（结论行判据 `场景=N/20`）。
- **M2-B S1（代码就位、未接线）**：`gateway/`（独立零依赖 Node 润色网关，本地 `node --test` 19/19）+
  `scripts/services/PolishService.lua`（白名单 payload、严格校验镜像、事实词表守卫、8 秒预算 FIFO 回落）。
  **网关未部署、客户端真实 transport 未接线，运行时文字回复仍是纯 Lua 模板**；环境变量表与本地跑法见
  `gateway/README.md`，全貌见 [M2-B 设计文档](docs/2026-09-23-m2b-llm-gateway-design.md) §12。
- **M3 四城初始化与关系档案（代码就位，未经云端构建）**：`scripts/ProfileService.lua` 是城市×关系档案真源
  （四城各绑生活身份 / 关系起点 / ≥2 场景词汇 / 日程表；随机入口按创建 UTC 秒定种、可复现、落盘不再掷）；
  `scripts/ui/ProfileOverlay.lua` 提供首次初始化与换档选择；`TimeState.SCHEDULE_BY_CITY` 四城分表，
  事件/场景/文案全随城市。存档升 **v5**：v1–v4 旧档迁移为「洛杉矶 × 陌生网友」，记录、引用、
  事件计划与待回复队列不丢。开发自检扩到 26 场景（新增 U–Z，结论行判据 `场景=N/26`）；
  时区/DST/随机常量另有 Node 独立对照（`node tools/m3-node-crosscheck.js`，29/29）。
  四城背景为渐变占位图（16 组），真实美术待确认。
- **3D 场景与角色移动**：分层方案已出（T1–T5）。**首选 T1＝固定镜头完全不动 + 角色沿预设路径移动并转向，
  全程无玩家输入**——不需要任何新资产、约 60 行，已在本机用真实项目资产跑出 3 张渲染截图（镜头三次逐像素一致）。
  T2（角色有 idle/walk）有两条独立阻塞项：`import-gltf` 丢了源 GLB 的 65 关节 skin，且源 GLB 本身不含动画数据。
  详见 [3D 场景与角色移动分层方案](docs/3d-scene-character-movement.md)。
- **仍未完成**：图标需在 Maker 网页「发布素材」界面人工确认（`game_material/*` 被远端 pre-receive 排除，
  git 与 MCP 都交付不了）；真机截图已有两张（`screenshots/device/m00-realdevice-01-fullframe.jpg` 与
  `-02-crop.jpg`），`assets.screenshots` 仍为 `[]` 且还差第三张（隔一会儿再截同一画面以证「稳定」）；角色**悬空**（分层设计无共享地面，
  需调固定相机纵向取景）；移动端中文 IME 未实测；云变量记忆未接。
- M0-1 阶段的进度与阻塞逐条快照记在 `PROGRESS.md` / `BLOCKED.md`（已归档，仅覆盖该阶段），跨阶段决策记在 [CHANGELOG.md](CHANGELOG.md)。

已知阻塞项与实测数据（面数超标、导入器丢骨骼与 RM 贴图、状态窗每帧重渲）统一记在 [角色资产溯源](docs/asset-provenance.md) 与规格的 M0-1 前置修复项里。完整资产契约与验收标准见[设计规格的 M0-0](docs/2026-09-15-parallel-companion-design.md#m0-0林若夕可见状态窗已冻结开工基线2026-09-16)。

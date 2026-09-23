# 送给你这个回来的人

Tripothon S1 原创参赛项目：一位生活在另一座城市、与你共处同一真实时间线的人。用户以聊天为主和她相处；她的当地时间、日程和生活事件决定何时回复，而 3D 状态窗展示她此刻所在的咖啡馆、公寓、通勤路上或休闲地点。

## 当前设计

- 单一核心人格；关系前史与所在城市决定她的一条平行人生；
- 首轮城市：上海、成都、洛杉矶、伦敦；
- 用户消息可排队；她忙碌或睡眠后带着经历自然回复；
- 关系和共同记忆会影响以后她愿意分享的内容；
- 仅使用原创资产，不使用现有动漫 IP。

## 文档

| 文件 | 内容 |
| --- | --- |
| [设计规格](docs/2026-09-15-parallel-companion-design.md) | 产品机制、数据模型、状态机、PoC 与验收 |
| [平台能力与资产规格](docs/platform-capabilities.md) | Tripo、Marble、TapTap Maker 的用法、格式和限制 |
| [3D 场景与角色移动分层方案](docs/3d-scene-character-movement.md) | 固定镜头 + 预设移动等五层方案的实测证据、Tripo/Marble 本地可操作性、3D 体量预算 |
| [Maker 平台假设验证报告](docs/maker-lua-api-verification.md) | 时区 / 运行时 LLM / GLB→MDL / clientCloud / 全景 的逐项核实结论 |
| [角色资产溯源与实测数据](docs/asset-provenance.md) | 资产唯一真源表、GLB/MDL 实测差异、重导入命令与阻塞项 |
| [赛事规则](docs/demand.md) | Tripothon S1 赛道、提交物与评审规则 |
| [变更记录](CHANGELOG.md) | 当前阶段与历史决策 |

## 实施顺序

M0-0（真机可见状态窗）与 M0-1（聊天情绪化垂直切片）均已在 Maker 云端跑通：M0-0 于 2026-09-21 真机验收，
M0-1 于同日完成「发送 → 等待 → 输入中 → 回复」闭环的云端实测。再往后是规格 §9 的 M1（多时段状态与消息排队）
与 M2（关系记忆落到云变量）。

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
- **3D 场景与角色移动**：分层方案已出（T1–T5）。**首选 T1＝固定镜头完全不动 + 角色沿预设路径移动并转向，
  全程无玩家输入**——不需要任何新资产、约 60 行，已在本机用真实项目资产跑出 3 张渲染截图（镜头三次逐像素一致）。
  T2（角色有 idle/walk）有两条独立阻塞项：`import-gltf` 丢了源 GLB 的 65 关节 skin，且源 GLB 本身不含动画数据。
  详见 [3D 场景与角色移动分层方案](docs/3d-scene-character-movement.md)。
- **仍未完成**：图标需在 Maker 网页「发布素材」界面人工确认（`game_material/*` 被远端 pre-receive 排除，
  git 与 MCP 都交付不了）；真机截图已有两张（`screenshots/device/m00-realdevice-01-fullframe.jpg` 与
  `-02-crop.jpg`），`assets.screenshots` 仍为 `[]` 且还差第三张（隔一会儿再截同一画面以证「稳定」）；角色**悬空**（分层设计无共享地面，
  需调固定相机纵向取景）；移动端中文 IME 未实测；云变量记忆未接。
- 阶段级进度与阻塞逐条记在 `PROGRESS.md` / `BLOCKED.md`，跨阶段决策记在 [CHANGELOG.md](CHANGELOG.md)。

已知阻塞项与实测数据（面数超标、导入器丢骨骼与 RM 贴图、状态窗每帧重渲）统一记在 [角色资产溯源](docs/asset-provenance.md) 与规格的 M0-1 前置修复项里。完整资产契约与验收标准见[设计规格的 M0-0](docs/2026-09-15-parallel-companion-design.md#m0-0林若夕可见状态窗已冻结开工基线2026-09-16)。

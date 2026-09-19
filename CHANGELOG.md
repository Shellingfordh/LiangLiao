# Changelog

## 2026-09-19 — Maker 工程落地、历史合并与文档对账

### Added

- `npx -y @taptap/maker init` 完成：绑定 Maker 应用「若夕的归来」（`720b27bf-ca69-44ac-a776-a88ec2ec2b28`），AI Dev Kit 与 11 个 maker skills 落到本地；Maker MCP 注册进 Qoder 的 local 作用域。
- 合并 Maker 云端工程与文档仓两条无共同祖先的历史：`scripts/main.lua`、`scripts/StatusWindow.lua`、`.project/`、`assets/` 下的 MDL/材质/贴图/源 GLB 首次进入本仓库。
- `docs/asset-provenance.md`：资产唯一真源表、源 GLB 与导入后 MDL 的实测差异、云端权威重导入命令、五项阻塞待办。
- `research/taptap-pages/README.md`：记录登录墙判定依据与替代来源。

### Changed

- 远端拓扑（2026-09-19 两次变更，最终态）：先把两条无共同祖先的历史并成一棵树并短暂以 GitHub 为 `origin`；随后用户改定**所有推送只发 `maker`**，GitHub 暂不管。现 `origin` 与 `maker` 同指 Maker 云端 URL，另留 `github` 远端作只读留档把手。Maker 工具链（`init` / `build` / `logs watch`）会反复把 `origin` 抢回 Maker URL，已定为预期行为、不再手工纠正。本地保留 `maker-main` 分支作为 M0-0 的离线引用。
- 设计规格收敛到单一真源 `docs/2026-09-15-parallel-companion-design.md`（原 `docs/superpowers/specs/` 副本与之逐字节等价，仅行尾不同）。
- 按 2026-09-18 验证报告落地此前未写入的修订：§4.2 补 `clientCloud` 异步/配额/昵称禁令与本地文件兜底；§5.1 时间源改为 `common.get_server_time()` 并写明无 IANA 时区库、`os.date` 需 `"!"` 前缀；§7.2 补 `convert-panorama` 转 Cubemap 与「禁止从全景裁 4:3」；§7.3 与 §8 删除运行时 `Maker AI`，`ContentService` 改为纯模板；§9 M0-0 验收措辞 GLB→MDL 并新增 M0-1 前置修复项；§10 风险表重写；§12 改指 AI Dev Kit。
- `docs/platform-capabilities.md`：GLB→MDL 的交付/运行时双列、真实目录结构、无法溯源的大小上限统一标注「未核验」。
- `AGENTS.md`：恢复被 Maker 托管策略覆盖的项目段，并补入四条实测平台边界与双远端拓扑规则。
- 角色资产去重：确立单一真源，删除 2 份重复 GLB 与 `.gbm` 解包残留（删除前逐份 md5 比对并确认 uuid 无人引用），回收约 15 MB；`poc/` 交接位由 `docs/asset-provenance.md` 取代。
- 清理 26 份重复登录墙快照与 `research/node_modules`（与根副本同为 playwright 1.63.0）。
- `docs/maker-lua-api-verification.md` 新增 §11：预览卡 `Initializing 0%` 的定性（Chromium IndexedDB `InvalidStateError`，失败在 Lua 之前的资源装载层）、11 条已穷举排除假设的依据、从 `@taptap/maker` 0.0.33 源码与包内 skill 挖出的平台契约（预览验证 = build + `runtime.log`；`preview-refresh` 只刷服务端；日志窗口硬上限 1 小时），以及照抄可执行的收尾 runbook。
- 构建包瘦身：`.project/settings.json` 新增 `build.asset_ignores`，把 9.7 MB 非运行时文件（源 `.glb`、Tripo 多视图缩略图、`lin-ruoxi.mdl.bak`）剔出包；三条 glob 经 `fnmatch` 全量核验恰好命中 16 个文件，五个运行时必需路径均不被命中。
- 文档补齐"怎么跑"这一外部视角缺口：`README.md` 新增「怎么跑起来」、`AGENTS.md` 新增「没有本地运行时」硬边界、`docs/platform-capabilities.md` 补入包与瘦身规则；并修正 `AGENTS.md`「实施起点」里"本机 `scripts/`、`assets/` 为空需取回"的失效陈述与权威文档表缺失的 `asset-provenance.md` 条目。

### Known issues

- 源 GLB 14,298 三角面，超 `face_limit <= 5000` 约 2.9 倍；三张内嵌贴图均为 4096×4096。
- `import-gltf` 丢弃了源 GLB 的 65 关节 skin；**16:35 云端二次导入后 MDL 内骨骼命中数仍为 0**，问题未解决。
- 二次同步新增缺陷：材质由 `PBRDiffNormal.xml` 退成 `PBRDiff.xml`，**法线贴图丢失**，`lin-ruoxi_00_N.png` 成孤儿资源；metallicRoughness 依然未导出，材质用常量粗糙度。
- 工程内遗留 `assets/Meshes/lin-ruoxi.mdl.bak`（753,790 字节旧模型）。
- 状态窗 RenderTarget 用 `SURFACE_UPDATEALWAYS` 每帧重渲，且全局 HDR 开启后未在 `Shutdown()` 复原。
- 背景 `la-cafe-4x3.png` 缺失；图标与 3 张实机截图未产出，真机二维码仍被阻塞（但 `app_id` / `developer_id` / `miniapp_id` 已由云端写入）。
- **预览卡 `Initializing… 0%`**（console 报 Chromium IndexedDB `InvalidStateError`）：定性为浏览器资源缓存
  与当天被改三次的云端工作树不同步，属装载层而非 Lua 报错。悬空引用、`raw-assets/` 进包、DWP 预下载配置、
  工程健康四类假设均已用独立证据排除；远端构建 ✅100% ×2、preview-refresh ✅200 ×2。
  完整排查表与平台契约见 `docs/maker-lua-api-verification.md` §11。**待用户侧硬刷新后由 `runtime.log` 判定闭环。**
- `.project/settings.json` 新增 `build.asset_ignores`，把 9.7 MB 非运行时文件（源 `.glb`、Tripo 多视图缩略图、
  `lin-ruoxi.mdl.bak`）剔出构建包；文件仍留在库内，未删除。
- 云端 19:57 自动产生作者 `TapCode Rollback` 的同步 commit，把此前删掉的资产原样塞回项目根 `raw-assets/`（+24 MB）。
  该目录不在 `asset_dirs` 内所以不进包，但已进 git 历史；**结论：不要靠删 Maker 侧已追踪资产来瘦身。**
- `maker_build_current_directory` 会把 `origin` 改指回 Maker 云端 URL（与 `maker init` 同症状），GitHub 那条远端整个消失。
  已复原为 `git@github.com:melondy101/LiangLiao.git`；本批仍未推 GitHub。另将 `http.postBuffer=524288000` 固化到本仓
  `--local` 配置，避免 24 MB 增量再次触发 `send-pack: unexpected disconnect`。

### 与云端的双向合并

- 本地合并了云端 16:35 的 `4e8d55a`（重导 MDL、改材质/预制体/`StatusWindow.lua`、写入发布元数据），零冲突，代码与资产一律取云端版本。
- 反向推送时**会带走本地对 `assets/model/fashion+model+3d+model.glb` 与 `lin-ruoxi.gbm/` 的删除**（共 15 MB 非运行时资产）。判断依据是「无引用」，但材质引用已由 `uuid://` 改为路径，该结论需在推送时再确认一次。

### Next

- M0-0 真机验收：补背景静帧 + 图标/截图，出测试二维码；
- M0-1 前置：修骨骼、修 RM 贴图、降面数与贴图预算、改 RenderTarget 更新模式。

## 2026-09-16 — M0-0 林若夕状态窗基线冻结

### Added

- 锁定 M0-0：洛杉矶傍晚咖啡馆中的原创角色“林若夕”、固定 4:3 状态窗、Tripo 前景 GLB 与 Marble 静帧远景的真机验证目标。
- 在正式设计规格中补充角色资产契约、四视图交接、`poc/` 目录、分阶段验收，以及后续音频与自由输入的接口边界。

### Changed

- 正式废弃旧方案的自由移动、摇杆、镜头旋转和点击角色对话；它们不再是实施或验收要求。
- 清理研究脚本与汇总中的旧 IP 检索分类；保留非 IP 的通用设计研究并重建统计结果。

## 2026-09-15 — v2 平行时空陪伴设计

### Changed

- 项目从“三位 NPC 自动小镇”重构为“一位平行时空聊天对象 + 3D 状态窗”。
- 确立四城初始化：上海、成都、洛杉矶、伦敦；关系前史为陌生网友、高中同学、前同事、久未联系的朋友。
- 确立稳定核心人格、平行人生档案、关系状态、关键互动和开放生活上下文的数据分层。

### Added

- `docs/2026-09-15-parallel-companion-design.md`：正式设计规格。
- `docs/platform-capabilities.md`：Tripo、Marble、TapTap Maker 的独立平台与资产规格。

### Next

- M0：在 TapTap Maker 真机中验证 Tripo 原创角色 GLB 和 Marble 背景/镜头。

# Changelog

## 2026-09-19 — Maker 工程落地、历史合并与文档对账

### Added

- `npx -y @taptap/maker init` 完成：绑定 Maker 应用「若夕的归来」（`720b27bf-ca69-44ac-a776-a88ec2ec2b28`），AI Dev Kit 与 11 个 maker skills 落到本地；Maker MCP 注册进 Qoder 的 local 作用域。
- 合并 Maker 云端工程与文档仓两条无共同祖先的历史：`scripts/main.lua`、`scripts/StatusWindow.lua`、`.project/`、`assets/` 下的 MDL/材质/贴图/源 GLB 首次进入本仓库。
- `docs/asset-provenance.md`：资产唯一真源表、源 GLB 与导入后 MDL 的实测差异、云端权威重导入命令、五项阻塞待办。
- `research/taptap-pages/README.md`：记录登录墙判定依据与替代来源。

### Changed

- 远端拓扑：`origin` 改回 `git@github.com:melondy101/LiangLiao.git` 并作为 main 的 upstream，Maker 云端改名为 `maker`；本地保留 `maker-main` 分支作为 M0-0 的离线引用。
- 设计规格收敛到单一真源 `docs/2026-09-15-parallel-companion-design.md`（原 `docs/superpowers/specs/` 副本与之逐字节等价，仅行尾不同）。
- 按 2026-09-18 验证报告落地此前未写入的修订：§4.2 补 `clientCloud` 异步/配额/昵称禁令与本地文件兜底；§5.1 时间源改为 `common.get_server_time()` 并写明无 IANA 时区库、`os.date` 需 `"!"` 前缀；§7.2 补 `convert-panorama` 转 Cubemap 与「禁止从全景裁 4:3」；§7.3 与 §8 删除运行时 `Maker AI`，`ContentService` 改为纯模板；§9 M0-0 验收措辞 GLB→MDL 并新增 M0-1 前置修复项；§10 风险表重写；§12 改指 AI Dev Kit。
- `docs/platform-capabilities.md`：GLB→MDL 的交付/运行时双列、真实目录结构、无法溯源的大小上限统一标注「未核验」。
- `AGENTS.md`：恢复被 Maker 托管策略覆盖的项目段，并补入四条实测平台边界与双远端拓扑规则。
- 角色资产去重：确立单一真源，删除 2 份重复 GLB 与 `.gbm` 解包残留（删除前逐份 md5 比对并确认 uuid 无人引用），回收约 15 MB；`poc/` 交接位由 `docs/asset-provenance.md` 取代。
- 清理 26 份重复登录墙快照与 `research/node_modules`（与根副本同为 playwright 1.63.0）。

### Known issues

- 源 GLB 14,298 三角面，超 `face_limit <= 5000` 约 2.9 倍；三张内嵌贴图均为 4096×4096。
- `import-gltf` 丢弃了源 GLB 的 65 关节 skin，MDL 内骨骼命中数为 0；metallicRoughness 贴图未导出，材质退化为常量粗糙度。
- 状态窗 RenderTarget 用 `SURFACE_UPDATEALWAYS` 每帧重渲，且全局 HDR 开启后未在 `Shutdown()` 复原。
- 背景 `la-cafe-4x3.png` 缺失；图标与 3 张实机截图未产出，真机二维码仍被阻塞。

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

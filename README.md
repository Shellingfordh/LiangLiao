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
| [Maker 平台假设验证报告](docs/maker-lua-api-verification.md) | 时区 / 运行时 LLM / GLB→MDL / clientCloud / 全景 的逐项核实结论 |
| [角色资产溯源与实测数据](docs/asset-provenance.md) | 资产唯一真源表、GLB/MDL 实测差异、重导入命令与阻塞项 |
| [赛事规则](docs/demand.md) | Tripothon S1 赛道、提交物与评审规则 |
| [变更记录](CHANGELOG.md) | 当前阶段与历史决策 |

## 实施顺序

先完成 M0：把一位原创 Tripo 角色导入为 MDL，配一张 Marble 生成的 4:3 咖啡馆远景，在 Maker 真机验证加载与帧率。通过后再实现时区、消息排队和关系记忆。

## 当前交接

M0-0 的代码与角色资产已在 Maker 云端工程实现并同步到本仓库：竖屏页面、顶部固定 4:3 状态窗（RenderTarget 渲染 3D 预览）、静态状态文案，见 `scripts/main.lua` 与 `scripts/StatusWindow.lua`。

尚未完成、也不要在 M0-0 内做的：背景图 `assets/Textures/backgrounds/la-cafe-4x3.png` 仍缺（启动时打日志并用中性占位窗景）；图标与至少 3 张实机截图未产出，因此**还不能生成 TapTap 真机测试二维码**。

已知阻塞项与实测数据（面数超标、导入器丢骨骼与 RM 贴图、状态窗每帧重渲）统一记在 [角色资产溯源](docs/asset-provenance.md) 与规格的 M0-1 前置修复项里。完整资产契约与验收标准见[设计规格的 M0-0](docs/2026-09-15-parallel-companion-design.md#m0-0林若夕可见状态窗已冻结开工基线2026-09-16)。

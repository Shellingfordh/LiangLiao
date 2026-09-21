# 平台能力与资产规格

> 适用项目：《送给你这个回来的人》v2
>
> 核验日期：2026-09-15
>
> 用途：实施时唯一的平台能力速查；产品规则见 `docs/2026-09-15-parallel-companion-design.md`。

## 1. 结论

| 平台 | 在本项目中的唯一职责 | 运行时是否调用 |
| --- | --- | --- |
| Tripo Studio | 原创角色与小道具的 3D 资产生产 | 否，仅构建期网页导出 |
| Marble | 城市空间母版、全景、远景与 walkthrough 镜头 | 否，仅构建期网页导出 |
| TapTap Maker | 聊天 UI、轻量 3D 状态窗、Lua 状态机、存档、测试与发布 | 是，唯一运行时 |

不要将 Tripo、Marble 的账号凭据或生成能力交给最终用户；项目发布后不依赖它们在线生成内容。

## 2. Tripo Studio

### 可用能力

- 文本、单图或多视图生成 3D 模型；
- 贴图、格式转换、网格处理、自动绑定和动作重定向为可选后处理；
- 本项目网页端工作流：生成原创角色 / 道具 → 检查 → 导出 GLB → 导入 Maker。

### 文件与性能契约

| 资产 | 交付格式 | 运行时格式 | 目标 |
| --- | --- | --- | --- |
| 主角 | GLB（A-pose 低模） | **MDL**（`UrhoXCLI import-gltf` 转换） | 单角色 ≤ 5,000 faces；仅保留 PoC 需要的 idle、坐/看手机、walk |
| 小道具 | GLB | **MDL** | 单件 1,000–3,000 faces（咖啡杯、书、唱片、背包、台灯） |
| 备选 | FBX | MDL | 仅 GLB 转换失败时使用，且必须先做 Maker 真机验证 |

**GLB 不是 Maker 的运行时格式。** 运行时一律 `cache:GetResource("Model", "…mdl")`；导入会自动处理坐标系转换（右手系→左手系）、UV 翻转与单位换算。配套工具：`skills/model-info` 查面数（验证 ≤5,000 目标）、`skills/anim-info` 查动画轨道。实测导入注意事项（丢 skin、丢 metallicRoughness）见 `docs/asset-provenance.md`。

不要使用现有 IP 的人名、外形特征、台词、音乐或场景素材。Tripo Studio 网页会员和 OpenAPI 权益是否互通未核验；当前实施以网页导出为准。

官方资料：<https://studio.tripo3d.ai/>、<https://developers.tripo3d.ai/en/docs/introduction>、<https://developers.tripo3d.ai/en/docs/quick-start>。

## 3. Marble

### 可用能力

- 从文本、图片、多图、视频或粗 3D 结构创建世界；
- Studio 可组合世界、制作相机运动并录制镜头；
- 可导出浏览链接、360 全景、Gaussian splat、Collider GLB 与高质量 GLB。

### 本项目的允许用法

1. 为上海、成都、洛杉矶、伦敦分别生成公寓、咖啡馆、通勤、休闲地点的空间母版；
2. 导出 360 全景或录制短镜头，作为 Maker 状态窗的背景/远景与提交视频素材；
3. 前景始终由低模 Tripo 角色和少量 Maker 场景道具构成。

### 禁止作为默认方案的用法

Marble 高质量 GLB 不直接作为 Maker 移动端主场景：官方规格约为 60–100 万三角面，生成可达约一小时且有限流。Collider GLB 仍约 10–20 万三角面。若要导入，必须单独完成“单场景 + 真机帧率 + 包体大小”Spike 后才能采用。

| Marble 输出 | 本项目决策 |
| --- | --- |
| 360 panorama PNG（2560×1280，2:1 等距柱状） | **可用 `UrhoXCLI convert-panorama -i <panorama> -o <cubemap.dds> --mips` 转 Cubemap 天空球**（官方专用工具，输入格式正好匹配）。M0-0 先用静帧过真机，M0-1/M1 升 Cubemap |
| 从全景裁 4:3 | **禁止**：2560 px 铺 360° ⇒ 0.1406°/px，4:3 约需 70° 水平视角 ⇒ 仅约 498×373，放大到 1080 宽必糊。要 4:3 就从世界视口直接出高分辨率截图 |
| 录制镜头 | 用于 walkthrough 与视觉资产看板 |
| SPZ / PLY splat | 不进入首轮 Maker 运行时 |
| Collider GLB | 仅性能 Spike 候选 |
| 高质量 GLB | 概念/镜头来源，不进入首轮运行时 |

官方资料：<https://docs.worldlabs.ai/>、<https://docs.worldlabs.ai/marble/export/specs>、<https://docs.worldlabs.ai/marble/export/mesh>。

## 4. TapTap Maker

### 可用能力

- UrhoX + Lua 项目运行时；
- 资产目录、GLB / FBX / MDL 3D 资源、图片、音频、视频与 Spine 资源；
- 本地开发模式（`npx -y @taptap/maker init`）与 Maker MCP；
- 预览、真机测试二维码和 TapTap 发布；
- `clientCloud` 用于单用户跨设备存档。

### 项目目录与格式

下表的**路径**按当前工程实际结构（`scripts/` 为用户代码，`assets/` 各子目录为引擎导入产物）；**大小上限一栏全部标注为未核验**——原始出处是 `research/taptap-pages/` 的登录墙快照，在 AI Dev Kit 中找不到对应依据。

| 内容 | 放置位置 | 格式 | 大小上限 |
| --- | --- | --- | --- |
| 用户 Lua 代码 | `scripts/` | `.lua`（Lua 5.4） | — |
| 运行时模型 | `assets/Meshes/` | `.mdl` | 未核验 |
| 运行时材质 | `assets/Materials/` | `.xml`（Technique 见 §2） | 未核验 |
| 运行时贴图 | `assets/Textures/` | `.jpg` / `.png` + 同名 `.xml` | 未核验 |
| 预制体 | `assets/Prefabs/` | `.prefab` | 未核验 |
| 源 GLB / 参考图 | `assets/models/characters/…`、`assets/model/` | `.glb`、`.jpeg`、`.webp` | 未核验 |
| 背景 / 远景 | `assets/Textures/backgrounds/` | PNG / JPG / WebP | 未核验 |
| 环境音 | `assets/audio/` | OGG / MP3 | 未核验 |
| 录制片段 | `assets/video/` | MP4 / WebM | 未核验 |
| 状态与记忆 | `clientCloud`（`values` 表）+ 本地文件存档兜底 | 任意 Lua table / JSON | 单值上限未核验 |

**资源引用不带目录前缀**：`assets/` 与 `scripts/` 都是资源根，代码里写 `cache:GetResource("Model", "Meshes/lin-ruoxi.mdl")`，不写 `assets/Meshes/…`。

### 实施边界

- Lua 决定时区、可用性、事件事实与去重；**运行时没有 LLM 接口**，回复一律模板 + 变量替换（`docs/maker-lua-api-verification.md` §3）；
- WASM 预览的内存状态不等于真机/线上持久化，离线事件与记忆必须在真机测试；
- `clientCloud` 读写全异步、配额 300 次/分、昵称不可存云变量，详见规格 §4.2；
- Lua API 名称以本地 AI Dev Kit（`engine-docs/`、`.emmylua/`、`examples/`）为准，不从旧模板或历史快照推断；
- 构建前须过 Lua LSP 诊断（无 Error）再提交构建；
- **什么进包由 `build.asset_dirs` 决定**（当前只有 `../assets` 与 `../scripts`）。`resources.json` 里
  `groups` 的 glob 是**相对 `asset_dirs`** 匹配的，所以项目根其它目录（含云端回填的 `raw-assets/`）不进包。
  瘦身只用 `build.asset_ignores`（glob，**相对项目根**），文件留在库里；**不要靠删已追踪资产来瘦身**——
  Maker 云端会用 `TapCode Rollback` commit 把它们原样塞回 `raw-assets/`；
- 不要用 `asset_ignores` 排除贴图：导入后的 `.mdl` 是压缩的，无法从模型侧证明某张贴图未被引用；
- **本仓库没有本地运行时**，唯一的运行/预览入口是 Maker 云端；验证走 `runtime.log`，详见
  `maker-lua-api-verification.md` §11 的收尾 runbook；
- 发布前准备图标、至少 3 张截图、宣传图/封面、简介、开发者的话和实机视频。

官方入口：<https://maker.taptap.cn/help>、<https://maker.taptap.cn/skills>。

## 5. 最小验证顺序

1. Tripo 导出原创角色 GLB → `import-gltf` 转 MDL → Maker 真机显示；**（✅ 2026-09-21 真机验收通过：背景静帧已入包，角色正立、位于右侧约 65%、无黑底）**
2. Marble 导出咖啡馆 4:3 静帧 → Maker 状态窗远景；后续可升 Cubemap 天空球；
3. Lua 用 `common.get_server_time()` + 城市偏移表算洛杉矶当地时间并切换状态；
4. `clientCloud` 保存一条消息、一次事件和一条共同记忆（异步回调 + `BatchSet` + 本地文件兜底）；
   **（⏳ 2026-09-21 M0-1 只做到「本地文件兜底」这一半：`MemoryService` 用
   `memory/m0-1-la-stranger.json` 实测跨会话读回，`clientCloud` 侧仅留异步接口未启用，预览成功不绑定云存储）**
5. 之后才扩展城市、动画、音效和视觉资产。

若任一步失败，保留上一步已验收资产，选择低成本回退；不在运行时引入新的外部服务。

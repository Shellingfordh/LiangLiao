# 角色资产溯源与实测数据

> 记录日期：2026-09-19
>
> 用途：满足 `docs/demand.md` 与规格 M4「记录 Tripo 与 Marble 的生成、导出和接入过程，证明工具贡献」。
> 本文件只登记**事实与测量值**；资产路径契约以本文件「唯一真源」一节为准。

## 唯一真源

| 资产 | 唯一路径 | 说明 |
| --- | --- | --- |
| 角色源 GLB | `assets/models/characters/lin-ruoxi/lin-ruoxi.glb` | Tripo 导出的原始交付物 |
| 多视图参考 | `assets/model/multiview_{0..3}_d0313941-….jpeg` | Tripo 多视图生成的 4 张输入 |
| 角色缩略图 | `assets/model/fashion+model+3d+model.thumb.webp` | Tripo 交付预览图 |
| 运行时模型 | `assets/Meshes/lin-ruoxi.mdl` | `import-gltf` 产物 |
| 运行时材质 | `assets/Materials/lin-ruoxi_00_tripo_mat_8ae16fc0-7a3a-402e-9a6e-1180f6c269f7.xml` | Technique 与贴图引用方式见下方「云端二次同步」一节 |
| 运行时贴图 | `assets/Textures/lin-ruoxi_00_D.jpg` / `lin-ruoxi_00_N.png` | `_N.png` 目前**未被材质引用**（见下） |
| 角色预制体 | `assets/Prefabs/lin-ruoxi.prefab` | 运行时优先加载对象 |
| 背景静帧 | `assets/Textures/backgrounds/la-cafe-4x3.png` | 代码实际查找路径，见 `scripts/StatusWindow.lua`；Marble 世界视口原生导出，详见下方「背景静帧溯源」 |
| 应用图标 | `game_material/la-cafe-icon.png`（**仅本地**，见「应用图标溯源」） | `.project/project.json` 的 `assets.icon` 指向此路径；该目录被 Maker 远端 pre-receive 硬拒，不入 git 也不进运行包 |

### 本次清理掉的重复副本

| 被删副本 | 字节 | 删除依据 |
| --- | --- | --- |
| `poc/art/source/lin-ruoxi/fashion+model+3d+model.glb` | 8,582,828 | 与唯一真源 md5 相同；`poc/` 交接位由本节取代 |
| `poc/art/source/lin-ruoxi/multiview_{0..3}.jpeg` | 408,330 | 与 `assets/model/` 同名文件 md5 相同 |
| `assets/model/fashion+model+3d+model.glb` | 8,582,828 | md5 与唯一真源相同；其 `.meta` uuid 无任何 xml/prefab/json/lua 引用 |
| `assets/models/characters/lin-ruoxi/lin-ruoxi.gbm/` | 6,486,561 | GLB 解包残留；两份 embedded 与 `assets/Textures/` 的 D/N md5 相同，且 embedded 的 uuid 无人引用 |

规格原先在 `poc/art/source/lin-ruoxi/` 与 `assets/models/characters/lin-ruoxi/` 两处规定交接位，
`assets/model/` 又是 Maker `create_3d_asset` 的自动落地位——三份并存是文档冲突而非误操作，
现以本表为唯一约定。

### 云端同步隔离副本

Maker 云端在 2026-09-19 自动回填了 `raw-assets/` 下的源 GLB、解包贴图和四视图。这些文件是云端同步保留的隔离副本：不在 `asset_dirs` 内，且已被 `build.asset_ignores` 排除，因而不进入运行包；它们也不构成新的资产真源。不要仅为瘦身删除该目录或其中已追踪文件，后续变更须先在 `maker/main` 核实云端同步行为与两种引用方式（UUID 和路径）。

## 源 GLB 实测（`assets/models/characters/lin-ruoxi/lin-ruoxi.glb`）

| 项 | 实测值 |
| --- | --- |
| 文件 | 8,582,828 字节；generator `Tripo` |
| mesh / material | 1 / 1（`tripo_mat_8ae16fc0-…`） |
| 三角面 | **14,298** |
| 顶点 | 9,627 |
| POSITION 包围盒 | x ±0.255，y 0 → 0.979，z ±0.099（即身高 0.979 m） |
| UV | `TEXCOORD_0` 全部落在 0..1 |
| 蒙皮 | **含 `Armature` skin，65 个 `mixamorig:*` 关节**，`JOINTS_0`/`WEIGHTS_0` 齐全，权重和异常 0 例 |
| 动画 | 无 `animations` |
| 内嵌贴图 | 3 张，全部 **4096×4096**：`basecolor` JPEG 2.96 MB、`normal` PNG 3.23 MB、`rm`(metallicRoughness) JPEG 1.42 MB |

> 注意：baseColor 是 UV 图集，单独打开看像「碎脸＋黑底噪点」，这是正常展开结果，不是坏图。

## 导入后 MDL 实测差异（`assets/Meshes/lin-ruoxi.mdl`，753,790 字节）

| 项 | 结论 |
| --- | --- |
| 骨骼 | 源 GLB 有 65 关节，MDL 内 `mixamorig`/`Hips`/`Armature`/`Skeleton`/`Bone` 命中数**全为 0** → `import-gltf` 丢弃了 skin。运行时因此走 `StaticModel` 分支（`scripts/StatusWindow.lua`） |
| metallicRoughness | 源 GLB 有该贴图，材质 XML 只声明 `unit="diffuse"` 与 `unit="normal"`，**无 metallicRoughness 槽** → 导入器未导出，改用常量 `Metallic=0`、`Roughness=0.62` |
| 高度 | 0.979 m，运行时按 `CHARACTER_TARGET_HEIGHT=1.68` 缩放（`StatusWindow.lua`） |
| LOD | 重导入命令带 `--no-lod`（见 `assets/models/characters/lin-ruoxi/README.txt`），未生成 LOD |

## 重导入命令（云端权威版本，摘自 `assets/models/characters/lin-ruoxi/README.txt`）

```bash
/workspace/.cli/UrhoXCLI import-gltf \
  -i /workspace/assets/models/characters/lin-ruoxi/lin-ruoxi.glb \
  -o /workspace/assets/Meshes/lin-ruoxi.mdl \
  --material-dir /workspace/assets/Materials \
  --texture-dir /workspace/assets/Textures \
  --prefab /workspace/assets/Prefabs/lin-ruoxi.prefab \
  --resource-root /workspace/assets \
  --no-lod
```

## 云端二次同步后的状态（2026-09-19 16:35，commit `4e8d55a`）

本地合并该次同步后逐项复核，结论是**问题没有解决，且新增一项**：

| 项 | 一次同步（12:38） | 二次同步（16:35） | 判定 |
| --- | --- | --- | --- |
| MDL 体积 | 753,790 B | **658,378 B**（另存 `lin-ruoxi.mdl.bak` = 旧版全量） | 重导过 |
| 骨骼 | 无 | **仍然无**：`mixamorig`/`Hips`/`Armature`/`Skeleton`/`Bone` 命中数全为 0 | ❌ 未修复 |
| 材质 Technique | `PBR/PBRDiffNormal.xml` | **`PBR/PBRDiff.xml`** | ⚠️ 降级 |
| diffuse 槽 | 有（`uuid://Ecz6yaUN…`） | 有（改为路径 `Textures/lin-ruoxi_00_D.jpg`） | 引用方式变了 |
| normal 槽 | 有（`uuid://DEdyWZxR…`） | **无** | ❌ **新增缺陷：法线贴图丢失**，`assets/Textures/lin-ruoxi_00_N.png`（3.23 MB）成为孤儿资源 |
| 常量粗糙度 | `Metallic=0 / Roughness=0.62` | 同 | 未变 |
| 代码绑定方式 | `drawable:ApplyMaterialList()` | 自写 `bindCharacterMaterial()` 手动 `GetResource("Material")` + `SetMaterial` | 这是材质改用路径引用的原因 |
| `.project/project.json` | 无发布元数据 | 新增 `developer_id: 471831`、`app_id: 940330`、`miniapp_id: tapmc1yds3rzoloihc` | ✅ 二维码/广告前置已具备，仍缺图标与 3 张截图 |

> 材质引用从 `uuid://` 改成路径，意味着早先「按 uuid 判定某文件无人引用」的结论**只对当时那一版成立**。
> 后续再判断资产是否可删，必须同时检查 uuid 与路径两种引用。

## 背景静帧溯源（Marble 世界视口原生导出，2026-09-20）

| 项 | 实测值 |
| --- | --- |
| 世界 | Marble「Los Angeles Coffee Shop Evening」，Marble 1.1，世界编号 `ca969969` |
| 世界链接 | `https://marble.worldlabs.ai/world/a77b4852-ffac-4030-a5c3-bfaa515467e8` |
| 导出方式 | 世界视口工具条 `Screenshot`（原生导出，画面无任何网页 UI 叠加）；**不是** 2:1 全景裁切 |
| 导出分辨率来源 | 该按钮的出图尺寸等于浏览器视口 CSS 尺寸，故先把视口设为 1280×960 再导出，得到精确 4:3 |
| 尺寸 / 格式 | 1280×960（1.3333），8-bit RGBA PNG，非隔行 |
| 文件大小 | 2,407,171 字节 |
| md5 | `ee5e1430f5bfc44b42ed90463af29c4c` |
| 原始文件名 | `screenshot-2026-09-20T11_46_36.028Z.png`（UTC） |
| 用途 | M0-0 洛杉矶咖啡馆状态窗背景；命中 `scripts/StatusWindow.lua` 的 `BACKGROUND_CANDIDATES[1]`，由 `main.lua` 作为状态窗 `backgroundImage`（`backgroundFit="cover"`）绘制 |

构图与规格的差异留档：窗外街景与蓝调暮色在左、软木板海报在右（右侧留给角色立位）均符合，
但**画面内没有出现吊灯**，吊灯需另行调整机位或后期确认。

## 应用图标溯源（2026-09-20）

| 项 | 实测值 |
| --- | --- |
| 交付路径 | `game_material/la-cafe-icon.png` |
| 尺寸 / 体积 | 512×512，536,022 字节 |
| md5 | `eb323c470eea57da9b07e7488131f6f1` |
| 生成方式 | Maker MCP `generate_image`，落地在 `assets/image/la-cafe-icon_20260920121307.png` |
| 与配置的关系 | `.project/project.json` 的 `assets.icon` 由 Maker 侧写为 `./game_material/la-cafe-icon.png`。该目录在本地、git 历史与 `maker/main` 三处都不存在，**不是悬空引用而是设计如此**：Maker 远端 pre-receive 用 `EXCLUDE_PATTERNS` 硬拒 `game_material/*`（实测 push 被 `! [remote rejected]` 退回，见 `apps/agent-server/src/lib/rollback.ts`），所以这个路径从未能进过仓库 |
| 交付方式 | 本地按配置把生成件复制到位（md5 与 `assets/image/` 的生成件一致）；**该文件不入库、不打包**，云端图标仍需经 Maker 网页侧的发布素材流程确认 |
| 为什么只能走网页（2026-09-20 查源码定论） | 本地 Maker MCP（`@taptap/maker` 0.0.33 `dist/maker.js`）**完全不读也不上传** `assets.icon`：全文 `game_material` 命中 0 次，`"icon"` 仅 1 处且是应用列表的 `icon: numberField(...)` / `iconColor` 字段，与发布图标无关；`game_material/*` 的排除发生在**服务端** pre-receive（`agent-server/src/lib/rollback.ts`）。结论：图标既走不了 git 也走不了任何 MCP 工具，只能网页侧交付 |
| 被否掉的替代方案 | 把图标放进「已跟踪但被 `build.asset_ignores` 排除」的仓库路径，让 `assets.icon` 在云端可解析。**不做**：上条已证明没有任何消费方读这个字段，改了也不会让图标生效，只是徒增一个包体排除规则 |
| 为何不改配置指向 `assets/image/` | `assets/` 在 `build.asset_dirs` 内，图标会被打进运行包；且 `.project/project.json` 属 Maker 托管元数据，改指过去有被后续构建覆写的风险 |
| 画面内容 | 洛杉矶咖啡馆傍晚窗景：暖黄吊灯、冰咖啡、窗外棕榈树与暮色街景，与 M0-0 冻结的美术方向一致 |

## 待办（阻塞项，按优先级）

1. **恢复 normal 贴图槽**：材质改回 `Techniques/PBR/PBRDiffNormal.xml` 并接上 `Textures/lin-ruoxi_00_N.png`，否则 3.23 MB 的法线图白备着，角色表面细节全平。
2. **骨骼**：源 GLB 的 65 关节 skin 在两次导入后都没进 MDL。M0-1 的 idle/坐/走动画在此之前无从谈起；先确认 `import-gltf` 的绑定参数，必要时改用带绑定的导出或 FBX 通路。
3. **RM 贴图**：让导入器导出 metallicRoughness，替换常量粗糙度。
4. **面数**：14,298 面对 `spec` 与 `docs/demand.md` 的 `face_limit <= 5000` 不达标。
5. **贴图预算**：三张 4096² 对 14k 面角色过配；状态窗只占竖屏约 35%，建议 basecolor/normal 降到 2048² 与 1024²。
6. **清理 `assets/Meshes/lin-ruoxi.mdl.bak`**：753,790 字节的旧模型备份，确认新版可用后删除。
7. **背景包体预算**：`assets/Textures/backgrounds/la-cafe-4x3.png` 已于 2026-09-20 从 Marble 世界视口导出并落地（见上节），但 2.30 MB 相对当前 1.20 MB 运行包偏大，且 RGBA 的 alpha 通道并未使用；进包前确认是否需要转 RGB 或压缩。

## 原始留档（MarkItDown 转换记录，自 `poc/art/source/lin-ruoxi/*.md` 收拢）

- GLB：已尝试 MarkItDown 转换，当前版本不支持 GLB 二进制，无自动转换输出；源文件保留在唯一真源路径。
- 四张多视图 JPEG：MarkItDown 已执行，图像不含可提取文字；四张共同描述最终无包角色。
- 肖像授权：若使用真人照片作参考，须由用户本人提供且拥有授权，只可作非识别性比例与气质参考；最终角色不得设计为可识别的真人复制。

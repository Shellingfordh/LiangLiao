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

## M4 场景静帧与生活痕迹（Maker MCP 批量生成，2026-09-24）

16 张背景由 `batch_generate_images` 分两批生成（洛杉矶+上海 `_20260924155332` 批、成都+伦敦 `_20260924155606` 批），
每张均请求 `aspect_ratio="4:3"`、`target_size=1152x864`，全部 RGB（无 alpha，colorType=2）。
**生成器实际交付的是 1296×864（3:2），与请求不符**——2026-09-25 已按画面中心裁左右各 72px
转成精确 4:3（1152×864）并以 `optimize` 重存（合计 45.8 MB → 26.4 MB）；
`SceneService` 的全部归一化 x/scale 已按 x'=(x·1296−72)/1152 同步重映射（rx 同比例放大、y 向不变），
人物站位在 3D 空间不受像素裁剪影响；
9 张生活痕迹同工具 `_20260924155918` 批，512×512 RGBA（colorType=6，透明底）。
两批背景用首批成品作 `reference_images` 锁风格（同一角色同一美术语言的空景）。
路径与 `scripts/SceneService.lua` 的 `BG`/`TRACES` 表一一对应，命中即入包（`image/**` 已在
`.project/resources.json` 的 `groups.default`，增强引用模式）；旧一轮 `_202609241322xx` 候选图不再被代码引用，
按增强模式会被裁出包，仓库内暂留作风格对照。

构图纪律（M4 验收 3）：16 张统一「主活动区与留白在右」，唯一例外 `lon-recordshop-interior`
（柜台上在左）——该包的人物站位、接地阴影、痕迹锚点三处一起翻到左侧，与静帧留白同侧。

装载取证（2026-09-25，本地引擎运行时 `.cli/rt/UrhoXRuntime.exe`，PoC `.tmp/poc/m4_asset_probe.lua`）：
25 个声明路径以资源根（`<tapcode_dir>/assets`，与 M0 `Meshes/lin-ruoxi.mdl` 同一条规则）
`cache:GetResource("Texture2D", path)` 全量解析 **25/25 OK**，尺寸逐张核对
（背景 1152×864、痕迹 512×512），证据文件 `Documents/temp/savedata/unknown/0/m4-asset-probe.txt`。
即 `image/...` 写法在真实引擎资源系统里可解析，真机侧只剩打包裁剪与 GPU 内存两项运行时变量。
4:3 裁剪后重跑一次，仍是 **25/25 OK、1152×864**。

| 场景包 id | 文件（`assets/image/`） | 字节 | md5 |
| --- | --- | --- | --- |
| la_apartment | la-apartment-night_20260924155332.png | 1,494,351 | `3461739e3dc8b82ed96ee7a963204dba` |
| la_studio | la-studio-day_20260924155332.png | 1,673,514 | `0e3c43b12672884c8b245cddae8a00c2` |
| la_cafe | la-cafe-night_20260924155332.png | 1,531,384 | `dbcfcb10f0aea1871b5d495f2f1e2f07` |
| la_commute | la-street-dusk_20260924155332.png | 1,505,745 | `f4a391316572f0cef63a6072cc956e2c` |
| sha_apartment | sha-apartment-morning_20260924155332.png | 1,668,318 | `a84ec902d8ac4661d2529566758af629` |
| sha_office | sha-office-day_20260924155332.png | 1,468,255 | `e89f67244376aa311344810988b5919a` |
| sha_bookstore | sha-bookstore-night_20260924155332.png | 1,518,863 | `ac62d81fe0f3f1c92abd16cbc9c34984` |
| sha_commute | sha-street-morning_20260924155332.png | 1,921,629 | `297a6f763e5433bc8ec54aade07fa9bf` |
| cdu_apartment | cdu-apartment-day_20260924155606.png | 1,727,291 | `1801aca9154016c7ecc24d3839e0015a` |
| cdu_studio | cdu-studio-day_20260924155606.png | 1,708,921 | `7d058ac4e4de36f27dec740c1ce75ec4` |
| cdu_cafe | cdu-teahouse-day_20260924155606.png | 1,875,651 | `3944ea3adb20bfc2c17257834892baf1` |
| cdu_commute | cdu-nightmarket-street_20260924155606.png | 1,823,379 | `502b5cf17760427c742a8bc8796599d2` |
| lon_apartment | lon-apartment-rain-night_20260924155606.png | 1,322,080 | `a19611706ed8baac96d0caecfc7b721e` |
| lon_studio | lon-studio-recording_20260924155606.png | 1,542,479 | `073c550109566d02c980300c2b7a8c43` |
| lon_recordshop | lon-recordshop-interior_20260924155606.png | 1,779,349 | `2d16e3f53e96e221964db8d2be92af9f` |
| lon_commute | lon-street-rain-dusk_20260924155606.png | 1,816,362 | `b800fdbeff18d0ef880a0a3277944993` |

| 痕迹键 | 文件（`assets/image/`） | 字节 | md5 |
| --- | --- | --- | --- |
| note | trace-note_20260924155918.png | 232,605 | `f8ce64c8e836e96de9f5c2d33fb9a3e5` |
| coffee | trace-coffee_20260924155918.png | 258,402 | `6ad535b2cf4b1401639a636abe3570fa` |
| vinyl | trace-vinyl_20260924155918.png | 317,755 | `f3e76bb43383de5177c3d7e5480eed67` |
| umbrella | trace-umbrella_20260924155918.png | 105,068 | `0eade39cc473a56c9f895e3d930038b3` |
| postcard | trace-postcard_20260924155918.png | 300,213 | `b550f8622d26473dd014e0ebe152824f` |
| proofs | trace-proofs_20260924155918.png | 321,195 | `f9d366997b49c16af46e96c146a034d6` |
| grocery | trace-grocery_20260924155918.png | 336,977 | `d43965150fe2b9ef2dd931520695bfec` |
| oldbook | trace-oldbook_20260924155918.png | 336,039 | `d4da3417db75b72d933f89b5aed7d4aa` |
| gaiwan | trace-gaiwan_20260924155918.png | 227,041 | `f0e25fa82c0f8082be621cf1acbb6071` |


### 生成提示词逐张登记（设计 §8）

<details><summary>16 张背景与 9 张痕迹的完整 prompt（生成调用原文，点击展开）</summary>

- **la_apartment**（`la-apartment-night`）：原创游戏场景静帧：洛杉矶公寓客厅，深夜到清晨两用。暖黄台灯（色温约3000K）从画面左侧照入，落地窗外是城市夜景灯海与远山剪影，木地板，布艺沙发一角，书桌上摊着活动便签和一杯冷掉的咖啡，墙上钉着开放麦克风之夜的小海报。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面右侧约三分之一留出干净地面空间（供后期人物叠加），画面中不要出现任何人物，光影方向明确，无水印无文字。
- **la_studio**（`la-studio-day`）：原创游戏场景静帧：独立出版工作室。大长桌上摊着小册子版面校样和裁纸刀，晾绳上夹着一排样张，丝网印刷架在背景，上午偏冷日光（色温约5600K）从画面右侧大窗照入，在水泥地面拉出长影。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面右侧约三分之一留出干净地面空间（供后期人物叠加），画面中不要出现任何人物，光影方向明确，无水印无文字。
- **la_cafe**（`la-cafe-night`）：原创游戏场景静帧：「塞法尔东非」咖啡馆开放麦克风之夜。晚上暖光（色温约2900K）从左上方吊灯洒下，角落有小型演出台的话筒架和暖色串灯，木质吧台一角与两把椅子，靠窗座位透出洛杉矶街灯，墙面贴满演出海报。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面右侧约三分之一留出干净地面空间（供后期人物叠加），画面中不要出现任何人物，光影方向明确，无水印无文字。
- **la_commute**（`la-street-dusk`）：原创游戏场景静帧：洛杉矶街区傍晚通勤路上。公交站牌与棕榈树影，晚霞余光照亮人行道，暖橙色天空（色温约3500K）从画面左侧低角度照入，街对面是低层商铺与霓虹初上，人行道右侧留出一段干净的街面。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面中不要出现任何人物，光影方向明确，无水印无文字。
- **sha_apartment**（`sha-apartment-morning`）：原创游戏场景静帧：上海老弄堂公寓客厅与阳台。清晨微光与暖黄室内灯混合（色温约3400K），阳台外是晾衣杆与对面石库门屋顶，圆木桌上摊着专栏选题草稿和一杯茶，藤椅，阳台栏杆上几盆绿植。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面右侧约三分之一留出干净地面空间（供后期人物叠加），画面中不要出现任何人物，光影方向明确，无水印无文字。
- **sha_office**（`sha-office-day`）：原创游戏场景静帧：报社版房办公区。上午日光灯偏冷（色温约5000K）从顶面均匀照下，长条办公桌上是双屏排版机和成叠报纸清样，白板贴满选题便签表，靠墙文件柜，右侧留出一段干净的地板和一把转椅周围空地。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面中不要出现任何人物，光影方向明确，无水印无文字。
- **sha_bookstore**（`sha-bookstore-night`）：原创游戏场景静帧：旧书店值夜班的店内。暖黄台灯（色温约2800K）从画面右侧木柜台照过来，高大书架之间立着木梯，玻璃柜台里码着旧书和明信片架，门口街灯透进来一点冷光形成对比，木地板。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面右侧约三分之一留出干净地面空间（供后期人物叠加），画面中不要出现任何人物，光影方向明确，无水印无文字。
- **sha_commute**（`sha-street-morning`）：原创游戏场景静帧：上海街区清晨通勤路上。地铁站出入口的扶梯与报亭，梧桐树影，早餐车冒着蒸汽，晨光低角度暖白（色温约4500K）从画面左侧照入，人行道砖面微微湿润反光，右侧留出干净的街面。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面中不要出现任何人物，光影方向明确，无水印无文字。
- **cdu_apartment**（`cdu-apartment-day`）：原创游戏场景静帧：成都会式公寓客厅。白天柔和天光（色温约4000K）从院坝方向的窗照入，木桌上摊着没干的本地风物明信片和一叠线稿，阳台外是竹林和远山，藤椅绿植，门口摆着一双帆布鞋。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面右侧约三分之一留出干净地面空间（供后期人物叠加），画面中不要出现任何人物，光影方向明确，无水印无文字。
- **cdu_studio**（`cdu-studio-day`）：原创游戏场景静帧：插画工作室。大画架与晁满明信片样稿的木架，颜料瓶和毛笔洗笔筒，工作台上摊着勾线中的本地屋檐明信片，上午天光从画面右侧窗照入（色温约4800K）在水磨石地面拉出长影。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面右侧约三分之一留出干净地面空间（供后期人物叠加），画面中不要出现任何人物，光影方向明确，无水印无文字。
- **cdu_cafe**（`cdu-teahouse-day`）：原创游戏场景静帧：老式成都茶馆。竹椅竹桌，盖碗茶冒着热气，方桌茶阵之间一个老虎灶，午后斜射暖光（色温约3600K）从高窗照入，青砖地，墙上挂着茶牌，右侧留出一段干净的青砖地面。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面中不要出现任何人物，光影方向明确，无水印无文字。
- **cdu_commute**（`cdu-nightmarket-street`）：原创游戏场景静帧：成都夜市街口傍晚到夜里。小吃摊暖黄灯泡串（色温约2700K）从画面左侧摊位照过来，蒸汽和霓虹招牌，自行车和推车上摆着一叠明信片停在路边，青石板路反光，右侧留出干净的街面。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面中不要出现任何人物，光影方向明确，无水印无文字。
- **lon_apartment**（`lon-apartment-rain-night`）：原创游戏场景静帧：伦敦公寓房间。窗外雨夜与街灯，室内暖光（色温约2900K）从画面左侧台灯照入，桌上是耳机和打开的混音工程笔记本，墙上钉着黑胶封套，斜屋顶阁楼天窗，羊毛毯搭在椅子上，木地板。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面右侧约三分之一留出干净地面空间（供后期人物叠加），画面中不要出现任何人物，光影方向明确，无水印无文字。
- **lon_studio**（`lon-studio-recording`）：原创游戏场景静帧：学院录音棚。调音台推子与监听音箱，话筒与防喷罩立在录音角，墙上吸音棉和声学扩散板，冷蓝工作光（色温约6500K）从顶面照下，设备指示灯暖红点缀，地面整洁，右侧留空。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面中不要出现任何人物，光影方向明确，无水印无文字。
- **lon_recordshop**（`lon-recordshop-interior`）：原创游戏场景静帧：老唱片行店内。木质唱片架一排排黑胶封套，柜台后老式唱机正在播放，金色暖光（色温约3200K）从画面右上方吊灯洒下，玻璃柜里竖着单曲封套，地上铺波斯地毯，门口街灯冷蓝对比。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面左侧约三分之一留出干净地面空间（供后期人物叠加），画面中不要出现任何人物，光影方向明确，无水印无文字。
- **lon_commute**（`lon-street-rain-dusk`）：原创游戏场景静帧：伦敦街区傍晚雨天。红色电话亭和远处双层巴士虚影在雨雾里，湿石板路反着暖黄路灯（色温约3000K，从画面右侧路灯照来），铸铁栏杆与联排住宅门廊，门口台阶上搭着一把收起的长柄伞，右侧留出干净的街面。写实偏水彩质感的插画风格，4:3 构图，透视平视，画面中不要出现任何人物，光影方向明确，无水印无文字。
- **trace-note**：透明背景，游戏 UI 道具图标：一张淡黄色便签纸，边角微微卷起，上面有钢笔字迹纹理，写实偏水彩质感插画风格，光影柔和，单一物体居中，无文字水印。
- **trace-coffee**：透明背景，游戏 UI 道具图标：一只喝了一半的外带纸杯咖啡，杯盖放在旁边，杯身有牛皮纸隔热套，写实偏水彩质感插画风格，光影柔和，单一物体居中，无文字水印。
- **trace-vinyl**：透明背景，游戏 UI 道具图标：一张半滑出封套的黑胶唱片，封套是深蓝墨绿色，唱片纹路反光，写实偏水彩质感插画风格，光影柔和，单一物体居中，无文字水印。
- **trace-umbrella**：透明背景，游戏 UI 道具图标：一把收起靠放的深蓝灰色长柄雨伞，搭着木质伞柄，伞尖有水滴，写实偏水彩质感插画风格，光影柔和，单一物体居中，无文字水印。
- **trace-postcard**：透明背景，游戏 UI 道具图标：两三张叠放略错开的原创风景明信片，背面朝上写着地址栏，旁边一支铅笔，写实偏水彩质感插画风格，光影柔和，无文字水印。
- **trace-proofs**：透明背景，游戏 UI 道具图标：一叠报纸版面校样纸，边缘有红笔批注圈画痕迹，最上一张微卷，写实偏水彩质感插画风格，光影柔和，无文字水印。
- **trace-grocery**：透明背景，游戏 UI 道具图标：一只搗在地上的帆布袋，袋口露出青葱和一把青菜叶子，写实偏水彩质感插画风格，光影柔和，单一物体居中，无文字水印。
- **trace-oldbook**：透明背景，游戏 UI 道具图标：两本叠放的旧书，封面磨损，书脊脱色，最上一本夹着一根旧书签，写实偏水彩质感插画风格，光影柔和，无文字水印。
- **trace-gaiwan**：透明背景，游戏 UI 道具图标：一只盖碗茶，青瓷茶碗配木茶托，盖半斜着碗沿，冒着一缕热气，写实偏水彩质感插画风格，光影柔和，单一物体居中，无文字水印。

</details>

## 待办（阻塞项，按优先级）

1. **恢复 normal 贴图槽**：材质改回 `Techniques/PBR/PBRDiffNormal.xml` 并接上 `Textures/lin-ruoxi_00_N.png`，否则 3.23 MB 的法线图白备着，角色表面细节全平。
2. **骨骼（2026-09-23 重写）**：**资产本身是绑好骨骼的，是转换器把 skin 丢了**——这与「资产没绑骨骼」是两回事，修复动作完全不同。
   源 GLB 含 `Armature` skin、65 个 `mixamorig:*` 关节、`JOINTS_0`/`WEIGHTS_0` 齐全、权重和异常 0 例；
   而两次导入后的 MDL 侧 `mixamorig`/`Hips`/`Armature`/`Skeleton`/`Bone` 命中数全为 0，`import-gltf` 丢弃了 skin。
   本地运行时实测（`.tmp/poc/anim_probe.lua`，经 `File` API 落盘）：`skeleton = true`、`numBones = 0.0`、
   `GetNumAnimations` 报 `attempt to call a nil value` ⇒ 运行时只能走 `StaticModel` 分支。
   要查 `import-gltf` 的绑定参数，或改用 FBX 通路。
   ⚠️ **这是两条独立阻塞项，不是一个**：第二条见下，修好 skin 也不会自动获得动画。
3. **动画数据（2026-09-23 新增，与上一条独立）**：源 GLB 本身 `animations | 无`——**即使 skin 修好了，也没有 idle/walk 可播**。
   引擎侧 API 面是齐全的（`AnimatedModel`、`AnimationController:PlayExclusive`、`AnimationState` 都在 `.emmylua/`），缺的是数据。
   Maker MCP 的 `create_3d_asset` 只提供 `rig` / `texture` / `retopology` / `convert` 四种 operation，**没有动画**，
   工具描述亦明确「Tripo animation retargeting is intentionally not supported」；`face_limit` 范围是 48–20000（不是只到 5000）。
   所以动画只能去 Tripo 网页版产出（账号是会员），T2 这一层基本绑定在网页工作流上。
4. **RM 贴图**：让导入器导出 metallicRoughness，替换常量粗糙度。
5. **面数**：14,298 面对 `spec` 与 `docs/demand.md` 的 `face_limit <= 5000` 不达标；可用 MCP `create_3d_asset` 的
   `retopology`（`face_limit` 48–20000）压。
6. **贴图预算**：三张 4096² 对 14k 面角色过配；状态窗只占竖屏约 35%，建议 basecolor/normal 降到 2048² 与 1024²。
7. **清理 `assets/Meshes/lin-ruoxi.mdl.bak`**：753,790 字节的旧模型备份，确认新版可用后删除。
8. **背景包体预算**：`assets/Textures/backgrounds/la-cafe-4x3.png` 已于 2026-09-20 从 Marble 世界视口导出并落地（见上节），但 2.30 MB 相对当前 1.20 MB 运行包偏大，且 RGBA 的 alpha 通道并未使用；进包前确认是否需要转 RGB 或压缩。
9. **发布素材（2026-09-21 复核）**：真机截图已有**两张**在库（`screenshots/device/m00-realdevice-01-fullframe.jpg`
   13:12、`m00-realdevice-02-crop.jpg` 13:21，均为原生设备截图、同一 `5ac225f` 构建），还差第三张以证「稳定」；
   `.project/project.json` 的 `assets.screenshots` 仍为 `[]`（登记动作需要改 `.project/`，未做），
   `assets.icon` 指向 `./game_material/la-cafe-icon.png` —— 该目录被远端 pre-receive 排除，图标只能走 Maker 网页侧。
   ⚠️ 这两张截图上状态文案仍是 `洛杉矶 18:20`，那是被抄成常量的规格举例值（真机时刻应为约 22:21），
   M0-1 起时间由 `common.get_server_time()` + 偏移表算出，云端日志实测已随真实时刻变化（02:10 / 03:03 / 03:59）。
10. **M4 背景包体预算（2026-09-24 新增，2026-09-25 更新）**：16 张背景经 4:3 裁剪 + optimize 重存后
   合计 26.4 MB（单张 1.3–1.9 MB），痕迹 9 张合计约 2.5 MB，包体压力减半；
   真机分发前视 GPU 表现决定是否再降采样或转 8-bit 索引色。
   旧一轮 `_202609241322xx` / `_202609241323xx` 候选图已无代码引用，可择机删出仓库。

## 原始留档（MarkItDown 转换记录，自 `poc/art/source/lin-ruoxi/*.md` 收拢）

- GLB：已尝试 MarkItDown 转换，当前版本不支持 GLB 二进制，无自动转换输出；源文件保留在唯一真源路径。
- 四张多视图 JPEG：MarkItDown 已执行，图像不含可提取文字；四张共同描述最终无包角色。
- 肖像授权：若使用真人照片作参考，须由用户本人提供且拥有授权，只可作非识别性比例与气质参考；最终角色不得设计为可识别的真人复制。

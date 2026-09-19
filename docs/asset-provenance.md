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
| 运行时材质 | `assets/Materials/lin-ruoxi_00_tripo_mat_8ae16fc0-7a3a-402e-9a6e-1180f6c269f7.xml` | Technique `PBRDiffNormal.xml` |
| 运行时贴图 | `assets/Textures/lin-ruoxi_00_D.jpg` / `lin-ruoxi_00_N.png` | 材质 XML 以 `uuid://` 引用这两份 |
| 角色预制体 | `assets/Prefabs/lin-ruoxi.prefab` | 运行时优先加载对象 |
| 背景（待补） | `assets/Textures/backgrounds/la-cafe-4x3.png` | 代码实际查找路径，见 `scripts/StatusWindow.lua` |

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

## 待办（阻塞项，按优先级）

1. **面数**：14,298 面对 `spec` 与 `docs/demand.md` 的 `face_limit <= 5000` 不达标，需重生成或减面。
2. **贴图预算**：三张 4096² 对 14k 面角色过配；状态窗只占竖屏约 35%，建议 basecolor/normal 降到 2048² 与 1024²。
3. **骨骼**：重导入时保留 skin，否则 M0-1 的 idle/坐/走动画无从谈起。
4. **RM 贴图**：让导入器导出 metallicRoughness，替换常量粗糙度。
5. **背景**：`assets/Textures/backgrounds/la-cafe-4x3.png` 仍缺；不要从 2560×1280 全景裁 4:3（有效分辨率仅约 498×373），应从 Marble 世界视口直接出高分辨率 4:3 静帧。

## 原始留档（MarkItDown 转换记录，自 `poc/art/source/lin-ruoxi/*.md` 收拢）

- GLB：已尝试 MarkItDown 转换，当前版本不支持 GLB 二进制，无自动转换输出；源文件保留在唯一真源路径。
- 四张多视图 JPEG：MarkItDown 已执行，图像不含可提取文字；四张共同描述最终无包角色。
- 肖像授权：若使用真人照片作参考，须由用户本人提供且拥有授权，只可作非识别性比例与气质参考；最终角色不得设计为可识别的真人复制。

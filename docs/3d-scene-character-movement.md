# 3D 场景与角色移动：分层实现方案

> 适用项目：《送给你这个回来的人》v2
>
> 提出日期：2026-09-23
>
> 目的：回答「能不能做到固定视角下角色移动」以及其降级路径，**每一层都标注了确定性证据**。
> 产品规则见 `docs/2026-09-15-parallel-companion-design.md`；平台规格见 `docs/platform-capabilities.md`；
> Lua API 逐条核验见 `docs/maker-lua-api-verification.md`。

---

## 1. 结论

| 层 | 效果 | 需要新资产 | 代码量 | 确定性证据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| **T1** | **固定镜头完全不动，角色沿预设路径移动并转向，全程无玩家输入** | 无 | ~60 行 | **✅ 已在本地 UrhoXRuntime 用真实项目资产跑出 3 张渲染截图** | **首选** |
| **T2** | T1 + 角色有 idle/walk 动作 | **有**（动画数据 + 修 skin） | ~30 行 | ⚠️ 引擎 API 齐全；但 `import-gltf` 丢了 skin（两次）、源 GLB 本身无动画，两个阻塞项都未解除 | T1 稳定后做 |
| **T3** | 镜头沿预设路径推进/环绕，角色静止 | 无 | ~40 行 | ⚠️ 相机 API 已在 T1 与现有代码中验证可用，轨迹版未验证 | 与 T1 叠加 |
| **T4** | 导入整块 3D 场景，角色在其中移动 | **有**（且需性能 Spike） | 未知 | ❌ 平台未公布面数/包体/内存上限，未验证 | 不做首轮 |
| **T5** | 背景静止 + 角色静止（线上现状） | 无 | 0 | ✅ 已上线验收 | 兜底 |

**最重要的一条结论：用户点名的「最佳效果」（固定视角 + 角色预设移动）不需要任何新资产、不需要任何新 API，
在现有 `StatusWindow.lua` 的场景里就能成立。** 这一点已经用真实渲染截图证明，不是推断。

---

## 2. 本次实测拿到地基事实

以下全部是 2026-09-23 在本地 `UrhoXRuntime.exe` 上用**本项目真实资产**跑出来的，不是文档推断。

### 2.1 本地可以真跑（推翻旧文档结论）

`docs/platform-capabilities.md` §4 写着「本仓库没有本地运行时」。**这是过时的**（已于同日更正为
「本地运行时与云端验证的分工」）。

运行时存在：`D:/Develop/ShanTianLiang/.cli/rt/UrhoXRuntime.exe`，与 Maker CLI 内部参数完全一致即可跑：

```bash
UrhoXRuntime.exe <entry.lua> -tapcode_dir=<source> -skip_login -p=Res -w -width=1080 -height=1920
```

`cwd` 必须是 `<source>`。这条命令等价于「云端跑得通」——同一套参数。

### 2.2 沙箱里能用来取证的只有两条通道

| 通道 | 可用 | 说明 |
| --- | --- | --- |
| `print()` | ❌ | 不进引擎日志，也不进 stdout，本地完全看不到 |
| `log:Write()` | ❌ | 同上，本地 grep 不到任何 `[POC]` 行 |
| `Image:SavePNG(path)` | ✅ | **唯一可靠的位图取证**，写真实渲染像素 |
| `File(path, FILE_WRITE)` + `WriteString` + `Close` | ✅ | **唯一可靠的文本取证** |

沙箱限制（与 `engine-docs/recipes/file-storage.md` 一致）：

- `io` 库整体为 `nil`（`io.stdout:flush()` 直接报 `attempt to index a nil value`）；
- `os.execute` / `os.remove` / `os.rename` 已移除，`os.clock` / `os.time` / `os.date` 保留；
- `File` 写入被固定在 `C:/Users/<user>/Documents/temp/savedata/<project>/<userId>/`，
  **子目录必须预先存在**，否则 `SavePNG` 报 `Could not open file`。

### 2.3 角色资产的真实状态（本次新查明，影响分层）

**先说结论：资产本身是绑好骨骼的，是转换器把 skin 丢了。** 这和「资产没绑骨骼」是两回事，
修复动作完全不同。

探针落盘结果（`anim-probe.txt`，经 `File` API）——MDL 侧：

```
model = true
skeleton = true
numBones = 0.0
GetNumAnimations -> attempt to call a nil value (method 'GetNumAnimations')
```

源 GLB 侧（`docs/asset-provenance.md` §「源 GLB 实测」，2026-09-19）：

| 项 | 实测值 |
| --- | --- |
| 蒙皮 | **含 `Armature` skin，65 个 `mixamorig:*` 关节**，`JOINTS_0`/`WEIGHTS_0` 齐全，权重和异常 0 例 |
| 三角面 | 14,298（超 `face_limit <= 5000` 的目标） |
| 动画 | **无 `animations`** |
| 内嵌贴图 | 3 张全 4096×4096（basecolor / normal / rm） |

而 MDL 侧 `mixamorig`/`Hips`/`Armature`/`Skeleton`/`Bone` 命中数**全为 0**——
`import-gltf` 丢弃了 skin，**两次导入都没救回来**。运行时因此走 `StaticModel` 分支。

配套事实：

- `assets/` 下**只有一个** `.mdl`（`Meshes/lin-ruoxi.mdl`），**零个动画类资产**；
- `assets/Prefabs/lin-ruoxi.prefab` 自己用的就是 `<component type="StaticModel">`。

**所以 T2 有两个独立的阻塞项，不是一个：**

1. **skin 丢失**：GLB 有 65 关节但 MDL 没有。要查 `import-gltf` 的绑定参数，
   或改用 FBX 通路（`asset-provenance.md` 待办 #2 原文）。
2. **没有动画数据**：源 GLB 本身 `animations | 无`。即使 skin 修好了，也没有 walk/idle 可播。
   引擎侧 API 齐全（`AnimatedModel` / `AnimationController:PlayExclusive` / `AnimationState` 都在 `.emmylua`），
   缺的是数据。

### 2.4 本地 ≠ 云端的已知差异（拉平前不要把本地结论当云端结论）

| 差异 | 本地 | 影响 |
| --- | --- | --- |
| `common.get_server_time()` | 返回越界值，`TimeState.lua:349` 的 `os.date("!%Y")` 直接抛 `date result cannot be represented` | `main.lua:222` 的 `RefreshSnapshot()` 会中断，**本地跑不起来完整游戏**；PoC 绕开了 TimeState 才跑通 |
| `RenderPaths/Forward.xml` | 缺失 | PoC 回退默认 RenderPath，仍能渲染 |
| `Cube/*/…SpecularHDR.dds`、`Editor/Textures/Engine/Vignetting.png` | 缺失 | 本地 `Autoload/*.pak` 集不全 |
| 预览截图 MCP | `screenshots_supported: false` | 改走引擎原生 `TakeScreenShot` + `SavePNG` |

> 因此：**本地可以证明「渲染 + 移动 + 固定镜头」这条 3D 链路成立**，
> 但不能证明「整个游戏在云端同样跑法」——云端多一份 `resources.json` 与构建产物。

---

## 3. 分层方案

### T1 — 固定镜头 + 角色预设移动（首选，已实证）

**目标效果**：状态窗里镜头完全固定，角色沿预设路径往返移动，朝向只由移动方向决定，
全程没有任何玩家输入，也没有摇杆/角色控制器。

**为什么是它**：`StatusWindow.lua:409 frameFixedCamera()` 已经在算一把固定相机
（`cameraNode_.position` + `LookAt` + `Quaternion(180, UP)` 补 MDL 正面朝向），
`StatusWindow.lua:447` 还有同一套 +Z 补偿。**固定相机这件事现成的，缺的只有「让角色动」。**

**实现要点**（插入点，不写全量代码）：

1. 保持 `frameFixedCamera()` 一次性的取景结果不变 —— 它就是「固定视角」的本体；
2. 新增预设路径（闭合航点表 + 恒定速度），在 `Update` 订阅里只改两件事：
   `characterRoot_.position`（沿路径插值前进）与 `characterRoot_.worldRotation`（按移动方向算 yaw）；
3. `frameFixedCamera()` 里那句「让角色转向相机」是一次性的，不与逐帧移动转向冲突；
   但要注意它**不能**被搬到 Update 里，否则每帧都会把角色掰回面向相机。

**取景上的一个真实约束**：现有取景把人物放在画面右侧约 71%、背景留在左侧
（`StatusWindow.lua:436-437` 的 `look.x - viewW * 0.21`）。横向移动空间很小，
**沿 Z 轴做纵深移动更合适**，或者只做小幅横移；否则角色会走出 4:3 小窗。

**证据**：`.tmp/poc/poc_tier1.lua` 已在本地跑通，`Documents/temp/savedata/unknown/0/poc-evidence/`
下 3 张真实渲染截图（t=1.0 / 2.5 / 4.0）：相机取景三次逐像素一致（镜头确实没动），
角色从中间 → 左侧 → 右侧并转向，另有一个对照小球走同一条路径，
用来把「角色资产问题」和「移动链路问题」分开。

**风险**：低。不引入新资产、不引入新 API、不动现有取景。

---

### T2 — T1 + 角色有动作

**目标效果**：同样的固定镜头 + 预设移动，但角色有 idle / walk 动画，步频与移动速度匹配。

**两个独立阻塞项**（见 §2.3，都不是代码问题）：

1. **skin 在转换时丢了**：源 GLB 有 65 关节、权重正常，`import-gltf` 两次都没带进 MDL。
   要查 `import-gltf` 的绑定参数，或改走 FBX 通路。
2. **没有动画数据**：源 GLB 本身不含 `animations`。需要 Tripo 侧产出动画
   （网页版有动作库/重定向；Maker MCP 的 3D 资产工具**只提供 rig，没有动画操作**，
   官方描述亦写明「Tripo animation retargeting is intentionally not supported」）。

**实现要点**：

- `StaticModel` → `AnimatedModel`（`hero_:CreateComponent("AnimatedModel")` + `SetModel`）；
- `AnimationController:PlayExclusive("walk", 0, true, fadeTime)` 起走，`SetSpeed` 与 `MOVE_SPEED` 对齐；
  停下的航点切回 idle；`SetLooped` / `FadeOthers` 处理过渡。

**确定性状态**：引擎 API 面已在 `.emmylua` 确认齐全，**但端到端未验证**——
阻塞项 1 和 2 都没解除前，这一层不能算「能做到」。

**工作量**：代码约 30 行；**主要成本在资产侧**（转换参数或 FBX 通路 + 动画产出 + 真机验收）。

---

### T3 — 镜头沿预设路径运动，角色静止

**目标效果**：镜头沿预设轨迹缓推/环绕/横移，角色站在原地（或与 T1 叠加，角色也在动）。

**实现要点**：纯 Node 数学，**不需要任何新资产、不需要任何新 API**：

- 相机位置走关键帧/贝塞尔插值（`cameraNode_.position = lerp(p0, p1, t)`）；
- 目标点可固定在角色身上（`cameraNode_:LookAt(charPos, UP, TS_WORLD)`）⇒ 环绕；
  或目标点也走轨迹 ⇒ 自由运镜；
- `cameraNode_.position` 与 `LookAt` 都已在 T1 PoC 和 `frameFixedCamera()` 里验证可用。

**状态**：相机 API 已验证；**轨迹版未验证**，需一次与 T1 同规格的 PoC。

**约束**：状态窗是 4:3 竖屏小窗（`RT_WIDTH × RT_HEIGHT` 决定真实像素预算），
运镜幅度必须小——大幅横移在这个尺寸下只会显得糊和抖。Marble 的「录制镜头」也可以作为
预渲染素材直接当视频/背景用，绕开实时运镜。

---

### T4 — 导入整块 3D 场景，角色在其中移动（可选扩展，不做首轮）

用户明确说「不用开放世界」，所以这层是**能力边界说明**，不是计划。

- 平台**没有公布**三角面/包体/内存上限，也没有角色控制器、物理、状态机、虚拟摇杆的 API 承诺；
- Marble 高质量 GLB 约 60–100 万面、Collider GLB 约 10–20 万面，直接进移动端主场景不现实
  （`docs/platform-capabilities.md` §3 已记录该判断）；
- 已上线的 Maker 3D 作品（如《灵异直播间》）是第一人称漫游，**没有**「导入场景 + 角色在其中跑」的先例；
- 角色移动只能用**关键帧/样条驱动 `position`**，不能依赖刚体或角色控制器。

**若要试，必须先做 Spike**：单场景 + 真机帧率 + 包体大小，三项都过再谈。

---

### T5 — 背景静止 + 角色静止（线上现状，兜底）

即当前已验收的状态窗静帧。任何一层失败都退到这里，**保留已验收资产，不引入新的外部服务**。

---

## 4. 推荐路线

1. **现在就做 T1**：零新资产、~60 行、插在 `StatusWindow.lua` 已有场景里，风险最低，
   且直接命中用户点名的「固定视角 + 预设移动」。
2. T1 稳定后，**并行推进 T2 的资产侧**（Tripo 重出带骨骼角色）——这是长周期项，越早开始越好；
   代码侧等资产到位再写。
3. T3 作为 T1 的变体，同一套 PoC 框架改相机轨迹即可，按需取用。
4. T4 除非 Spike 三项全过，否则不进首轮。

---

## 5. Tripo / Marble 能做什么、怎么接进 Maker（2026-09-23 实测）

### 5.1 Tripo（3D 角色/道具制作）——**可以本地操作，走 Maker MCP**

不需要浏览器、不需要你的网页登录态。Maker MCP 的 `create_3d_asset` 就是 Tripo 通道，
本次已实测连通（`action=get_options` 正常返回）。

| 能力 | 是否可用 | 实测参数 |
| --- | --- | --- |
| 文本 → 模型 | ✅ | `prompt` / `quality_tier`(fast/balanced/high_quality) / `subject_type`(biped/quadruped/scenery/other) |
| 图片 / 多视图 → 模型 | ✅ | `images{front,left,back,right}` |
| **rig（自动绑骨骼）** | ✅ | `rig_type`: biped / quadruped / hexapod / octopod / avian / serpentine / aquatic |
| texture | ✅ | `texture_quality`: standard / detailed / **extreme**，`pbr` 开关 |
| retopology（减面） | ✅ | `face_limit` **48–20000** |
| convert | ✅ | GLTF / FBX / USDZ / OBJ / STL / 3MF |
| **动画（idle/walk 等）** | ❌ | **没有这个 operation**；工具描述明确「Tripo animation retargeting is intentionally not supported」 |

**两条关键结论：**

1. **面数上限是 20000，不是无限。** 当前角色 14,298 面在限内，但 `docs/demand.md` 的
   `face_limit <= 5000` 目标要靠 `retopology` 压。
2. **动画只能去 Tripo 网页版做**（你有会员）。MCP 这条线能 rig、能减面、能转格式，
   但产不出动画数据。所以 T2 的阻塞项 2 基本绑定在网页工作流上。

**本地跑不通的那一环**：`UrhoXCLI import-gltf` **本地不存在**（全盘扫过 `.cli/`、
npm 缓存、`mcp-runtime/0.0.34/dist/maker.js`，命中 0 次）。它只在云端 `/workspace/.cli/` 下。
也就是说 **GLB → MDL 这步本地做不了**，只能在 Maker 云端构建时发生。

**你给的那个 Tripo3d_Godot_Bridge 是什么**：解包看了，是个 Godot 插件，
起一个本地 WebSocket 服务（`127.0.0.1:60650`）**接收** Tripo 网页端「发送到 Godot」推来的文件
（`.fbx/.obj/.glb/.gltf/.zip`，5 MB 分片）。它**不能驱动 Tripo**，只是个接收端，
配对动作在 Tripo 网页侧由人点。实测该端口当前无人监听。
用途参考：如果你在网页版生成/导出，可以用它把文件落到本地，省去手动下载。

### 5.2 Marble（3D 场景制作）——**本地操作不了，也没有 MCP 通道**

Maker MCP 工具列表里**没有任何 Marble 工具**。查了一圈可行性：

| 路径 | 结论 |
| --- | --- |
| Maker MCP | ❌ 无对应工具 |
| Playwright 驱动浏览器 | ❌ **未安装**（`import("playwright")` → Module not found） |
| 复用你正在跑的 Chrome | ⚠️ Chrome 在跑（20 进程）、profile 存在（含登录态），但**调试端口 9222/9223 都没开**。要接管就得让你重启 Chrome 带 `--remote-debugging-port`，会打断你当前的会话 |
| 全新无头浏览器 | ⚠️ 能起，但**没有你的登录态**，进不去会员功能 |
| WebSearch / WebFetch 官方文档 | ❌ 本环境网络策略拦截（`docs.worldlabs.ai` 无法验证安全性，搜索接口 400） |

**现实分工**：Marble 只能你在网页端操作导出，我把文件接进工程。已有的成功先例（`docs/asset-provenance.md`）：

- 世界 `Los Angeles Coffee Shop Evening`（Marble 1.1，世界编号 `ca969969`，
  链接 `https://marble.worldlabs.ai/world/a77b4852-ffac-4030-a5c3-bfaa515467e8`）；
- 导出方式：**世界视口工具条 `Screenshot` 原生导出**，先把视口设为 1280×960 拿到精确 4:3；
- 产物 `la-cafe-4x3.png`，1280×960、2,407,171 字节、md5 `ee5e1430…`，已作为状态窗背景上线。

**注意 2:1 全景不能用裁切冒充 4:3**（`platform-capabilities.md` §3 已判）：2560 px 铺 360° ⇒ 0.1406°/px，
4:3 约需 70° 水平视角 ⇒ 仅约 498×373，放大到 1080 宽必糊。要 4:3 就从世界视口直接出图。

**Marble 全景 → Cubemap 这条路本地验不了**，两个原因叠加：`UrhoXCLI convert-panorama` 本地不存在；
且本地运行时连引擎自带的 `Cube/Day/DaySpecularHDR.dds`、`Cube/Dusk/DuskSpecularHDR.dds`
都加载不到（引擎日志实证 `Could not find resource`），没有对照物。这条只能上云端验。

### 5.3 本地运行时 ≠ 云端构建（资产侧新增证据）

引擎日志实证，本地 `Autoload/*.pak` 是云端构建的**子集**，以下资源本地缺失：

```
Could not find resource RenderPaths/Forward.xml
Could not find resource Cube/Day/DaySpecularHDR.dds
Could not find resource Cube/Dusk/DuskSpecularHDR.dds
Could not find resource Editor/Textures/Engine/Vignetting.png
```

含义：本地能证明「渲染 + 移动 + 固定镜头」这条链路，但**不能证明任何依赖上述资源的特性**。

### 5.4 当前「3D 场景」的真实体量（2026-09-23 实测）

| 项 | 值 |
| --- | --- |
| 状态窗渲染目标 | **960×720**（4:3），`CAMERA_FOV=32°`，角色缩放到 1.68 m |
| 角色模型 | `Meshes/lin-ruoxi.mdl`，658,378 B |
| 背景 PNG ×3 | 约 1.96 / 2.41 / 2.37 MB，合计 **6.74 MB** |
| `assets/Textures` 合计 | 8.8 MB |
| `assets/Meshes` 合计 | 1.4 MB |

**这是一切的尺度参照**：所谓「3D 场景」目前是一个 960×720 的小窗里放一个 658 KB 的静态模型，
外加一张 2.4 MB 的静帧背景。T3/T4 想在这个画布上做运镜或放大场景，先按这个像素预算算。

---

## 6. 复现方式

PoC 与运行器在 `.tmp/poc/`（`poc_tier1.lua` / `run-poc.sh` / `anim_probe.lua` / `run-probe.sh`）。
⚠️ `.tmp/` 被 gitignore，属**临时物、不会随仓库分发**；本文档的命令、判据与证据路径才是耐久记录。
PoC 脚本丢失不影响已得出的结论，但要重跑就需要照 §3 T1 的实现要点重写那约 60 行。

```bash
bash D:/Develop/ShanTianLiang/.tmp/poc/run-poc.sh
```

证据落在 `C:/Users/20145/Documents/temp/savedata/unknown/0/poc-evidence/`（PNG）
与 `.../0/anim-probe.txt`（文本）。**该目录的子目录需先存在**，否则 `SavePNG` 报
`Could not open file`。

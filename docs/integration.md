# Tripo × TapTap Maker 联动调研报告

> 调研日期：2026-09-10
> 所有能力均来自官方公开文档，已核实现网可用。
> 引用：`https://docs.tripo3d.ai/`（Tripo OpenAPI 文档）、`https://maker.taptap.cn/docs`（TapTap Maker 文档）

---

## 目录

1. [Tripo 现网能力](#1-tripo-现网能力)
2. [TapTap Maker 现网能力](#2-taptap-maker-现网能力)
3. [两者交集（资产 + 数据流）](#3-两者交集资产--数据流)
4. [可行的联动模式](#4-可行的联动模式)
5. [面向 Tripothon S1 的实操建议](#5-面向-tripothon-s1-的实操建议)
6. [踩坑提醒](#6-踩坑提醒)

---

## 1. Tripo 现网能力

> 来源：`https://docs.tripo3d.ai/`
> 接口基础 URL：`https://api.tripo3d.ai/v2/openapi`
> 鉴权：`Authorization: Bearer YOUR_TRIPO_API_KEY`
> 官方 Python SDK：`pip install tripo3d`（仓库 `VAST-AI-Research/tripo-python-sdk`）

### 1.1 输入 → 输出 矩阵

| 任务类型 (type) | 输入 | 输出 | 默认模型版本 | 积分基线 |
| --- | --- | --- | --- | --- |
| `text_to_model` | 文本 prompt（≤1024 字符） | 3D 模型（GLB） | `P1-20260311`（低模拓扑最佳）/ `H3` / `H2` | P1: 30 / 40 积分 |
| `image_to_model` | 单张图（PNG/JPG ≤20MB） | 3D 模型（GLB） | `P1-20260311` / `H3` / `H2` | P1: 40 / 50 积分 |
| `multiview_to_model` | 4 视图（前/左/后/右） | 3D 模型（GLB） | `P1-20260311` / `H3` / `H2` | P1: 40 / 50 积分 |
| `import_model` | 上传 GLB/OBJ/FBX/STL（≤150MB） | 进入下游 pipeline 的 task_id | — | 免费 |
| `generate_image` | 文本 prompt | 图片（用于多视图或参考） | `flux.1_kontext_pro` 等 | 5–10 积分 |
| `generate_multiview_image` | 单图 | 4 视图（前/左/后/右 URL） | — | 10 积分 |
| `edit_multiview_image` | 原 multiview task + 指令 | 编辑后的视图 | — | 5 积分/视图 |
| `texture_model` | 已有模型 task_id + 文本/图参考 | 重新贴图/PBR | `v3.0-20250812` / `v2.5-20250123` | 10 积分起 |
| `mesh_segmentation` | 已有模型 task_id | 部件分割信息 | `v1.0-20250506` | 40 积分 |
| `mesh_completion` | 已有模型 task_id | 合并后的整模 | `P-v2.0-20251225` | 50 积分 |
| `highpoly_to_lowpoly`（Smart Low Poly） | 已有模型 task_id | 低面数模型（quad 选项时强制 FBX） | `P-v2.0-20251225` | 30 积分 |
| `animate_rig`（自动绑定） | 已有模型 task_id | 带骨骼的 GLB/FBX | `v2.5-20260210` | 25 积分 |
| `animate_retarget`（套预设动作） | 已 rig 的 task_id | 带动画的 GLB/FBX | — | 10 积分/动作 |
| `convert_model`（格式转换） | 已有 GLB task_id | GLTF / USDZ / FBX / OBJ / STL / 3MF | — | 5 积分起 |

> ⚠️ **下游任务有依赖关系**：texture / segmentation / completion / low-poly / rig / retarget / convert 必须使用 ≥ `Turbo-v1.0-20250506` 或 `v2.0-20240919` 起的上游 task_id。1.x 模型的 task_id 不被接受。

### 1.2 关键参数

**`text_to_model`（P1）**
- `prompt` 必填；`negative_prompt` ≤255 字符
- `model_seed` / `image_seed` / `texture_seed`：相同种子可复现
- `face_limit`：48 ~ 20000
- `texture`（默认 true）/ `pbr`（默认 true）/ `texture_quality`（`standard` | `detailed`）
- `auto_size`：把模型缩放到真实米级尺寸（仅贴图模型）
- `compress`：`geometry` 用几何压缩，否则默认 meshopt
- `export_uv`：默认 true；false 时跳过 UV，生成更快、模型更小

**`image_to_model`（P1）** 多了：
- `texture_alignment`：`original_image` | `geometry`
- `orientation`：`align_image` 让模型对齐原图
- `enable_image_autofix`：自动优化输入图

**`convert_model`** 可调输出规格：
- `format`：GLTF / USDZ / FBX / OBJ / STL / 3MF
- `quad`、`force_symmetry`、`face_limit`、`flatten_bottom`、`texture_size`、`texture_format`、`pivot_to_center_bottom`、`scale_factor`
- `with_animation`（默认 true）、`pack_uv`、`bake`、`export_vertex_colors`、`export_orientation`
- `fbx_preset`（实验性）：`blender` | `3dsmax` | `mixamo`

**`animate_retarget`** 预设动作清单：
- 双足：`idle` / `walk` / `run` / `dive` / `climb` / `jump` / `slash` / `shoot` / `hurt` / `fall` / `turn`
- 多足：`quadruped:walk` / `hexapod:walk` / `octopod:walk` / `serpentine:march` / `aquatic:march`
- `out_format`：`glb`（默认）| `fbx`
- `animations` 数组最多 5 个

### 1.3 文件 & 上传约束

- **STS 临时凭证上传**（推荐）：POST 拿到 `s3_host` / `resource_bucket` / `resource_uri` / `session_token` / `sts_ak` / `sts_sk`，再 PUT 到 S3
- **图片格式**：`webp` / `jpeg` / `png`；**模型格式**：`glb` / `obj` / `fbx` / `stl`
- 单文件 ≤ 20 MB（STS 上传）；`import_model` ≤ 150 MB

### 1.4 任务结果与有效期

- `GET /v2/openapi/task/{task_id}` 轮询
- 状态：`queued` / `running` / `success` / `failed` / `banned` / `expired` / `cancelled` / `unknown`
- 输出 URL（`model` / `base_model` / `pbr_model` / `generated_image` / `rendered_image` / 四视图 URL）**默认 5 分钟内过期**——必须立即下载或转存。
- 任务只能用发起它的同一 API key 查询。

### 1.5 重要边界

- **没有「场景 / 世界生成」端点**。Tripo 主页宣传的「Scenario / Instant Environment Generation」目前只在 Studio Web 内部，**OpenAPI 未暴露**——不能靠 API 直接做场景级生成。
- `stylize` 在营销页提到，**OpenAPI 暂无此端点**。
- Tripo 不提供「游戏引擎场景组装」能力，只产出单个模型/材质/动画。

---

## 2. TapTap Maker 现网能力

> 来源：`https://maker.taptap.cn/docs`
> 产品名：TapTap 制造
> 引擎：自研 **UrhoX**（基于 Urho3D 改造），脚本 **Lua**，预览跑 **WASM**

### 2.1 创作方式（两种）

| 方式 | 适合 | 主要体验 |
| --- | --- | --- |
| 浏览器工作区 | 零门槛 | 对话 + 预览 + 集中在一个页面 |
| **本地开发模式** | 想用自己 IDE/Agent | 本地目录 + **Maker MCP**（`@taptap/maker`），支持 Codex / Cursor / Claude Code |

本地开发初始化：

```bash
npx -y @taptap/maker install --ide codex,cursor,claude   # 单独装 MCP
npx -y @taptap/maker init                                # 一体化：登录+建项目+绑定+拉取
```

初始化后项目目录约定：

| 目录 | 用途 |
| --- | --- |
| `assets/` | 资源根 |
| `assets/image` | 普通图片 |
| `assets/sprites` | 精灵图 |
| `assets/video` | 视频 |
| `assets/audio` | 音频 |
| `scripts/` | 游戏脚本（Lua） |

### 2.2 项目支持的素材类型与格式

| 类型 | 可上传格式 | 单文件上限 | 备注 |
| --- | --- | --- | --- |
| 图片 | PNG / JPG / JPEG / WebP / GIF | 16 MB | 拒收 AVIF / HEIC / HEIF / SVG |
| 音频 | OGG / MP3 | 16 MB | — |
| 视频 | MP4 / WebM | 50 MB | 按 `video/*` MIME 识别 |
| Spine | `.skel` / `.json` / `.atlas` + 配套贴图 | 16 MB | 整文件夹或 zip 整包上传 |
| **3D 模型** | **GLB / FBX / MDL** + 材质 / 预制体 / 动画 / 贴图 | **50 MB** | GLB/FBX 自动生成缩略图，MDL 不生成 |

> ✅ **Tripo 默认输出 GLB —— 可直接吃下。**
> ✅ **Tripo `convert_model` 也支持转 FBX —— 双保险。**

支持 zip 整包上传，单个压缩包最多 500 个文件。文件夹嵌套最多 4 层。

### 2.3 Maker 内置的 AI 生成能力（按「让 AI 生成素材」官方说法）

> 在对话里直接描述素材，AI 会自动生成并写入项目。

| 素材 | 生成方式 |
| --- | --- |
| 图片 | 文本描述 |
| 音效 | 单条 / 一组批量 |
| BGM | 文本描述 |
| 角色配音 | 先试听音色，再生成台词 |
| **3D 模型** | **文本描述 / 参考图 / 现有 3D 素材库检索** |
| 发布物料 | 图标、截图等 |

> Maker 自带一个 3D 模型生成能力。**Tripo 是更专业、可控、可脚本化的备选/补充**。

### 2.4 运行环境与数据（理解引擎边界）

| 环境 | 进入方式 | 用途 |
| --- | --- | --- |
| 预览 | Maker 内置预览 | 快速验证 |
| 测试 | 分享链接 / 实机测试二维码 | 真实设备测试 |
| 线上 | TapTap 启动 | 正式玩家 |

**三种存档**（数据归属不同）：

| 类型 | API | 数据归属 |
| --- | --- | --- |
| 本地 | `File` / `FileSystem` | 当前设备当前用户 |
| 客户端云 | `clientCloud` | 当前登录用户 |
| 服务端 | `serverCloud` | 由 `userId` 索引（UrhoXServer） |

预览环境只跑 WASM，文件存内存，**刷新即丢**；实机测试/线上才会持久化。**素材数据一定要在实机环境验证**。

### 2.5 UI 主题（自带视觉风格）

| 主题 | 适合 |
| --- | --- |
| Astroon：宇宙卡通 | 太空/科幻/魔法奇幻/暗色氛围 |
| BrawlForge：竞技卡通 | 竞技对战、动作闯关、战斗 HUD |
| PixelForge：像素风 | 像素/复古街机/8-bit |

> 选定主题后，AI 会按该风格统一界面。

### 2.6 Skills（制造 Skills）

- 可安装的游戏开发知识/工作流包（Markdown + JSON + 脚本 + 参考图）
- 安装后 AI 可读取并遵循
- 每个 Skills 文件夹下载上限 2 MB
- 支持发布自己的 Skill

### 2.7 预览与发布

- 桌面预览支持 PC/Pad/手机分辨率模拟，可显示 TapTap 胶囊菜单
- 分享链接最多 100 人参与测试
- 实机测试二维码固定指向测试版
- 正式发布前置物料：**图标、≥3 张截图、宣传图、横版+竖版封面、≥10 字简介、≥10 字开发者的话、实机测试视频**（竖屏游戏还要方形宣传图）
- 发布面板操作不消耗创作积分

### 2.8 积分（Maker 内）

- 类型：周期 / 长期 / 活动 / 项目包 / 付费
- 消耗顺序：活动 → 项目包 → 周期 → 长期 → 付费
- 紧急积分申请条件：周期+长期 < 5000 时可一次性领 5000 长期积分
- 黑客松期间：每位参赛选手 10w 积分

### 2.9 重要边界

- 引擎是 UrhoX + Lua，**不是 Unity / UE / Godot**。你不能直接拖 .cs / .cpp / .gd 进去。
- 没有公开的「3D 模型导入脚本 API」——你只能把模型放到 `assets/` 目录或在素材面板上传，再让 AI 引用。
- Maker MCP 工具集由官方维护，具体可用清单以连接后 Agent 看到的为准。

---

## 3. 两者交集（资产 + 数据流）

### 3.1 模型格式交集（关键！）

| 来源 | Tripo 输出 | TapTap Maker 接受 |
| --- | --- | --- |
| 直接产出 | **GLB** | ✅ GLB |
| `convert_model` | GLTF / USDZ / **FBX** / OBJ / STL / 3MF | ✅ **FBX**（GLB 之外唯一 3D 兼容格式） |

> **首选方案：Tripo 直接给 GLB（默认产物）。次选：convert_model 转 FBX。**

### 3.2 文件大小

| | 上限 |
| --- | --- |
| Tripo `import_model` | 150 MB |
| Tripo STS 上传 | 20 MB |
| TapTap Maker 3D 模型单文件 | 50 MB |

**→ Tripo 单模型输出远小于 50 MB，TapTap 可直接收。**

### 3.3 任务/资源 ID 关系

- Tripo 用 `task_id` 串起所有下游（texture / rig / retarget / convert），**输出 URL 5 分钟过期**
- TapTap Maker 用 `project_id`（项目内通过 `assets/` 引用）——两边 ID 不互通，是各自系统

### 3.4 共同使用场景的能力对齐

| 能力 | Tripo | TapTap Maker |
| --- | --- | --- |
| 文本 → 3D | ✅ `text_to_model`（API） | ✅（AI 对话触发，自带） |
| 图片 → 3D | ✅ `image_to_model`（API） | ✅（参考图生成） |
| 4 视图 → 3D | ✅ `multiview_to_model`（API） | ❌ 无 |
| 骨骼绑定 | ✅ `animate_rig`（API） | ❌ Maker 无对应能力 |
| 预设动作 | ✅ `animate_retarget`（API） | ❌ Maker 无对应能力 |
| PBR 贴图 | ✅ `texture_model`（API） | ❌ Maker 不暴露 |
| 网格分割 | ✅ `mesh_segmentation`（API） | ❌ Maker 不暴露 |
| 智能低面数 | ✅ `highpoly_to_lowpoly`（API） | ❌ Maker 不暴露 |
| 模型格式转换 | ✅ GLB → GLTF/FBX/OBJ/STL/3MF/USDZ | ❌ |
| 多视角参考图 | ✅ `generate_multiview_image` | ❌ |
| 文/图生图 | ✅ `generate_image` | ✅（AI 对话触发） |
| BGM / 音效 / 配音 | ❌ | ✅ AI 内置 |
| Spine 动画 | ❌ | ✅ 内置支持 |
| 游戏逻辑 | ❌ | ✅ Lua 脚本 |
| 多人联机 / 排行榜 / 匹配 | ❌ | ✅ UrhoXServer + `serverCloud` |
| TapTap 平台发布 | ❌ | ✅ 一键发布 + 实机二维码测试 |

> **结论：Tripo 是「3D 资产生成深度工作流」的强项；TapTap Maker 是「游戏闭环 + 发布到 TapTap」的强项。两者是天然的上下游。**

---

## 4. 可行的联动模式

> 模式按「玩家可感知的内容复杂度」从轻到重排列。每条都注明可在 Tripothon 现场真实复现。

### 模式 A：Tripo 出单件模型 → Maker 用作素材

**最简方案。** 单独跑一个 Python 脚本，调用 Tripo 生成主角模型，下载 GLB，把它丢进 Maker 项目的 `assets/`（本地开发模式）或上传到素材面板（浏览器模式），再让 AI Agent 把模型放进场景。

```text
流程：
1. Tripo API：text_to_model P1 生成主角 GLB
2. 5 分钟内下载 GLB
3. 落到 Maker 项目 assets/ 目录
4. 在对话里告诉 Maker AI：「用 assets/hero.glb 做主角，添加 idle 动画」
```

**适用玩法**：剧情向、解谜、角色情感体验、放置类、3D 互动演示。

**实际产物**：Tripo 的动画是 bake 后的 GLB，Maker 加载后由 UrhoX 渲染。

---

### 模式 B：Tripo 出多个道具 + Maker 拼装场景

适合「送给某个对象的礼物」这种「小世界」作品。Tripo 一次性出 5–10 件道具，Maker AI 负责组合成场景/家具摆位/装饰物。

```text
流程：
1. Tripo 批量生成：礼物盒、蜡烛、信件、摆件、装饰品
   - 用 text_to_model P1，prompt 列表
   - face_limit=2000 控低面数（移动端友好）
2. 下载所有 GLB 到 assets/props/
3. 让 Maker AI：「按以下清单摆一个客厅场景，3D 透视，鼠标拖拽旋转视角」
```

**关键参数**：
- `face_limit: 1000~3000`：避免单模型太大拖慢移动端
- `texture: true, pbr: false`：拿基础贴图即可，Maker 自带光照
- `model_seed` 固定 → 可复现，调试时省事

**适用玩法**：场景解谜、叙事空间、礼物盒解谜。

---

### 模式 C：Tripo 出可动画角色 → Maker 用 Lua 驱动

Tripo 全自动出「能走的 NPC」。这是 Tripo 区别于 Maker 自带 3D 生成最明显的价值点。

```text
流程：
1. Tripo text_to_model P1 生成角色 GLB
2. animate_rig v2.5（spec: mixamo）→ 得到骨骼 GLB
3. animate_retarget preset:walk → 得到带动画的 GLB
4. 落到 Maker assets/characters/
5. Maker 端：AI 写 Lua 脚本，根据玩家输入切换动作
```

**注意**：
- `retarget` 输出含骨骼 + 动画，GLB 内嵌；Maker 直接吃
- 复杂多动作可用 `animations` 数组（≤5）一次出：idle + walk + run + jump + turn
- 复杂装备建议 `mesh_segmentation` → `mesh_completion`，分件后再 rig

**适用玩法**：3D 跑酷、互动故事、虚拟宠物、NPC 对话。

---

### 模式 D：Tripo 视图化 + Maker 二次加工

不直接传 GLB，而是把 Tripo 的 **渲染图** 当作参考，反向喂给 Maker 自带的 3D 生成/图像生成。

```text
流程：
1. Tripo text_to_model → rendered_image（产品宣传图）
2. 把图给 Maker AI：「照着这个风格做一个礼物盒 3D 模型」
```

**为什么有用**：Tripo 风格可控、质感强；Maker 自带 3D 生成更「懂游戏」，两者通过视觉风格桥接。

**适用玩法**：想要统一美术风格、但又需要快速迭代模型细节。

---

### 模式 E：Tripo 多视图做高精度道具 + Maker 用作关键 Boss/核心物件

主角/关键道具用 Tripo multiview 路线，凑齐 4 张视图后 `multiview_to_model` —— 这是 Tripo 在精度上最能打的入口。

```text
流程：
1. AI 一次性出 4 张图（前/左/后/右）作为角色概念稿
2. generate_multiview_image 拿到固定 4 视图
3. multiview_to_model H3 / P1（face_limit 高一些：8000）
4. Smart Low Poly（P-v2.0）转低面数
5. animate_rig → animate_retarget
6. 落到 Maker
```

**适用玩法**：核心角色 + 高精度 Boss，给玩家「这件作品是用心做的」感受。

---

### 模式 F：Tripo 做场景道具 + Maker 出场景骨架

Maker 自带 3D 引擎 + Lua，能搭场景骨架（地形、天空盒、相机、碰撞体）。Tripo 出主体物件。

```text
流程：
1. Maker AI：搭一个漂浮岛地形 + 第一人称相机 + 昼夜循环
2. Tripo：出树、屋、桥、灯、雕像 → assets/
3. Maker AI：把物件摆放进场景、连线脚本交互
4. Maker BGM/SFX：AI 一键出背景音乐和音效
```

**适用玩法**：3D 探索、解谜、世界构建类（与「A Gift for ______」主题高度契合）。

---

### 模式 G：Tripo 做 AR/3D 预览 → Maker 出可玩小游戏（应用赛道）

把 Tripo 3D 模型做成应用类作品的「展示 + 互动」核心。

```text
1. Tripo 出一个礼物盒 GLB（P1，face_limit=5000）
2. Maker：玩家点击礼物盒触发拆解动画（用 maker 的 Spine/2D 序列帧也可以）
3. Maker：拆开后生成文字信息、播放配音、记录到 clientCloud
```

**适用玩法**：送给某个具体对象的礼物拆解体验、送未来自己的时间胶囊。

---

### 模式 H（进阶）：批量工业化（如果做 30+ 模型的内容农场型作品）

Tripo API 是异步 + 任务队列，**适合脚本批量生成**。

```text
1. 准备 prompt 列表（CSV / JSON）
2. 用 tripo3d Python SDK 批量 POST → 拿到 task_id 列表
3. 异步轮询，下载所有 GLB（注意 5 分钟过期，必须并行处理）
4. 统一改名 + 落到 Maker assets/ 子目录
5. Maker AI 用脚本统一摆放
```

**Tripothon 建议**：与其用满 25,000 积分，不如先验证 1–2 件，再决定要不要批量化（Hackathon 时间短，批量化调试成本高）。

---

## 5. 面向 Tripothon S1 的实操建议

### 5.1 工具赛道选择建议

| 赛道 | 用 Tripo 的方式 | 用 Maker 的方式 |
| --- | --- | --- |
| 🎮 **游戏**（推荐组合） | 模式 A/C/E：出 1–3 个主角 + 几件道具 | Maker 搭场景 + Lua 玩法 + 发布 |
| 🎬 **影视 / 视效** | 模式 D：出风格图 + 关键物件 | Maker 内置 AI 协助叙事，但 Maker 不是动画工具——影视赛道建议还是用 Blender/UE |
| 🥽 **VR / XR / AR** | 模式 E：multiview 高精度单件 | Maker 跑的是 2D/WASM，预览里没有真 VR——VR 赛道请谨慎 |
| 📱 **应用（推荐组合）** | 模式 G：单个精美模型 + 互动 | Maker 搭应用 UI + TapTap 闭环发布 |
| 🛠️ **实体设计** | 模式 E：multiview 高精度 | 实体赛道 Maker 不太合适——Maker 没有 STL/3MF 整包处理工具，用 Blender |

### 5.2 工具赛道叠加

按赛事规则，可同时选 1 个方向赛道 + 0–3 个工具赛道：

- **Tripo 工具赛道**（推荐叠加）：用 `text_to_model` + `animate_rig` + `animate_retarget` 出可玩角色模型给 Maker 用 → **「Best Use of Tripo」可叠加**
- **TapTap 工具赛道**：未出现在赛事公布名单中（当前是 Tripo / PICO / Heygears / World Labs），**只能用 Maker 当开发工具，不能作为工具赛道参评**

### 5.3 时间线建议（Hackathon 周期短）

| Day | 动作 |
| --- | --- |
| Day 1–2 | Maker 起项目，搭玩法骨架 + Lua 核心循环 |
| Day 3 | 用 Tripo API（用 SDK）跑出主角/关键道具 GLB → 落到 `assets/` |
| Day 4 | 让 Maker AI 引用新模型，替换占位 |
| Day 5 | Tripo 出更多道具 + 动画 |
| Day 6 | Maker 端：实机测试二维码 + UI 调优 + 写简介 |
| Day 7 | 录演示视频 + 截图 + 提交 |

### 5.4 必交材料清单（按赛事规则）

- ✅ 完整可玩 Demo（Maker 给了 TapTap 实机测试二维码）
- ✅ 演示录屏视频（Maker 浏览器预览里直接录）
- ✅ 视觉资产看板（≥3 张核心场景截图）
- 可选：公开 Build Log（小红书 + #Tripothon，可冲 Mac Mini）

### 5.5 怎么让 Maker AI 真正调用上 Tripo 出的模型

本地开发模式下最稳：

```bash
npx -y @taptap/maker init
# 此时得到一个绑定到 TapTap 项目的本地目录，里头有 assets/ scripts/ 等
```

接下来：
1. 在外部跑 Python 脚本，下载 Tripo GLB 到 `assets/models/hero.glb`
2. 在同目录下让 Cursor/Claude Code 通过 Maker MCP 知道项目
3. 让 Agent：「用 `assets/models/hero.glb` 作为主角，添加 idle 走动状态，键盘左右移动」
4. Maker MCP 工具集会负责构建 + 预览

**避免踩坑**：不要试图在 Maker 对话里让 AI 直接调 Tripo API——Maker 内置 AI 不一定能感知到 Tripo 的 endpoint。**用本地 Agent 串接是更稳的姿势。**

---

## 6. 实现验证要求（Tripo × Maker 链路）

每次完成模型生成 / 导入 / 脚本对接后，按以下顺序验证：

1. **游戏是否能正常开始**
   - Maker 预览 / 实机测试可进入主场景。
   - 3 个角色模型正确显示，场景无崩溃。
2. **操作是否符合预期**
   - PC：WASD / 方向键移动、鼠标点击对话、鼠标拖拽旋转视角。
   - 手机：虚拟摇杆移动、点击角色对话、双指缩放 / 旋转视角。
3. **成功、失败和重新开始是否完整**
   - 成功：离线 1 小时后进入，角色头顶出现"在想你"气泡并带小时数。
   - 失败：网络超时 / 模型加载失败时，显示重试按钮。
   - 重新开始：支持回到上一次存档点。
4. **画面在目标设备上是否清楚**
   - 实机测试手机 + PC 预览。
   - 角色与 UI 可读，无严重掉帧。
   - 模型 `face_limit <= 5000`。
5. **是否存在卡住流程的问题**
   - 进入场景后首个事件可触发。
   - 对话、日记、离线检测不出现死循环或无限 loading。

## 7. 踩坑提醒

| 坑 | 现象 | 规避 |
| --- | --- | --- |
| **5 分钟 URL 过期** | Tripo 任务 success 后模型 URL 5 分钟失效 | 任务一 success 立刻下载；或写脚本循环 GET + 重下载 |
| **模型太大装不进 Maker** | 单文件 > 50 MB 被拒 | 用 `face_limit`（≤5000）+ `texture_quality: standard`，必要时 `export_uv: false`；或 `convert_model` 重新压 |
| **Tripo 上传 20 MB 限制** | 上传大 STL/OBJ 失败 | 用 `import_model` 的 ≤150 MB 通道；或先在外部用 `gltfpack` / `obj2glb` 压一下 |
| **骨骼数据被破坏** | rig 后跑 mesh 编辑，骨骼没了 | 顺序：先做网格编辑（segment/complete/lowpoly）→ 再 rig → 再 retarget |
| **MDL 模型没缩略图** | 素材面板里看不到图 | 直接用 GLB 或 FBX，避免 MDL |
| **Tripo 没有场景 API** | 想用 Tripo 一键出世界 | 现阶段不行，要用 Maker 自带 3D 引擎 + 自己拼接 |
| **Maker WASM 预览 ≠ 实机** | 浏览器里能跑，手机上卡 | 提交前用实机测试二维码在真机过一遍 |
| **三角面数过高** | Maker 移动端掉帧 | `face_limit` ≤ 5000，复杂件分件 |
| **贴图风格不一致** | Tripo 模型和 Maker 自带图片风格割裂 | 同一个 prompt 关键词反复用，或统一抽 reference image 喂给 `texture_model` |
| **Maker 引擎是 UrhoX 不是 Unity** | 习惯性写 `MonoBehaviour` | 用 Lua 写脚本，参考 Maker docs |
| **Tripo 1.x 模型的 task_id 无法走下游** | `convert_model` 报错 | 上游模型必须 ≥ `Turbo-v1.0-20250506` 或 `v2.0-20240919` |
| **FBX quad 输出** | Smart Low Poly `quad=true` 强制 FBX | 给 Maker 用没事，但要记得「只能用 FBX 不能换回 GLB」 |

---

## 附录 A：Tripo 任务类型与 task_id 链

```text
text_to_model ─┐
image_to_model ┼───► task_id ─┬─► texture_model        (换皮/换 PBR)
multiview_to_model┘           ├─► mesh_segmentation     (部件分割)
                               ├─► mesh_completion       (合并)
                               ├─► highpoly_to_lowpoly   (降面)
                               ├─► animate_rig           (绑骨)
                               ├─► animate_retarget      (套动画)
                               └─► convert_model         (改格式)

import_model ──────────────► task_id ─┬─► 上述所有下游
```

## 附录 B：Tripo API 一行调用样例

```python
# pip install tripo3d
import asyncio
from tripo3d import TripoClient, TaskStatus

async def main():
    async with TripoClient(api_key="YOUR_KEY") as c:
        # 1. 出主角
        tid = await c.text_to_model(
            prompt="a cute handmade ceramic kitten, gift style",
            model_version="P1-20260311",
            face_limit=4000,
            texture=True, pbr=True, texture_quality="standard",
        )
        # 2. 等
        task = await c.wait_for_task(tid, verbose=True)
        # 3. 下载（5 分钟内）
        if task.status == TaskStatus.SUCCESS:
            files = await c.download_task_models(task, "./assets/models/")
            # -> ./assets/models/{task_id}/model.glb

asyncio.run(main())
```

## 附录 C：Maker 项目里引用 GLB 的对话 prompt 模板

```text
我刚把一只陶瓷小猫的 GLB 模型放进了 assets/models/kitten.glb。
请帮我：
1. 在场景中放置这个模型，作为主角
2. 添加一个 idle 轻浮动动画（上下 5px，2s 周期）
3. 鼠标点击触发旋转一圈 + 弹出一个写着「送给我童年」的对话框
4. 配套一个 BGM 和点击音效（让 AI 用 Maker 内置生成）
```

> 这段 prompt 写在 `npx -y @taptap/maker init` 之后的本地目录里，让 Cursor/Claude Code + Maker MCP 一起执行。
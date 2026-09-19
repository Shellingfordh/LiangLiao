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

| 资产 | 首选格式 | 目标 | 说明 |
| --- | --- | --- | --- |
| 主角 | GLB | 单角色 ≤ 5,000 faces | 仅保留 PoC 需要的 idle、坐/看手机、walk 动作 |
| 小道具 | GLB | 单件 1,000–3,000 faces | 咖啡杯、书、唱片、背包、台灯等 |
| 备选 | FBX | 仅 GLB 导入失败时使用 | 必须先做 Maker 真机验证 |

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
| 360 panorama PNG（2560×1280） | 首选远景，先验证 Maker 图片/材质承载方式 |
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

| 内容 | 放置位置 | 接受格式 / 限制 |
| --- | --- | --- |
| 角色、低模道具 | `assets/` | GLB 首选；FBX 备选；单个 3D 文件上限 50 MB |
| 背景 / 远景 | `assets/image/` | PNG / JPG / JPEG / WebP / GIF；单文件上限 16 MB |
| 环境音 | `assets/audio/` | OGG / MP3；单文件上限 16 MB |
| 录制片段 | `assets/video/` | MP4 / WebM；单文件上限 50 MB |
| 状态与记忆 | `clientCloud` | JSON 序列化，真机验证持久化 |

### 实施边界

- Lua 决定时区、可用性、事件事实与去重；生成式文本只能润色既定事实；
- WASM 预览的内存状态不等于真机/线上持久化，离线事件与记忆必须在真机测试；
- Maker 中具体 Lua API 名称、Marble 全景的贴图接入与复杂 GLB 动画支持都必须先实测，不能从旧模板推断；
- 发布前准备图标、至少 3 张截图、宣传图/封面、简介、开发者的话和实机视频。

官方入口：<https://maker.taptap.cn/help>、<https://maker.taptap.cn/skills>。

## 5. 最小验证顺序

1. Tripo 导出原创角色 GLB → Maker 真机显示；
2. Marble 导出一个咖啡馆全景/镜头 → Maker 状态窗背景；
3. Lua 计算洛杉矶当地时间并切换状态；
4. `clientCloud` 保存一条消息、一次事件和一条共同记忆；
5. 之后才扩展城市、动画、音效和视觉资产。

若任一步失败，保留上一步已验收资产，选择低成本回退；不在运行时引入新的外部服务。

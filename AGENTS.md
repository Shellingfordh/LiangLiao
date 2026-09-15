# AGENTS — 项目背景

## 项目一句话

《送给你这个回来的人》是 Tripothon S1 的原创陪伴体验：用户与一位生活在另一座城市、同一真实时间线上的角色聊天；她有自己的日程与关系网络，3D 状态窗展示她此刻的生活。

## 硬边界

- 只使用原创角色、场景、文本、音乐和视觉资产；不得复刻现有 IP。
- 聊天优先；3D 窗口是固定镜头状态展示，不做开放大地图。
- Lua 负责时间、状态、事件事实和存档；生成式文本只能润色既定事实。
- 不接入真实天气、新闻或运行时 Tripo/Marble 调用；离线状态按时间窗反推。
- Marble 高质量网格不得直接作为移动端主场景，除非先通过 Maker 真机性能 Spike。

## 权威文档

| 文件 | 用途 |
| --- | --- |
| `docs/superpowers/specs/2026-09-15-parallel-companion-design.md` | 产品、数据模型、时间状态、场景、PoC 范围与验收 |
| `docs/platform-capabilities.md` | Tripo、Marble、TapTap Maker 的能力、格式、资产流程与限制 |
| `docs/demand.md` | Tripothon S1 赛事规则与提交物 |
| `CHANGELOG.md` | 当前阶段与已完成决策 |

`research/game-design-sources/` 保留非 IP 的通用竞品、叙事、关系系统与生活模拟原始调研；不得恢复其旧的 `bocchi/` 目录或以原作角色为查询目标。

## 实施起点

1. 先完成 Tripo 角色 GLB 和 Marble 背景/镜头在 Maker 真机的 M0 Spike；
2. 用 `npx -y @taptap/maker init` 创建实际 Maker 项目；
3. 在实际项目 Dev Kit 中确认 Lua API、资产导入和 `clientCloud` 行为；
4. 通过 M0 后，才实现时区、消息排队与关系记忆。

不要恢复或引用已移除的旧“三位 NPC 小镇”方案、旧角色名或旧 PoC 模板。

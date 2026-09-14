# TapTap Maker 技术调研报告

> 基于 2026-09-10 对 maker.taptap.cn、developer.taptap.cn、TapTap 应用商店的爬取和分析

---

## 一、TapTap Maker 定位

**一句话定位**：零门槛 AI 游戏创作工具，"对话即创作，完成即发布"

**官网**：https://maker.taptap.cn  
**Maker Studio**（云端开发环境）：https://developer.taptap.cn/forge（需登录）  
**开发者文档**：https://developer.taptap.cn/maker/docs（需登录）

---

## 二、两种开发模式

### 模式 A：云端 Maker Studio（浏览器）
- 地址：`developer.taptap.cn/forge`
- 特点：浏览器内一体化开发环境，无需本地安装
- 需要 TapTap 开发者账号登录
- **结论：文档需登录才能访问，无法直接爬取**

### 模式 B：本地开发（MCP 协议）
- 支持任何 MCP 兼容 AI 工具：Codex、Cursor、Claude Code
- 安装命令：`npx -y @taptap/maker install --ide codex,cursor,claude`
- 初始化项目：`npx -y @taptap/maker init`（在空目录中执行）
- **这是我们可以实际开发的路径**

---

## 三、核心架构

| 特性 | 描述 |
|------|------|
| **AI Native 引擎** | Code-First，AI 对游戏逻辑、美术、音乐的全栈掌控 |
| **工业级 3D 游戏底座** | 高性能渲染管线、物理引擎、PBR 物理渲染、动态多光源、动力学解算 |
| **内置联网对战** | 开箱即用的联机能力 |
| **免费工具和服务器** | 免费 Token 额度，TapTap 云原生基础设施，零运维、零成本、自动扩缩 |

**引擎名称**：UrhoX（从 Leaderboard 页面确认）

---

## 四、重要限制（来自服务协议 §2.1）

> ⚠️ 以下为官方明确声明的限制

1. **❌ 不提供源码导出** — 不提供输出内容对应的底层源代码导出及交付服务
2. **❌ 不生成独立运行包** — 不生成可脱离平台环境独立分发、运行的源代码包或二进制文件
3. **❌ 不交付底层引擎代码** — 不负责解释、修改或交付工具基础代码、引擎渲染逻辑等部分

**影响**：游戏完全在 TapTap Maker 生态内运行，无法导出到其他平台。

---

## 五、发布与部署

- **一键发布**：通过输入指定口令将游戏发布到 TapTap 平台
- **自动托管**：TapTap 云原生基础设施，零运维、自动扩缩
- **跨平台**：支持安卓、iOS、PC 端（从展示游戏页面确认）
- **试玩 DEMO**：可直接在 TapTap PC 端下载试玩

---

## 六、TapTap Maker Benchmark 排行榜

> 评测 AI 在 TapTap Maker 场景下开发真实游戏的能力，由 UrhoX 引擎真实执行，无 LLM 裁判。

### Top 10 模型（2026-09-10 数据）

| 排名 | 模型 | L2 通过率 | 每题成本 (¥) |
|------|------|-----------|-------------|
| 1 | claude-fable-5-1 (high) | 90.5% | 25.20 |
| 2 | claude-fable-5 (high) | 89.0% | 31.82 |
| 3 | gpt-6-astra (xhigh) | 88.9% | 21.85 |
| 4 | claude-opus-5 (xhigh) | 88.9% | 48.72 |
| 5 | muse-spark-1.3 (xhigh) | 87.3% | 4.93 |
| 6 | grok-4.6 (xhigh) | 87.3% | 7.96 |
| 7 | gemini-3.8-flash (high) | 86.8% | 5.35 |
| 8 | gpt-5.6-sol (xhigh) | 86.5% | 15.79 |
| 9 | claude-opus-5 (high) | 86.5% | 31.13 |
| 10 | grok-4.6 (high) | 84.1% | 6.12 |

### 性价比最优
- **qwen3.8-flash (xhigh)**：82.5% 通过率，仅 ¥0.69/题
- **deepseek-v4-flash (max)**：74.6% 通过率，仅 ¥0.73/题
- **deepseek-v4.1-flash (max)**：82.5% 通过率，仅 ¥0.95/题

---

## 七、展示游戏案例分析

### 1. 微观战争（弹幕射击）
- **类型**：割草 / 弹幕射击 / 模拟
- **评分**：4.2（8 条评价）
- **玩法**：在微观世界中操控免疫细胞，对抗病毒、细菌等病原体
- **操作**：WASD/方向键移动，鼠标瞄准射击，空格使用技能
- **反馈**：手机端操控困难，PC 端体验更好；难度较高
- **TapTap 链接**：https://www.taptap.cn/app/810894

### 2. TowerHell 塔楼跑酷（3D 跑酷）
- **类型**：平台跳跃 / 竞速 / 跑酷
- **评分**：3.6（80 条评价）
- **玩法**：从塔底攀爬到金色塔顶，六大平台类型（静态/旋转/移动/掉落/窄桥/弹跳）
- **特色**：随机生成塔楼、8 层递进难度、计时挑战、第三人称视角
- **灵感来源**：Roblox Tower of Hell
- **反馈**：跳跃按键太小、操控不灵敏、难度过高
- **TapTap 链接**：https://www.taptap.cn/app/813196

### 3. 霓虹防线（塔防）
- **类型**：割草 / 塔防 / 策略
- **评分**：暂无评分（2 条评价）
- **玩法**：极简线条视觉风暴，霓虹塔可进化四次，编织弹幕网络
- **特色**：数据主题、赛博风格、纯视觉爽感
- **反馈**：类似保卫萝卜、激光晃眼、缺少音效
- **TapTap 链接**：https://www.taptap.cn/app/813265

### 4. TapTap 制造应用 - PC端官方参与测试
- **TapTap 链接**：https://www.taptap.cn/app/810249
- 这是 TapTap Maker 本身的测试入口

---

## 八、对项目的影响与建议

### 项目约束
1. **必须使用 TapTap Maker**：不能自行开发引擎或使用其他框架
2. **只能在 TapTap 生态内发布**：无法导出到其他平台
3. **MCP 是本地开发的唯一路径**：通过 `@taptap/maker` npm 包接入

### 开发建议
1. **优先使用 MCP 本地开发**：更灵活，可以配合 Claude Code 等 AI 工具
2. **游戏类型选择**：
   - 展示案例覆盖了弹幕射击、3D 跑酷、塔防
   - 可以考虑叙事向游戏（与山田凉/后藤一里角色契合）
   - TapTap Maker 支持 3D 游戏，适合制作角色互动场景
3. **角色资产**：
   - 使用 Tripo Studio 生成 3D 模型
   - 导出为 Maker 支持的格式
4. **叙事设计**：
   - 可借鉴 mattpocock/skills 中的 `writing-fragments` → `writing-shape` → `writing-beats` 工作流
   - 先用 `grilling` 技能深入挖掘山田凉的角色故事

### 下一步行动
1. 安装 TapTap Maker MCP：`npx -y @taptap/maker install`
2. 初始化项目：`npx -y @taptap/maker init`
3. 尝试创建第一个简单场景，验证 MCP 工作流
4. 结合 Tripo 生成的 3D 模型进行集成测试

---

## 九、数据来源

- maker.taptap.cn 首页（公开可访问）
- TapTap Maker Benchmark Leaderboard（公开可访问）
- TapTap 应用商店展示游戏页面（公开可访问）
- TapTap 制造服务协议（公开可访问）
- Playwright 爬取时间：2026-09-10 21:33-21:38

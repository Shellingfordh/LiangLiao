# Build Log — 送给你这个回来的人

> 7 天 PoC 计划。每条记录："做了什么 / 踩了什么坑 / 下一步是什么"。

---

## Day 0（2026-09-10）—— 选题与设计

### 完成
- [x] 把 Tripothon S1 的赛事规则存到 `docs/demand.md`
- [x] 调研 Tripo OpenAPI 全部 19 个端点 → `docs/integration.md`（540 行，8 个联动模式）
- [x] 调研 TapTap Maker 全部 12 篇文档 → 同上
- [x] 调研 AI Town (`mewamew/my_ai_town`) + HelloAgents ch15 + Generative Agents 论文
- [x] 选题定稿：「送给你这个回来的人 / A Gift for 'You Who Came Back'」
- [x] 设计三大子系统（Tripo 出角色 / Maker AI + Lua 调度事件 / clientCloud 持久化时间线）
- [x] 写 `docs/topic.md`（265 行）
- [x] 写 `poc/README.md` + `poc/tripo-gen.py` + `poc/tripo-prompts.json` + `poc/.env.example`
- [x] 写 Maker 模板：`scripts/{main,event_scheduler,time_sync,memory_io,bubble}.lua`
- [x] 写 Maker 模板：`scripts/role/{xiaoman,aize,grandma}.lua`
- [x] 写 Maker AI Prompt：`prompts/{skill,xiaoman.system,aize.system,grandma.system,event.system}.md`
- [x] 写 `poc/architecture.md` + `poc/demo-walkthrough.md` + 本 build-log

### 下一步
- Day 1：用户拿到 TRIPO_API_KEY 后跑 `python tripo-gen.py`，出 3 个角色 GLB
- Day 1：同时初始化 Maker 本地项目

---

## Day 1（计划）—— 第一个角色跑通

### 目标
- [ ] 跑通 `tripo-gen.py --only xiaoman`，拿到 `xiaoman.glb`
- [ ] 初始化 Maker 项目：`npx -y @taptap/maker init`
- [ ] 把 `xiaoman.glb` 拷到 `assets/models/`
- [ ] 在 Maker 对话里跟 AI 说"放一个小满角色在面包店"
- [ ] 实机测试：手机扫码能看到小满

### 验收
- 手机屏幕上能看到一个站立的二次元少女角色
- 点击角色能打开对话面板

### 风险
- Tripo 出的二次元不够像二次元 → 改 prompt / 改 `negative_prompt` / 调高 `face_limit`
- Maker 不认识 GLB 里的骨骼 → 关闭骨骼只用 mesh（v2.5-20260210 rig 任务先不做）

---

## Day 2（计划）—— 3 角色都到位

### 目标
- [ ] 跑 `tripo-gen.py`，出 3 个角色
- [ ] 把 3 个 GLB 都拷到 `assets/models/`
- [ ] 让 Maker AI 把 3 个角色放在 面包店 / 图书馆 / 镇郊菜园
- [ ] 让 Maker AI 配置 3 个角色的对话 system prompt（来自 `prompts/*.system.md`）

### 验收
- 手机屏幕上 3 个角色各自站在合理位置
- 点击任一角色能打开符合人设的对话

---

## Day 3（计划）—— 头顶气泡 + 走近打招呼

### 目标
- [ ] 接入 `scripts/event_scheduler.lua` + `scripts/ui/bubble.lua`
- [ ] 玩家走近角色 5 米内 → 触发"打招呼"气泡
- [ ] 头顶气泡 UI 样式选定（Astroon 的 SpeechBubble）

### 验收
- 玩家走近小满 → 头顶出现"嘿，你来啦。今天来得早嘛。"
- 走近阿泽 → 出现"……你来了。今天想借什么？"
- 走近奶奶 → 出现"哎呀来啦？刚摘的小白菜，带点回去。"

---

## Day 4（计划）—— 离线事件触发

### 目标
- [ ] 接入 `scripts/main.lua` + `scripts/time_sync.lua` + `scripts/memory_io.lua`
- [ ] 玩家离开 ≥ 1 小时再回来 → 3 个角色头顶都出现"在想你"气泡（带具体小时数）
- [ ] 玩家离开 ≥ 24 小时再回来 → 📮 信箱按钮变红，显示离线累积

### 验收
- 关闭 App → 等 1 小时 → 重进 → 三个角色头顶同时出现气泡
- 关闭 App → 等 24 小时 → 重进 → 信箱有 24 小时累积的事件

---

## Day 5（计划）—— 日记 UI

### 目标
- [ ] 在 Maker AI 对话里请求"按 event.system.md 实现日记面板"
- [ ] 每个角色可点击 💭 图标 → 弹出最近 7 天的日记
- [ ] 日记按 `prompts/<role>.system.md` 的人格生成

### 验收
- 点小满的 💭 → 看到最近 3 天的面包店日记，风格暖系、嘴硬心软
- 点阿泽的 💭 → 看到图书馆日记，风格安静、偶尔引书
- 点奶奶的 💭 → 看到菜园日记，风格慈祥、提节气

---

## Day 6（计划）—— 实机测试 + 发布物料

### 目标
- [ ] 在真机（iPhone / 安卓）扫码测试全部功能
- [ ] 录 1~2 分钟 walkthrough 视频（按 `demo-walkthrough.md`）
- [ ] 截 ≥3 张图（镇口全景 / 3 角色特写 / 事件触发界面）
- [ ] 准备图标、宣传图、简介、开发者的话

### 验收
- 视频里能看到：进入小镇 → 走近 3 角色 → 离开 → 24h 后回到 → 信箱有 24 条事件
- 截图清晰、二次元风格一致

---

## Day 7（计划）—— 提交 + 社媒发布

### 目标
- [ ] TapTap 制造发布面板更新测试版
- [ ] 录最终视频（含离线再进入的关键场景）
- [ ] 在小红书写 Build Log + @TripoAI + #Tripothon
- [ ] Tripothon 平台提交

### 验收
- 实机测试链接可点
- 视频上传完毕
- 提交表单填完（项目名 / 简介 / 工具赛道勾选）

---

## 风险日志

| 日期 | 风险 | 触发条件 | 应对 |
| --- | --- | --- | --- |
| Day 0 | Tripo 出的二次元不够二次元 | prompt 没生效 | 加 `negative_prompt: realistic, photographic, 3d render` |
| Day 0 | Maker AI 不按 system prompt 演 | prompt 没注入 | 改成在对话面板手动贴 system prompt |
| Day 0 | clientCloud 写入失败 | 实机网络问题 | 让 AI 加本地内存 fallback |
| Day 0 | Maker Lua API 实际命名不同 | 推测的命名不对 | 让 AI 修正（AI 能读 skill.md） |

---

## 时间总览

- 设计 / 文档：~6 小时（Day 0）
- 跑通 3 角色 GLB：~2 小时（Day 1~2）
- 接入事件调度：~3 小时（Day 3~4）
- 日记 UI + 实机测试：~3 小时（Day 5~6）
- 录屏 + 发布：~2 小时（Day 6~7）

**合计：~16 小时**，分 7 天完成，符合"7 天可交付"目标。
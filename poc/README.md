# PoC：送给你这个回来的人

> Tripothon S1 项目 PoC —— 「送给你这个回来的人 / A Gift for 'You Who Came Back'」
> 选题与设计详见 [`docs/topic.md`](../docs/topic.md)
> 联动调研详见 [`docs/integration.md`](../docs/integration.md)

---

## 这是什么

一个陪伴型二次元小镇 PoC：

- **3 个二次元角色**（小满/阿泽/奶奶），每个由独立的事件生成器驱动
- **平行时间线**：基于真实 wall clock，玩家离开后角色继续"活着"
- **离线反推**：玩家回来时根据时间差生成可信的事件累积
- **Maker AI 扮演对话**：所有文案由 Maker 内置 AI 按 system prompt 生成

**关键能力出处**：
- 角色 3D 模型：Tripo OpenAPI `text_to_model` (P1-20260311) → GLB
- 资产投递：Maker 项目 `assets/models/`（GLB 直接吃）
- LLM 对话：Maker 内置 AI（通过 Skill 注入 system prompt）
- 数据持久化：Maker `clientCloud`
- 触发逻辑：Lua 脚本（无外部后端）

---

## 目录结构

```
poc/
├── README.md                          ← 你在这里
├── tripo-gen.py                       ← Tripo 批量生成脚本（唯一 Python 依赖：requests + python-dotenv）
├── tripo-prompts.json                 ← 3 角色 + 3 道具的 prompt 配置
├── requirements.txt
├── .env.example                       ← 复制成 .env 后填 TRIPO_API_KEY
├── maker-template/                    ← Maker 本地项目骨架
│   ├── scripts/
│   │   ├── main.lua                   ← 入口
│   │   ├── event_scheduler.lua        ← 调度 + 去重
│   │   ├── time_sync.lua              ← 时间差反推
│   │   ├── memory_io.lua              ← clientCloud 封装
│   │   ├── role/
│   │   │   ├── xiaoman.lua            ← 小满的事件触发
│   │   │   ├── aize.lua               ← 阿泽
│   │   │   └── grandma.lua            ← 奶奶
│   │   └── ui/
│   │       └── bubble.lua             ← 头顶气泡
│   └── prompts/
│       ├── skill.md                   ← Maker Skill（工作流）
│       ├── xiaoman.system.md
│       ├── aize.system.md
│       ├── grandma.system.md
│       └── event.system.md            ← 事件生成器 system prompt
├── build-log.md                       ← 7 天开发日志
├── demo-walkthrough.md                ← 录屏脚本
└── architecture.md                    ← 系统架构图 + 数据流
```

---

## 跑起来：5 步

### 第 1 步：装依赖 + 拿 Tripo API key

```bash
pip install -r requirements.txt
cp .env.example .env
# 用编辑器打开 .env，把 TRIPO_API_KEY= 后面的占位符换成你的真实 key
# key 在 https://platform.tripo3d.ai/api-keys 申请
```

### 第 2 步：跑 Tripo 生成脚本

```bash
# 跑全部（3 角色 + 3 道具）
python tripo-gen.py

# 只跑角色
python tripo-gen.py --characters-only

# 只跑小满 + 阿泽
python tripo-gen.py --only xiaoman,aize

# 输出在 ./out/models/，每个 .glb 旁边有 metadata.json 记录 task_id
```

预期耗时：每个角色 30~120 秒。失败的任务会记录在 metadata.json 的 `failed` 字段，可以重跑（脚本会自动去重——同 ID 已存在的 GLB 不重新下载）。

### 第 3 步：把模型拷到 Maker 项目

```bash
# 假设你已经在本地 init 了 Maker 项目：npx -y @taptap/maker init
# 把 Tripo 出的 GLB 拷到 Maker 项目的 assets/models/
cp out/models/*.glb /path/to/maker-project/assets/models/

# 把 maker-template/scripts/ 里的 Lua 文件拷到 Maker 项目的 scripts/
cp maker-template/scripts/*.lua maker-template/scripts/role/*.lua maker-template/scripts/ui/*.lua /path/to/maker-project/scripts/

# 把 prompts/ 里的 markdown 拷到 Maker 项目的 prompts/
cp maker-template/prompts/*.md /path/to/maker-project/prompts/
```

### 第 4 步：在 Maker 里装 Skill

1. 在 Maker 工作区的"Skills"面板点"创建 Skill"
2. 把 `maker-template/prompts/skill.md` 的内容粘进去
3. 设为公开/私有都行（PoC 阶段私有即可）
4. 安装到自己的账号

### 第 5 步：跟 Maker AI 对话

打开 Maker 对话面板，输入：

```
按 skill.md 的工作流继续。先用 assets/models/ 里现有的 3 个 GLB（xiaoman.glb, aize.glb, grandma.glb），
分别放在 面包店 / 图书馆 / 镇郊菜园。
按 prompts/event.system.md 的事件生成规则接入事件调度。
点击角色时按 prompts/<role>.system.md 的人格对话。
```

Maker AI 会自己读 skill.md，按里面的 Step 1~6 推进。

---

## 验收清单

完成后按这个清单测：

### 阶段 1：游戏是否能正常开始
- [ ] TapTap Maker 预览 / 实机测试入口可正常进入主场景
- [ ] 3 个角色站在各自位置，模型正确显示
- [ ] 场景无黑屏 / 白屏 / 崩溃

### 阶段 2：操作是否符合预期
- [ ] PC：WASD / 方向键移动、鼠标点击对话 / 交互、鼠标拖拽旋转视角
- [ ] 手机：左侧虚拟摇杆移动、右侧点击角色触发对话、双指缩放 / 旋转视角
- [ ] 走近任一角色，头顶出现"打招呼"气泡
- [ ] 点击角色打开对话，文案符合人设（小满嘴硬心软 / 阿泽安静博学 / 奶奶慈祥爱操心）
- [ ] 所有交互在 2 次点击内可完成，无菜单卡死

### 阶段 3：成功、失败和重新开始是否完整
- [ ] 成功：关闭 App 1 小时以上再进入，3 个角色头顶都出现"在想你"气泡，**带具体小时数**
- [ ] 成功：关闭 24 小时再进入，📮 信箱按钮显示红色数字，点击能看到离线事件和日记
- [ ] 失败：定义明确的失败条件与提示（如网络超时、存档损坏、模型加载失败），并有"重试 / 重新开始"入口
- [ ] 重新开始：支持从头开始 / 回到上一次存档点，且状态恢复一致

### 阶段 4：画面在目标设备上是否清楚
- [ ] 目标设备：Maker 实机测试手机 + PC 预览
- [ ] 角色与 UI 在真机分辨率下可读、无严重锯齿 / 掉帧
- [ ] 3D 模型面数控制在移动端可接受范围（建议 `face_limit <= 5000`）

### 阶段 5：是否存在卡住流程的问题
- [ ] 从进入到触发首个事件，无死循环、无无限 loading、无对话卡死
- [ ] 离线时间检测准确，不会出现事件不触发或重复触发导致流程中断
- [ ] 所有必交物（Demo / 录屏 / 截图）可在流程内正常生成
- [ ] 点奶奶的 💭：能看到节气提醒 / 蔬菜熟了 / 日记条目

---

## 已知限制

1. **Maker AI 的 system prompt 遵循程度**依赖 Skill 安装质量。如果发现角色跑题，强化对应 `<role>.system.md` 里的"绝对不要"。
2. **Lua API 的真实名称**以连接后 Maker AI 看到的为准。本脚本里的 `clientCloud.Get` `clientCloud.Set` `clientCloud.SetInt` `clientCloud.GetInt` `ui.CreateNode` `ai.OpenConversation` 是按文档推测的命名；如果实际不同，让 AI 帮忙修正。
3. **离线事件反推是按规则生成的，不是真"模拟运行"**。Maker 引擎限制，无法后台跑 NPC。这是按 `docs/integration.md §2.4` 的"无法做持续后台"约束做的妥协方案。
4. **没有真实视频/截图**。PoC 阶段按 `demo-walkthrough.md` 录制即可。

---

## 下一步

- 录屏 → 写 README → 提交到 Tripothon
- 详见 `build-log.md` 和 `demo-walkthrough.md`
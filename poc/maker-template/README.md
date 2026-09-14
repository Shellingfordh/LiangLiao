# Maker Template

> 这是 TapTap Maker 本地开发项目骨架的 **代码部分**。
> 用户需要在本地用 `npx -y @taptap/maker init` 创建一个真正的 Maker 项目，然后把这里的文件拷过去。

---

## 怎么用

### Step 1：在本地初始化 Maker 项目

```bash
mkdir my-town && cd my-town
npx -y @taptap/maker init
```

按提示登录、选择/创建 Maker 项目、绑定本地目录。

### Step 2：拷贝文件

把 `scripts/` 和 `prompts/` 拷到 Maker 项目根目录：

```bash
cp -r /path/to/poc/maker-template/scripts ./
cp -r /path/to/poc/maker-template/prompts ./
```

把 Tripo 出的 GLB 拷到 `assets/models/`：

```bash
mkdir -p assets/models
cp /path/to/poc/out/models/*.glb assets/models/
```

### Step 3：安装 Skill

在 Maker 工作区的 "Skills" 面板：

1. 点 "创建 Skill"
2. 把 `prompts/skill.md` 的全部内容粘到 Skill 描述里
3. 把 `prompts/event.system.md` 作为 Skill 的"事件生成规则"附注
4. 把 3 个 `prompts/<role>.system.md` 作为附件上传
5. 保存并安装到当前账号

### Step 4：跟 Maker AI 对话

在 Maker 对话面板输入：

```
我已经把 skill.md 装好了，并且 assets/models/ 里有 xiaoman.glb, aize.glb, grandma.glb。
请按 skill.md 的工作流继续。

第一步：在主场景里创建 3 个 NPC，分别叫 小满/阿泽/奶奶，放在 面包店/图书馆/镇郊菜园。
第二步：每个 NPC 对话时按对应 prompts/<role>.system.md 的人格回复。
第三步：把 scripts/event_scheduler.lua 接入主循环，让玩家走近 5 米内触发打招呼。
第四步：把 scripts/main.lua 设为进入主场景时的初始化函数。
第五步：把 scripts/time_sync.lua 的离线事件反推接入 last_visit_ts。
```

Maker AI 会按 skill.md 的 Step 1~6 推进，遇到 Lua API 命名问题时让它自己修正。

---

## 文件清单

```
scripts/
├── main.lua                   ← 入口（玩家进入主场景时调用）
├── event_scheduler.lua        ← 事件调度（去重 + 优先级）
├── time_sync.lua              ← 时间差反推
├── memory_io.lua              ← clientCloud 封装
├── role/
│   ├── xiaoman.lua            ← 小满的事件触发（早 7 点面包出炉）
│   ├── aize.lua               ← 阿泽（下午 3 点新书）
│   └── grandma.lua            ← 奶奶（节气当天）
└── ui/
    └── bubble.lua             ← 头顶气泡

prompts/
├── skill.md                   ← ★ 装到 Maker 的 Skill 面板
├── xiaoman.system.md          ← 小满人格
├── aize.system.md             ← 阿泽人格
├── grandma.system.md          ← 奶奶人格
└── event.system.md            ← 事件生成规则
```

---

## 注意事项

1. **Lua API 实际命名**：本模板里的 `clientCloud.Get` `clientCloud.Set` `ui.CreateNode` `ai.OpenConversation` 是按 TapTap Maker 文档推测的命名。实际连接到 Maker 后，**让 AI 读取它的 MCP 工具清单**，如有不同则让 AI 帮忙替换。

2. **JSON 解析**：`pcall(json.decode, raw)` 是 Lua 标准模式。如果 Maker 实际使用的 Lua 版本不带 JSON 库，让 AI 加 `require("json")` 或换用 cjson。

3. **客户端存档 `clientCloud`**：只在 Standalone / Client 模式可用。预览环境（WASM）也能用，但刷新即丢。**所有云存档数据必须在实机测试 / 线上环境验证**，不要只看预览。

4. **气泡组件**：本模板假设 Maker 内置 UI 主题（Astroon / BrawlForge / PixelForge）有 `SpeechBubble` 组件。如果没有，让 AI 在对话里要求"用现有 UI 组件做一个头顶气泡"。

5. **Maker AI 的 system prompt 注入**：Skill 装好后，AI 在被调用时能自动读取。但对话内容生成时，让 AI 显式 `LoadSystemPrompt("prompts/xiaoman.system.md")` 会更稳。
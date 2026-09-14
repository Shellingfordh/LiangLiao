# TapTap Maker 架构与技术指南

> 基于对 [taptap/instant-games-open-mcp](https://github.com/taptap/instant-games-open-mcp) 仓库的深度分析

---

## 一、整体架构

TapTap Maker 采用 **CLI-first + MCP Server** 的架构设计：

```
┌─────────────────────────────────────────────────────────────┐
│                    AI 客户端 (Claude Code / Codex / Cursor)  │
├─────────────────────────────────────────────────────────────┤
│                      MCP 协议层                              │
├─────────────────────────────────────────────────────────────┤
│  Maker CLI (一次性)  │  Maker MCP Server (运行时)           │
│  - 登录/PAT          │  - 项目状态查询                       │
│  - 项目选择/创建     │  - 远端构建/提交                      │
│  - Git clone         │  - 素材生成 (图片/音频/视频/3D)       │
│  - Dev Kit 安装      │  - 运行时日志                         │
│  - MCP 配置写入      │  - Proxy Tools                        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    TapTap 云基础设施                          │
│  - UrhoX 游戏引擎                                            │
│  - 远端构建服务                                              │
│  - 素材生成服务 (AI 图片/音频/视频/3D)                       │
│  - 游戏托管与分发                                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、核心组件

### 2.1 Maker CLI (`@taptap/maker`)

**职责**：一次性初始化流程

```bash
npx -y @taptap/maker init
```

**工作流程**：
1. **环境检查**：Git、Python、maker-lua-lsp
2. **登录认证**：OAuth 2.0 Device Code Flow（扫码登录）
3. **项目选择**：从 TapTap 开发者账号的 app 列表选择，或创建新项目
4. **Git Clone**：拉取 Maker 项目代码到本地
5. **Dev Kit 安装**：安装 AI 开发工具包（CLAUDE.md、examples、templates、urhox-libs）
6. **MCP 配置**：写入 Claude Code / Codex / Cursor 等客户端的 MCP 配置

**常用命令**：
```bash
taptap-maker init          # 初始化/克隆项目
taptap-maker login         # 登录
taptap-maker doctor        # 诊断环境
taptap-maker apps          # 列出应用
taptap-maker install       # 安装 MCP
taptap-maker dev-kit update  # 更新 Dev Kit
taptap-maker lua-lsp setup   # 设置 Lua LSP
```

### 2.2 Maker MCP Server

**职责**：运行时开发支持

**核心 Tools**：
| Tool | 功能 |
|------|------|
| `maker_status_lite` | 查询项目状态 |
| `maker_build_current_directory` | 提交/推送/构建（一站式） |
| `generate_image` | AI 生成图片 |
| `batch_generate_images` | 批量生成图片 |
| `edit_image` | 编辑图片 |
| `create_video_task` | 生成视频 |
| `text_to_music` | 文本生成音乐 |
| `text_to_sound_effect` | 文本生成音效 |
| `text_to_dialogue` | 文本生成对话 |
| `create_3d_asset` | 生成 3D 素材 |
| `generate_test_qrcode` | 生成测试二维码 |
| `get_ad_config` | 获取广告配置 |
| `get_debug_feedbacks` | 获取玩家反馈 |

**Resources**：
- `maker://status` — 项目完整状态信息
- `maker://runtime_logs` — 运行时日志

### 2.3 AI Dev Kit

**安装位置**：项目根目录下

```
project/
├── CLAUDE.md           # 主 AI 开发指南（必读）
├── examples/           # 可运行的示例代码
├── templates/          # 文件模板
├── urhox-libs/         # UrhoX 引擎 API 文档
├── .project/
│   ├── project.json    # 项目配置
│   └── settings.json   # 构建设置
└── scripts/
    └── main.lua        # 入口脚本
```

**关键文件说明**：
- `CLAUDE.md`：开发前必读，包含引擎 API、开发规范、常见模式
- `examples/`：各种游戏功能的示例代码（移动、碰撞、UI 等）
- `templates/`：创建新文件的模板
- `urhox-libs/`：UrhoX 引擎的完整 API 参考

---

## 三、UrhoX 游戏引擎

### 3.1 引擎特性

| 特性 | 说明 |
|------|------|
| **渲染** | 高性能渲染管线、PBR 物理渲染、动态多光源 |
| **物理** | 内置物理引擎、碰撞检测、动力学解算 |
| **脚本** | Lua 脚本语言 |
| **平台** | 跨平台运行（Web/移动端/PC） |
| **多人** | 内置联网对战能力 |

### 3.2 开发语言

**Lua** 是 TapTap Maker 的主要开发语言：

```lua
-- 示例：基本的游戏脚本结构
local Game = {}

function Game:init()
    -- 初始化游戏
end

function Game:update(dt)
    -- 每帧更新
end

function Game:cleanup()
    -- 清理资源
end

return Game
```

### 3.3 项目结构

```
.project/
├── project.json        # 项目元数据
│   ├── name           # 项目名称
│   ├── entry@client   # 客户端入口（如 scripts/main.lua）
│   └── entry@server   # 服务端入口（多人游戏）
└── settings.json      # 构建和运行时设置
    ├── sources        # 资源源配置
    ├── build          # 构建配置
    └── @runtime       # 运行时配置
        └── multiplayer # 多人游戏配置
            ├── enabled
            ├── max_players
            ├── background_match
            ├── match_info
            └── persistent_world
```

---

## 四、开发工作流

### 4.1 标准开发流程

```
1. 初始化项目
   taptap-maker init

2. 开发游戏代码
   - 编辑 scripts/main.lua
   - 参考 examples/ 和 urhox-libs/
   - 使用 AI 辅助开发

3. 生成素材（可选）
   - 使用 MCP tools 生成图片/音频/3D 模型
   - 素材自动下载到 assets/ 目录

4. 提交构建
   - 告诉 AI "提交" 或 "构建"
   - 或直接调用 maker_build_current_directory

5. 预览验证
   - 构建成功后返回 Maker URL
   - 在浏览器中预览游戏效果

6. 查看日志
   - 运行时日志自动保存
   - 用于调试 Lua 脚本错误
```

### 4.2 Git 工作流

**重要**：Maker 项目使用简化的 Git 工作流，**不使用分支**：

```
❌ 不要创建 feature 分支
❌ 不要创建 PR/MR
❌ 不要使用通用 Git 工作流

✅ 直接在 main 分支提交
✅ 使用 maker_build_current_directory 一站式操作
```

**提交流程**：
```
maker_build_current_directory
  ├── 检查本地变更
  ├── 自动 fast-forward（如果只有落后）
  ├── 创建 commit
  ├── push 到 Maker 远端
  └── 触发远端构建
```

### 4.3 多人游戏开发

**配置方式**：通过 `maker_build_current_directory` 的结构化参数

```json
{
  "entry_client": "scripts/main.lua",
  "entry_server": "scripts/server.lua",
  "multiplayer": {
    "enabled": true,
    "max_players": 4,
    "background_match": false,
    "match_info": {},
    "persistent_world": false
  }
}
```

**注意**：首次多人构建时，必须同时传入 `multiplayer.enabled=true` 和入口文件

---

## 五、素材生成能力

### 5.1 图片生成

```bash
# 单张图片
generate_image(prompt="可爱的卡通角色", style="anime")

# 批量图片
batch_generate_images(prompts=["背景1", "背景2", "背景3"])

# 编辑图片
edit_image(image="assets/sprite.png", prompt="添加帽子")
```

### 5.2 音频生成

```bash
# 背景音乐
text_to_music(prompt="轻松愉快的冒险音乐", duration=60)

# 音效
text_to_sound_effect(prompt="跳跃音效")

# 批量音效
batch_sound_effects(prompts=["攻击", "受伤", "拾取"])

# 角色配音
text_to_dialogue(text="你好，冒险者！", character="hero")
```

### 5.3 视频生成

```bash
# 生成视频任务
create_video_task(prompt="角色待机动画", reference_image="assets/hero.png")

# 查询任务状态
query_video_task(task_id="xxx")
```

### 5.4 3D 素材生成

```bash
# 创建 3D 资产
create_3d_asset(
  prompt="卡通风格的宝箱",
  action="start"  # start → query → continue → get_options → post_process
)
```

**工作流程**：
1. `start` — 开始生成任务
2. `query` — 查询生成进度
3. `continue` — 继续生成（如果需要）
4. `get_options` — 获取生成选项
5. `post_process` — 后处理（纹理、优化等）

---

## 六、环境配置

### 6.1 支持的 AI 客户端

| 客户端 | 配置方式 | 特殊说明 |
|--------|----------|----------|
| **Claude Code** | MCP 配置 | 默认支持 |
| **Codex** | 插件安装 | 内置 Maker MCP + Skills |
| **Cursor** | MCP 配置 | 默认支持 |
| **Trae** | MCP 配置 | 自动检测 Solo/CN 版本 |
| **WorkBuddy** | 插件安装 | 专用插件 |
| **DSH** | Bundle 插件 | `@taptap/dsh-maker` |
| **OpenCode** | MCP 配置 | 检测到配置文件时写入 |

### 6.2 环境变量

**核心变量**：
```bash
# Maker 安装目录（默认 ~/.taptap-maker）
TAPTAP_MAKER_HOME

# 分发渠道标识（插件模式必须设置）
TAPTAP_MAKER_DISTRIBUTION=codex_plugin

# 启用 raw tools（OpenClaw 插件专用）
TAPTAP_MCP_ENABLE_RAW_TOOLS=true
```

### 6.3 Python/Lua LSP 环境

```bash
# 检查 Python 环境
taptap-maker python setup

# 检查 Lua LSP
taptap-maker lua-lsp doctor

# 设置 Lua LSP
taptap-maker lua-lsp setup

# 安装 LSP 到 IDE
maker-lua-lsp install --ide codex,cursor,claude
```

**要求**：
- Python >= 3.8
- Lua LSP 用于本地代码诊断（不阻塞远端构建）

---

## 七、Proxy Tools（远端能力）

### 7.1 可用的 Proxy Tools

| Tool | 功能 | 输出位置 |
|------|------|----------|
| `generate_image` | AI 生图 | `assets/images/` |
| `batch_generate_images` | 批量生图 | `assets/images/` |
| `edit_image` | 编辑图片 | 原地修改 |
| `create_video_task` | 生成视频 | `assets/video/` |
| `query_video_task` | 查询视频状态 | - |
| `text_to_music` | 生成音乐 | `assets/audio/` |
| `text_to_sound_effect` | 生成音效 | `assets/audio/` |
| `batch_sound_effects` | 批量音效 | `assets/audio/` |
| `text_to_dialogue` | 生成对话 | `assets/audio/` |
| `audition_voices_for_character` | 试听角色音色 | - |
| `confirm_character_voice` | 确认角色音色 | - |
| `create_3d_asset` | 生成 3D 模型 | `assets/3d/` |
| `generate_test_qrcode` | 生成测试二维码 | - |
| `get_ad_config` | 获取广告配置 | - |
| `get_debug_feedbacks` | 获取玩家反馈 | - |

### 7.2 素材路由规则

- **图片**：成功后自动下载到 `assets/images/`
- **视频**：成功后下载到 `assets/video/`
- **音频**：音乐到 `assets/audio/`，音效到 `assets/audio/`
- **3D**：通过 `action` 参数管理完整生命周期

---

## 八、调试与诊断

### 8.1 运行时日志

构建成功后，`maker_build_current_directory` 会自动：
1. 调用远端 `query_runtime_logs`
2. 拉取 `engine`、`user_script`（Lua）、`server_user_script`（服务端 Lua）日志
3. 保存到本地文件

**日志分析**：
- 读取 `runtime_logs.local_file` 获取完整日志
- Lua 报错会包含行号和堆栈信息
- 引擎日志包含渲染、物理等底层信息

### 8.2 MCP 连接诊断

```bash
# 验证 MCP 安装
taptap-maker mcp verify

# 诊断环境问题
taptap-maker doctor

# 查看 MCP 状态
taptap-maker mcp report --ide codex --target-dir . --json
```

### 8.3 常见问题排查

| 问题 | 解决方案 |
|------|----------|
| MCP 连接失败 | 运行 `taptap-maker doctor` 检查环境 |
| Lua LSP 不工作 | 运行 `taptap-maker lua-lsp setup` |
| 构建失败 | 查看返回的错误信息，通常是 Lua 语法错误 |
| 素材生成失败 | 检查网络连接，重试 |
| 认证过期 | 运行 `taptap-maker login` 刷新 |

---

## 九、与 Tripo Studio 集成

### 9.1 集成路径

```
Tripo Studio                    TapTap Maker
    │                               │
    ▼                               ▼
生成 3D 模型 ──────────────→ 导入 assets/
    │                               │
    ▼                               ▼
GLB/FBX 格式 ──────────────→ UrhoX 加载
    │                               │
    ▼                               ▼
材质/动画 ────────────────→ Lua 脚本控制
```

### 9.2 3D 模型导入

1. **在 Tripo Studio 生成模型**
   - 选择合适的风格（卡通/写实）
   - 导出为 GLB 或 FBX 格式

2. **导入到 Maker 项目**
   - 将模型文件放入 `assets/3d/` 目录
   - 或使用 `create_3d_asset` MCP tool 生成

3. **在 Lua 中加载**
   ```lua
   -- 加载 3D 模型
   local model = loadModel("assets/3d/character.glb")
   ```

### 9.3 注意事项

- Maker 不支持导出源码，3D 模型必须在 Maker 生态内使用
- 使用 `create_3d_asset` 可以直接在 Maker 内生成模型
- Tripo 生成的模型可能需要调整材质以适配 UrhoX 渲染管线

---

## 十、最佳实践

### 10.1 开发建议

1. **先读 CLAUDE.md**：每次开发前先阅读项目中的 `CLAUDE.md`
2. **参考 examples/**：遇到问题时查看 `examples/` 中的示例
3. **使用 Lua LSP**：配置本地 Lua 诊断，提高开发效率
4. **小步提交**：频繁使用 `maker_build_current_directory` 验证
5. **查看日志**：构建失败时仔细阅读运行时日志

### 10.2 性能优化

1. **资源管理**：及时释放不用的资源
2. **批处理**：尽量批量处理同类操作
3. **异步加载**：大资源使用异步加载
4. **对象池**：频繁创建销毁的对象使用对象池

### 10.3 多人游戏

1. **权威服务器**：重要逻辑放在服务端
2. **状态同步**：合理设计同步频率和数据量
3. **断线重连**：处理玩家断线情况
4. **防作弊**：服务端验证关键操作

---

## 十一、参考资源

### 官方资源
- **GitHub 仓库**：https://github.com/taptap/instant-games-open-mcp
- **Maker NPM**：https://www.npmjs.com/package/@taptap/maker
- **官方文档**：https://developer.taptap.cn/maker/docs（需登录）

### 本地资源（Dev Kit）
- `CLAUDE.md` — AI 开发指南
- `examples/` — 示例代码
- `templates/` — 文件模板
- `urhox-libs/` — 引擎 API 文档

### 社区资源
- **展示游戏**：
  - 微观战争：https://www.taptap.cn/app/810894
  - TowerHell 塔楼跑酷：https://www.taptap.cn/app/813196
  - 霓虹防线：https://www.taptap.cn/app/813265

---

## 附录 A：项目配置文件参考

### project.json
```json
{
  "name": "My Game",
  "entry@client": "scripts/main.lua",
  "entry@server": "scripts/server.lua",
  "taptap_publish": {
    "screen_orientation": "landscape"
  }
}
```

### settings.json
```json
{
  "$schema": "settings.schema.json",
  "sources": {
    "stable": {
      "tag": "stable"
    }
  },
  "build": {
    "output_dir": "../dist",
    "asset_dirs": ["../assets", "../scripts"],
    "generate_fs_path": true,
    "asset_ignores": []
  },
  "@runtime": {
    "multiplayer": {
      "enabled": false
    }
  }
}
```

---

## 附录 B：CLI 命令速查

| 命令 | 功能 |
|------|------|
| `taptap-maker init` | 初始化/克隆项目 |
| `taptap-maker init --create` | 创建新项目 |
| `taptap-maker init --create --name "name"` | 创建指定名称的项目 |
| `taptap-maker login` | 登录 |
| `taptap-maker doctor` | 诊断环境 |
| `taptap-maker apps` | 列出应用 |
| `taptap-maker apps --json` | 列出应用（JSON 格式） |
| `taptap-maker install` | 安装 MCP |
| `taptap-maker upgrade` | 升级 MCP |
| `taptap-maker dev-kit update` | 更新 Dev Kit |
| `taptap-maker lua-lsp setup` | 设置 Lua LSP |
| `taptap-maker mcp verify` | 验证 MCP 安装 |
| `taptap-maker mcp report` | 生成 MCP 报告 |
| `taptap-maker agents update` | 更新 Agent 策略 |

---

*文档生成时间：2026-09-10*  
*基于仓库版本：taptap/instant-games-open-mcp (main branch)*

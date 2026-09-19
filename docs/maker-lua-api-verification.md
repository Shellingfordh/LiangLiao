# TapTap Maker Lua API 验证报告

> 验证日期：2026-09-18
>
> 方法：下载官方 AI Dev Kit（`@taptap/maker` CLI 内嵌的公开 CDN 地址），对照
> `docs/2026-09-15-parallel-companion-design.md` 与 `docs/platform-capabilities.md`
> 中的每一条平台假设逐项核对。
>
> 证据来源（均为官方产物，非推测）：
> - `@taptap/maker@0.0.33` npm 包（CLI + MCP + workflow skills）
> - AI Dev Kit `https://urhox-demo-platform.spark.xd.com/ai-dev-kit/pd/stable/ai-dev-kit.zip`（28 MB，免登录）
>   - `engine-docs/`（API + recipes + gotchas）
>   - `.emmylua/*.d.lua`（引擎全部类型定义，权威 API 签名）
>   - `urhox-libs/`、`examples/`、`templates/`、`skills/`

---

## 0. 结论速览

| # | 规格中的假设 | 结论 | 影响 |
| --- | --- | --- | --- |
| 1 | `clientCloud` 可保存关系/记忆 JSON | ✅ 成立 | 无需改设计 |
| 2 | `clientCloud` 有可用配额 | ✅ 成立（300 次/分、48 MB/分） | 无需改设计 |
| 3 | 角色城市使用 **IANA 时区** | ❌ **不成立** | 必须改：引擎无时区库 |
| 4 | Maker AI 在**运行时**润色文案 | ❌ **不成立** | 必须改：无运行时 LLM |
| 5 | GLB 放进 `assets/` 即可运行时加载 | ❌ **不成立** | 必须改：GLB→MDL 构建期转换 |
| 6 | Marble 全景能否接入 Maker「必须实测」 | ✅ 成立且**优于预期** | 官方有专用转换工具 |
| 7 | 聊天 UI 需要文本输入控件 | ✅ 成立（`LineEdit`） | 无需改设计 |
| 8 | 时间来源可信 | ✅ 成立且**优于预期**（`common.get_server_time()`） | 建议采用 |
| 9 | `research/taptap-pages/` 作为文档依据 | ❌ **无效** | 38 份中 27 份是登录墙 |

规格第 203 行写的「不可把历史文档中的推测 API 当作已验收事实」是对的——本次验证发现 **3 条核心假设不成立**，
其中 2 条会直接影响已冻结的 M0-0 基线。

---

## 1. ✅ 成立：`clientCloud` 支持任意 Lua table

权威签名（`.emmylua/ClientCloud.d.lua`）：

```lua
--- 单个写入任意类型值 (写入到 values 表)
--- 支持 string, number, boolean, table 等任意 Lua 类型
---@param key string
---@param value any
function ClientCloud:Set(key, value, events) end

function ClientCloud:Get(key, events) end       -- ok = function(values, iscores)
function ClientCloud:BatchSet() end             -- 链式 :Set():SetInt():Delete():Save(desc, events)
function ClientCloud:BatchGet() end   -- 链式 :Key():Fetch(events)
```

规格 §4.2 的四张表（`relationship` / `interaction_log` / `shared_memories` / `life_context`）
可以直接作为 table 存入 `values`。**设计无需修改。**

### 实施约束（规格未写，需补）

1. **全异步 + 回调**。`Get` / `Set` 都走 `events = { ok = ..., error = function(code, reason) }`。
   规格 §8 的 `MemoryService` 不能写成同步读写，冷启动必须有「记忆加载中」状态。
2. **`Set` 写 `values`，`SetInt`/`Add` 写 `iscores`，两张表分开**。回调第 1 参数是 values、
   第 2 参数是 iscores。本项目只需要 `values`；`iscores` 是排行榜用的，本项目不需要排行榜。
3. **昵称不能存云变量**。文档明确警告：`不要用 clientCloud:Set("player_name", ...)`，
   昵称由 TapTap 账号系统管，用 `GetUserNickname()` 查。涉及规格里「称呼」字段时注意区分：
   角色对用户的称呼是游戏内数据（可存），TapTap 账号昵称不是。
4. **`clientCloud` 仅限客户端（Standalone / Client 模式）**。服务端是另一套 `serverCloud`。
   本项目是单机单人，用 `clientCloud` 正确。
5. **配额**：读 300 次/分、写 300 次/分、数据量 48 MB/分，超限 `error(-429, "send failed")`。
   聊天应用完全够用，但**不要每条消息都单独写一次**，用 `BatchSet()` 合并。

### 备选：本地文件存储

`engine-docs/recipes/file-storage.md` 提供了引擎自动做**项目 + 用户双重隔离**的本地存档：

```lua
local file = File("save.json", FILE_WRITE)
file:WriteString(cjson.encode({ ... }))
file:Close()
```

建议组合使用：本地文件做**即时写入 + 离线兜底**，`clientCloud` 做**跨设备同步**。
这正好回应规格 §10 风险表里「`clientCloud` 或离线时间异常 → 本地内存保底」那一条，
而且比「内存保底」更强——本地文件重启后还在。

---

## 2. ❌ 不成立：引擎没有 IANA 时区库

### 证据

`engine-docs/recipes/server-time.md` 明确写：

> **时区**：返回值是 UTC 秒，显示本地时区时间要自己偏移

官方给出的唯一换算方式是**手工加固定秒数**：

```lua
local sec = common.get_server_time()
print("北京时间:", os.date("!%Y-%m-%d %H:%M:%S", sec + 8 * 3600))
```

Lua 5.4 标准库的 `os.date` 不接受时区参数，引擎也没有暴露 tz database。
规格 §5.1 写的「角色城市 **IANA 时区**」在 Maker 里**没有对应实现**。

### 这不是理论问题——它会在评审期内咬人

本项目四座城市在赛事窗口内的真实 UTC 偏移：

| 城市 | 今天 09-18 | 评审结束 10-25 | DST 切换点 |
| --- | --- | --- | --- |
| 上海 / 成都 | +8 | +8 | 中国无夏令时，永远 +8 ✅ |
| 洛杉矶 | **-7**（PDT） | **-7** | 11-01 才切 -8 ✅ 整个赛期安全 |
| 伦敦 | **+1**（BST） | **+0**（GMT） | ⚠️ **2026-10-25 当天切换，正好是颁奖日** |

**最危险的具体错误**：M0-0 已冻结的基线场景是「洛杉矶 **18:20** 初秋傍晚」。
如果实现时按常识写「洛杉矶 = UTC-8」：

```
真实 LA  : 18:20 PDT   ← 规格要的
硬编码-8 : 17:20        ← 差一小时，傍晚的光线设定跟着错
```

九月的洛杉矶是 **PDT (-7)**，不是 -8。

### 建议修法（低成本）

不要引入时区库。四城各写一张**带生效区间的偏移表**，Lua 查表即可。表必须从标准时
开始，并覆盖存档可能读取到的全部时间范围；不能把当前赛期的 PDT / BST 当作从 Unix epoch
起就一直生效的默认值。

```lua
-- scripts/services/timezone.lua
local CITY_TZ = {
  shanghai    = { { from = 0,     offset =  8 * 3600 } },        -- 永不变
  chengdu     = { { from = 0,          offset =  8 * 3600 } },
  los_angeles = {
    { from = 0,          offset = -8 * 3600 }, -- PST
    { from = 1772964000, offset = -7 * 3600 }, -- 2026-03-08 10:00 UTC, PDT
    { from = 1793523600, offset = -8 * 3600 }, -- 2026-11-01 09:00 UTC, PST
  },
  london = {
    { from = 0,          offset = 0 },          -- GMT
    { from = 1774746000, offset = 1 * 3600 },   -- 2026-03-29 01:00 UTC, BST
    { from = 1792890000, offset = 0 },          -- 2026-10-25 01:00 UTC, GMT
  },
}

local function local_time(city, utc_sec)
  local rules, off = CITY_TZ[city], 0
  for _, r in ipairs(rules) do
    if utc_sec >= r.from then off = r.offset end
  end
  return utc_sec + off
end

-- 用法：注意必须用 "!" 前缀强制按 UTC 解析，否则会叠加运行设备的本地时区
os.date("!%H:%M", local_time("los_angeles", common.get_server_time()))
```

上例覆盖到 2026 年末；若存档要跨 2027 年继续使用，必须再加入下一次春季切换规则，
或改为按目标年份计算北美 / 欧洲的 DST 规则。不能让表在 2026-11-01 后永久停留在 PST / GMT。

必测边界：伦敦在 `2026-10-25 00:30 UTC` 仍为 BST、`01:30 UTC` 已为 GMT；洛杉矶在
`2026-11-01 08:30 UTC` 仍为 PDT、`09:30 UTC` 已为 PST。

`"!"` 前缀是官方文档特别强调的点（「强制按 UTC 解析，避免叠加运行环境的本地时区」）——
漏掉它会在不同用户设备上得到不同结果，而这个 bug 在开发者自己机器上往往看不出来。

规格 §5.1 的「季节取角色城市的当地日期」和 §5.1 的天气种子（`city_id + YYYY-MM-DD`）
都要基于这个 `local_time` 的结果，不能基于 UTC 日期，否则跨日线的城市会算错一天。

---

## 3. ❌ 不成立：没有运行时 LLM / "Maker AI" 文案接口

### 证据

对整个 Dev Kit（`engine-docs/`、`.emmylua/`、`urhox-libs/`、`examples/`）检索
`LLM` / `大模型` / `generate_text` / `AI 对话` / `Maker AI`，**唯一命中是**：

- `engine-docs/lua-scripting-guide.md` 讲「AI（LLM）生成代码时经常混淆 `\uXXXX` 和 `\u{XXXX}`」——
  说的是**写代码的 AI**，不是运行时接口
- `AGENTS.md` 的「`scripts/` ✅ AI 生成的用户代码放这里」——同样是构建期

npm 包里的 MCP 工具（`generate_image`、`text_to_music`、`text_to_dialogue`、`create_3d_asset` …）
全部是 **MCP 开发期工具**，跑在开发者的 AI 客户端里，**不是游戏运行时 Lua API**。

结论：规格 §7.3「Maker AI（若实测可用）只负责把已选事实润色成角色对话」和
§8 的 `ContentService → Maker AI 文案` —— **这条路不存在。**

### 影响与建议

好消息是：**这反而验证了设计的核心决策是对的。**

规格 §5.3 已经写了「生成失败时，使用同一事件模板的确定性保底文案」，
§10 也写了「事件事实由 Lua 固定；用模板文案与短句兜底」。
现在的结论只是：**那个「兜底」就是唯一路径，不是兜底。**

需要改的是把 `ContentService` 从「LLM 润色 + 模板降级」改成「纯模板 + 变量替换」，
并且**把文案量提前算进工期**——这是从「技术问题」变成「写作工作量」的转移。

> 理论上 `http:Create()` 可以在运行时调外部 LLM API，但那需要把 API key 打进客户端，
> 且违反 `AGENTS.md` 的硬边界「不接入真实天气、新闻或运行时调用」。**不建议。**

一个可行的质量补偿：用构建期的 MCP `text_to_dialogue`（ElevenLabs）给关键回复配音，
把「文案是预置的」这个弱点转化成「她的声音」这个强点。不过这属于 M4 打磨，不进 M0。

---

## 4. ❌ 不成立：GLB 不是运行时格式

### 证据

`skills/import-glb/SKILL.md`：

```bash
/workspace/.cli/UrhoXCLI import-gltf -i <glb_path> -o <mdl_path> [options]
```

> 工具会自动处理坐标系转换（右手系→左手系）、UV 翻转和单位转换，输出符合 UrhoX 引擎规范的 MDL 文件

而运行时加载一律是 `.mdl`（`templates/`、`examples/` 中无一例外）：

```lua
model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
```

### 影响

规格 §7.3 写「角色与低模道具放入 `assets/`」、平台文档写「GLB 首选；FBX 备选」——
**不完整**。真实链路是：

```
Tripo 导出 GLB
  → UrhoXCLI import-gltf
  → .mdl（模型）+ .xml（材质）+ 纹理 + .ani（动画）+ .prefab
  → 运行时 cache:GetResource("Model", "...mdl")
```

M0-0 的验收标准「Maker 真机稳定显示林若夕 A-pose GLB」需要改写为 **MDL**，
并且资产交接目录要相应调整：

```text
poc/maker/assets/
  Meshes/lin-ruoxi.mdl
  Materials/lin-ruoxi_00_*.xml
  Textures/lin-ruoxi_00_D.jpg + .xml
  Prefabs/lin-ruoxi.prefab
  Animations/lin-ruoxi/idle.ani
```

这是**好消息**：转换是官方工具一条命令，且自动生成 LOD（默认 3 级）。
但它是一个规格里完全没提到的构建步骤，排期时要算进去。

配套工具：`skills/model-info`（查 MDL 面数，验证 ≤5,000 faces 的目标）、
`skills/anim-info`（查 ANI 时长/轨道，排查动画重定向问题）。

---

## 5. ✅ 优于预期：Marble 全景有官方转换工具

规格 §7.2 和平台文档都把「Marble 全景能否接入 Maker」列为**必须实测的未知项**，
并谨慎地退守到「用静帧 PNG 当背景」。

实际上官方有专用 skill `convert-panorama`：

```bash
/workspace/.cli/UrhoXCLI convert-panorama -i <panorama> -o <cubemap.dds> --mips
```

| 输入布局 | 宽高比 | 说明 |
| --- | --- | --- |
| 等距柱状投影（Equirectangular） | **2:1** | 最常见的全景图格式 |
| 横条（Horizontal Strip） | 6:1 | 6 面横向排列 |

**Marble 导出的 360 全景是 2560×1280，正好是 2:1 等距柱状投影**，
即工具的首选输入格式，可直接转成 Cubemap 天空盒/天空球。

这意味着规格里「不得把 Marble 高面数 GLB 导入 Maker」的结论依然正确，
但**退守方案比预想的强**：不是一张贴死的静帧，而是真正的天空球——
固定机位下可以有轻微视差和镜头呼吸感，视觉上明显高一档，且成本几乎为零。

建议 M0-0 保持静帧（先过真机），M0-1 或 M1 升级为 Cubemap。

---

## 6. ✅ 成立：聊天 UI 有文本输入控件

`.emmylua/LineEdit.d.lua`：

```lua
---@class LineEdit : BorderImage
---@field text string
---@field maxLength integer
function LineEdit:SetText(text) end
function LineEdit:GetText() end
function LineEdit:SetMaxLength(length) end
function LineEdit:SetCursorMovable(enable) end
function LineEdit:SetTextSelectable(enable) end
```

规格 §6.1 的「下部：主聊天流与消息输入」可以实现。

**未验证项（需真机确认）**：`LineEdit` 在 Android / iOS 上的**中文输入法（IME）**行为。
Dev Kit 中未检索到 IME 相关说明。这是移动端文本输入的经典坑
（候选词、拼音上屏、软键盘遮挡输入框），建议在 M0-1 做可编辑输入时**第一个验证**。

规格 §9 的 M0-1 已经很聪明地把首版设为「默认可编辑消息」而非任意输入，
这个设计正好能在 IME 有问题时降级为「预置消息 + 轻度编辑」。**保持这个设计。**

---

## 7. ✅ 优于预期：有权威时间源

`common.get_server_time()` 返回**权威 UTC 秒**，官方说明：

> 权威源 + 单调推算，**用户改系统时间无效**

| 场景 | 推荐 |
| --- | --- |
| 客户端 UI 显示当前时间 | `os.time()`（玩家看自己设备时间，符合预期） |
| 限时活动判定 / 冷却倒计时 / 防作弊 | `common.get_server_time()` |

对本项目：**角色当地时间、离线时长反推、消息排队计时必须用 `get_server_time()`**。
否则用户改一下系统时间就能跳过「她在忙」的等待——那会直接摧毁
规格 §1.1 主题陈述「你不必立刻被回答」的全部分量。

规格 §5.1 写的是「设备当前时间 + 用户时区」，应改为 `common.get_server_time()`。
（用户自己那一侧显示「我的时间」时可以继续用 `os.time()`。）

---

## 8. ❌ `research/taptap-pages/` 不能作为依据

38 份 HTML 快照中 **27 份 byte 级完全相同**（md5 `f4f7eb90...`，345,407 bytes），
全部是 TapTap 登录墙。`_index.json` 里每一条的 `title` 都是 `"登录 | TapTap"`，
`status: 200` 具有误导性——HTTP 200 返回的是登录页而非文档。

受影响的文件包括所有 API 文档：`api.html`、`api-engine.html`、`api-script.html`、
`api-taptap.html`、`api-game.html`、`guide-script.html`、`guide-asset.html`、`examples.html`、
`faq.html`、`changelog.html` …

**这大概率就是「大量 Lua API 是未验证的假设」的根因**：当初抓取时没识别出登录墙，
`platform-capabilities.md` 里那些具体数字（50 MB / 16 MB 上限等）
本次在 Dev Kit 中**无法找到对应出处**，来源存疑。

建议：
1. 在 `AGENTS.md` 的权威文档表中**移除** `research/taptap-pages/` 的 API 部分，
   或标注「登录墙快照，无效」；
2. 改以 **AI Dev Kit 为唯一 API 依据**——它免登录、有类型定义、有可执行示例；
3. `platform-capabilities.md` 中未能溯源的文件大小限制，标注为「未核验」。

---

## 9. 本次未能验证的项

| 项 | 原因 | 建议 |
| --- | --- | --- |
| 真机运行 Lua | `UrhoXRuntime` 需 GLIBC 2.38，当前沙箱为 2.35 | 在开发机跑 `skills/run-lua-headless` 验证时区表 |
| 移动端中文 IME | 文档无记载 | M0-1 真机第一优先验证 |
| 资产文件大小上限 | Dev Kit 无记载，原始来源是登录墙 | 实测，或以 Maker 后台报错为准 |
| `clientCloud` 单值大小上限 | 只查到频率/总量配额（300/分、48 MB/分） | 记忆摘要做长度上限，勿无限增长 |

> `UrhoXRuntime` 与 `UrhoXCLI` 均可从 `https://urhox-demo-platform.spark.xd.com/runtime/<platform>/latest/UrhoXRuntime.zip`
> 免登录下载（已验证 linux 版 45 MB 可下载解压）。开发机上 `python3 .cli/install-urhox-runtime.py` 会自动处理。

---

## 10. 建议的规格修订清单

> **状态（2026-09-19）**：下列 7 条已全部落地，逐条去向见 `CHANGELOG.md` 的 2026-09-19 条目。
> 本节保留为当时的核实记录，不要再当作待办重复执行。第 1 条的偏移表已按「从 epoch 起、覆盖到 2026 年末」
> 的区间写法确认；第 3 条的资产目录以 `docs/asset-provenance.md` 的唯一真源表为准（不是下面示例里的
> `poc/maker/assets/`）。

按优先级：

1. **§5.1 + M0-0**：删除「IANA 时区」，改为四城固定偏移表 + DST 生效区间；
   明确洛杉矶赛期内为 **UTC-7 (PDT)**，确认 18:20 基线；`os.date` 必须带 `"!"` 前缀。
2. **§7.3 + §8**：删除 `Maker AI` 运行时润色；`ContentService` 改为纯模板 + 变量替换；
   把文案工作量显式列入排期。
3. **§7.3 + M0-0 验收 + 平台文档**：GLB → **MDL** 构建期转换，更新资产目录结构与验收措辞。
4. **§5.1**：时间源改为 `common.get_server_time()`（权威 UTC），并说明防改表意义。
5. **§4.2**：补 `clientCloud` 异步回调语义、`BatchSet` 合并写、配额、昵称禁令；
   增加本地文件存储作为离线兜底。
6. **§7.2**：Marble 全景可用 `convert-panorama` 转 Cubemap 天空球，作为 M0-1/M1 的视觉升级项。
7. **AGENTS.md**：权威文档改指 AI Dev Kit；标注 `research/taptap-pages/` API 快照无效。

---

## 11. 预览卡 `Initializing… 0%` 的定性（2026-09-19 实测）

**现象**：Maker 网页预览停在 `Initializing… 0%`，console 两条：

```
Uncaught [object ErrorEvent]
Uncaught InvalidStateError: An operation that depends on state cached in an interface
           object was made but the state had changed since it was read from disk.
```

第二句是 **Chromium IndexedDB 的 `InvalidStateError` 原文**，失败点在**引擎启动前的资源装载层**，
不是 Lua 报错。触发条件是浏览器缓存的资源状态与其对应的服务端工作树不再一致——本项目当天工作树被
改过三次（16:35 云端重导入 → 19:35 我们推送 → 19:57 平台 `TapCode Rollback`），符合该成因。

**逐项排除的"代码/资产缺陷"假设**（每条都有独立证据，不是"应该没事"）：

| 假设 | 结论 | 依据 |
| --- | --- | --- |
| 推送删掉了被引用的资产 | 否 | `prefab → Meshes/lin-ruoxi.mdl` ✅、`material → Textures/lin-ruoxi_00_D.jpg` ✅；全库 `uuid://` 引用 0 条；无孤儿 `.meta` |
| 云端塞回的 `raw-assets/`（24 MB）撑爆包 | 否 | `build.asset_dirs` 只有 `../assets`、`../scripts`；schema 原文「groups 中的本地路径**相对于这些目录**匹配」 |
| `preload_groups: []` 导致启动取不到资源 | 否 | `download-while-playing.md`：`.mdl/.xml/.prefab` 属 render-blocking，脚本启动前已就绪；`Texture2D` 自动触发 DWP |
| 报错由 19:35 的推送引起 | 否 | reflog 钉死推送时间 19:35:53，**晚于** 19:09:13 的报错 |
| 工程/凭据不健康 | 否 | `maker_status_lite`：`project_health: ready`，auth/git/python/lua_lsp 全绿；远端构建 ✅ 100% ×2 |

**平台契约（读 `@taptap/maker` 0.0.33 的 `dist/maker.js` 与包内 `skills/taptap-maker-local/SKILL.md` 得到，仓库文档里没有）**：

- 「预览 / 跑一下 / 看结果」的官方路径**就是** `maker_build_current_directory` + 读 `runtime_logs.local_file`，
  agent 侧没有浏览器步骤。包内两份 skill 文档与连接排障文档**均无 0% / IndexedDB / 清缓存条目**——
  因为这属浏览器环境态，不是工程态。
- `preview-refresh` 是**纯服务端**动作：`POST {apiBase}/apps/{projectId}/preview-refresh`，
  `Authorization: Bearer <PAT>`，body `{}`，每次成功构建自动调一次。**它刷不到浏览器里的 IndexedDB。**
- 运行日志窗口有上限：`DEFAULT_RUNTIME_LOG_SINCE_SECONDS = 600`、`MAX_RUNTIME_LOG_WINDOW_SECONDS = 3600`，
  且抓取器空转 10 分钟即退出（`DEFAULT_RUNTIME_LOG_IDLE_TIMEOUT_MS`）。
  ⚠️ 手改 `.maker/logs/runtime/state.json` 的 `nextStartTime` 倒回历史**无效**（会被窗口夹住 +
  `isFreshRuntimeLogCursor()` 判定不新鲜）。 topics 含 `engine`，所以引擎层报错也会进 `runtime.log`。
- `logs watch --reset` 会连 `state.json` 与 `runtime.log` 一起清空，补拉时**不要带**。

**已做处置**：干净重建 ×2 + preview-refresh ✅200 ×2；用 `build.asset_ignores` 把 9.7 MB 非运行时文件
（源 `.glb`、Tripo 多视图缩略图、`lin-ruoxi.mdl.bak`）剔出构建包（文件保留在库内）。
**不要用 `asset_ignores` 剔贴图**：`lin-ruoxi.mdl`(UMD2) 整份压缩，全文件对 `tex|mat|jpg|png|normal`
零明文匹配，无法证明某张贴图未被引用，剔了有打断模型的风险。

**未闭环**：`runtime.log` 至今不存在，说明还没有一次会话真正加载过。浏览器预览页需 TapTap 开发者会话，
自动化浏览器会被 302 到 `/intro`，`generate_test_qrcode` 的 schema 禁止在构建/预览流程自动调用，
故**最后一步只能由人在自己浏览器里做**：关掉多余预览标签页 → `Ctrl+Shift+R`；仍卡 0% 则
Clear site data for `maker.taptap.cn` 后重开。

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
| 7 | 聊天 UI 需要文本输入控件 | ✅ 成立，但**只能用 `urhox-libs/UI` 的 `TextField`**（原生 `LineEdit` 已废弃） | 见 §6（2026-09-21 云端实测更新） |
| 8 | 时间来源可信 | ✅ 成立且**优于预期**（`common.get_server_time()`） | 建议采用 |
| 9 | `research/taptap-pages/` 作为文档依据 | ❌ **无效** | 38 份中 27 份是登录墙 |
| 10 | 「输入框旁边的按钮点一下就能发」 | ❌ **不成立**，默认会静默失效 | 必须改：按钮加 `focusable = false`，见 §6.1 |

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

| 城市 | 实测基准日 09-18 | 评审结束 10-25 | DST 切换点 |
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

## 6. ✅ 成立：聊天 UI 有文本输入控件（2026-09-21 云端实测后修正用法）

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

⚠️ **但 `LineEdit` 属于已废弃的原生 UI 系统，不要用。** 本条是 2026-09-18 按「引擎里有没有输入控件」这个
问题验证的，答案是有；而 AGENTS.md 规则 #10 已把原生 UI 判为废弃，2026-09-21 做 M0-1 时用的是新 UI 系统的
`urhox-libs/UI` → `UI.TextField`（Yoga + NanoVG），它同时提供 `text` / 占位文案 / 提交回调，规格 §6.1 的
「下部：主聊天流与消息输入」据此已跑通。

**云端实测已确认**（本阶段共五次构建 `415cb4c` → `f70bf4b`，其中 `4bde79c` 起聊天链路可用，
全程 `runtime.log` 零 ERROR）：
`UI.TextField` 在 Maker 云端预览里可显示预填草稿、可编辑、回车可提交，且提交后草稿按预期保留/清空。

**仍未验证**：Android / iOS 上**中文输入法（IME）**的候选词与上屏行为——Dev Kit 里没有 IME 相关说明，
而 M0-1 的实测全程用的是预填草稿，没有真的用拼音输入法打过字。规格 §9 把首版设成「默认可编辑消息」
正好能在 IME 有问题时降级为「预置消息 + 轻度编辑」，**保持这个设计**。

（同一轮实测还发现「输入框旁边的按钮默认点不动」，独立成条 → §13。）

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
**回归核验**：三条 glob 恰好命中 16 个文件，且 `Meshes/lin-ruoxi.mdl`、`Materials/lin-ruoxi_00_tripo_mat_*.xml`、
`Textures/lin-ruoxi_00_D.jpg`、`Prefabs/lin-ruoxi.prefab`、`Textures/lin-ruoxi_00_N.png` 五个运行时必需路径
**均不被任何 glob 命中**——即该改动不会自己造成资源缺失。
**不要用 `asset_ignores` 剔贴图**：`lin-ruoxi.mdl`(UMD2) 整份压缩，全文件对 `tex|mat|jpg|png|normal`
零明文匹配，无法证明某张贴图未被引用，剔了有打断模型的风险。

**另已排除的两条代码侧假设**：

- **模块加载期副作用**：`StatusWindow.lua` 与 `main.lua` 顶层**没有任何可执行语句**，全是 `local`/`function`
  声明，实际工作都在 `Start()` 里。所以不存在"加载期抛错被宿主报成 `ErrorEvent`"这条路。
- **候选路径探测打爆网络**：`resourceExists()` 走的是 `cache:Exists(path)`（清单查询，非 HTTP 请求），
  `findFirstExisting()` 命中即返回。缺失的 `la-cafe-4x3.png` 由 `RefreshResourceNotices()` 优雅降级成
  一条 UI 提示，不会形成 404 风暴。

**已闭环（2026-09-21 补）**：`runtime.log` 后来出现了，而且多轮会话完整跑到 Lua 层，零 ERROR——
「卡 `Initializing… 0%`」不是这几次构建的故障，装载层已通。取日志的实际操作口径见下面的 runbook，
其中「跑 ~20s 后 Ctrl-C」与判据字符串都已按实测更正。

### 复现/收尾 runbook（下一次照抄即可，不要重新探索）

```bash
# 0) 用户侧：关掉多余预览标签页，硬刷新预览页
#    https://maker.taptap.cn/app/720b27bf-ca69-44ac-a776-a88ec2ec2b28?localDev=1

# 1) 拉运行日志。CLI 位置随 @taptap/maker 版本漂移，先确认哪个存在：
#    C:/Users/20145/.taptap-maker/mcp-runtime/<ver>/dist/maker.js        （MCP 自运行时）
#    C:/Users/20145/AppData/Local/npm-cache/_npx/<hash>/node_modules/@taptap/maker/bin/taptap-maker
node "<上面任一个>" logs watch --target-dir "D:/Develop/ShanTianLiang" --interval 5s
#    ⚠️ 绝对不要带 --reset：它会连 state.json 与 runtime.log 一起清空（构建工具自己重启时就是带的）。
#    判据：`.maker/logs/runtime/runtime.log` 出现入口行
#          "[M0-1] 启动 M0-1 竖切片"（M0-0 时代是 "[M0-0] 启动 M0-0 原型"）→ Lua 已跑到，问题在代码层；
#          文件仍不存在 → 仍在装载层。链路日志前缀：[MsgService] / [EventService] / [Memory] / [ChatPanel]，
#          一次发送的闭环落点是 "[M0-1] 回复 #N → replied 事实=la_cafe_open_mic"。
```

**四条踩过的 watcher 运维坑（2026-09-21 一天内全部实测，别再重复探索）**：

| 坑 | 实测 | 应对 |
| --- | --- | --- |
| 每次构建都会重启 watcher 且带 `--reset` | 构建返回值里 `watch_command: … --reset`、`previous_watch_stopped: yes`，本地 `runtime.log` 当场消失 | **下一次构建之前必须把日志证据转录进文档**；原始文件不跨构建存活 |
| CLI watcher 只活 **4~8 分钟** | 同日三次：08:57:22Z、09:30:50Z、10:43:45Z 停在 `watcher stopped`；另两次约 4 分钟后崩在 `EPERM: rename state.json.<pid>.<ts>.tmp` | 取证当下**先量** `state.json.updatedAt` 与当前 UTC 的差，超十几秒就重启 |
| 「人死了日志就取不回来」是错的 | 死时游标停在 18:28:49，19:07 不带 `--reset` 重启，一次拉回 21,345 字节，把 18:59 那次会话完整补回（`runtime.log` 25,550 → 46,895） | 判断标准只有**「`now - nextStartTime` 是否超过 1 小时窗口」** |
| `watcher.out.log` 会假死 | 用 `logs watch \| tail -N` 起的时候，它自己的 `pulled: N` 行被管道憋住不落盘，文件停在上一实例的 `stopped` 行 | **判活性只看 `state.json.updatedAt` 和 `runtime.log` 的 mtime/字节数**（后者由进程直写） |

顺带一条被证伪的推测：EPERM 崩**不是**「两个 watcher 并存互杀」——第二次重启时前一个实例已退出 4 分钟，
单实例照样在 4 分钟后崩。真实原因是本机另有进程短期占用 `state.json`（索引/杀软/编辑器一类），与并发无关。

收尾不变：`logs watch` 会把 `origin` 改指回 Maker URL —— 按 2026-09-19 的决定这是预期行为，不需要纠正
（见 AGENTS.md「Git 拓扑」：所有推送只发 `maker`，GitHub 暂不管，`github` 远端仅留档）。
只有当确实要动 GitHub 时，才临时 `set-url` 并**重新 fetch**（tracking ref 不重 fetch 会残留假值）。

服务端只读探针（本次全部跑过，均正常，别再重复）：`maker_status_lite`（`project_health: ready`）、
`get_ad_config`（`app_id 940330` / `developer_id 471831` 均在，广告未开通与预览无关；
顺带暴露云端工作树在 `/userspaces/<project_id>/workspace/`）、
`get_debug_feedbacks` 全量（`total: 0`）。

**已穷举并排除的假设清单**（11 条，含依据）：悬空引用 / `raw-assets` 进包 / DWP 预下载配置 /
推送时间因果 / 工程健康 / 模块加载期副作用 / 候选路径 404 风暴 / `asset_ignores` 误剔必需资源 /
headless 引擎验证（本地无此能力）/ 自动化浏览器（无登录态）/ 反馈与历史日志通道（恒空且窗口仅 1 小时）。

## 12. ✅ 已定：`nvgCreateVideo` 对 RenderTarget 的方向处理，引擎文档写错了（2026-09-20 提出，2026-09-21 真机定案）

> **结论先说，见 §12.2**：不加 `nvgRotate(math.pi)` 角色上下颠倒，加了才正立——WebGL 与原生 Android 行为一致，
> `scene-to-nanovg.md:13` 那句「不需要额外翻转 Y」不成立，代码里那枚旋转**必须保留**。
> 下面 §12 主体保留 2026-09-20 当时「文档与实测矛盾、只能等真机」的完整推演与判读表（方法本身仍可复用），
> 读的时候把它当过程记录，不要当未决项。

M0-0 状态窗把独立 3D 场景渲到 `Texture2D` RenderTarget，再用 `nvgCreateVideo` + `nvgImagePattern`
画进 UI。这条路径的**画面方向**目前只有矛盾证据，没有定论：

| 来源 | 说法 |
| --- | --- |
| `engine-docs/recipes/scene-to-nanovg.md:13` | 「`nvgCreateVideo` 已处理预览纹理的上下方向，按普通图片绘制即可，不需要额外翻转 Y」 |
| `.emmylua/NanoVG.d.lua:299-300` | 「Render targets are normalized to NanoVG image orientation internally」 |
| 本项目 2026-09-20 浏览器预览实测 | **不加任何旋转时角色上下颠倒**（`screenshots/m00-check.png`，commit `94a317e` 引入 `nvgRotate` 之前的状态）；加 `nvgRotate(π)` 后角色正立（`screenshots/m00-frame-check.png`） |

两条文档依据与一条实机证据直接对立。按 AGENTS.md「API 依据只有本地 AI Dev Kit」应以文档为准，
但文档无法解释那张颠倒的截图，故当前代码**保留** `StatusWindow.Draw()` 里的 `nvgRotate(math.pi)`，
把它标记为待真机裁决的假设而非结论。

一个能同时容纳两者的解释：`nvgCreateVideo` 的类型注释自己写了「or 0 on failure/**unsupported platform**」，
即方向归一化可能分平台；`m00-check.png` 出自 WebGL 浏览器预览，而验收目标是原生 Android/iOS，
两者行为可以不一致。此解释同样未经证实。

**真机扫码时的判读表**（一次扫码即可定论，无需改代码再跑）：

> **判读基准变了，注意。** 静帧改由 UI 层绘制之后，两层各自独立定向：背景走普通 UI 图片路径
> （恒正立），角色走 RT 路径（受本冲突影响）。所以**不能再靠"角色是否正立"单独下结论**——
> 要以背景为基准图，同时看角色在**哪一侧**。`nvgRotate(π)` 会把画面绕中心转 180°，
> 等价于 x→(W−x)：镜头按规格把她摆在右侧约 71% 处，一旦这 180° 是多余的，她就会跑到左侧约 29%，
> 直接违反「背景主体和窗景在左，角色预留区在右」。左右位置因此成了一个不依赖正立判断的第二信号。

| 真机现象 | 结论 | 动作 |
| --- | --- | --- |
| 角色正立**且在右侧**、窗景方向正确 | 保留 `nvgRotate(π)` 正确，且原生与 WebGL 一致 | 删掉本节冲突，转为 ✅ |
| 角色**上下颠倒**（多半同时跑到左侧） | 原生端已归一化，文档正确，`nvgRotate(π)` 是多余补偿 | 删 `Draw()` 里的 translate/rotate/translate 三行 |
| 角色正立但**左右镜像**（也会跑到左侧） | 归一化只处理了 Y，X 仍需修正 | 把 `nvgRotate(π)` 换成水平翻转 |
| 状态窗整块变黑、只剩窗景 | 透明底 RT 的 alpha 未被保留 | 退回「远景也进 3D 场景」方案，改为预先把静帧按实测轴向翻转后再生成贴图 |
| 窗景缺失、只有角色 | 背景未下载成功，或 `preload_groups` 未生效 | 屏上会显示 `GetBackgroundError()` 文案；按文案而非猜 |

### 12.1 WebGL 侧已定论：判读表第 1 行成立（2026-09-20 23:23 实测）

上面「四条本地验证路全死」的结论**被推翻了一条**：用户的真实 Chrome 带有 TapTap 登录态，
但 `mcp__user-browser-use__list_pages` 在浏览器未开窗口时报 `No current window`——
先 `cmd //c start "" "<maker_url>"` 把默认浏览器拉起来，连接器就能接管标签页并截图。
这条路以前没走通只是因为**没有浏览器窗口**，不是因为拿不到登录态。

`build 5ac225f` 在 390×867（9:20，DPR≈1.02）移动视口下的预览，**五项全部符合判读表第 1 行**：

| 检查项 | 结果 |
| --- | --- |
| 4:3 窗景方向 | ✅ 与源图一致：窗与暮色街景在左、海报板在右、木桌在下。无镜像、无上下翻 |
| 透明底 RT 的 alpha | ✅ **保留**。角色四周透出的正是窗景，没有出现「整块变黑」 |
| 角色朝向 | ✅ 正立且**面向镜头**（可见面部与米白内搭），180° yaw 修正生效 |
| 角色横向位置 | ✅ 落在右侧约 70%，符合「角色预留区在右」，未因多余旋转跑到左侧 |
| 状态文案 | ✅ 「若夕 · 洛杉矶 18:20 · 还在外面」正常渲染（旧截图里完全没有文字的问题一并消失） |

留档：`screenshots/preview-m00-after-fix.png`（整页）与
`screenshots/preview-m00-after-fix-statuswindow-crop.png`（状态窗放大裁切）。

**当时仍未决**：原生 Android/iOS 是否与 WebGL 同行为。`nvgCreateVideo` 的类型注释自己写了
「or 0 on failure/**unsupported platform**」，方向归一化与 alpha 都可能分平台，
所以 WebGL 的正结果**不能**外推成真机结论；判读表其余四行对真机依然有效。
**（这一条已由 §12.2 在 2026-09-21 真机定案：与 WebGL 同行为。）**

**两条二维码通道不一致，扫码前须知**（同日实测）：

| 通道 | 状态 |
| --- | --- |
| MCP `generate_test_qrcode` | ✅ 成功，返回 `https://tapcode-sce.spark.xd.com/qrcode/m_c7s3_1789916661057.png`，HTTP 200、300×300 有效 PNG，且已确认云端包含其对应构建 `5ac225f` |
| Maker 网页「真机自测」面板 | ❌ 自报「**项目配置暂不可读**，测试版本待确认」「暂时无法读取测试二维码，发布状态不受影响」，只提供「重新读取」 |

留档：`screenshots/preview-m00-realdevice-panel-qr-unreadable.png`。
以 MCP 那条为准去扫码；**若扫码后打不开**，先怀疑这个面板暴露的配置读取问题，
不要先怀疑构建本身——构建与资源装载已由 §12.1 的 `runtime.log` 证明可用。


**顺带记一条引擎告警**（非阻塞，角色仍带贴图正常渲染）：

```
WARNING: DownloadManager: cannot resolve 'uuid://-73mcwx1QB6NyLrwJxv8Kg', skipping
WARNING: DownloadManager: cannot resolve 'uuid://u05oYbz5RtecsyHB9-bmKQ', skipping
WARNING: DownloadManager: no resources resolved for batch download
```

两个悬空 `uuid://` 引用（材质引用由 uuid 改为路径后遗留），与 §「云端二次同步后的状态」
记录的引用方式变更同源；`asset-provenance.md` 已警告过「按 uuid 判定无人引用」的结论只对当时那一版成立，
反过来**残留的 uuid 引用**同样要清。属 M0-1 资产对账项，不影响 M0-0 通过条件。



窗景本身的方向已与本冲突解耦：静帧不再贴 3D `Plane`（Plane 的 UV 轴向会镜像静帧，
且为修正角色而加的 `nvgRotate(π)` 会把该镜像变成可见的上下翻转），改由 UI 层
`backgroundImage` + `backgroundFit="cover"` 绘制，走的是普通 UI 图片路径。

**为什么这个冲突只能等真机，不能自己验**（2026-09-20 把路全部走了一遍，四条全断，别再重试）：

| 想走的路 | 结果 |
| --- | --- |
| 本地 headless 跑引擎出图对方向 | 仓库无引擎可执行文件，`.cli/` 只有 `install-urhox-runtime.py`；AGENTS.md 已定「没有本地运行时」为硬边界，不为此现装引擎 |
| 从 Lua 里回读 RT 像素的 alpha 直接判定 | **API 不存在**：`GetPixel` / `GetPixelInt` 只在 CPU 侧 `Image`（`.emmylua/Image.d.lua:141-169`），`Texture2D` 侧只有 `GetDataSize`。RenderTarget 是 GPU 纹理，读不回来 |
| 解码测试二维码拿到可公开访问的 play 链接，用浏览器自己截图 | 失败：`cv2.QRCodeDetector` 对 2/3/4/6 倍放大 + 灰度 + Otsu 全部解不出（Maker 二维码是带样式的非标准模块图），`pyzbar`/`zxingcpp` 本机没有 |
| 用浏览器打开 Maker 预览页截图 | **部分可行，见下方 §12.1**。`mcp__browser-use`（Qoder 内置浏览器）与 `playwright` 两条都被 302 到 `/intro`，它们没有 TapTap 会话；但 `mcp__user-browser-use`（接管用户真实 Chrome）**有登录态**，只是要求浏览器当前有窗口，否则报 `No current window`。先 `cmd //c start "" "<url>"` 拉起浏览器即可 |

结论：方向与 alpha 两个未知数**只有真机（或用户已登录的预览页）能判定**，
一次扫码按上面的判读表即可同时给出两个答案。

**扫码之后的两条取证通道（2026-09-20 从 `@taptap/maker` 0.0.33 包内 skill 核实）**：

| 通道 | 拿什么 | 注意 |
| --- | --- | --- |
| `runtime.log`（本地 watcher，`.maker/logs/runtime/`） | **当前本地构建/运行会话**的运行时日志，含 `[M0-0]` 启动行与资源加载结果 | 包内 skill 明令：本地运行日志**不能**代替远端玩家反馈 |
| Maker MCP `get_debug_feedbacks` | 本游戏**线上玩家提交的反馈，含真机游戏日志与真机截图**、指定会话的服务端/Lua 日志 | 现在 `total: 0` 只因为还没有任何客户端加载过构建；扫码后应复查此工具，**真机截图可能可以直接从这里取回**，不必让用户手动拍照 |

这条改变了 M0-0 收尾的取物方式：用户扫码并试玩一次之后，先查 `get_debug_feedbacks`，
再决定是否需要人工补拍截图。

### 12.2 ✅ 真机侧已定论：判读表第 1 行成立，本节冲突结束（2026-09-21 12:53 实测）

用户用 TapTap 扫码在原生手机上跑通 `5ac225f`，系统截图存于 `screenshots/device/m00-realdevice-01-fullframe.jpg`。
三项判读全部落在第 1 行，**与 §12.1 的 WebGL 结论一致，不分平台**：

| 判读项 | 真机结果 | 对本节的意义 |
| --- | --- | --- |
| 角色上下方向 | 正立 | 「unsupported platform 归一化」这个解释**不需要**，文档那句「不需要额外翻转 Y」才是错的 |
| 角色横向位置 | 右侧约 65%（WebGL 为约 70%） | 与基准同侧 ⇒ 没有多余的那 180°，`nvgRotate(math.pi)` **必须保留** |
| 角色框是否黑底 | 无黑底，四周透出窗景 | 透明底 RT 的 alpha 在原生生效 ⇒ 判读表第 4 行排除 |

同时排除了「设备其实是浏览器仿真」的可能：该会话日志打 `屏幕物理分辨率: 462.0x1029.0 DPR=0.94866532087326`，
而 WebGL 预览是 712×906 一类的桌面/移动仿真尺寸。

⇒ **最终结论：`engine-docs/recipes/scene-to-nanovg.md:13` 与 `.emmylua/NanoVG.d.lua:299-300` 两条文档说法在
WebGL 与原生 Android 上都不成立**，本项目代码里的 `nvgRotate(math.pi)` 是必须保留的修正，不是待清理的临时补丁。
上面那张判读表作为方法保留（下次再遇到方向争议仍然适用），四条本地死路（§12 末表）里除
「用 `mcp__user-browser-use` 接管已登录 Chrome」那一条外依然有效。

## 13. ❌ 不成立：输入框旁边的按钮默认点不动（2026-09-21 云端实测）

同一个 `UI.TextField` + `UI.Button` 组合里，**回车能提交，点「发送」却毫无反应，而且不报任何错**。
根因在引擎的点击判定与软键盘引起的布局位移，两段源码即可解释：

| 位置 | 事实 |
| --- | --- |
| `urhox-libs/UI/Core/UI.lua:2379` | `HandlePointerUp` 只在**按下与抬起命中同一个控件**时才派发 `OnClick` |
| `urhox-libs/UI/Core/UI.lua:2341` | 焦点继承的判据是 `widget.focusable ~= false`——引擎自己的 `EditMenu` 就用这个开关避免抢走输入框焦点 |

链条：点按钮 → `TextField` 失焦 → 软键盘收起 → **画布高度变化 → 整棵 Yoga 布局位移** → 抬起时命中的已经不是按钮
→ `OnClick` 静默不触发。**修法就是一行**：按钮设 `focusable = false`（`scripts/ui/ChatPanel.lua` 里「发送」与
「跳过等待」两个按钮都加了），改完用户复测确认「它可以发送」。

**How to apply:** 界面里只要有软键盘输入框，它旁边的按钮**默认**加 `focusable = false`，不要等复现。
排查时旁证比报错快——同一份包里「跳过等待」点击是好的，因为那时键盘已经因回车收起、不再产生位移。
⚠️ 另记一条取证限制：**日志区分不出「点击发出」和「回车发出」**（两条路径汇入同一个发送函数）。
要做成硬证据必须在发送入口带一个来源标签再构建一轮，别拿时序旁证当结论写进验收材料。

## 14. ✅ 每日事件计划的云端运行证据（2026-09-22 17:45–17:46 实测，构建 `ea56ca2`）

会话：预览带 `?localDev=1`，屏幕 502x1116 / DPR≈1.03，洛杉矶当地 02:45 冷启动，存档为空
（`[Memory] 没有本地存档，使用初始内存状态`）。日志由 watcher 落在 `.maker/logs/runtime/runtime.log`
（45 KB，最后一条 17:46:49）。下面每条都是日志原文（同一行的 `[Script]` 与 `INFO` 双写已去重）。

### 14.1 计划只生成一次，时间来回跳不重算

```
[EventService] 生成 los_angeles 2026-09-22 的事件计划 8 个事件（种子=los_angeles|2026-09-22|m1-events-v1）
[EventService] 接管存档事件计划 0 天
[M0-1] 事件计划落盘 true
```

同一会话里连点面板 02:45 → 01:30 → 14:30 → 12:30，`生成 … 事件计划` 全日志**只出现一次**，
且各钟点都命中当日计划里自己的实例：

```
[EventService] 事件事实 key=los_angeles/2026-09-22/la_apartment_night_rest state=ongoing scene=la_apartment clock=01:30 fromSave=false
[EventService] 事件事实 key=los_angeles/2026-09-22/la_studio_zine_layout state=ongoing scene=la_studio clock=14:30 fromSave=false
[EventService] 事件事实 key=los_angeles/2026-09-22/la_cafe_midday state=ongoing scene=la_cafe clock=12:30 fromSave=false
```

`fromSave` 在这里必然是 `false`——同进程内存缓存即可命中，**不能**拿它当「没重算」的证据；
跨进程的那一半要靠重进后 `接管存档事件计划 N 天`（N≥1）+ `fromSave=true`，本轮**尚未取到**（见 14.5）。

### 14.2 状态背景确实跟着事件实例走

```
[M0-1] 开发测试事件 key=los_angeles/2026-09-22/la_studio_zine_layout 模板=la_studio_zine_layout 状态=ongoing 场景=la_studio 提示=小册子版面校样 钟点=14:30
[M0-0] 切换状态窗场景: la_studio → Textures/backgrounds/la-studio-dev-placeholder.png
[M0-0] 场景静帧已在本地: Textures/backgrounds/la-studio-dev-placeholder.png
```

两张开发占位图（apartment / studio）能被 `PrepareBackground` 命中，说明 `.project/resources.json`
的 `Textures/backgrounds/**` 把它们带进了包，增强引用模式没有裁掉。

### 14.3 排队补回把已结束事件说成已结束（真链路，非自检）

```
[MsgService] 用户消息 #27 已发出 serverTime=1790070348 计划回复=1790082010（排队到下一个窗口 · 队列 1 条）
[M0-1] 发送 #27 → 排队（她 06:00 之后能回，计划 1790082010）
[EventService] 排队补回 送达key=los_angeles/2026-09-22/la_apartment_night_rest 送达态=ended 送达=02:45 隔 42255 秒
[M0-1] 回复 #27 → replied 事实=la_studio_zine_layout key=los_angeles/2026-09-22/la_studio_zine_layout 状态=ongoing 场景=la_studio 送达key=los_angeles/2026-09-22/la_apartment_night_rest 送达态=ended 正文长度=264
```

回复引用**送达时刻**的实例并标 `ended`，同时自身落在**回复时刻**的实例上（studio ongoing）——
目标里「不得把已结束事件说成未开始」这条在主链路上成立。

### 14.4 日志隐私符合约定

用户消息只落 `#id / serverTime / 计划回复 / 队列长度`；回复只落 `fact / key / 状态 / 场景 / 正文长度`。
全程没有任何一条打出用户原文。

### 14.5 本轮没取到的两项（都只需人手，代码侧无待办）

1. **自检只跑到 A6 就没了后续**：`自检开始 → 场景 A → PASS A0…A6`，之后既无 `A7`、也无任何
   `场景 B…` 与 `自检结束` 汇总行，且整份日志 `ERROR`/`FAIL` 计数为 0。新加的 I（计划覆盖）与
   J（重进）断言一行都没出现在日志里。
   **「suite 中途抛出」这条已排除**：`DevSelfTest.Run` 的调用点本来就包在 `pcall` 里，异常会打
   `开发自检异常退出（正式会话继续，不受影响）`，而这行同样没出现。同批应当出现却同样缺席的还有
   `开场事件 key=…` 与 `M1 已就绪：…`——但之后 UI 完全能用、用户消息 #27 起一路正常，
   说明那几行**打过了、整批没上来**。
   → 结论：开机瞬间的突发日志会被管道**整批丢弃**（§11 第五条的加重形态，不是截掉尾巴而是丢一整批）。
   「自检结论只在开机说过一次」这件事本身就不可取证。已改为：① 逐场景 `pcall` +
   `场景 X 结束：判定 N 条`；② 一行式结论 `自检结论 通过=N 失败=M 场景=10/10[A B C D E F I J G H]`；
   ③ 该结论由 `HandleUpdate` 每 4 秒原样重发、共 3 次，落进后面的抓取窗口。
   **判据改成看结论行的 `场景=N/10`，不再数 PASS 条数。**
2. **面板 19:45 没点、也没做第二次冷进**：本轮点了 01:30 / 14:30 / 12:30，缺 19:45 那一档；
   会话只启动过一次，所以「同日期重进 occurrenceKey 不变」还缺 `接管存档事件计划 ≥1 天` 的证据。

### 14.6 不依赖设备的那一层：日期算法与落盘上限（2026-09-22 离线对拍）

条件 (b) 的后半句「下一本地日期才产生新实例」只靠 `daysFromCivil` / `civilDaySeconds` /
`TimeState.ShiftDateKey`，这部分不需要云端会话就能验：把 Lua 里的 Hinnant 原式逐行搬进 Node，
与真实 UTC 日历对拍 **2000-01-01 … 2100-12-31 共 36,890 天，不一致 0 条**；
`ShiftDateKey(+1/-1)` 在 `2026-03-31→04-01`、`2026-12-31→2027-01-01`、`2028-02-28→02-29→03-01`
（闰年）与 `2100-02-28→03-01`（百年非闰）上全部正确。
`EventService.ExportPlans` 的 4 天上限是从**队头** `table.remove`，即留最新丢最旧，
不存在「攒满 4 天后当天计划被裁掉→次日重算」的反向缺陷。

这两条只证日期与裁剪口径；变体定种的可复现性、重进接管、以及 19:45 那一档，仍然只能等 §14.5 的第二次会话。

同一层还能顺手证「日期变体不是空话」：把 `fnv1a`（Lua 5.4 的 64 位整数乘再 `& 0xFFFFFFFF`，
用 BigInt 忠实移植；种子串全 ASCII，`charCodeAt` 等价 `s:byte(i)`）+ `rolled % #variants + 1`
按 2026 全年 365 个 `dateKey` 跑一遍，8 个模板**每个都两种变体都命中**（182/183 与 183/182 对半分），
同一输入重算恒等，换城市则整批下标改变。也就是「同一天一定一样、不同天确实不一样」两条同时成立；
剩下的「重进后仍引用同一实例」仍需 §14.5 那次会话。




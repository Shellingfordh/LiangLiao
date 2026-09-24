# M2-B 设计：外部 LLM 润色网关（S1 代码已就位；部署与路径 A 仍待确认，见 §12）

日期：2026-09-23。状态：**设计稿，等待确认；零代码改动。**
权威边界不变：`TimeState` / `EventService` / `MessageService` / `MemoryService` 是时间、事实、
FIFO 与存档的唯一来源；LLM 只负责把已选定事实表达得更自然，任何失败立即回落 `ContentService` 模板。

---

## 0. 平台硬约束（决定整个形态，先于一切设计选择）

`engine-docs/recipes/http.md`（本地 AI Dev Kit，唯一 API 依据）：

| 运行形态 | HTTP 能力 |
| --- | --- |
| **客户端模式**（单机游戏的全部 Lua 代码） | `http` / `GetHttp` / `HttpClient` **完全屏蔽，不可用** |
| **服务端模式**（联机 C/S 的 server Lua 进程） | 可用，但受 **URL 白名单**限制：全字符串精确匹配（非域名匹配），加白名单**须联系 TapTap 制造团队** |

当前工程是纯单机（`.project/project.json` 只有 `entry: main.lua`，无 `entry_server`），
所以**游戏侧不存在"直接 fetch 网关"这条路**。可选接入路径只有三条：

- **路径 A（完整接入，推荐但依赖外部配合）**：启用 Maker 联机模式（`multiplayer.enabled=true` +
  server 入口），由服务端 Lua 进程持有唯一出站 HTTP 能力，做「白名单上下文 → 网关」的转发；
  客户端 Lua → 服务端 Lua 走引擎内建网络 API。需要：
  ① 向 TapTap 制造团队申请把网关 URL 精确加入白名单；
  ② 接受单机游戏引入联网基础设施（匹配/断线重连等），**这是对 M2-A 稳定形态的最大扰动源**。
- **路径 B（网关先行）**：本仓库只交付网关 + 契约 + 校验/回退层与其全部测试，
  客户端接入（`GATEWAY_ENABLED` 默认 false）留在适配层内但不接通 A 路径。
  游戏行为与 M2-A 逐字节一致；LLM 链路的端到端验证推迟到 A 条件齐备。
- **路径 C（明确放弃）**：把 key 打进客户端——违反硬边界，不讨论。

**本设计按 A 为目标形态撰写，B 为可先落地的子集。** 确认时请明确选 A（含向 TapTap 提白名单申请）
还是先 B。

---

## 1. 网关：独立、最小化、无数据库

### 1.1 目录与部署

```
gateway/                     # 独立 Node/TypeScript 服务，与 scripts/、assets/ 完全隔离
  package.json               # 零运行时依赖：node:http + fetch + 手写严格 JSON 校验
  src/
    server.ts                # 路由、鉴权、体大小限制、超时、错误映射
    validate.ts              # 请求 schema + 响应 schema（与 Lua 侧同一套规则的两份实现）
    prompt.ts                # system prompt 模板与白名单上下文渲染
    ratelimit.ts             # 内存固定窗口限流
    upstream.ts              # OpenAI 兼容 chat/completions 调用
  test/                      # node:test，上游用假 fetch 注入
  README.md                  # 部署与变量说明
  .env.example               # 只有变量名，无任何值
```

- 运行环境：**中国大陆可达**的 Serverless/容器（建议阿里云函数计算 Web 函数，备选腾讯云 SCF /
  Render 免费档）。不建议 Cloudflare Workers——真机用户在中国大陆，到 CF 的连通性未验证。
- 单实例、无状态、内存计数即可（演示级玩家量级 < 100 请求/天）；不引入 Redis、不引入数据库。
- 部署动作（上传、绑域名、出 HTTPS 证书、提白名单）**全部是用户侧待办**，git/MCP 代不了。

### 1.2 接口 schema

`POST https://<gateway-host>/v1/polish`

请求（客户端 → 网关，全部字段为白名单生成，见 §3）：

```json
{
  "v": 1,
  "requestId": "c-17-1727000000",
  "core": {
    "characterId": "lin_ruoxi",
    "characterName": "林若夕",
    "cityLabel": "洛杉矶",
    "relationStage": "陌生网友",
    "persona": "…≤400 字的固定人格摘要（构建期常量，非用户数据）…"
  },
  "deliveryFact":   { "eventTitle": "…", "eventSummary": "…", "sceneLabel": "…",
                      "clock": "19:45", "weather": "…", "availabilityLabel": "…",
                      "endTime": "22:00", "state": "ongoing|ended" },
  "sendFact":     { "eventTitle": "…", "state": "…", "endTime": "…",
                      "gapText": "42 分", "thenPhrase": "…" },
  "queued": false,
  "availability": "idle",
  "brief": false,
  "maxCharsPerSegment": 40,
  "maxTotalChars": 120,
  "userMessage": "…≤300 字符（发送前裁剪）…",
  "quote": { "messageId": 123, "role": "user", "preview": "…≤24 字…" }
}
```

响应 200：

```json
{ "source": "llm", "segments": ["短句一", "短句二"], "replyToQuotedMessageId": 123 }
```

- `source` 为网关审计字段，客户端不消费、不信任。
- 非 200 一律错误（见 §5），错误体只有 `{"error":"<机器码>"}`，不透传上游原文。

### 1.3 环境变量（只存在于网关部署平台）

| 变量 | 含义 |
| --- | --- |
| `LLM_API_BASE` | OpenAI 兼容端点（DeepSeek / 智谱 / Moonshot / OpenAI 均可） |
| `LLM_API_KEY` | 模型 Key。**只此一处**；不进 Lua、不进资源、不进 git、不进日志 |
| `LLM_MODEL` | 如 `deepseek-chat`（中文好、便宜；候选待用户定） |
| `GATEWAY_SHARED_SECRET` | 调用方鉴权密钥（见 §4） |
| `PORT` | 监听端口 |
| `RATE_LIMIT_PER_MIN` / `DAILY_TOKEN_BUDGET` | 默认 `2` / `30000`（completion tokens） |

### 1.4 上游调用参数

非流式；`response_format={"type":"json_object"}`；`temperature≈0.7`；
`max_tokens≈250`；上游超时 15s，网关整体预算 20s，超时 → 504。
禁止记录 `userMessage` / `quote.preview` / 模型输出原文；访问日志只记：
状态类别、`source`、请求体字节数、segments 数、总字符数、token 用量、时延、脱敏错误码。

---

## 2. 严格 JSON 契约与双重校验

模型被要求且只被允许输出：

```json
{ "segments": ["短句一", "短句二"], "replyToQuotedMessageId": 123 }
```

**网关侧 + 客户端侧各实现一份**（规则必须一致）：

1. 顶层恰为 `segments` 与 `replyToQuotedMessageId` 两键，多一键即拒绝（先剥 Markdown 围栏失败则拒绝）；
2. `segments`：数组，1–3 条；每条为非空字符串、trim 后非空；
3. 单句 ≤ `min(40, maxCharsPerSegment)` 字符；`brief=true` 时单句 ≤ 20 且只允许 1 句；总长 ≤ 120；
4. 拒绝含控制字符、`{`/`}`/反引号的句子（防泄 prompt/JSON）；
5. `replyToQuotedMessageId`：当且仅当等于本次请求的 `quote.messageId` 或 `null`，否则拒绝；
6. 任何一条不满足：网关 → `502 upstream_schema`；客户端 → 进回落。

客户端还会做**事实词表守卫**（Lua 侧最后一道）：segments 中出现词表白名单外的事件名/城市名/
时间表达即整条回落。词表 = 本次请求 facts 里的字段值 + 固定允许词。

---

## 3. 白名单上下文构建（谁生成什么）

全部输入由 Lua 在**交付时刻**从既有快照生成（`MakeSendContext`/`HandleDeliver` 同源），
新增字段 `brief`、`maxCharsPerSegment` 等来自 `ReplyPlan`：

- 角色与关系阶段：构建期常量（`core`）；
- 发送时 + 交付时事件事实：`EventService` 快照，含 `state`（ongoing/ended）与 `gapText`；
- 可用性与长度限制：`TimeState.ReplyPlanFor`；
- 当前用户消息：仅本条，≤300 字符（超了裁剪，不截存档原文）；
- 引用摘要：仅 `quotedTextPreview`（已有 24 字裁剪逻辑，复用）；
- **不发送**：历史消息、MemoryService 任何内容、真实 id/设备信息。

## 4. 鉴权与限流

- 服务端 Lua 出站时带 `Authorization: Bearer $GATEWAY_SHARED_SECRET`（值只存在于
  Maker 服务端环境变量/网关侧配置，**不写进 Lua 源码**——若 Maker 运行时不支持 server 侧
  env，则此校验降级为「白名单 URL 即边界」，设计中标为待验证项）。
- 网关校验：`401 unauthorized`。
- 限流（内存固定窗口，按 `X-Request-Meta` 的会话桶 + 全局）：默认每会话 2 req/min → `429`；
  全局日 token 预算耗尽 → `503 budget_exhausted`。
- 幂等：`requestId` 经 5 分钟 LRU 去重，重复请求直接重放缓存结果（防重发打穿限流）。

## 5. 错误分类与回落链路

| 网关返回 | 机器码 | 客户端动作 |
| --- | --- | --- |
| 200 + 合法 | — | 用 LLM segments |
| 400 | `invalid_request` | 回落（属客户端 bug，日志记类别） |
| 401 | `unauthorized` | 回落 + 本次会话熔断（不再试） |
| 429 | `rate_limited` | 回落 |
| 502 | `upstream_schema` / `upstream_error` | 回落 |
| 503 | `budget_exhausted` / `circuit_open` | 回落 + 会话级冷却 |
| 504 / 网络错误 | `timeout` | 回落 |

**回落 = 调用现有 `ContentService.ReplySegments(...)`，与 M2-A 完全同路径。**
客户端适配层总预算 8s（含排队），到点必交付——队列永不阻塞。
日志：`润色 结果=llm|fallback:<类别> 长度=N 段数=K`（不记原文）。

## 6. 队列与逐句展示时序（保持 M2-A FIFO）

现状：`planReplyAtUtc` 到点 → `Deliver()` → `onDeliver` **同步**生成模板并 `BeginReplyStream`。

改造（在 main.lua 的 `onDeliver` 适配层，MessageService 状态机语义不变）：

1. 到点交付前，队首先进入 `typing` 相位（现有 `EffectiveReplyAt` 已保证计划前 3s 显示
   「若夕正在输入」，视觉上无新增等待感）；
2. `onDeliver` 改为可异步：发出润色请求，挂起该条回复 ≤ `min(8s, 原 typing 窗口)`；
   等待期间相位保持 typing；
3. 成功且过双重校验 → `BeginReplyStream(llmSegments, ...)`；失败/超时 →
   `BeginReplyStream(templateSegments, ...)`——两条路都走同一个逐句上屏、同一个版本号机制；
4. 该条回复完成前，下一条队列消息不提前出队（现有 FIFO 天然保证）；
5. 若等待期间新消息入队，不影响本条：出队顺序仍按 `planReplyAtUtc`。

`replyToQuotedMessageId` 校验通过后仅用于标记本条回复「回应了被引用那句」，
不改变 M2-A 的引用展示。

## 7. 提示词（进 `prompt.ts`，构建期常量）

```
你是「林若夕」，生活在{cityLabel}，与对方是「{relationStage}」关系的异地聊天对象。
把下面提供的既定事实说成自然、克制、生活化的中文聊天口语。
硬性规则：
- 只允许表达「事实」区块中的内容；不得新增城市、事件、时间、关系历史、承诺或私人事实。
- 优先回应「对方消息」或被引用内容，但不得机械复述。
- 可短可分句（1–3 句），不必长篇；不确定时保守、含糊也可以。
- 不声称记得未提供的历史；不承诺现实行动；不扮演真人或任何现有作品角色。
- 输出只能是这个 JSON，不加 Markdown、解释或额外字段：
  {"segments": ["短句一", "短句二"], "replyToQuotedMessageId": <数字或null>}
上下文（JSON）：{whitelisted_payload}
```

## 8. AGENTS.md 边界措辞冲突（需一并决）

AGENTS.md 写有「不接入……运行时 Tripo/Marble 调用」，§7.3 修订记录写「模板是唯一方案」。
M2-B 引入运行时出站调用（仅润色、仅经服务端中继），**与这两句字面冲突**。
建议确认后把硬边界改修为：「运行时不做天气/新闻/Tripo/Marble 调用；运行时 LLM 润色仅允许经
白名单 URL 的无 key 网关调用，且事实权威始终在 Lua」——同时更新 `docs/2026-09-15-parallel-companion-design.md`
§7.3/§10 与 `docs/maker-lua-api-verification.md` §3 的相应结论。

---

## 9. 测试矩阵

**网关单测（node:test，假 fetch 注入，可在本地跑）**：

| # | 用例 | 期望 |
| --- | --- | --- |
| G1 | 上游返回非法 JSON / Markdown 围栏 | 502 upstream_schema |
| G2 | 额外字段（如 `"thought"`） | 拒绝 |
| G3 | `segments: []` / 4 条 / 含空串 | 拒绝 |
| G4 | 单句 41 字 / 总长 121 字 | 拒绝 |
| G5 | `replyToQuotedMessageId` ≠ 请求允许值且非 null | 拒绝 |
| G6 | 上游 401 / 429 / 5xx | 映射 502/503，不泄上游体 |
| G7 | 上游超时 | 504 |
| G8 | 缺/错 Authorization | 401 |
| G9 | 请求体 > 16 KB / 含未知字段 / schema 非法 | 400 |
| G10 | 限流：第 3 次/分钟 | 429 |
| G11 | 日预算耗尽 | 503 budget_exhausted |
| G12 | 同 requestId 重放 | 去重返回缓存 |
| G13 | brief=true 且返回 2 句 | 拒绝 |

**客户端适配层测试（DevSelfTest 扩展，确定性 UTC 驱动 + mock 传输层）**：

| # | 用例 | 期望 |
| --- | --- | --- |
| C1 | 成功路径 | 用 LLM segments，逐句 2.5s 间隔上屏，与 BeginReplyStream 同路径 |
| C2–C6 | 非法 JSON / 额外字段 / 空数组 / 超长句 / 错误引用 ID | 各自回落模板，日志只有类别与长度 |
| C7 | 401/429/5xx/超时/模型不可用 逐一注入 | 全部回落，队列时间线不变 |
| C8 | 连续 3 条消息排队 + 网关全挂 | FIFO 顺序、每条回复时刻与 M2-A 基线一致（不阻塞） |
| C9 | 逐句 typing 顺序 | 每段到达前保持「若夕正在输入」，全部上屏后才 idle |
| C10 | 词表守卫命中（编造城市名） | 回落 |
| C11 | GATEWAY_ENABLED=false | 行为与 M2-A 逐字节一致（基线保护） |

## 10. 成本、回滚与分阶段

- 模型建议 `deepseek-chat` 级：每次 ~1.5k in + 150 out tokens，单请求成本 < ¥0.01；
  日预算 30k tokens ≈ 每天 ~20 次润色，超限自动全模板——成本上界即预算本身。
- 回滚：`GATEWAY_ENABLED=false` 一行回 M2-A；网关可整体不部署，游戏零影响。
- 阶段：**S1** 网关 + 全部校验/适配层代码 + 测试（路径 B 范围，纯本地可验证）；
  **S2** 联机 server 中继 + 白名单申请（依赖 TapTap 团队与 Maker 联机改造）；
  **S3** 真机端到端验证与文档更新。S1 不改变当前游戏行为。

## 11. 需要你确认的决策点

1. **A 还是先 B**：是否现在启用 Maker 联机模式走完整接入（并向 TapTap 制造团队提白名单），
   还是先落地 S1（网关 + 适配层 + 测试，游戏行为不变）？
2. **部署位置**：阿里云函数计算（推荐）/ 腾讯云 SCF / Render / 你已有的其他可部署服务？
3. **模型与端点**：`deepseek-chat`（推荐）还是其他 OpenAI 兼容端点？
4. **AGENTS.md 措辞修订**（§8）是否随实施一并提交？
5. ~~确认后才写代码；本设计稿之外当前零实现改动。~~（已过时，见 §12：S1 范围的代码已按
   目标续跑指令落地，游戏行为不变；部署与路径 A 仍未获确认、未实施。）

## 12. 实施状态（2026-09-24 更新）

- **已落地（S1 / 路径 B 范围，全部本地可验证）**：`gateway/`（Node 零依赖，`node --test` 19/19 绿）；
  `scripts/services/PolishService.lua`（白名单 payload + validate.js 镜像校验 + 事实词表守卫 +
  FIFO 槽位泵 / 8s 预算 / 401 熔断 / 503 冷却）；`main.lua` 集成（`HandleDeliver` 走润色出口，
  `GatewayEnabled=false` 时同步回调，行为与 M2-A 一致、零外发）；`DevSelfTest` 场景 R/S/T
  覆盖 §9 测试矩阵中不需要真实网络的条目；maker-lua-lsp watch 诊断 0 Error。
- **与设计的差异**：网关源码用 CommonJS `.js` 而非设计里提过的 `prompt.ts`（零构建依赖优先）；
  其余 schema、错误映射、限流/预算/熔断语义与 §1–§7 一致。
- **仍未做（被上面 1–4 号决策点阻塞）**：网关部署与环境变量配置；路径 A（Maker 多人房中转 +
  TapTap URL 白名单）的真实 transport 接线；`GATEWAY_ENABLED=true`；R/S/T 真机构建验证；
  AGENTS.md §8 措辞修订。
- 运行记录与回滚：见 `CHANGELOG.md` 2026-09-24 条目；回滚仍是一行 `GatewayEnabled=false`。

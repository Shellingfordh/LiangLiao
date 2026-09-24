# M2-B 润色网关（m2b-polish-gateway）

`scripts/`（游戏客户端）与 `assets/` 完全隔离的最小 Node 服务：把白名单事件事实
润色成 1–3 条中文短句。**API Key 只存在于本服务的环境变量里，绝不出现在游戏端、
git 历史或日志中。** 设计全文见 `docs/2026-09-23-m2b-llm-gateway-design.md`。

当前状态：**S1 切片——代码与测试完成，未部署，游戏端 `GATEWAY_ENABLED=false`，
零外发。** 接入路径（A：Maker 多人房服务端中转 + TapTap URL 白名单）待用户确认。

## 目录

```
gateway/
  src/server.js      HTTP 入口（env 校验、16KB 流式上限、安全访问日志）
  src/gateway.js     核心处理：鉴权→熔断→限流→预算→校验→上游→严格解析
  src/validate.js    请求/响应双向严格契约（与 Lua 侧 PolishService 同一套规则）
  src/prompt.js      系统提示词 + 白名单上下文渲染
  src/ratelimit.js   固定窗口限流 / 日 token 预算 / 熔断 / requestId 幂等
  src/upstream.js    OpenAI 兼容上游调用（可注入 fetch，15s AbortController 超时）
  test/              node:test，覆盖设计矩阵 G1–G13 + 日志脱敏
```

## 运行

```bash
cp .env.example .env   # 填值（值不入库）
npm start              # node src/server.js
npm test               # node --test
```

## 环境变量

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| `LLM_API_BASE` | 是 | OpenAI 兼容基址，如 `https://api.deepseek.com/v1` |
| `LLM_API_KEY` | 是 | 上游模型 Key。**只进这里** |
| `LLM_MODEL` | 是 | 模型名，如 `deepseek-chat` |
| `GATEWAY_SHARED_SECRET` | 是 | 客户端 Bearer 鉴权共享密钥 |
| `PORT` | 否 | 默认 8080 |
| `RATE_LIMIT_PER_MIN` | 否 | 默认 2 |
| `DAILY_TOKEN_BUDGET` | 否 | 默认 30000（completion tokens/日） |
| `UPSTREAM_TIMEOUT_MS` | 否 | 默认 15000 |

## 接口

- `GET /healthz` → `{ "ok": true }`
- `POST /v1/polish`（`Authorization: Bearer <secret>`，体 ≤16KB）
  → 成功 `{ "source":"llm", "segments":[...], "replyToQuotedMessageId": n|null }`；
  失败只有 `{ "error": "<机器码>" }`（400/401/429/502/503/504，见设计 §5）。

## 部署建议（待确认后执行）

推荐**阿里云函数计算**（Web 函数，custom runtime 直接跑 `node src/server.js`，
环境变量在控制台配置；国内可达性优于 Cloudflare Workers）。
成本：默认限流 2/min + 日预算 30k token ≈ 每日个位数人民币（deepseek-chat 输出价）。

## 安全边界（不可回退）

- 响应校验失败、上游超时、模型不可用 → 对应 5xx 机器码，客户端立即回落
  `ContentService` 本地模板；队列永不阻塞。
- 日志只记状态/机器码/字节数/段数/字数/token/时延；有测试断言日志不含
  用户原文与模型输出原文。
- Lua 仍是时间、事件、FIFO 与存档的唯一来源；网关无状态、不持久化任何业务数据。

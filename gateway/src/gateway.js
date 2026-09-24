'use strict';

const { validateRequest, parseAndValidateModelText, runeLen } = require('./validate');
const { buildMessages } = require('./prompt');
const { createLimits, createIdempotency } = require('./ratelimit');

const DEFAULTS = {
  maxBodyBytes: 16 * 1024,
  ratePerMin: 2,
  dailyTokenBudget: 30000,
};

const err = (code) => {
  const e = new Error(code);
  e.code = code;
  return e;
};

/**
 * 与 HTTP 层解耦的核心处理器：rawBody(Buffer) + headers → {status, body}。
 * 只记安全字段：状态、机器码、字节数、段数、总字数、token、时延。
 * 绝不记录 userMessage / quote.preview / 模型输出原文。
 */
function createGateway(config) {
  const cfg = { ...DEFAULTS, ...config };
  if (!cfg.sharedSecret) throw new Error('GATEWAY_SHARED_SECRET missing');
  if (!cfg.callUpstream) throw new Error('callUpstream missing');
  const limits = createLimits({
    ratePerMin: cfg.ratePerMin,
    dailyTokenBudget: cfg.dailyTokenBudget,
    now: cfg.now,
  });
  const idem = createIdempotency(cfg.idempotencyTtlMs, cfg.idempotencyMax);

  return async function handle(rawBody, headers = {}) {
    const startedAt = Date.now();
    const safeLog = (entry) => {
      if (cfg.log) cfg.log({ ms: Date.now() - startedAt, ...entry });
    };
    const finish = (status, body, logEntry) => {
      safeLog(logEntry || { status, code: body && body.error ? body.error : 'ok' });
      return { status, body };
    };

    if (!Buffer.isBuffer(rawBody) || rawBody.length > cfg.maxBodyBytes) {
      return finish(400, { error: 'invalid_request' });
    }
    const auth = headers.authorization || '';
    if (auth !== `Bearer ${cfg.sharedSecret}`) {
      return finish(401, { error: 'unauthorized' });
    }
    if (limits.breakerOpen()) {
      return finish(503, { error: 'circuit_open' });
    }
    if (!limits.acquireRate()) {
      return finish(429, { error: 'rate_limited' });
    }
    if (limits.budgetLeft() <= 0) {
      return finish(503, { error: 'budget_exhausted' });
    }

    let json;
    try {
      json = JSON.parse(rawBody.toString('utf8'));
    } catch {
      return finish(400, { error: 'invalid_request' });
    }
    const vr = validateRequest(json);
    if (!vr.ok) {
      return finish(400, { error: 'invalid_request' });
    }
    const req = vr.req;
    if (runeLen(req.userMessage) > 300) {
      return finish(400, { error: 'invalid_request' });
    }
    const cached = idem.get(req.requestId);
    if (cached) {
      return finish(cached.status, cached.body, { status: cached.status, code: 'replay' });
    }

    let up;
    try {
      up = await cfg.callUpstream(buildMessages(req));
    } catch (e) {
      limits.recordFailure();
      const ecode = String((e && e.code) || '');
      let code;
      let status;
      if (ecode === 'upstream_timeout') {
        code = 'timeout';
        status = 504;
      } else if (ecode === 'upstream_status:401' || ecode === 'upstream_status:403') {
        code = 'upstream_unauthorized';
        status = 502;
      } else {
        code = 'upstream_error';
        status = 502;
      }
      idem.set(req.requestId, { status, body: { error: code } });
      return finish(status, { error: code }, { status, code, bytes: rawBody.length });
    }

    let validated;
    try {
      validated = parseAndValidateModelText(up.text, req);
    } catch {
      limits.recordFailure();
      idem.set(req.requestId, { status: 502, body: { error: 'upstream_schema' } });
      return finish(502, { error: 'upstream_schema' }, { status: 502, code: 'upstream_schema', bytes: rawBody.length });
    }
    // 只有走到「契约校验通过」才算一次真正的成功：
    // 若在上游调用后就重置，模型持续输出非法 JSON 时失败计数永远到不了熔断阈值。
    limits.recordSuccess();

    limits.addTokens(up.completionTokens || 0);
    const out = {
      source: 'llm',
      segments: validated.segments,
      replyToQuotedMessageId: validated.replyToQuotedMessageId,
    };
    idem.set(req.requestId, { status: 200, body: out });
    return finish(200, out, {
      status: 200,
      code: 'ok',
      bytes: rawBody.length,
      segments: out.segments.length,
      chars: out.segments.reduce((a, s) => a + runeLen(s), 0),
      tokens: up.completionTokens || 0,
    });
  };
}

module.exports = { createGateway };

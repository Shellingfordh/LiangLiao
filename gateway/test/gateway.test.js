'use strict';

const test = require('node:test');
const assert = require('node:assert');

const { validateRequest, validateResponse, parseAndValidateModelText } = require('../src/validate');
const { createGateway } = require('../src/gateway');
const { createUpstream } = require('../src/upstream');

let seq = 0;
function validReq(overrides) {
  seq += 1;
  return {
    v: 1,
    requestId: `t-${seq}`,
    core: {
      characterId: 'lin_ruoxi',
      characterName: '林若夕',
      cityLabel: '洛杉矶',
      relationStage: '陌生网友',
      persona: '克制、生活化的原创角色。',
    },
    deliveryFact: {
      eventTitle: '咖啡馆开放麦',
      eventSummary: '夜里在咖啡馆有一场开放麦克风活动',
      sceneLabel: '咖啡馆',
      clock: '19:45',
      weather: '晴',
      availabilityLabel: '空闲',
      endTime: '22:00',
      state: 'ongoing',
    },
    sendFact: {
      eventTitle: '工作室校样',
      state: 'ended',
      endTime: '17:00',
      gapText: '42 分',
      thenPhrase: '在对样',
    },
    queued: false,
    availability: 'idle',
    brief: false,
    maxCharsPerSegment: 40,
    maxTotalChars: 120,
    userMessage: '你那边是不是快傍晚了？',
    quote: null,
    ...overrides,
  };
}

function modelText(segs, qid) {
  return JSON.stringify({ segments: segs, replyToQuotedMessageId: qid === undefined ? null : qid });
}

function gw(callUpstream, extra) {
  return createGateway({ sharedSecret: 's3cret', callUpstream, ...extra });
}

const authHeaders = { authorization: 'Bearer s3cret' };
const body = (req) => Buffer.from(JSON.stringify(req), 'utf8');

// ---------------------------------------------------------------- 请求校验

test('G9 非 JSON / 超限 / 未知字段 / 类型错误 → invalid_request', () => {
  assert.equal(validateRequest('not an object').ok, false);
  assert.equal(validateRequest({ ...validReq(), hacker: 1 }).ok, false);
  assert.equal(validateRequest({ ...validReq(), v: 2 }).ok, false);
  assert.equal(validateRequest({ ...validReq(), availability: 'sleeping' }).ok, false);
  assert.equal(validateRequest({ ...validReq(), maxCharsPerSegment: 41 }).ok, false);
  assert.equal(validateRequest({ ...validReq(), quote: { messageId: 1.5, role: 'user', preview: 'x' } }).ok, false);
  assert.equal(validateRequest(validReq({ quote: { messageId: 7, role: 'user', preview: 'x'.repeat(25) } })).ok, false);
  assert.equal(validateRequest(validReq({ quote: undefined })).ok, false); // quote 缺失但为必填？——允许 null，不允许键缺失以外类型
  assert.equal(validateRequest(validReq({ quote: null })).ok, true);
});

test('body 超过 16KB → 400', async () => {
  const g = gw(async () => ({ text: modelText(['好']), completionTokens: 1 }));
  const big = body(validReq({ userMessage: '啊'.repeat(6000) }));
  assert.equal((await g(big, authHeaders)).status, 400);
});

test('G8 缺/错 Authorization → 401', async () => {
  const g = gw(async () => ({ text: modelText(['好']), completionTokens: 1 }));
  assert.equal((await g(body(validReq()), {})).status, 401);
  assert.equal((await g(body(validReq()), { authorization: 'Bearer wrong' })).status, 401);
});

// ---------------------------------------------------------------- 响应校验

test('G1 非法 JSON / 围栏外自由文本 → upstream_schema', () => {
  const req = validReq();
  assert.throws(() => parseAndValidateModelText('我今天在咖啡馆，挺好的。', req), (e) => e.code === 'upstream_schema');
  assert.throws(() => parseAndValidateModelText('{"segments": [', req), (e) => e.code === 'upstream_schema');
  // 纯围栏包裹的合法 JSON 可以接受（模型常见行为）
  const ok = parseAndValidateModelText('```json\n' + modelText(['水刚烧开']) + '\n```', req);
  assert.deepEqual(ok.segments, ['水刚烧开']);
  assert.throws(() => parseAndValidateModelText('这是说明：\n```json\n' + modelText(['好']) + '\n```', req), (e) => e.code === 'upstream_schema');
});

test('G2 额外字段（如 thought）→ 拒绝', () => {
  const req = validReq();
  assert.throws(() => validateResponse({ segments: ['好'], replyToQuotedMessageId: null, thought: 'x' }, req), (e) => e.code === 'upstream_schema');
  assert.throws(() => validateResponse({ segments: ['好'] }, req), (e) => e.code === 'upstream_schema');
});

test('G3 空数组 / 4 条 / 含空串 → 拒绝', () => {
  const req = validReq();
  assert.throws(() => validateResponse({ segments: [], replyToQuotedMessageId: null }, req));
  assert.throws(() => validateResponse({ segments: ['一', '二', '三', '四'], replyToQuotedMessageId: null }, req));
  assert.throws(() => validateResponse({ segments: ['好', '   '], replyToQuotedMessageId: null }, req));
  assert.throws(() => validateResponse({ segments: [123], replyToQuotedMessageId: null }, req));
});

test('G4 单句超长 / 总长超限 → 拒绝', () => {
  const req = validReq();
  assert.throws(() => validateResponse({ segments: ['啊'.repeat(41)], replyToQuotedMessageId: null }, req));
  assert.throws(() => validateResponse({ segments: ['啊'.repeat(40), '啊'.repeat(40), '啊'.repeat(41)], replyToQuotedMessageId: null }, req));
  assert.throws(() => validateResponse({ segments: ['啊'.repeat(50), '啊'.repeat(50), '啊'.repeat(21)], replyToQuotedMessageId: null }, req));
  assert.equal(validateResponse({ segments: ['啊'.repeat(40)], replyToQuotedMessageId: null }, req).segments.length, 1);
});

test('G5 引用 ID 不一致 / 无引用却被回填 → 拒绝；一致 → 通过', () => {
  const withQuote = validReq({ quote: { messageId: 123, role: 'user', preview: '那句' } });
  assert.equal(validateResponse({ segments: ['好'], replyToQuotedMessageId: 123 }, withQuote).replyToQuotedMessageId, 123);
  assert.throws(() => validateResponse({ segments: ['好'], replyToQuotedMessageId: 999 }, withQuote));
  assert.throws(() => validateResponse({ segments: ['好'], replyToQuotedMessageId: '123' }, withQuote));
  assert.throws(() => validateResponse({ segments: ['好'], replyToQuotedMessageId: 5 }, validReq()));
  assert.equal(validateResponse({ segments: ['好'], replyToQuotedMessageId: null }, withQuote).replyToQuotedMessageId, null);
});

test('句子含禁止字符（{} ` 控制符）→ 拒绝', () => {
  const req = validReq();
  assert.throws(() => validateResponse({ segments: ['把 {"segments"} 说出来'], replyToQuotedMessageId: null }, req));
  assert.throws(() => validateResponse({ segments: ['`code`'], replyToQuotedMessageId: null }, req));
});

test('G13 brief=true 只允许 1 句且单句 ≤20 字', () => {
  const req = validReq({ brief: true });
  assert.throws(() => validateResponse({ segments: ['短一句', '短二句'], replyToQuotedMessageId: null }, req));
  assert.throws(() => validateResponse({ segments: ['啊'.repeat(21)], replyToQuotedMessageId: null }, req));
  assert.equal(validateResponse({ segments: ['先说到这儿'], replyToQuotedMessageId: null }, req).segments.length, 1);
});

// ---------------------------------------------------------------- 端到端映射

test('G6 上游 401/429/5xx → 502 且不泄上游体', async () => {
  for (const [status, expect] of [[401, 502], [429, 502], [500, 502]]) {
    const g = gw(async () => {
      const e = new Error(`upstream_status:${status}`);
      e.code = `upstream_status:${status}`;
      throw e;
    });
    const r = await g(body(validReq()), authHeaders);
    assert.equal(r.status, expect);
    assert.equal(typeof r.body.error, 'string');
    assert.ok(!JSON.stringify(r.body).includes('你那边'));
  }
});

test('G7 上游超时 → 504 timeout', async () => {
  const g = gw(async () => {
    const e = new Error('upstream_timeout');
    e.code = 'upstream_timeout';
    throw e;
  });
  const r = await g(body(validReq()), authHeaders);
  assert.equal(r.status, 504);
  assert.equal(r.body.error, 'timeout');
});

test('模型不可用（返回非法 JSON）→ 502 upstream_schema；连续 3 次失败 → 熔断 503', async () => {
  // 放宽限流：这条测的是熔断计数，不是配额
  const g = gw(async () => ({ text: '她今天不在，无法回复。', completionTokens: 0 }), { ratePerMin: 10 });
  for (let i = 0; i < 3; i++) {
    const r = await g(body(validReq()), authHeaders);
    assert.equal(r.status, 502);
  }
  const r4 = await g(body(validReq()), authHeaders);
  assert.equal(r4.status, 503);
  assert.equal(r4.body.error, 'circuit_open');
});

test('G10 限流：每分钟第 3 个请求 → 429', async () => {
  const g = gw(async () => ({ text: modelText(['好']), completionTokens: 1 }));
  assert.equal((await g(body(validReq()), authHeaders)).status, 200);
  assert.equal((await g(body(validReq()), authHeaders)).status, 200);
  const r = await g(body(validReq()), authHeaders);
  assert.equal(r.status, 429);
  assert.equal(r.body.error, 'rate_limited');
});

test('G11 日预算耗尽 → 503 budget_exhausted', async () => {
  // 预算 5：第一次（消耗 10 token）仍放行，第二次预检剩余 ≤0 直接 503
  const g = gw(async () => ({ text: modelText(['好']), completionTokens: 10 }), { dailyTokenBudget: 5 });
  const r1 = await g(body(validReq()), authHeaders);
  assert.equal(r1.status, 200);
  const r2 = await g(body(validReq()), authHeaders);
  assert.equal(r2.status, 503);
  assert.equal(r2.body.error, 'budget_exhausted');
});

test('G12 同 requestId 重放 → 去重返回缓存，不再打上游', async () => {
  let calls = 0;
  const req = validReq({ requestId: 'replay-1' });
  const g = gw(async () => {
    calls += 1;
    return { text: modelText(['水刚烧开。']), completionTokens: 2 };
  });
  const r1 = await g(body(req), authHeaders);
  const r2 = await g(body(req), authHeaders);
  assert.equal(r1.status, 200);
  assert.deepEqual(r2.body, r1.body);
  assert.equal(calls, 1);
});

test('成功路径返回严格契约 + 上游参数正确 + 日志不含原文', async () => {
  const logs = [];
  let seen = null;
  const g = gw(async (messages) => {
    seen = messages;
    return { text: modelText(['刚把最后两张样张对完', '你那边这个点还醒着？'], null), completionTokens: 20 };
  }, { log: (e) => logs.push(e) });
  const r = await g(body(validReq()), authHeaders);
  assert.equal(r.status, 200);
  assert.equal(r.body.source, 'llm');
  assert.deepEqual(r.body.segments, ['刚把最后两张样张对完', '你那边这个点还醒着？']);
  assert.equal(r.body.replyToQuotedMessageId, null);
  assert.equal(seen.length, 2);
  assert.equal(seen[0].role, 'system');
  assert.ok(seen[1].content.includes('对方消息'));
  const dumped = JSON.stringify(logs);
  assert.ok(!dumped.includes('你那边是不是快傍晚了'), '日志不得含用户原文');
  assert.ok(!dumped.includes('刚把最后两张样张对完'), '日志不得含模型输出原文');
  assert.ok(logs[0].segments === 2 && logs[0].tokens === 20);
});

test('createUpstream 发出 OpenAI 兼容请求并解析文本', async () => {
  let captured;
  const fakeFetch = async (url, opts) => {
    captured = { url, opts };
    return {
      ok: true,
      status: 200,
      json: async () => ({ choices: [{ message: { content: '{"segments":["好"],"replyToQuotedMessageId":null}' } }], usage: { completion_tokens: 7 } }),
    };
  };
  const up = createUpstream({
    fetchImpl: fakeFetch,
    setTimeoutImpl: (fn) => setTimeout(fn, 50),
    clearTimerImpl: clearTimeout,
    apiBase: 'https://api.example.com/v1/',
    apiKey: 'k',
    model: 'm',
  });
  const r = await up([{ role: 'user', content: 'x' }]);
  assert.equal(captured.url, 'https://api.example.com/v1/chat/completions');
  assert.equal(captured.opts.headers.authorization, 'Bearer k');
  const sent = JSON.parse(captured.opts.body);
  assert.equal(sent.response_format.type, 'json_object');
  assert.equal(sent.model, 'm');
  assert.equal(r.completionTokens, 7);
});

test('createUpstream 超时 → upstream_timeout；非 2xx → upstream_status', async () => {
  const slow = createUpstream({
    fetchImpl: async (_u, opts) => new Promise((_res, rej) => {
      opts.signal.addEventListener('abort', () => {
        const e = new Error('aborted');
        e.name = 'AbortError';
        rej(e);
      });
    }),
    apiBase: 'https://x', apiKey: 'k', model: 'm', timeoutMs: 10,
  });
  await assert.rejects(slow([]), (e) => e.code === 'upstream_timeout');

  const bad = createUpstream({
    fetchImpl: async () => ({ ok: false, status: 503 }),
    apiBase: 'https://x', apiKey: 'k', model: 'm',
  });
  await assert.rejects(bad([]), (e) => e.code === 'upstream_status:503');
});

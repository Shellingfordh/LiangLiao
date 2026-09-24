'use strict';

// 请求/响应双向严格校验。与 Lua 侧 scripts/services/PolishService.lua 是同一套契约的
// 两份实现：任何一条不满足都走回落，绝不放行「接近正确」的输出。

/** 按 Unicode 码点计数（与 Lua 侧 UTF-8 序列计数口径一致：一个汉字/emoji 记 1） */
function runeLen(s) {
  return Array.from(s).length;
}

function isStr(v, max) {
  return typeof v === 'string' && v.length > 0 && v.length <= max;
}

function isObj(v) {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

const AVAILABILITY = new Set(['idle', 'fragments', 'busy', 'offline']);
const EVENT_STATE = new Set(['upcoming', 'ongoing', 'ended']);

function validateFact(f, maxLen) {
  if (!isObj(f)) return false;
  const strFields = ['eventTitle', 'eventSummary', 'sceneLabel', 'clock', 'weather', 'availabilityLabel', 'state'];
  for (const k of strFields) {
    if (!isStr(f[k], maxLen)) return false;
  }
  if (!EVENT_STATE.has(f.state)) return false;
  if (!isStr(f.endTime, 8)) return false;
  return true;
}

/**
 * 校验并归一化客户端 → 网关的请求体。
 * 返回 { ok:true, req } 或 { ok:false, code:'invalid_request' }。
 * 未声明的顶层字段与 sendFact.queuedEnded 之外的多余键一律拒绝（防走私上下文）。
 */
function validateRequest(body) {
  if (!isObj(body)) return { ok: false, code: 'invalid_request' };
  try {
    const TOP = new Set(['v', 'requestId', 'core', 'deliveryFact', 'sendFact', 'queued', 'availability', 'brief', 'maxCharsPerSegment', 'maxTotalChars', 'userMessage', 'quote']);
    for (const k of Object.keys(body)) {
      if (!TOP.has(k)) return { ok: false, code: 'invalid_request' };
    }
    if (body.v !== 1) return { ok: false, code: 'invalid_request' };
    if (!isStr(body.requestId, 64)) return { ok: false, code: 'invalid_request' };

    const core = body.core;
    if (!isObj(core)) return { ok: false, code: 'invalid_request' };
    const CORE = new Set(['characterId', 'characterName', 'cityLabel', 'relationStage', 'persona']);
    for (const k of Object.keys(core)) {
      if (!CORE.has(k)) return { ok: false, code: 'invalid_request' };
    }
    if (!isStr(core.characterId, 40) || !isStr(core.characterName, 20) ||
        !isStr(core.cityLabel, 20) || !isStr(core.relationStage, 20) ||
        !isStr(core.persona, 400)) {
      return { ok: false, code: 'invalid_request' };
    }

    const df = body.deliveryFact;
    if (!validateFact(df, 60) || !isStr(df.eventSummary, 200)) {
      return { ok: false, code: 'invalid_request' };
    }
    const sf = body.sendFact;
    if (!isObj(sf)) return { ok: false, code: 'invalid_request' };
    const SEND = new Set(['eventTitle', 'state', 'endTime', 'gapText', 'thenPhrase']);
    for (const k of Object.keys(sf)) {
      if (!SEND.has(k)) return { ok: false, code: 'invalid_request' };
    }
    if (!isStr(sf.eventTitle, 60) || !EVENT_STATE.has(sf.state) || !isStr(sf.endTime, 8) ||
        !isStr(sf.gapText, 20) || !isStr(sf.thenPhrase, 40)) {
      return { ok: false, code: 'invalid_request' };
    }

    if (typeof body.queued !== 'boolean' || typeof body.brief !== 'boolean') return { ok: false, code: 'invalid_request' };
    if (!AVAILABILITY.has(body.availability)) return { ok: false, code: 'invalid_request' };
    if (!Number.isInteger(body.maxCharsPerSegment) || body.maxCharsPerSegment < 1 || body.maxCharsPerSegment > 40) return { ok: false, code: 'invalid_request' };
    if (!Number.isInteger(body.maxTotalChars) || body.maxTotalChars < 1 || body.maxTotalChars > 120) return { ok: false, code: 'invalid_request' };

    if (!isStr(body.userMessage, 300)) return { ok: false, code: 'invalid_request' };

    // quote 是显式契约：无引用必须传 null。键缺失 = 非法，
    // 防「客户端忘了带 quote」被静默当成「没有引用」而绕过引用校验。
    if (!('quote' in body)) return { ok: false, code: 'invalid_request' };
    if (body.quote !== null) {
      const q = body.quote;
      if (!isObj(q)) return { ok: false, code: 'invalid_request' };
      const QUOTE = new Set(['messageId', 'role', 'preview']);
      for (const k of Object.keys(q)) {
        if (!QUOTE.has(k)) return { ok: false, code: 'invalid_request' };
      }
      if (!Number.isInteger(q.messageId) || q.messageId <= 0) return { ok: false, code: 'invalid_request' };
      if (q.role !== 'user' && q.role !== 'her') return { ok: false, code: 'invalid_request' };
      if (!isStr(q.preview, 24)) return { ok: false, code: 'invalid_request' };
    }

    return { ok: true, req: body };
  } catch {
    return { ok: false, code: 'invalid_request' };
  }
}

/** 剥掉模型偶尔加的 Markdown 代码围栏；围栏外还有内容即判定失败 */
function stripCodeFence(text) {
  const t = text.trim();
  const m = /^```(?:json)?\s*([\s\S]*?)\s*```$/.exec(t);
  return m ? m[1] : t;
}

/** 句子禁止出现的字符：JSON 大括号/反引号（防泄 prompt 与契约）、控制字符 */
function hasForbiddenChar(s) {
  for (const ch of s) {
    const cp = ch.codePointAt(0);
    if (cp < 0x20 || cp === 0x7f) return true;
    if (ch === '{' || ch === '}' || ch === '`') return true;
  }
  return false;
}

/**
 * 严格解析并校验模型输出文本 → { segments, replyToQuotedMessageId }。
 * req 提供本次允许的引用 id 与长度限制。失败抛 Error，err.code 为机器码。
 */
function parseAndValidateModelText(text, req) {
  let parsed;
  try {
    parsed = JSON.parse(stripCodeFence(String(text)));
  } catch {
    const e = new Error('model_json');
    e.code = 'upstream_schema';
    throw e;
  }
  return validateResponse(parsed, req);
}

/** 响应对象校验（供测试与网关复用；入参应为已解析的 JS 值） */
function validateResponse(obj, req) {
  const fail = (why) => {
    const e = new Error(why);
    e.code = 'upstream_schema';
    throw e;
  };
  if (!isObj(obj)) fail('not_object');
  const keys = Object.keys(obj).sort();
  if (keys.length !== 2 || keys[0] !== 'replyToQuotedMessageId' || keys[1] !== 'segments') {
    fail('key_set'); // 仅允许 segments 与 replyToQuotedMessageId，多一键即拒绝
  }
  const segs = obj.segments;
  if (!Array.isArray(segs) || segs.length < 1 || segs.length > 3) fail('segments_count');

  const brief = req && req.brief === true;
  const perMax = Math.min(40, (req && req.maxCharsPerSegment) || 40);
  const totalMax = Math.min(120, (req && req.maxTotalChars) || 120);
  const effectivePer = brief ? Math.min(perMax, 20) : perMax;

  const cleaned = [];
  let total = 0;
  for (const s of segs) {
    if (typeof s !== 'string') fail('segment_type');
    const t = s.trim();
    if (t === '') fail('segment_empty');
    if (hasForbiddenChar(t)) fail('segment_char');
    const n = runeLen(t);
    if (n > effectivePer) fail('segment_long');
    total += n;
    cleaned.push(t);
  }
  if (total > totalMax) fail('total_long');
  if (brief && cleaned.length > 1) fail('brief_multi');

  const qid = obj.replyToQuotedMessageId;
  const allowed = req && req.quote ? req.quote.messageId : null;
  if (qid !== null && qid !== undefined) {
    if (!Number.isInteger(qid)) fail('quote_type');
    if (allowed === null || qid !== allowed) fail('quote_id');
  }

  return { segments: cleaned, replyToQuotedMessageId: (qid === undefined ? null : qid) };
}

module.exports = { validateRequest, validateResponse, parseAndValidateModelText, stripCodeFence, runeLen };

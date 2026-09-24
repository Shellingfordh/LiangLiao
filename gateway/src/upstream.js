'use strict';

// OpenAI 兼容 chat/completions 出站。fetch 与 setTimeout 可注入（测试用假实现）。
// 失败语义只暴露机器码：upstream_timeout / upstream_status:<n> / upstream_malformed，
// 上游响应体原文一律不外传。

function timeoutError() {
  const e = new Error('upstream_timeout');
  e.code = 'upstream_timeout';
  return e;
}

function createUpstream({ fetchImpl, setTimeoutImpl, clearTimerImpl, apiBase, apiKey, model, timeoutMs = 15000, maxTokens = 250, temperature = 0.7 }) {
  const f = fetchImpl || fetch;
  const st = setTimeoutImpl || setTimeout;
  const ct = clearTimerImpl || clearTimeout;
  return async function callUpstream(messages) {
    const ac = new AbortController();
    const timer = st(() => ac.abort(), timeoutMs);
    let res;
    try {
      res = await f(`${apiBase.replace(/\/$/, '')}/chat/completions`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model,
          messages,
          temperature,
          max_tokens: maxTokens,
          response_format: { type: 'json_object' },
        }),
        signal: ac.signal,
      });
    } catch (err) {
      ct(timer);
      throw err && err.name === 'AbortError' ? timeoutError() : new Error('upstream_unreachable');
    }
    ct(timer);
    if (!res.ok) {
      const e = new Error(`upstream_status:${res.status}`);
      e.code = `upstream_status:${res.status}`;
      throw e;
    }
    let body;
    try {
      body = await res.json();
    } catch {
      throw new Error('upstream_malformed');
    }
    const choice = body && Array.isArray(body.choices) ? body.choices[0] : null;
    const text = choice && choice.message && typeof choice.message.content === 'string'
      ? choice.message.content : null;
    if (text === null) throw new Error('upstream_malformed');
    const usage = body.usage || {};
    return {
      text,
      completionTokens: Number.isFinite(usage.completion_tokens) ? usage.completion_tokens : 0,
    };
  };
}

module.exports = { createUpstream, timeoutError };

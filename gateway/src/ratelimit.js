'use strict';

// 内存固定窗口限流 + 日 token 预算 + 最小熔断。无状态单实例足够（演示级 <100 请求/天）。

function createLimits({ ratePerMin, dailyTokenBudget, now = () => Date.now() }) {
  const minute = { window: 0, count: 0 };
  const budget = { day: '', tokens: 0 };
  const breaker = { fails: 0, openUntil: 0 };

  function acquireRate() {
    const w = Math.floor(now() / 60000);
    if (w !== minute.window) {
      minute.window = w;
      minute.count = 0;
    }
    if (minute.count >= ratePerMin) return false;
    minute.count += 1;
    return true;
  }

  function budgetLeft() {
    const day = new Date(now()).toISOString().slice(0, 10);
    if (day !== budget.day) {
      budget.day = day;
      budget.tokens = 0;
    }
    return dailyTokenBudget - budget.tokens;
  }

  function addTokens(n) {
    budgetLeft(); // 触发跨日重置
    budget.tokens += Math.max(0, n | 0);
  }

  // 连续 3 次上游失败 → 熔断 10 分钟，期间直接 503（客户端回落模板）
  function breakerOpen() {
    return breaker.openUntil > now();
  }

  function recordFailure() {
    breaker.fails += 1;
    if (breaker.fails >= 3) {
      breaker.openUntil = now() + 10 * 60 * 1000;
      breaker.fails = 0;
    }
  }

  function recordSuccess() {
    breaker.fails = 0;
  }

  return { acquireRate, budgetLeft, addTokens, breakerOpen, recordFailure, recordSuccess };
}

/** requestId 幂等缓存：TTL 内重放同一结果，防重发打穿限流 */
function createIdempotency(ttlMs = 5 * 60 * 1000, max = 256) {
  const map = new Map();
  function get(key) {
    const hit = map.get(key);
    if (!hit) return undefined;
    if (hit.expires < Date.now()) {
      map.delete(key);
      return undefined;
    }
    return hit.value;
  }
  function set(key, value) {
    if (map.size >= max) {
      map.delete(map.keys().next().value);
    }
    map.set(key, { value, expires: Date.now() + ttlMs });
  }
  return { get, set };
}

module.exports = { createLimits, createIdempotency };

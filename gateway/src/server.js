'use strict';

const http = require('node:http');
const { createGateway } = require('./gateway');
const { createUpstream } = require('./upstream');

function requiredEnv(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`missing required env: ${name}`);
    process.exit(1);
  }
  return v;
}

function main() {
  const callUpstream = createUpstream({
    apiBase: requiredEnv('LLM_API_BASE'),
    apiKey: requiredEnv('LLM_API_KEY'),
    model: requiredEnv('LLM_MODEL'),
    timeoutMs: Number(process.env.UPSTREAM_TIMEOUT_MS || 15000),
  });
  const handle = createGateway({
    sharedSecret: requiredEnv('GATEWAY_SHARED_SECRET'),
    callUpstream,
    ratePerMin: Number(process.env.RATE_LIMIT_PER_MIN || 2),
    dailyTokenBudget: Number(process.env.DAILY_TOKEN_BUDGET || 30000),
    // 访问日志只含安全字段：状态、机器码、字节数、段数、字数、token、时延
    log: (e) => console.log(JSON.stringify({ t: new Date().toISOString(), ...e })),
  });

  const server = http.createServer((req, res) => {
    const send = (status, body) => {
      const data = JSON.stringify(body);
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(data);
    };
    if (req.method === 'GET' && req.url === '/healthz') {
      send(200, { ok: true });
      return;
    }
    if (req.method !== 'POST' || req.url !== '/v1/polish') {
      send(404, { error: 'not_found' });
      return;
    }
    const chunks = [];
    let size = 0;
    let aborted = false;
    req.on('data', (c) => {
      size += c.length;
      if (size > 16 * 1024) {
        aborted = true;
        send(400, { error: 'invalid_request' });
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      if (aborted) return;
      handle(Buffer.concat(chunks), { authorization: req.headers.authorization || '' })
        .then((r) => send(r.status, r.body))
        .catch(() => send(500, { error: 'internal' }));
    });
  });

  const port = Number(process.env.PORT || 8788);
  server.listen(port, () => console.log(`polish-gateway listening on ${port}`));
}

if (require.main === module) main();

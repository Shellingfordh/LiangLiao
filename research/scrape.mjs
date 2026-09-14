import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const OUT = 'taptap-pages';
fs.mkdirSync(OUT, { recursive: true });

const ROUTES = [
  ['home',         'https://developer.taptap.cn/maker/docs'],
  ['intro',        'https://developer.taptap.cn/maker/docs/intro'],
  ['intro-what',   'https://developer.taptap.cn/maker/docs/intro/what-is-maker'],
  ['quickstart',   'https://developer.taptap.cn/maker/docs/quickstart'],
  ['guide',        'https://developer.taptap.cn/maker/docs/guide'],
  ['guide-script', 'https://developer.taptap.cn/maker/docs/guide/script'],
  ['guide-asset',  'https://developer.taptap.cn/maker/docs/guide/asset'],
  ['guide-publish','https://developer.taptap.cn/maker/docs/guide/publish'],
  ['guide-deploy', 'https://developer.taptap.cn/maker/docs/guide/deploy'],
  ['guide-export', 'https://developer.taptap.cn/maker/docs/guide/export'],
  ['guide-run',    'https://developer.taptap.cn/maker/docs/guide/run'],
  ['api',          'https://developer.taptap.cn/maker/docs/api'],
  ['api-script',   'https://developer.taptap.cn/maker/docs/api/script'],
  ['api-game',     'https://developer.taptap.cn/maker/docs/api/game'],
  ['api-engine',   'https://developer.taptap.cn/maker/docs/api/engine'],
  ['api-taptap',   'https://developer.taptap.cn/maker/docs/api/taptap'],
  ['guide-multiplayer','https://developer.taptap.cn/maker/docs/guide/multiplayer'],
  ['guide-pvp',    'https://developer.taptap.cn/maker/docs/guide/pvp'],
  ['guide-monetize','https://developer.taptap.cn/maker/docs/guide/monetize'],
  ['showcase',     'https://developer.taptap.cn/maker/docs/showcase'],
  ['examples',     'https://developer.taptap.cn/maker/docs/examples'],
  ['faq',          'https://developer.taptap.cn/maker/docs/faq'],
  ['changelog',    'https://developer.taptap.cn/maker/docs/changelog'],
  ['sdk',          'https://developer.taptap.cn/maker/docs/sdk'],
];

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

const summary = [];
for (const [name, url] of ROUTES) {
  try {
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    const status = resp ? resp.status() : 'no-resp';
    // Wait for SPA to render
    await page.waitForTimeout(3000);
    // Try a longer wait for content
    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    const html = await page.content();
    const title = await page.title();
    fs.writeFileSync(path.join(OUT, `${name}.html`), html);
    summary.push({ name, url, status, title, bytes: html.length });
    console.log(`${name.padEnd(22)} ${status} ${title} ${html.length}b`);
  } catch (e) {
    summary.push({ name, url, error: String(e).slice(0, 200) });
    console.log(`${name.padEnd(22)} ERR  ${String(e).slice(0, 120)}`);
  }
}
fs.writeFileSync(path.join(OUT, '_index.json'), JSON.stringify(summary, null, 2));
await browser.close();
console.log('DONE');

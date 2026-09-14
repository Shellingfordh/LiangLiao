import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const OUT = 'taptap-pages';
fs.mkdirSync(OUT, { recursive: true });

const ROUTES = [
  ['forge-home',          'https://developer.taptap.cn/forge'],
  ['forge-en',            'https://developer.taptap.cn/en/forge'],
  ['forge-zh',            'https://developer.taptap.cn/zh/forge'],
  ['doc-27',              'https://www.taptap.cn/doc/27'],
  ['doc-27-en',           'https://www.taptap.cn/en/doc/27'],
  ['doc-maker-agree',     'https://www.taptap.cn/doc/taptap-maker-agreement/'],
  ['leaderboard',         'https://maker.taptap.cn/leaderboard/'],
  // sample games on showcase
  ['app-810249',          'https://www.taptap.cn/app/810249'],
  ['app-810894',          'https://www.taptap.cn/app/810894'],
  ['app-813196',          'https://www.taptap.cn/app/813196'],
  ['app-813265',          'https://www.taptap.cn/app/813265'],
];

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

const summary = [];
for (const [name, url] of ROUTES) {
  try {
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    const status = resp ? resp.status() : 'no-resp';
    await page.waitForLoadState('networkidle', { timeout: 12000 }).catch(() => {});
    await page.waitForTimeout(2500);
    const html = await page.content();
    const title = await page.title();
    fs.writeFileSync(path.join(OUT, `${name}.html`), html);
    summary.push({ name, url, status, title, bytes: html.length });
    console.log(`${name.padEnd(24)} ${status} ${title.slice(0,40).padEnd(40)} ${html.length}b`);
  } catch (e) {
    summary.push({ name, url, error: String(e).slice(0, 200) });
    console.log(`${name.padEnd(24)} ERR  ${String(e).slice(0, 120)}`);
  }
}
fs.writeFileSync(path.join(OUT, '_index3.json'), JSON.stringify(summary, null, 2));
await browser.close();
console.log('DONE');

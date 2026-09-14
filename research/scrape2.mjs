import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const OUT = 'taptap-pages';
fs.mkdirSync(OUT, { recursive: true });

// Public-facing TapTap Maker site + alternate hosts + help center + search
const ROUTES = [
  // Maker public site (English & Chinese)
  ['maker-home',           'https://maker.taptap.cn/'],
  ['maker-home-en',        'https://maker.taptap.cn/en'],
  ['maker-home-zh',        'https://maker.taptap.cn/zh'],
  // Help center
  ['help-cn',              'https://help.taptap.cn/'],
  ['help-maker',           'https://help.taptap.cn/maker'],
  ['help-maker-faq',       'https://help.taptap.cn/maker/faq'],
  // Docs mirror
  ['docs-taptap',          'https://docs.taptap.cn/'],
  ['docs-taptap-maker',    'https://docs.taptap.cn/maker/'],
  // Maker sub-routes (guess from SPA)
  ['maker-tutorial',       'https://maker.taptap.cn/tutorial'],
  ['maker-tutorial-en',    'https://maker.taptap.cn/en/tutorial'],
  ['maker-tutorial-zh',    'https://maker.taptap.cn/zh/tutorial'],
  ['maker-guide',          'https://maker.taptap.cn/guide'],
  ['maker-guide-en',       'https://maker.taptap.cn/en/guide'],
  ['maker-guide-zh',       'https://maker.taptap.cn/zh/guide'],
  ['maker-help',           'https://maker.taptap.cn/help'],
  ['maker-help-en',        'https://maker.taptap.cn/en/help'],
  ['maker-help-zh',        'https://maker.taptap.cn/zh/help'],
  ['maker-doc',            'https://maker.taptap.cn/doc'],
  ['maker-doc-en',         'https://maker.taptap.cn/en/doc'],
  ['maker-doc-zh',         'https://maker.taptap.cn/zh/doc'],
  ['maker-docs',           'https://maker.taptap.cn/docs'],
  ['maker-docs-en',        'https://maker.taptap.cn/en/docs'],
  ['maker-docs-zh',        'https://maker.taptap.cn/zh/docs'],
  ['maker-about',          'https://maker.taptap.cn/about'],
  ['maker-about-en',       'https://maker.taptap.cn/en/about'],
  ['maker-about-zh',       'https://maker.taptap.cn/zh/about'],
  ['maker-create',         'https://maker.taptap.cn/create'],
  ['maker-editor',         'https://maker.taptap.cn/editor'],
  ['maker-showcase',       'https://maker.taptap.cn/showcase'],
  ['maker-showcase-en',    'https://maker.taptap.cn/en/showcase'],
  ['maker-showcase-zh',    'https://maker.taptap.cn/zh/showcase'],
  ['maker-publish',        'https://maker.taptap.cn/publish'],
  ['maker-publish-en',     'https://maker.taptap.cn/en/publish'],
  ['maker-publish-zh',     'https://maker.taptap.cn/zh/publish'],
];

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

const summary = [];
for (const [name, url] of ROUTES) {
  try {
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    const status = resp ? resp.status() : 'no-resp';
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
    await page.waitForTimeout(2000);
    const html = await page.content();
    const title = await page.title();
    fs.writeFileSync(path.join(OUT, `${name}.html`), html);
    summary.push({ name, url, status, title, bytes: html.length });
    console.log(`${name.padEnd(24)} ${status} ${title.padEnd(36)} ${html.length}b`);
  } catch (e) {
    summary.push({ name, url, error: String(e).slice(0, 200) });
    console.log(`${name.padEnd(24)} ERR  ${String(e).slice(0, 120)}`);
  }
}
fs.writeFileSync(path.join(OUT, '_index2.json'), JSON.stringify(summary, null, 2));
await browser.close();
console.log('DONE');

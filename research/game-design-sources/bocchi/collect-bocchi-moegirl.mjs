import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';

const ROOT = path.resolve('./');
const BOCCHI_DIR = path.join(ROOT, 'research/game-design-sources/bocchi');
if (!fs.existsSync(BOCCHI_DIR)) fs.mkdirSync(BOCCHI_DIR, { recursive: true });

function buildExistingUrlSet() {
  const urls = new Set();
  for (const file of fs.readdirSync(BOCCHI_DIR).filter(f => f.endsWith('.json'))) {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(BOCCHI_DIR, file), 'utf8'));
      const items = Array.isArray(data) ? data : (data.items || []);
      for (const item of items) {
        const u = item.url || item.arcurl || item.html_url || item.image_url || item.file_url || item.page_url || item.artwork_url || item.post_url || item.src || item.imageUrl || '';
        if (u && !u.includes('javascript:') && !u.startsWith('http://localhost')) urls.add(u);
      }
    } catch (e) {}
  }
  return urls;
}

const existingUrls = buildExistingUrlSet();
console.log(`Existing unique URLs loaded: ${existingUrls.size}`);

const sleep = ms => new Promise(r => setTimeout(r, ms));

function readJSON(name) {
  const p = path.join(BOCCHI_DIR, name);
  if (!fs.existsSync(p)) return [];
  try {
    const data = JSON.parse(fs.readFileSync(p, 'utf8'));
    return Array.isArray(data) ? data : (data.items || []);
  } catch (e) {
    return [];
  }
}

function writeJSON(filePath, items) {
  fs.writeFileSync(filePath, JSON.stringify({ items }, null, 2));
  console.log(`Wrote ${path.basename(filePath)}: ${items.length} items`);
}

function isRelevantImage(src, alt, title, caption) {
  const text = [alt, title, caption, src].join(' ').toLowerCase();
  return /(bocchi|后藤|山田|iyo|リョウ|伊地知|虹夏|喜多|郁代|kessoku|結束|バンド|btr|gotoh|yamada|ijichi|kita)/i.test(text);
}

async function collectMoegirlCharacter(page, name, url) {
  const outFile = path.join(BOCCHI_DIR, `moegirl-${name}.json`);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(3000);

  const results = await page.evaluate(() => {
    const items = [];
    const selectors = ['img', 'a img', 'div img', 'figure img', '.gallery img', '.mw-gallery img', '.thumb img', 'img.image'];
    const seen = new Set();
    document.querySelectorAll(selectors.join(', ')).forEach(img => {
      const src = img.getAttribute('src') || img.getAttribute('data-src') || img.getAttribute('data-original') || img.currentSrc || '';
      if (!src || seen.has(src)) return;
      seen.add(src);
      const alt = img.getAttribute('alt') || '';
      const title = img.getAttribute('title') || '';
      let caption = '';
      const candidates = [img.closest('figcaption'), img.parentElement?.parentElement?.querySelector('figcaption'), img.parentElement];
      for (const el of candidates) {
        if (!el) continue;
        caption += ' ' + (el.innerText || el.textContent || el.getAttribute('aria-label') || ''));
      }
      items.push({ url: src, alt, title, text: [alt, title, caption, src].join(' ').slice(0, 240) });
    });
    return items;
  });

  const unique = [];
  for (const item of results) {
    if (!item.url || existingUrls.has(item.url)) continue;
    existingUrls.add(item.url);
    if (!isRelevantImage(item.url, item.alt, item.title, item.text)) continue;
    unique.push(item);
  }
  const merged = [...readJSON(path.basename(outFile)), ...unique];
  writeJSON(outFile, merged);
  console.log(`Moegirl ${name}: ${results.length} raw, ${unique.length} relevant new, total ${merged.length}`);
  return unique.length;
}

async function main() {
  const browser = await chromium.launch();
  const context = await browser.newContext({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36' });
  const page = await context.newPage();

  const targets = [
    { name: 'hitori', url: 'https://zh.moegirl.org.cn/%E5%90%8E%E8%97%A4%E4%B8%80%E9%87%8C' },
    { name: 'ryo', url: 'https://zh.moegirl.org.cn/%E5%B1%B1%E7%94%B0RyO' },
    { name: 'nijika', url: 'https://zh.moegirl.org.cn/%E4%BC%8A%E5%9C%B0%E7%9F%A5%E8%99%B9%E5%A4%8F' },
    { name: 'ikuyo', url: 'https://zh.moegirl.org.cn/%E5%96%9C%E5%A4%9A%E9%83%81%E4%BB%A3' },
    { name: 'kessoku_band', url: 'https://zh.moegirl.org.cn/%E7%BB%88%E7%BB%93%E6%A3%8B%E5%B8%88' }
  ];

  for (const t of targets) {
    try {
      await collectMoegirlCharacter(page, t.name, t.url);
    } catch (e) {
      console.log(`Moegirl ${t.name}: ERROR - ${e.message.slice(0, 120)}`);
    }
    await sleep(1500);
  }

  await browser.close();
  console.log('Moegirl collection complete');
}

main().catch(e => { console.error(e); process.exit(1); });

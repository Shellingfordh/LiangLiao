import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve('./');
const BOCCHI_DIR = path.join(ROOT, 'bocchi');
if (!fs.existsSync(BOCCHI_DIR)) fs.mkdirSync(BOCCHI_DIR, { recursive: true });

function buildExistingUrlSet() {
  const dirs = ['github','forums','blogs','communities','competitors','tutorials','game-jams','chinese-community'];
  const urls = new Set();
  for (const dir of dirs) {
    const dirPath = path.join(ROOT, dir);
    if (!fs.existsSync(dirPath)) continue;
    for (const file of fs.readdirSync(dirPath).filter(f => f.endsWith('.json'))) {
      try {
        const data = JSON.parse(fs.readFileSync(path.join(dirPath, file), 'utf8'));
        const items = Array.isArray(data) ? data : (data.items || []);
        for (const item of items) {
          const candidates = [];
          if (item.links && Array.isArray(item.links)) {
            for (const l of item.links) if (l.href) candidates.push(l.href);
          }
          if (item.html_url) candidates.push(item.html_url);
          if (item.url) candidates.push(item.url);
          for (const u of candidates) {
            if (u && !u.includes('javascript:') && !u.startsWith('http://localhost')) urls.add(u);
          }
        }
      } catch (e) {}
    }
  }
  if (fs.existsSync(BOCCHI_DIR)) {
    for (const file of fs.readdirSync(BOCCHI_DIR).filter(f => f.endsWith('.json') && !f.startsWith('restore-'))) {
      try {
        const data = JSON.parse(fs.readFileSync(path.join(BOCCHI_DIR, file), 'utf8'));
        const items = Array.isArray(data) ? data : (data.items || []);
        for (const item of items) {
          const u = item.url || item.arcurl || item.html_url || '';
          if (u && !u.includes('javascript:') && !u.startsWith('http://localhost')) urls.add(u);
        }
      } catch (e) {}
    }
  }
  return urls;
}

const existingUrls = buildExistingUrlSet();
console.log(`Existing unique URLs loaded: ${existingUrls.size}`);

const sleep = ms => new Promise(r => setTimeout(r, ms));

function readExisting(name) {
  const p = path.join(BOCCHI_DIR, name);
  if (!fs.existsSync(p)) return [];
  try {
    const data = JSON.parse(fs.readFileSync(p, 'utf8'));
    return Array.isArray(data) ? data : (data.items || []);
  } catch (e) {
    return [];
  }
}

function writeMerged(name, newItems) {
  const existing = readExisting(name);
  const merged = [...existing];
  let added = 0;
  for (const item of newItems) {
    const u = item.url || '';
    if (!u || existingUrls.has(u)) continue;
    existingUrls.add(u);
    merged.push(item);
    added++;
  }
  fs.writeFileSync(path.join(BOCCHI_DIR, name), JSON.stringify({ items: merged }, null, 2));
  console.log(`Wrote ${name}: +${added} items, total ${merged.length}`);
  return added;
}

async function scrapeLinks(page, url, maxLinks = 250) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 20000 });
  await page.waitForTimeout(2000);
  return await page.evaluate((maxLinks) => {
    return Array.from(document.querySelectorAll('a')).filter(a =>
      a.href && !a.href.includes('javascript:') && a.textContent.trim().length > 3
    ).map(a => ({
      text: a.textContent.trim().slice(0, 120),
      href: a.href
    })).slice(0, maxLinks);
  }, maxLinks);
}

async function collectSearchEngine(page, query, name, pages = 8) {
  const allItems = [];
  for (let pageNum = 1; pageNum <= pages; pageNum++) {
    const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}&s=${(pageNum-1)*50}`;
    const links = await scrapeLinks(page, url, 300);
    const items = links.filter(l => !existingUrls.has(l.href)).map(l => ({ source: name, text: l.text, url: l.href }));
    const added = writeMerged(`web-${name}.json`, items);
    allItems.push(...items);
    if (links.length < 5) break;
    await sleep(1200);
  }
  console.log(`Search ${name}: ${allItems.length} items collected`);
  return allItems.length;
}

async function main() {
  const browser = await chromium.launch();
  const context = await browser.newContext({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' });
  const page = await context.newPage();

  const targets = [
    { type: 'page', url: 'https://bgm.tv/character/236856', name: 'bangumi-bocchi' },
    { type: 'page', url: 'https://bgm.tv/character/236857', name: 'bangumi-ryo' },
    { type: 'search', query: 'Bocchi the Rock brand collaboration official', name: 'search-brands-en' },
    { type: 'search', query: '孤独摇滚 官方 合作 品牌', name: 'search-brands-zh' },
    { type: 'search', query: 'Bocchi the Rock X Twitter trending', name: 'search-twitter-en' },
    { type: 'search', query: '孤独摇滚 X 推特 热门', name: 'search-twitter-zh' },
    { type: 'search', query: 'Bocchi the Rock fan creation Pixiv', name: 'search-fanart' },
    { type: 'search', query: '孤独摇滚 二创 Pixiv', name: 'search-fancreation-zh' },
    { type: 'search', query: 'Bocchi the Rock github repo fan project', name: 'search-opensource' },
    { type: 'search', query: '孤独摇滚 开源 项目 github', name: 'search-opensource-zh' },
    { type: 'search', query: 'Bocchi the Rock reddit community', name: 'search-reddit' },
    { type: 'search', query: '孤独摇滚 B站 专栏 二创', name: 'search-bilibili-article' },
    { type: 'search', query: 'Bocchi the Rock niconico ニコニコ', name: 'search-niconico' }
  ];

  for (const t of targets) {
    try {
      if (t.type === 'page') {
        const links = await scrapeLinks(page, t.url, 250);
        const items = links.filter(l => !existingUrls.has(l.href)).map(l => ({ source: t.name, text: l.text, url: l.href }));
        writeMerged(`web-${t.name}.json`, items);
      } else {
        await collectSearchEngine(page, t.query, t.name, 8);
      }
    } catch (e) {
      console.log(`${t.name}: ERROR - ${e.message.slice(0, 80)}`);
    }
    await sleep(500);
  }

  await browser.close();
  console.log('Search collection complete');
}

main().catch(e => { console.error(e); process.exit(1); });

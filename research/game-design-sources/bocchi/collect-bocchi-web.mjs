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
  // existing bocchi files
  if (fs.existsSync(BOCCHI_DIR)) {
    for (const file of fs.readdirSync(BOCCHI_DIR).filter(f => f.endsWith('.json') && f !== 'collect-bocchi-web.mjs')) {
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

function writeFile(name, items) {
  fs.writeFileSync(path.join(BOCCHI_DIR, name), JSON.stringify({ items }, null, 2));
  console.log(`Wrote ${name}: ${items.length} items`);
}

async function scrapeLinks(page, url, name, maxLinks = 200) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 20000 });
  await page.waitForTimeout(2000);
  const links = await page.evaluate((maxLinks) => {
    return Array.from(document.querySelectorAll('a')).filter(a =>
      a.href && !a.href.includes('javascript:') && a.textContent.trim().length > 3
    ).map(a => ({
      text: a.textContent.trim().slice(0, 120),
      href: a.href
    })).slice(0, maxLinks);
  }, maxLinks);
  const filtered = links.filter(l => !existingUrls.has(l.href));
  console.log(`${name}: ${links.length} raw, ${filtered.length} new`);
  return filtered;
}

async function collectCategory(baseUrl, categoryName, pages = 20) {
  const items = [];
  for (let pageNum = 1; pageNum <= pages; pageNum++) {
    const url = `${baseUrl}${pageNum > 1 ? `?page=${pageNum}` : ''}`;
    const links = await scrapeLinks(page, url, `${categoryName} p${pageNum}`, 300);
    for (const l of links) {
      if (existingUrls.has(l.href)) continue;
      existingUrls.add(l.href);
      items.push({ source: categoryName, text: l.text, url: l.href });
    }
    if (links.length < 10) break;
    await sleep(1000);
  }
  writeFile(`web-${categoryName}.json`, items);
  return items.length;
}

async function collectSearchEngine(page, query, name, pages = 10) {
  const items = [];
  for (let pageNum = 1; pageNum <= pages; pageNum++) {
    const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}&s=${(pageNum-1)*50}`;
    const links = await scrapeLinks(page, url, `${name} p${pageNum}`, 300);
    for (const l of links) {
      if (existingUrls.has(l.href)) continue;
      existingUrls.add(l.href);
      items.push({ source: name, text: l.text, url: l.href });
    }
    if (links.length < 5) break;
    await sleep(1200);
  }
  writeFile(`web-${name}.json`, items);
  return items.length;
}

async function main() {
  const browser = await chromium.launch();
  const context = await browser.newContext({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' });
  const page = await context.newPage();

  const targets = [
    // Wiki / database
    { type: 'page', url: 'https://bocchi-the-rock.fandom.com/wiki/Bocchi_the_Rock!_Wiki', name: 'fandom-main' },
    { type: 'page', url: 'https://bocchi-the-rock.fandom.com/wiki/Category:Characters', name: 'fandom-characters' },
    { type: 'page', url: 'https://bocchi-the-rock.fandom.com/wiki/Category:Episodes', name: 'fandom-episodes' },
    { type: 'page', url: 'https://bocchi-the-rock.fandom.com/wiki/Category:Music', name: 'fandom-music' },
    { type: 'page', url: 'https://bocchi-the-rock.fandom.com/wiki/Category:Merchandise', name: 'fandom-merchandise' },
    { type: 'page', url: 'https://bocchi-the-rock.fandom.com/wiki/Category:Collaborations', name: 'fandom-collabs' },
    { type: 'page', url: 'https://en.wikipedia.org/wiki/Bocchi_the_Rock!', name: 'wikipedia-en' },
    { type: 'page', url: 'https://zh.wikipedia.org/wiki/%E5%AD%A4%E7%8B%AC%E6%91%87%E6%8A%97', name: 'wikipedia-zh' },
    { type: 'page', url: 'https://myanimelist.net/anime/50477/Bocchi_the_Rock', name: 'mal-main' },
    { type: 'page', url: 'https://myanimelist.net/anime/50477/Bocchi_the_Rock/characters', name: 'mal-characters' },
    { type: 'page', url: 'https://www.crunchyroll.com/series/G4PH0WXVJ/bocchi-the-rock', name: 'crunchyroll' },
    { type: 'page', url: 'https://www.animenewsnetwork.com/search?q=bocchi+the+rock', name: 'ann-search' },
    { type: 'page', url: 'https://bgm.tv/subject/328609', name: 'bangumi-subject' },
    { type: 'page', url: 'https://bgm.tv/character/236856', name: 'bangumi-bocchi' },
    { type: 'page', url: 'https://bgm.tv/character/236857', name: 'bangumi-ryo' },
    // search engines for brands / X
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
        const links = await scrapeLinks(page, t.url, t.name, 250);
        const items = links.map(l => ({ source: t.name, text: l.text, url: l.href }));
        writeFile(`web-${t.name}.json`, items);
      } else {
        const count = await collectSearchEngine(page, t.query, t.name, 8);
        console.log(`Search ${t.name}: ${count} items`);
      }
    } catch (e) {
      console.log(`${t.name}: ERROR - ${e.message.slice(0, 80)}`);
    }
    await sleep(500);
  }

  await browser.close();
  console.log('Web collection complete');
}

main().catch(e => { console.error(e); process.exit(1); });

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
  console.log(`Wrote ${filePath}: ${items.length} items`);
}

async function fetchJSON(url) {
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      Referer: 'https://search.bilibili.com/'
    }
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return res.json();
}

async function collectKeyword(keyword) {
  const safeName = keyword.replace(/[^A-Za-z0-9\u4e00-\u9fff]+/g, '_');
  const outFile = path.join(BOCCHI_DIR, `bilibili-article-${safeName}.json`);
  const allItems = [];
  const seenIds = new Set();
  if (fs.existsSync(outFile)) {
    try {
      const existing = JSON.parse(fs.readFileSync(outFile, 'utf8'));
      if (existing.items) {
        for (const it of existing.items) {
          allItems.push(it);
          seenIds.add(it.id);
        }
      }
    } catch (e) {}
  }
  for (let page = 1; page <= 50; page++) {
    const url = `https://api.bilibili.com/x/web-interface/search/type?search_type=article&keyword=${encodeURIComponent(keyword)}&page=${page}`;
    try {
      const data = await fetchJSON(url);
      if (data.code !== 0) {
        console.log(`${keyword} p${page}: API code ${data.code}`);
        break;
      }
      if (!data.data?.result?.length) {
        console.log(`${keyword} p${page}: no results`);
        break;
      }
      let added = 0;
      for (const article of data.data.result) {
        const id = String(article.id);
        if (seenIds.has(id)) continue;
        seenIds.add(id);
        const articleUrl = `https://www.bilibili.com/read/cv${id}`;
        if (existingUrls.has(articleUrl)) continue;
        const title = (article.title || '').replace(/<[^>]+>/g, '');
        const desc = (article.desc || '').replace(/<[^>]+>/g, '');
        const images = (article.image_urls || []).map(img => {
          if (img.startsWith('//')) return `https:${img}`;
          if (img.startsWith('http')) return img;
          return `https:${img}`;
        });
        const item = {
          source: 'bilibili-article',
          url: articleUrl,
          id,
          title,
          description: desc,
          author: article.author,
          image_count: images.length,
          image_urls: images,
          view: article.view,
          like: article.like,
          pubdate: article.pubdate
        };
        allItems.push(item);
        existingUrls.add(articleUrl);
        for (const img of images) {
          if (!existingUrls.has(img)) {
            existingUrls.add(img);
            allItems.push({
              source: 'bilibili-article-image',
              url: img,
              article_url: articleUrl,
              article_title: title,
              id: `${id}_img_${img.split('/').pop()}`
            });
          }
        }
        added++;
      }
      console.log(`${keyword} p${page}: +${added} articles, total ${allItems.length}`);
      if (added === 0) break;
      if (page % 5 === 0) {
        writeJSON(outFile, allItems);
      }
      await sleep(1000);
    } catch (e) {
      console.log(`${keyword} p${page}: ${e.message.slice(0, 80)}`);
      break;
    }
  }
  writeJSON(outFile, allItems);
  console.log(`Finished ${keyword}: ${allItems.length} items`);
  return allItems.length;
}

async function main() {
  const keywords = [
    '后藤一里 设定图',
    '后藤一里 立绘',
    '后藤一里 壁纸',
    '山田リョウ 设定图',
    '山田リョウ 立绘',
    '伊地知虹夏 设定图',
    '伊地知虹夏 立绘',
    '喜多郁代 设定图',
    '喜多郁代 立绘',
    'Bocchi the Rock character design',
    'Bocchi the Rock official art',
    'Bocchi the Rock illustration',
    '孤独摇滚 角色设定',
    '結束バンド 設定画',
    '結束バンド イラスト',
    'ぼっち・ざ・ろっく イラスト',
    '后藤一里 头像',
    '山田リョウ 头像',
    '伊地知虹夏 头像',
    '喜多郁代 头像'
  ];
  let total = 0;
  for (const kw of keywords) {
    const count = await collectKeyword(kw);
    total += count;
    console.log(`Running total: ${total}`);
  }
  console.log(`All article collection complete. Total items: ${total}`);
}

main().catch(e => { console.error(e); process.exit(1); });

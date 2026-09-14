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
  // also load existing bocchi files to avoid cross-bocchi duplicates
  if (fs.existsSync(BOCCHI_DIR)) {
    for (const file of fs.readdirSync(BOCCHI_DIR).filter(f => f.endsWith('.json') && f !== 'collect-bilibili-bocchi.mjs')) {
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

function writeJSON(filePath, data) {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
}

async function fetchJSON(url) {
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      Accept: 'application/json',
      'Referer': 'https://search.bilibili.com/'
    }
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return res.json();
}

function extractVideoItems(resultBlock) {
  const items = [];
  if (!resultBlock.data) return items;
  for (const video of resultBlock.data) {
    const title = (video.title || '').replace(/<[^>]+>/g, '');
    const desc = (video.description || '').replace(/<[^>]+>/g, '');
    const tags = video.tag || '';
    const relevant = /bocchi|rock|摇滚|结束乐队|kessoku|后藤|山田|伊地知|喜多|波奇|虹夏|凉|郁代|gotoh|hitori|ryo|nijika|ikuyo| Kita|kita/i.test(title + desc + tags);
    if (!relevant) continue;
    const aid = String(video.aid);
    const url = video.arcurl || `https://www.bilibili.com/video/av${aid}`;
    items.push({
      source: 'bilibili-bocchi',
      url,
      aid,
      bvid: video.bvid,
      title,
      author: video.author,
      description: desc,
      tags: video.tag,
      play: video.play,
      favorites: video.favorites,
      pubdate: video.pubdate
    });
  }
  return items;
}

async function collectKeyword(keyword) {
  const safeName = keyword.replace(/[^A-Za-z0-9\u4e00-\u9fff]+/g, '_');
  const outFile = path.join(BOCCHI_DIR, `bilibili-bocchi-${safeName}.json`);
  const allItems = [];
  const seenAids = new Set();
  // load partial if exists
  if (fs.existsSync(outFile)) {
    try {
      const existing = JSON.parse(fs.readFileSync(outFile, 'utf8'));
      if (existing.items) {
        for (const it of existing.items) {
          allItems.push(it);
          seenAids.add(it.aid);
        }
      }
    } catch (e) {}
  }
  let startPage = 1;
  // if we already have items, try to infer next page (crude: assume continuous from 1)
  // we just restart from page 1 and rely on dedup; to save time we could skip ahead,
  // but simplicity first.
  let consecutiveEmpty = 0;
  for (let page = startPage; page <= 50; page++) {
    const url = `https://api.bilibili.com/x/web-interface/search/all/v2?keyword=${encodeURIComponent(keyword)}&search_type=video&page=${page}`;
    try {
      const data = await fetchJSON(url);
      if (data.code !== 0) {
        console.log(`${keyword} p${page}: API code ${data.code}`);
        break;
      }
      const videoBlocks = (data.data?.result || []).filter(r => r.result_type === 'video');
      if (!videoBlocks.length) {
        console.log(`${keyword} p${page}: no video blocks`);
        break;
      }
      let added = 0;
      for (const block of videoBlocks) {
        const videos = extractVideoItems(block);
        for (const v of videos) {
          if (seenAids.has(v.aid)) continue;
          seenAids.add(v.aid);
          if (existingUrls.has(v.url)) continue;
          allItems.push(v);
          added++;
        }
      }
      console.log(`${keyword} p${page}: +${added} items, total ${allItems.length}`);
      if (added === 0) {
        consecutiveEmpty++;
        if (consecutiveEmpty >= 3) break;
      } else {
        consecutiveEmpty = 0;
      }
      // write checkpoint every 5 pages
      if (page % 5 === 0) {
        writeJSON(outFile, { items: allItems });
      }
      await sleep(500);
    } catch (e) {
      console.log(`${keyword} p${page}: ${e.message.slice(0, 80)}`);
      break;
    }
  }
  writeJSON(outFile, { items: allItems });
  console.log(`Finished ${keyword}: ${allItems.length} items`);
  return allItems.length;
}

async function main() {
  const keywords = [
    '孤独摇滚','Bocchi+the+Rock','Kessoku+Band','結束バンド','后藤一里','山田リョウ','伊地知虹夏','喜多郁代',
    'bocchi','Kessoku','Bocchi+the+Rock+anime','孤独摇滚+游戏','孤独摇滚+二创','孤独摇滚+同人','孤独摇滚+音乐',
    '孤独摇滚+吉他','bocchi+game','bocchi+fan+game','bocchi+rhythm','bocchi+typing','bocchi+chess','bocchi+walking+simulator',
    'bocchi+rock+band','結束バンド+吉他','結束バンド+音楽','孤独摇滚+OP','孤独摇滚+ED','孤独摇滚+OST','孤独摇滚+角色',
    '孤独摇滚+剧情','Bocchi+Guitar','Bocchi+Band','Bocchi+Live','孤独摇滚+LIVE','孤独摇滚+现场','Bocchi+Cover',
    'Bocchi+Piano','Bocchi+Drum','Bocchi+Bass','Bocchi+MV','孤独摇滚+MAD','孤独摇滚+AMV','Bocchi+AMV'
  ];
  let total = 0;
  for (const kw of keywords) {
    const count = await collectKeyword(kw);
    total += count;
    console.log(`Running total: ${total}`);
  }
  console.log(`All Bilibili collection complete. Total items: ${total}`);
}

main().catch(e => { console.error(e); process.exit(1); });

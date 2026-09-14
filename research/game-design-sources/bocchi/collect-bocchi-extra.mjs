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
  return urls;
}

const existingUrls = buildExistingUrlSet();
console.log(`Existing unique URLs loaded: ${existingUrls.size}`);

const sleep = ms => new Promise(r => setTimeout(r, ms));

function writeFile(name, items) {
  fs.writeFileSync(path.join(BOCCHI_DIR, name), JSON.stringify({ items }, null, 2));
  console.log(`Wrote ${name}: ${items.length} items`);
}

async function fetchJSON(url, options = {}) {
  const res = await fetch(url, {
    headers: {
      'User-Agent': options.userAgent || 'PenguinHarness/1.0',
      Accept: options.accept || 'application/json',
      ...(options.headers || {})
    }
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return res.json();
}

async function collectBilibiliArticles() {
  const keywords = [
    '孤独摇滚', 'Bocchi+the+Rock', 'Kessoku+Band', '結束バンド',
    '后藤一里', '山田リョウ', '伊地知虹夏', '喜多郁代',
    'bocchi', 'Kessoku', 'Bocchi+the+Rock+anime', '孤独摇滚+游戏'
  ];
  const seen = new Set();
  const items = [];
  for (const kw of keywords) {
    for (let page = 1; page <= 50; page++) {
      const url = `https://api.bilibili.com/x/web-interface/search/all/v2?keyword=${kw}&search_type=article&page=${page}`;
      try {
        const data = await fetchJSON(url, { userAgent: 'Mozilla/5.0' });
        if (data.code !== 0) break;
        const articleBlocks = data.data?.result?.filter(r => r.result_type === 'article') || [];
        if (!articleBlocks.length) break;
        let added = 0;
        for (const block of articleBlocks) {
          for (const article of (block.data || [])) {
            const id = String(article.id || article.aid || article.bvid || `${article.title}-${article.author}`);
            if (seen.has(id)) continue;
            seen.add(id);
            const articleUrl = article.url || article.arcurl || `https://www.bilibili.com/read/cv${article.id || ''}`;
            if (existingUrls.has(articleUrl)) continue;
            const title = (article.title || '').replace(/<[^>]+>/g, '');
            const desc = (article.desc || article.description || '').replace(/<[^>]+>/g, '');
            const relevant = /bocchi|rock|摇滚|结束乐队|kessoku|后藤|山田|伊地知|喜多|波奇|虹夏|凉|郁代/i.test(title + desc);
            if (!relevant) continue;
            items.push({ source: 'bilibili-article-bocchi', url: articleUrl, id: article.id, title, author: article.author, desc, play: article.play, like: article.like, publish_time: article.publish_time });
            added++;
          }
        }
        console.log(`Bilibili article ${kw} p${page}: +${added} items, total ${items.length}`);
        if (articleBlocks.length === 0) break;
        await sleep(800);
      } catch (e) {
        console.log(`Bilibili article ${kw} p${page}: ${e.message.slice(0, 80)}`);
        break;
      }
    }
    await sleep(500);
  }
  writeFile('bilibili-bocchi-articles.json', items);
  return items.length;
}

async function collectRedditExtra() {
  const endpoints = [
    'https://www.reddit.com/r/BocchiTheRock/hot/.json?limit=100',
    'https://www.reddit.com/r/BocchiTheRock/top/.json?limit=100&t=all',
    'https://www.reddit.com/r/anime/search.json?q=bocchi+the+rock&sort=top&limit=100&t=all',
    'https://www.reddit.com/r/gamedev/search.json?q=bocchi+game&sort=top&limit=100&t=all',
    'https://www.reddit.com/r/IndieGaming/search.json?q=bocchi&sort=top&limit=100&t=all',
    'https://www.reddit.com/r/visualnovels/search.json?q=bocchi&sort=top&limit=100&t=all',
    'https://www.reddit.com/r/cozygames/search.json?q=bocchi&sort=top&limit=100&t=all',
    'https://www.reddit.com/r/gamedesign/search.json?q=bocchi&sort=top&limit=100&t=all',
    'https://www.reddit.com/r/anime/search.json?q=%E5%AD%A4%E7%8B%AC%E6%91%87%E6%8A%97&sort=top&limit=100&t=all'
  ];
  const seen = new Set();
  const items = [];
  for (const url of endpoints) {
    try {
      const data = await fetchJSON(url, { userAgent: 'PenguinHarness/1.0' });
      const children = data.data?.children || (data.data?.data?.children) || [];
      if (!children.length) {
        console.log(`Reddit ${url}: no children`);
        continue;
      }
      for (const child of children) {
        const d = child.data;
        const id = d.id;
        if (seen.has(id)) continue;
        seen.add(id);
        const permalink = d.permalink || '';
        const itemUrl = permalink ? `https://www.reddit.com${permalink}` : (d.url || '');
        if (existingUrls.has(itemUrl)) continue;
        items.push({
          source: 'reddit-bocchi',
          id,
          title: d.title,
          url: itemUrl,
          subreddit: d.subreddit,
          author: d.author,
          score: d.score,
          num_comments: d.num_comments,
          created_utc: d.created_utc,
          selftext: (d.selftext || '').slice(0, 500)
        });
      }
      console.log(`Reddit ${url}: +${children.length} posts, total ${items.length}`);
      await sleep(2000);
    } catch (e) {
      console.log(`Reddit ${url}: ${e.message.slice(0, 100)}`);
    }
  }
  writeFile('reddit-bocchi-extra.json', items);
  return items.length;
}

async function main() {
  console.log('Starting Bocchi extra collection...');
  let articleCount = await collectBilibiliArticles();
  let redditCount = await collectRedditExtra();
  const total = articleCount + redditCount;
  console.log(`Collection complete. articles=${articleCount}, reddit=${redditCount}, total=${total}`);
}

main().catch(e => { console.error(e); process.exit(1); });

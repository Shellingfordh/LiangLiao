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

async function collectGithub() {
  const queries = [
    'bocchi+the+rock', 'kessoku+band', 'hitori+bocchi', 'gotoh+hitori',
    'yamada+ryo+bocchi', '孤独摇滚', '結束バンド', 'bocchi+fan+game',
    'bocchi+typing', 'bocchi+rhythm', 'bocchi+game', 'bocchi+chess',
    'bocchi+walking+simulator', 'bocchi+rock+band'
  ];
  const seen = new Set();
  const items = [];
  for (const q of queries) {
    for (let page = 1; page <= 3; page++) {
      const url = `https://api.github.com/search/repositories?q=${q}&per_page=100&page=${page}&sort=stars`;
      try {
        const data = await fetchJSON(url, { accept: 'application/vnd.github+json' });
        if (!data.items?.length) break;
        for (const repo of data.items) {
          const id = String(repo.id);
          if (seen.has(id)) continue;
          seen.add(id);
          if (existingUrls.has(repo.html_url) || existingUrls.has(repo.url)) continue;
          items.push({
            source: 'github-bocchi',
            html_url: repo.html_url,
            url: repo.url,
            name: repo.full_name,
            description: repo.description,
            language: repo.language,
            topics: repo.topics,
            stars: repo.stargazers_count,
            updated_at: repo.updated_at
          });
        }
        console.log(`GitHub ${q} p${page}: +${data.items.length} repos, total ${items.length}`);
        if (data.items.length < 100) break;
        await sleep(6500);
      } catch (e) {
        console.log(`GitHub ${q} p${page}: ${e.message.slice(0, 80)}`);
        break;
      }
    }
    await sleep(1000);
  }
  writeFile('github-bocchi-repos.json', items);
  return items.length;
}

async function collectBilibili() {
  const keywords = [
    '孤独摇滚', 'Bocchi+the+Rock', 'Kessoku+Band', '結束バンド',
    '后藤一里', '山田リョウ', '伊地知虹夏', '喜多郁代',
    'bocchi', 'Kessoku', 'Bocchi+the+Rock+anime', '孤独摇滚+游戏'
  ];
  const seen = new Set();
  const items = [];
  for (const kw of keywords) {
    for (let page = 1; page <= 50; page++) {
      const url = `https://api.bilibili.com/x/web-interface/search/all/v2?keyword=${kw}&search_type=video&page=${page}`;
      try {
        const data = await fetchJSON(url, { userAgent: 'Mozilla/5.0' });
        if (data.code !== 0) break;
        const videoBlocks = data.data?.result?.filter(r => r.result_type === 'video') || [];
        if (!videoBlocks.length) break;
        let added = 0;
        for (const block of videoBlocks) {
          for (const video of (block.data || [])) {
            const aid = String(video.aid);
            if (seen.has(aid)) continue;
            seen.add(aid);
            const url = video.arcurl || `https://www.bilibili.com/video/av${video.aid}`;
            if (existingUrls.has(url)) continue;
            const title = (video.title || '').replace(/<[^>]+>/g, '');
            const desc = (video.description || '').replace(/<[^>]+>/g, '');
            const tags = video.tag || '';
            const relevant = /bocchi|rock|摇滚|结束乐队|kessoku|后藤|山田|伊地知|喜多|波奇|虹夏|凉|郁代/i.test(title + desc + tags);
            if (!relevant) continue;
            items.push({ source: 'bilibili-bocchi', url, aid: video.aid, bvid: video.bvid,
              title, author: video.author, description: desc, tags: video.tag,
              play: video.play, favorites: video.favorites, pubdate: video.pubdate });
            added++;
          }
        }
        console.log(`Bilibili ${kw} p${page}: +${added} items, total ${items.length}`);
        if (videoBlocks.length === 0) break;
        await sleep(800);
      } catch (e) {
        console.log(`Bilibili ${kw} p${page}: ${e.message.slice(0, 80)}`);
        break;
      }
    }
    await sleep(500);
  }
  writeFile('bilibili-bocchi-videos.json', items);
  return items.length;
}

async function collectReddit() {
  const endpoints = [
    'https://www.reddit.com/r/BocchiTheRock/.json?limit=100',
    'https://www.reddit.com/r/anime/search.json?q=bocchi+the+rock&sort=top&limit=100',
    'https://www.reddit.com/r/gamedev/search.json?q=bocchi&sort=top&limit=100',
    'https://www.reddit.com/r/IndieGaming/search.json?q=bocchi&sort=top&limit=100',
    'https://www.reddit.com/r/visualnovels/search.json?q=bocchi&sort=top&limit=100',
    'https://www.reddit.com/r/cozygames/search.json?q=bocchi&sort=top&limit=100'
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
  writeFile('reddit-bocchi-posts.json', items);
  return items.length;
}

async function main() {
  console.log('Starting Bocchi collection...');
  let githubCount = await collectGithub();
  let bilibiliCount = await collectBilibili();
  let redditCount = await collectReddit();

  // TODO: add Fandom, MyAnimeList, Wikipedia, etc. if time/budget remains.

  const total = githubCount + bilibiliCount + redditCount;
  console.log(`Collection complete. github=${githubCount}, bilibili=${bilibiliCount}, reddit=${redditCount}, total=${total}`);
}

main().catch(e => { console.error(e); process.exit(1); });

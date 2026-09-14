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
  console.log(`Wrote ${path.basename(filePath)}: ${items.length} items`);
}

async function fetchJSON(url, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      const res = await fetch(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          Accept: 'application/json',
          Referer: 'https://www.pixiv.net/'
        }
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const text = await res.text();
      return JSON.parse(text);
    } catch (e) {
      if (i === retries - 1) throw e;
      await sleep(2000 * (i + 1));
    }
  }
}

async function collectPixivTag(tag, name, maxPages = 50) {
  const outFile = path.join(BOCCHI_DIR, `pixiv-${name}.json`);
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
  for (let page = 1; page <= maxPages; page++) {
    const url = `https://www.pixiv.net/ajax/search/artworks/${encodeURIComponent(tag)}?word=${encodeURIComponent(tag)}&order=popular_d&mode=all&p=${page}&s_mode=s_tag&type=all`;
    try {
      const data = await fetchJSON(url);
      if (data.error || !data.body?.illustManga?.data?.length) {
        console.log(`${tag} p${page}: no data or error`);
        break;
      }
      const artworks = data.body.illustManga.data;
      let added = 0;
      for (const art of artworks) {
        if (seenIds.has(String(art.id))) continue;
        seenIds.add(String(art.id));
        const imageUrl = art.url || '';
        const pageUrl = `https://www.pixiv.net/artworks/${art.id}`;
        const item = {
          source: `pixiv-${name}`,
          id: String(art.id),
          url: pageUrl,
          image_url: imageUrl,
          title: art.title,
          artist: art.userName,
          artist_id: art.userId,
          tags: art.tags || [],
          width: art.width,
          height: art.height,
          pageCount: art.pageCount,
          illustType: art.illustType,
          xRestrict: art.xRestrict,
          createDate: art.createDate,
          uploadDate: art.uploadDate
        };
        allItems.push(item);
        existingUrls.add(pageUrl);
        if (imageUrl && !existingUrls.has(imageUrl)) {
          existingUrls.add(imageUrl);
          allItems.push({
            source: `pixiv-${name}-image`,
            url: imageUrl,
            artwork_url: pageUrl,
            id: `${art.id}_img`
          });
        }
        added++;
      }
      console.log(`${tag} p${page}: +${added} artworks, total ${allItems.length}`);
      if (added === 0) break;
      if (page % 5 === 0) {
        writeJSON(outFile, allItems);
      }
      await sleep(1200);
    } catch (e) {
      console.log(`${tag} p${page}: ${e.message.slice(0, 80)}`);
      break;
    }
  }
  writeJSON(outFile, allItems);
  console.log(`Finished ${tag}: ${allItems.length} items`);
  return allItems.length;
}

async function collectDanbooruTag(tag, name, maxPages = 100) {
  const outFile = path.join(BOCCHI_DIR, `danbooru-${name}.json`);
  const allItems = [];
  const seenIds = new Set();
  if (fs.existsSync(outFile)) {
    try {
      const existing = JSON.parse(fs.readFileSync(outFile, 'utf8'));
      if (existing.items) {
        for (const it of existing.items) {
          allItems.push(it);
          seenIds.add(String(it.id));
        }
      }
    } catch (e) {}
  }
  for (let page = 1; page <= maxPages; page++) {
    const url = `https://danbooru.donmai.us/posts.json?tags=${encodeURIComponent(tag)}&page=${page}&limit=20`;
    try {
      const data = await fetchJSON(url);
      if (!Array.isArray(data) || data.length === 0) {
        console.log(`${tag} p${page}: no data`);
        break;
      }
      let added = 0;
      for (const post of data) {
        const id = String(post.id);
        if (seenIds.has(id)) continue;
        seenIds.add(id);
        const fileUrl = post.file_url || (post.media_asset?.variants?.[0]?.url) || '';
        const pageUrl = `https://danbooru.donmai.us/posts/${id}`;
        const item = {
          source: `danbooru-${name}`,
          id,
          url: pageUrl,
          file_url: fileUrl,
          rating: post.rating,
          score: post.score,
          fav_count: post.fav_count,
          tags: post.tag_string?.split(' ') || [],
          artist: post.tag_string_artist,
          character: post.tag_string_character,
          copyright: post.tag_string_copyright,
          width: post.image_width,
          height: post.image_height,
          file_ext: post.file_ext,
          file_size: post.file_size,
          pixiv_id: post.pixiv_id,
          source: post.source
        };
        allItems.push(item);
        existingUrls.add(pageUrl);
        if (fileUrl && !existingUrls.has(fileUrl)) {
          existingUrls.add(fileUrl);
          allItems.push({
            source: `danbooru-${name}-image`,
            url: fileUrl,
            post_url: pageUrl,
            id: `${id}_img`
          });
        }
        added++;
      }
      console.log(`${tag} p${page}: +${added} posts, total ${allItems.length}`);
      if (added === 0) break;
      if (page % 10 === 0) {
        writeJSON(outFile, allItems);
      }
      await sleep(800);
    } catch (e) {
      console.log(`${tag} p${page}: ${e.message.slice(0, 80)}`);
      break;
    }
  }
  writeJSON(outFile, allItems);
  console.log(`Finished ${tag}: ${allItems.length} items`);
  return allItems.length;
}

async function main() {
  const pixivTags = [
    { tag: '後藤ひとり', name: 'hitori' },
    { tag: '山田リョウ', name: 'ryo' },
    { tag: '伊地知虹夏', name: 'nijika' },
    { tag: '喜多郁代', name: 'ikuyo' },
    { tag: '結束バンド', name: 'kessoku' },
    { tag: 'ぼっち・ざ・ろっく', name: 'bocchi' },
    { tag: 'bocchi_the_rock', name: 'bocchi_en' }
  ];

  const danbooruTags = [
    { tag: 'gotoh_hitori', name: 'hitori' },
    { tag: 'yamada_ryo', name: 'ryo' },
    { tag: 'ijichi_nijika', name: 'nijika' },
    { tag: 'kita_ikuyo', name: 'ikuyo' },
    { tag: 'bocchi_the_rock', name: 'bocchi' }
  ];

  let total = 0;
  for (const t of pixivTags) {
    const count = await collectPixivTag(t.tag, t.name, 50);
    total += count;
    console.log(`Pixiv running total: ${total}`);
    await sleep(2000);
  }

  for (const t of danbooruTags) {
    const count = await collectDanbooruTag(t.tag, t.name, 100);
    total += count;
    console.log(`Danbooru running total: ${total}`);
    await sleep(2000);
  }

  console.log(`All image collection complete. Total items: ${total}`);
}

main().catch(e => { console.error(e); process.exit(1); });

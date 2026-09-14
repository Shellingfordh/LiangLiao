import { execFileSync } from 'child_process';
import fs from 'fs';
import path from 'path';

const BOCCHI_DIR = path.resolve('./research/game-design-sources/bocchi');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function readJSON(name) {
  const p = path.join(BOCCHI_DIR, name);
  if (!fs.existsSync(p)) return [];
  try {
    const data = JSON.parse(fs.readFileSync(p, 'utf8'));
    return Array.isArray(data) ? data : data.items || [];
  } catch (e) {
    return [];
  }
}

function writeJSON(name, items) {
  const p = path.join(BOCCHI_DIR, name);
  fs.writeFileSync(p, JSON.stringify({ items }, null, 2));
  console.log(`Wrote ${name}: ${items.length} items`);
}

function fetchPixivJSON(url) {
  return JSON.parse(
    execFileSync('curl', [
      '-L', '-s', url,
      '-H', 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      '-H', 'Referer: https://www.pixiv.net/',
      '-H', 'Accept: application/json'
    ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
  );
}

async function collectPixivTag(tag, name, maxPages = 20) {
  const outFile = `pixiv-${name}.json`;
  const allItems = readJSON(outFile);
  const seenIds = new Set(allItems.map((it) => String(it.id)));
  for (let page = 1; page <= maxPages; page++) {
    const url = `https://www.pixiv.net/ajax/search/artworks/${encodeURIComponent(tag)}?word=${encodeURIComponent(tag)}&order=popular_d&mode=all&p=${page}&s_mode=s_tag&type=all`;
    try {
      const data = fetchPixivJSON(url);
      if (data.error || !data.body?.illustManga?.data?.length) {
        console.log(`${tag} p${page}: no data or error`);
        break;
      }
      const artworks = data.body.illustManga.data;
      let added = 0;
      for (const art of artworks) {
        const id = String(art.id);
        if (seenIds.has(id)) continue;
        seenIds.add(id);
        const imageUrl = art.url || '';
        const pageUrl = `https://www.pixiv.net/artworks/${id}`;
        allItems.push({
          source: `pixiv-${name}`,
          id,
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
        });
        if (imageUrl) {
          allItems.push({
            source: `pixiv-${name}-image`,
            url: imageUrl,
            artwork_url: pageUrl,
            id: `${id}_img`
          });
        }
        added++;
      }
      console.log(`${tag} p${page}: +${added} artworks, total ${allItems.length}`);
      if (added === 0) break;
      if (page % 5 === 0) writeJSON(outFile, allItems);
      await sleep(1000);
    } catch (e) {
      console.log(`${tag} p${page}: ${e.message.slice(0, 120)}`);
      break;
    }
  }
  writeJSON(outFile, allItems);
  return allItems.length;
}

async function main() {
  const tags = [
    { tag: '後藤ひとり', name: 'hitori' },
    { tag: '山田リョウ', name: 'ryo' },
    { tag: '伊地知虹夏', name: 'nijika' },
    { tag: '喜多郁代', name: 'ikuyo' },
    { tag: '結束バンド', name: 'kessoku' },
    { tag: 'ぼっち・ざ・ろっく', name: 'bocchi' },
    { tag: 'bocchi_the_rock', name: 'bocchi_en' }
  ];
  let total = 0;
  for (const t of tags) {
    const count = await collectPixivTag(t.tag, t.name, 20);
    total += count;
    console.log(`Pixiv running total: ${total}`);
  }
  console.log(`Pixiv complete. Total items: ${total}`);
}

main().catch((e) => { console.error(e); process.exit(1); });

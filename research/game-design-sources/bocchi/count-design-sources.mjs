import fs from 'fs';
import path from 'path';

const ROOT = path.resolve('./');
const BOCCHI_DIR = path.join(ROOT, 'research/game-design-sources/bocchi');

function listJson(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter(f => f.endsWith('.json'));
}

function readItems(filePath) {
  try {
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return Array.isArray(data) ? data : (data.items || []);
  } catch (e) {
    return [];
  }
}

const designKeywords = [
  'design', '设定', '设定图', '設定', '設定画', '立绘', '头像', 'official_art', 'illustration', 'character_design',
  'moegirl', 'pixiv', 'danbooru'
];

function isDesignFile(name) {
  const lower = name.toLowerCase();
  if (!lower.startsWith('bocchi/') && !lower.startsWith('research/game-design-sources/bocchi/')) {
    // allow relative paths passed in
  }
  // Bing image files
  if (/^images-.*-(design|layout|wallpaper)\.json$/.test(name)) return true;
  if (/^images-.*-officialart\.json$/.test(name)) return true;
  if (/^images-.*-design-(en|zh|jp)\.json$/.test(name)) return true;
  if (/^images-.*-illustration-(en|zh|jp)\.json$/.test(name)) return true;
  if (/^images-.*-avatar\.json$/.test(name)) return true;
  // Bilibili design articles
  if (/^bilibili-article-.*(设定图|设定画|立绘|头像|角色设定|character_design|official_art|illustration)\.json$/.test(name)) return true;
  // Moegirl / Pixiv / Danbooru
  if (/^(moegirl|pixiv|danbooru)-.*\.json$/.test(name)) return true;
  return false;
}

function extractUrls(item) {
  const candidates = [];
  if (item.links && Array.isArray(item.links)) for (const l of item.links) if (l.href) candidates.push(l.href);
  if (item.html_url) candidates.push(item.html_url);
  if (item.url) candidates.push(item.url);
  if (item.arcurl) candidates.push(item.arcurl);
  if (item.image_url) candidates.push(item.image_url);
  if (item.file_url) candidates.push(item.file_url);
  if (item.page_url) candidates.push(item.page_url);
  if (item.artwork_url) candidates.push(item.artwork_url);
  if (item.post_url) candidates.push(item.post_url);
  if (item.src) candidates.push(item.src);
  if (item.imageUrl) candidates.push(item.imageUrl);
  return candidates.filter(u => u && !u.includes('javascript:') && !u.startsWith('http://localhost'));
}

const files = listJson(BOCCHI_DIR).filter(f => f !== 'count-design-sources.mjs' && isDesignFile(f));
const uniqueUrls = new Set();
const owner = new Map();
let totalItems = 0;
const fileStats = [];

for (const file of files) {
  const filePath = path.join(BOCCHI_DIR, file);
  const items = readItems(filePath);
  let counted = 0;
  for (const item of items) {
    const urls = extractUrls(item);
    for (const u of urls) {
      if (!uniqueUrls.has(u)) {
        uniqueUrls.add(u);
        owner.set(u, file);
      }
    }
    // Bing files: count image+page items as sources; article-image items count too
    if (file.startsWith('images-')) counted++;
    else if (file.startsWith('bilibili-article-') && item.source === 'bilibili-article-image') counted++;
    else if (!file.startsWith('bilibili-article-')) counted++;
    // bilibili article pages themselves are secondary; count image items primarily
  }
  totalItems += counted;
  fileStats.push({ file, items: items.length, counted });
}

fileStats.sort((a,b) => b.counted - a.counted);

console.log('=== Design-Specific Source Count ===');
for (const s of fileStats) {
  console.log(`${s.file}: ${s.counted} design sources (${s.items} raw items)`);
}
console.log('---');
console.log(`Design source files : ${files.length}`);
console.log(`Design source items : ${totalItems}`);
console.log(`Design unique urls  : ${uniqueUrls.size}`);
console.log('top owners:');
const counts = new Map();
for (const [, file] of owner) counts.set(file, (counts.get(file) || 0) + 1);
[...counts.entries()].sort((a,b)=>b[1]-a[1]).slice(0,20).forEach(([k,v])=>console.log(`  ${k}\t${v}`));

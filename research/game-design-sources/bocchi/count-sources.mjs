import fs from 'fs';
import path from 'path';

const ROOT = path.resolve('./');
const BOCCHI_DIR = path.join(ROOT, 'bocchi');
const DIRS = ['github','forums','blogs','communities','competitors','tutorials','game-jams','chinese-community'];

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

function collectFromDir(dir, set, map) {
  for (const file of listJson(dir)) {
    const items = readItems(path.join(dir, file));
    for (const item of items) {
      const urls = extractUrls(item);
      for (const u of urls) {
        if (!set.has(u)) {
          set.add(u);
          map[u] = file;
        }
      }
    }
  }
}

const urls = new Set();
const owner = new Map();
for (const dir of DIRS) {
  const dirPath = path.join(ROOT, dir);
  collectFromDir(dirPath, urls, owner);
}
collectFromDir(BOCCHI_DIR, urls, owner);

// Count source files (not including this script)
const sourceFiles = listJson(BOCCHI_DIR).filter(f => f !== 'count-sources.mjs');
let totalItems = 0;
for (const file of sourceFiles) {
  totalItems += readItems(path.join(BOCCHI_DIR, file)).length;
}

console.log(`bocchi source files: ${sourceFiles.length}`);
console.log(`bocchi source items: ${totalItems}`);
console.log(`bocchi unique urls : ${urls.size}`);
if (urls.size > 0) {
  console.log('top owners:');
  const counts = new Map();
  for (const [, file] of owner) counts.set(file, (counts.get(file) || 0) + 1);
  [...counts.entries()].sort((a,b)=>b[1]-a[1]).slice(0,20).forEach(([k,v])=>console.log(`  ${k}\t${v}`));
}

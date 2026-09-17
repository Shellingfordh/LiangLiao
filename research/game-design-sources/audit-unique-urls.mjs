import fs from 'fs';
import path from 'path';

const rootDir = process.cwd();
const dirs = ['github', 'forums', 'blogs', 'communities', 'competitors', 'tutorials', 'game-jams', 'chinese-community'];

const uniqueUrls = new Set();
const dirStats = {};

for (const dir of dirs) {
  const dirPath = path.join(rootDir, dir);
  if (!fs.existsSync(dirPath)) continue;
  const files = fs.readdirSync(dirPath).filter(f => f.endsWith('.json'));
  let dirCount = 0;
  for (const file of files) {
    const data = JSON.parse(fs.readFileSync(path.join(dirPath, file), 'utf8'));
    const items = Array.isArray(data) ? data : (data.items || []);
    for (const item of items) {
      let urls = [];
      if (item.links && Array.isArray(item.links)) {
        urls = item.links.map(l => l.href).filter(Boolean);
      }
      if (item.html_url) {
        urls = [item.html_url, ...urls];
      }
      if (item.url) {
        urls = [item.url, ...urls];
      }
      for (const u of urls) {
        if (u && !u.includes('javascript:') && !u.startsWith('http://localhost')) {
          uniqueUrls.add(u);
          dirCount++;
        }
      }
    }
  }
  dirStats[dir] = dirCount;
}

console.log('=== Unique URL Audit ===');
for (const [k, v] of Object.entries(dirStats)) {
  console.log(`${k}: ${v} urls`);
}
console.log('---');
console.log(`TOTAL unique urls: ${uniqueUrls.size}`);

fs.writeFileSync('unique-url-audit.json', JSON.stringify({
  total_unique: uniqueUrls.size,
  breakdown: dirStats,
  sample: Array.from(uniqueUrls).slice(0, 100)
}, null, 2));
console.log('Saved unique-url-audit.json');

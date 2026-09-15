import fs from 'fs';
import path from 'path';

const rootDir = process.cwd();
const dirs = ['github', 'forums', 'blogs', 'communities', 'competitors', 'tutorials', 'game-jams', 'chinese-community'];

const domainCount = {};

for (const dir of dirs) {
  const dirPath = path.join(rootDir, dir);
  if (!fs.existsSync(dirPath)) continue;
  const files = fs.readdirSync(dirPath).filter(f => f.endsWith('.json'));
  for (const file of files) {
    const data = JSON.parse(fs.readFileSync(path.join(dirPath, file), 'utf8'));
    const items = Array.isArray(data) ? data : (data.items || []);
    for (const item of items) {
      let urls = [];
      if (item.links && Array.isArray(item.links)) {
        urls = item.links.map(l => l.href).filter(Boolean);
      }
      if (item.html_url) urls.push(item.html_url);
      if (item.url) urls.push(item.url);
      for (const u of urls) {
        if (u && !u.includes('javascript:') && !u.startsWith('http://localhost')) {
          try {
            const host = new URL(u).hostname;
            domainCount[host] = (domainCount[host] || 0) + 1;
          } catch (e) {}
        }
      }
    }
  }
}

const topDomains = Object.entries(domainCount)
  .sort((a, b) => b[1] - a[1])
  .slice(0, 30);

console.log('=== Top Domains (full scan) ===');
for (const [d, c] of topDomains) {
  console.log(`${d}: ${c}`);
}

fs.writeFileSync('domain-summary.json', JSON.stringify({
  total_domains: Object.keys(domainCount).length,
  top_30: topDomains
}, null, 2));
console.log('\nSaved domain-summary.json');

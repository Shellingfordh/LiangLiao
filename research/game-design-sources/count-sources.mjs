import fs from 'fs';
import path from 'path';

const dirs = ['github', 'forums', 'blogs', 'communities', 'competitors', 'tutorials', 'game-jams', 'chinese-community', 'bocchi'];
let totalSources = 0;
const summary = [];

for (const dir of dirs) {
  const dirPath = path.join(process.cwd(), dir);
  if (!fs.existsSync(dirPath)) continue;
  
  const files = fs.readdirSync(dirPath).filter(f => f.endsWith('.json'));
  let dirTotal = 0;
  
  for (const file of files) {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(dirPath, file), 'utf8'));
      let count = 0;
      
      if (Array.isArray(data)) {
        // Array of results (forums, blogs, etc.)
        for (const item of data) {
          count += item.count || item.links?.length || 0;
        }
      } else if (data.total_count !== undefined) {
        // GitHub API response
        count = data.total_count;
      } else if (data.items) {
        count = data.items.length;
      }
      
      dirTotal += count;
    } catch (e) {
      // Skip invalid files
    }
  }
  
  summary.push({ directory: dir, sources: dirTotal });
  totalSources += dirTotal;
}

console.log('=== Source Count Summary ===');
for (const s of summary) {
  console.log(`${s.directory}: ${s.sources} sources`);
}
console.log('---');
console.log(`TOTAL: ${totalSources} sources`);

fs.writeFileSync('source-summary.json', JSON.stringify({ total: totalSources, breakdown: summary }, null, 2));

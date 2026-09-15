import fs from 'fs';
import path from 'path';

const dirs = ['github', 'forums', 'blogs', 'communities', 'competitors', 'tutorials', 'game-jams'];
let totalSources = 0;
const detailedSummary = [];

for (const dir of dirs) {
  const dirPath = path.join(process.cwd(), dir);
  if (!fs.existsSync(dirPath)) continue;
  
  const files = fs.readdirSync(dirPath).filter(f => f.endsWith('.json'));
  let dirTotal = 0;
  const fileDetails = [];
  
  for (const file of files) {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(dirPath, file), 'utf8'));
      let count = 0;
      
      if (Array.isArray(data)) {
        // Array of results (forums, blogs, communities, etc.)
        for (const item of data) {
          count += item.count || item.links?.length || 0;
        }
      } else if (data.total_count !== undefined) {
        // GitHub API response
        count = data.total_count;
      } else if (data.items) {
        count = data.items.length;
      } else if (typeof data === 'object') {
        // Check for other structures
        const keys = Object.keys(data);
        for (const key of keys) {
          if (Array.isArray(data[key])) {
            count += data[key].length;
          }
        }
      }
      
      if (count > 0) {
        fileDetails.push({ file, count });
        dirTotal += count;
      }
    } catch (e) {}
  }
  
  detailedSummary.push({ directory: dir, sources: dirTotal, files: fileDetails });
  totalSources += dirTotal;
}

console.log('=== COMPREHENSIVE SOURCE COUNT ===\n');
for (const s of detailedSummary) {
  console.log(`${s.directory.toUpperCase()}: ${s.sources} sources`);
  if (s.files.length > 0) {
    s.files.slice(0, 5).forEach(f => console.log(`  - ${f.file}: ${f.count}`));
    if (s.files.length > 5) console.log(`  ... and ${s.files.length - 5} more files`);
  }
}
console.log('\n---');
console.log(`TOTAL SOURCES: ${totalSources}`);
console.log(`TARGET: 2000 sources`);
console.log(`STATUS: ${totalSources >= 2000 ? '✅ ACHIEVED' : '❌ NEED MORE'}`);

fs.writeFileSync('final-count.json', JSON.stringify({ total: totalSources, target: 2000, achieved: totalSources >= 2000, breakdown: detailedSummary }, null, 2));

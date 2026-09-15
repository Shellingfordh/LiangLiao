import fs from 'fs';
import path from 'path';

const dirs = ['github', 'forums', 'blogs', 'communities', 'competitors', 'tutorials', 'game-jams'];
let totalSources = 0;
const detailedSummary = [];

for (const dir of dirs) {
  const dirPath = path.join(process.cwd(), dir);
  if (!fs.existsSync(dirPath)) continue;
  
  const files = fs.readdirSync(dirPath).filter(f => f.endsWith('.json') && !f.includes('summary') && !f.includes('results'));
  let dirTotal = 0;
  const fileDetails = [];
  
  for (const file of files) {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(dirPath, file), 'utf8'));
      let count = 0;
      
      if (Array.isArray(data)) {
        for (const item of data) {
          count += item.count || item.links?.length || 0;
        }
      } else if (data.total_count !== undefined) {
        count = data.total_count;
      } else if (data.items) {
        count = data.items.length;
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

console.log('=== FINAL SOURCE COUNT ===\n');
for (const s of detailedSummary) {
  console.log(`${s.directory.toUpperCase()}: ${s.sources} sources`);
  s.files.forEach(f => console.log(`  - ${f.file}: ${f.count}`));
}
console.log('\n---');
console.log(`TOTAL SOURCES: ${totalSources}`);

fs.writeFileSync('final-summary.json', JSON.stringify({ total: totalSources, breakdown: detailedSummary }, null, 2));

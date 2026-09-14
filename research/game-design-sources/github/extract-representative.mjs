import fs from 'fs';
import path from 'path';

const rootDir = process.cwd();
const files = [
  'research/game-design-sources/github/gh-cozy-game.json',
  'research/game-design-sources/github/gh-visual-novel-engine.json',
  'research/game-design-sources/github/gh-relationship-game.json',
  'research/game-design-sources/github/gh-walking-simulator.json'
];

const keywords = [
  'cozy','life','sim','farm','weather','day','night','schedule','routine','memory','dialogue','npc','character','visual novel','relationship','dating','romance','letter','mail','gift','time','loop','slice'
];

const seen = new Set();
const results = [];

for (const file of files) {
  const data = JSON.parse(fs.readFileSync(path.join(rootDir, file), 'utf8'));
  const items = data.items || [];
  for (const item of items) {
    const text = `${item.full_name} ${item.description || ''}`.toLowerCase();
    if (!keywords.some(k => text.includes(k))) continue;
    const key = item.html_url;
    if (seen.has(key)) continue;
    seen.add(key);
    results.push({
      name: item.full_name,
      url: item.html_url,
      description: item.description,
      stars: item.stargazers_count,
      language: item.language,
      topics: item.topics || []
    });
  }
}

results.sort((a, b) => (b.stars || 0) - (a.stars || 0));
const selected = results.slice(0, 80);

fs.writeFileSync('research/game-design-sources/github/representative-repos.json', JSON.stringify({
  total_scanned: files.reduce((s, f) => {
    const d = JSON.parse(fs.readFileSync(path.join(rootDir, f), 'utf8'));
    return s + (d.items || []).length;
  }, 0),
  matched: results.length,
  selected: selected.length,
  items: selected
}, null, 2));

console.log(`Scanned repos: ${files.reduce((s, f) => { const d = JSON.parse(fs.readFileSync(path.join(rootDir, f), 'utf8')); return s + (d.items || []).length; }, 0)}`);
console.log(`Matched: ${results.length}`);
console.log(`Selected: ${selected.length}`);
for (const r of selected.slice(0, 20)) {
  console.log(`${r.stars || 0} ★ | ${r.language || '-'} | ${r.name} | ${(r.description || '').slice(0,80)}`);
}

import fs from 'fs';

const categories = {
  'visual-novel': ['gh-visual-novel-engine.json'],
  'narrative': ['gh-narrative-game-engine.json', 'gh-story-driven-game.json', 'gh-dialogue-system-game.json'],
  'character': ['gh-character-interaction-game.json', 'gh-relationship-game.json'],
  'cozy': ['gh-cozy-game.json', 'gh-slice-of-life-game.json'],
  'anime': ['gh-anime-style-game.json'],
  'dating': ['gh-dating-sim-engine.json'],
  'taptap': ['gh-taptap-maker.json'],
  'tripo': ['gh-tripo-3d.json'],
  'rhythm': ['gh-music-rhythm-game.json'],
};

const results = {};

for (const [cat, files] of Object.entries(categories)) {
  const repos = [];
  for (const file of files) {
    try {
      const data = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (data.items) {
        repos.push(...data.items.map(i => ({
          name: i.full_name,
          stars: i.stargazers_count,
          desc: i.description?.slice(0, 120),
          url: i.html_url,
          topics: i.topics?.slice(0, 5)
        })));
      }
    } catch (e) {}
  }
  repos.sort((a, b) => (b.stars || 0) - (a.stars || 0));
  results[cat] = repos.slice(0, 20);
}

fs.writeFileSync('top-repos-by-category.json', JSON.stringify(results, null, 2));

console.log('=== Top Repos by Category ===');
for (const [cat, repos] of Object.entries(results)) {
  console.log(`\n--- ${cat.toUpperCase()} (${repos.length} repos) ---`);
  repos.slice(0, 5).forEach(r => console.log(`  ⭐${r.stars || 0} ${r.name}: ${r.desc || 'N/A'}`));
}

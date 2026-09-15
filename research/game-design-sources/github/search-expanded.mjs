import https from 'https';
import fs from 'fs';

const searches = [
  'npc memory system game',
  'persistent world simulation game',
  'offline progression mechanic game',
  'day night cycle simulation game',
  'dialogue memory system game',
  'quest system rpg game',
  'save system with history game',
  'farming sim game jam',
  'life simulation browser game',
  'relationship simulator open source',
  'gift economy game',
  'emotional narrative game',
  'comfort game cozy mechanic',
  'loneliness game design',
  'episodic narrative game',
  'mailbox letter game mechanic',
  'virtual pet game open source',
  'tamagotchi clone game',
  'idle life sim game',
  'npc daily routine game',
  'player housing game mechanic',
  'crafting system game',
  'weather system game',
  'time skip game mechanic',
  'returning player game mechanic',
  'npc memory persistence game',
  'slice of life indie game',
  'anime character interaction game',
  '3d anime character game',
  'interactive fiction web game',
  'walking simulator open source',
  'narrative choice game engine',
  'relationship point game mechanic',
  'daily visit game mechanic',
  'world building game tool',
  'procedural generation narrative',
  'ai character dialogue game',
  'llm npc game',
  'openai character game',
  'local llm game dialogue'
];

const token = process.env.GITHUB_TOKEN || '';
const results = [];
const seen = new Set();

function searchGithub(query, page = 1) {
  return new Promise((resolve, reject) => {
    const q = encodeURIComponent(query);
    const url = `https://api.github.com/search/repositories?q=${q}&sort=stars&order=desc&page=${page}&per_page=100`;
    const opts = {
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'PenguinHarness/1.0'
      }
    };
    if (token) opts.headers['Authorization'] = `Bearer ${token}`;
    https.get(url, opts, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve(json);
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

async function main() {
  for (const q of searches) {
    try {
      const json = await searchGithub(q, 1);
      const items = json.items || [];
      let added = 0;
      for (const item of items) {
        const key = item.html_url;
        if (!seen.has(key)) {
          seen.add(key);
          results.push({
            id: item.id,
            name: item.full_name,
            url: item.html_url,
            description: item.description,
            stars: item.stargazers_count,
            language: item.language,
            query: q
          });
          added++;
        }
      }
      console.log(`${q}: ${added} new (page 1)`);

      if (json.total_count > 100) {
        const json2 = await searchGithub(q, 2);
        const items2 = json2.items || [];
        let added2 = 0;
        for (const item of items2) {
          const key = item.html_url;
          if (!seen.has(key)) {
            seen.add(key);
            results.push({
              id: item.id,
              name: item.full_name,
              url: item.html_url,
              description: item.description,
              stars: item.stargazers_count,
              language: item.language,
              query: q
            });
            added2++;
          }
        }
        console.log(`${q}: ${added2} new (page 2)`);
      }
    } catch (e) {
      console.log(`${q}: ERROR - ${e.message.slice(0, 80)}`);
    }
    await new Promise(r => setTimeout(r, 1200));
  }

  fs.writeFileSync('gh-expanded-results.json', JSON.stringify({
    total_count: results.length,
    items: results
  }, null, 2));
  console.log(`Done. Total new GitHub repos: ${results.length}`);
}

main();

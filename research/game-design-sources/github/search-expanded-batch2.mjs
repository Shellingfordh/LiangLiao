import https from 'https';
import fs from 'fs';

const searches = [
  'npc schedule game',
  'npc routine game',
  'npc ai game',
  'npc dialogue game',
  'npc interaction game',
  'persistent npc game',
  'npc memory game',
  'npc behavior game',
  'npc life sim',
  'character schedule game',
  'daily routine game',
  'offline events game',
  'offline progress game',
  'idle events game',
  'world simulation game',
  'life sim game',
  'cozy game',
  'cozy world game',
  'cozy village game',
  'slice of life game',
  'relationship game',
  'dating sim',
  'visual novel',
  'interactive fiction',
  'walking simulator',
  'narrative game',
  'story game',
  'choice game',
  'multiple endings game',
  'gift game',
  'letter game',
  'mail game',
  'diary game',
  'memory game',
  'time skip game',
  'day night cycle game',
  'weather game',
  'farming game',
  'crafting game',
  'base building game',
  'survival game',
  'open world game',
  'management game',
  'anime game',
  '3d game',
  'browser game',
  'html5 game',
  'godot game',
  'unity game',
  'unreal game'
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
    await new Promise(r => setTimeout(r, 1000));
  }

  fs.writeFileSync('gh-expanded-batch2.json', JSON.stringify({
    total_count: results.length,
    items: results
  }, null, 2));
  console.log(`Done. Total new GitHub repos: ${results.length}`);
}

main();

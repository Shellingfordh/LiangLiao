import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'fdg-conf', url: 'https://fdg2024.org/' },
  { name: 'digra', url: 'http://www.digra.org/' },
  { name: 'chi-play', url: 'https://chiplay.acm.org/' },
  { name: 'gamestudies', url: 'http://gamestudies.org/' },
  { name: 'acm-games', url: 'https://dl.acm.org/topic/ccs2012/10010414' },
  { name: 'ieee-games', url: 'https://ieeexplore.ieee.org/search/searchresult.jsp?queryText=game+design' },
  { name: 'springer-games', url: 'https://link.springer.com/search?query=game+design' },
  { name: 'mdpi-games', url: 'https://www.mdpi.com/search?q=game+design' },
  { name: 'researchgate-games', url: 'https://www.researchgate.net/search?q=game+design' },
  { name: 'arxiv-games', url: 'https://arxiv.org/search/?searchtype=all&query=game+design' },
  { name: 'nintendo-direct', url: 'https://www.nintendo.com/store/product-research/' },
  { name: 'ign-game-design', url: 'https://www.ign.com/articles/game-design' },
  { name: 'polygon-game-design', url: 'https://www.polygon.com/game-design' },
  { name: 'kotaku-game-design', url: 'https://kotaku.com/tag/game-design' },
  { name: 'rock-paper-shotgun-design', url: 'https://www.rockpapershotgun.com/game-design' },
  { name: 'pcgamer-design', url: 'https://www.pcgamer.com/game-design/' },
  { name: 'eurogamer-design', url: 'https://www.eurogamer.net/game-design' },
  { name: 'gamespot-design', url: 'https://www.gamespot.com/game-design/' },
  { name: 'arstechnica-gaming', url: 'https://arstechnica.com/gaming/' },
  { name: 'venturebeat-games', url: 'https://venturebeat.com/category/games/' },
  { name: 'techcrunch-gaming', url: 'https://techcrunch.com/gaming/' },
  { name: 'wired-gaming', url: 'https://www.wired.com/tag/gaming/' },
  { name: 'the-verge-gaming', url: 'https://www.theverge.com/games' },
  { name: 'guardian-games', url: 'https://www.theguardian.com/games' },
  { name: 'bbc-gaming', url: 'https://www.bbc.co.uk/search?q=game+design' }
];

const browser = await chromium.launch();
const page = await browser.newPage();
const results = [];

for (const s of searches) {
  try {
    await page.goto(s.url, { waitUntil: 'domcontentloaded', timeout: 25000 });
    await page.waitForTimeout(3000);
    const links = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('a')).filter(a => 
        a.href && !a.href.includes('javascript:') && a.textContent.trim().length > 5
      ).map(a => ({
        text: a.textContent.trim().slice(0, 120),
        href: a.href
      })).slice(0, 120);
    });
    results.push({ source: s.name, count: links.length, links });
    console.log(`${s.name}: ${links.length} links`);
  } catch (e) {
    console.log(`${s.name}: ERROR - ${e.message.slice(0, 80)}`);
  }
}

fs.writeFileSync('academic-media-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Academic/media search completed');

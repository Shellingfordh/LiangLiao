import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'sketchfab-characters', url: 'https://sketchfab.com/search?type=models&q=anime+character' },
  { name: 'turbosquid-anime', url: 'https://www.turbosquid.com/Search/3D-Models/free/anime+character' },
  { name: 'cgtrader-anime', url: 'https://www.cgtrader.com/3d-models?keywords=anime+character' },
  { name: 'indie-db-games', url: 'https://www.indiedb.com/games' },
  { name: 'moddb-games', url: 'https://www.moddb.com/games' },
  { name: 'gamejolt-games', url: 'https://gamejolt.com/games' },
];

const browser = await chromium.launch();
const page = await browser.newPage();
const results = [];

for (const s of searches) {
  try {
    await page.goto(s.url, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(2000);
    const links = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('a')).filter(a => 
        a.href && !a.href.includes('javascript:') && a.textContent.trim().length > 5
      ).map(a => ({
        text: a.textContent.trim().slice(0, 100),
        href: a.href
      })).slice(0, 100);
    });
    results.push({ source: s.name, count: links.length, links });
    console.log(`${s.name}: ${links.length} links`);
  } catch (e) {
    console.log(`${s.name}: ERROR - ${e.message.slice(0, 50)}`);
  }
}

fs.writeFileSync('3d-indie-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('3D/Indie search completed');

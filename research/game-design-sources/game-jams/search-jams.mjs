import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'itch-io-jams', url: 'https://itch.io/jams' },
  { name: 'itch-io-narrative', url: 'https://itch.io/games/tag-narrative' },
  { name: 'itch-io-visual-novel', url: 'https://itch.io/games/tag-visual-novel' },
  { name: 'itch-io-cozy', url: 'https://itch.io/games/tag-cozy' },
  { name: 'itch-io-3d', url: 'https://itch.io/games/tag-3d' },
  { name: 'gamejolt-jams', url: 'https://gamejolt.com/games' },
  { name: 'global-game-jam', url: 'https://globalgamejam.org/games' },
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

fs.writeFileSync('jam-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Game jam search completed');

import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'itch-gift-games', url: 'https://itch.io/games/tag-gift' },
  { name: 'itch-romance', url: 'https://itch.io/games/tag-romance' },
  { name: 'itch-dating', url: 'https://itch.io/games/tag-dating-sim' },
  { name: 'itch-relationship', url: 'https://itch.io/games/tag-relationship' },
  { name: 'steam-gift-giving', url: 'https://store.steampowered.com/search/?tags=5350' },
  { name: 'steam-romance', url: 'https://store.steampowered.com/search/?tags=4947' },
  { name: 'gamejolt-gift', url: 'https://gamejolt.com/games?tag=gift' },
  { name: 'gamejolt-romance', url: 'https://gamejolt.com/games?tag=romance' },
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

fs.writeFileSync('gift-relationship-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Gift/Relationship search completed');

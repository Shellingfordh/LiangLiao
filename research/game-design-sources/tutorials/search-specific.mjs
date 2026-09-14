import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'gift-mechanic', url: 'https://www.google.com/search?q=game+design+gift+giving+mechanic+tutorial' },
  { name: 'relationship-system', url: 'https://www.google.com/search?q=game+design+relationship+system+tutorial' },
  { name: 'anime-style-3d', url: 'https://www.google.com/search?q=anime+style+3d+game+development+guide' },
  { name: 'character-interaction', url: 'https://www.google.com/search?q=character+interaction+game+mechanic+design' },
  { name: 'cozy-game-design', url: 'https://www.google.com/search?q=cozy+game+design+patterns+best+practices' },
  { name: 'visual-novel-mechanics', url: 'https://www.google.com/search?q=visual+novel+game+mechanics+design+guide' },
  { name: 'bocchi-rock-game', url: 'https://www.google.com/search?q=bocchi+the+rock+game+development' },
  { name: 'yamada-ryo-character', url: 'https://www.google.com/search?q=yamada+ryo+bocchi+rock+character+analysis' },
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
        a.href && !a.href.includes('google.com') && a.href.includes('http') && a.textContent.trim().length > 10
      ).map(a => ({
        text: a.textContent.trim().slice(0, 100),
        href: a.href
      })).slice(0, 50);
    });
    results.push({ source: s.name, count: links.length, links });
    console.log(`${s.name}: ${links.length} links`);
  } catch (e) {
    console.log(`${s.name}: ERROR - ${e.message.slice(0, 50)}`);
  }
}

fs.writeFileSync('specific-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Specific search completed');

import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'gamedeveloper-postmortems', url: 'https://www.gamedeveloper.com/design/postmortem' },
  { name: 'gamedeveloper-narrative', url: 'https://www.gamedeveloper.com/design/narrative-design' },
  { name: 'gamedeveloper-visual-novel', url: 'https://www.gamedeveloper.com/search?q=visual+novel' },
  { name: 'medium-game-design', url: 'https://medium.com/tag/game-design/recommended' },
  { name: 'medium-narrative', url: 'https://medium.com/tag/narrative-design/recommended' },
  { name: 'medium-indie-game', url: 'https://medium.com/tag/indie-game/recommended' },
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
        a.href && !a.href.includes('javascript:') && a.textContent.trim().length > 15
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

fs.writeFileSync('case-studies-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Case studies search completed');

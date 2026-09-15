import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'gamasutra', url: 'https://www.gamedeveloper.com/search?q=narrative+game+design' },
  { name: 'gamedesigning-org', url: 'https://www.gamedesigning.org/?s=visual+novel' },
  { name: 'gamefromscratch', url: 'https://gamefromscratch.com/?s=game+engine' },
  { name: 'medium-gamedev', url: 'https://medium.com/search?q=cozy+game+design' },
  { name: 'devto-gamedev', url: 'https://dev.to/search?q=game+development&sort_by=relevance' },
  { name: 'hackernoon-gamedev', url: 'https://hackernoon.com/search?q=indie+game+development' },
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
      })).slice(0, 50);
    });
    results.push({ source: s.name, count: links.length, links });
    console.log(`${s.name}: ${links.length} links`);
  } catch (e) {
    console.log(`${s.name}: ERROR - ${e.message.slice(0, 50)}`);
  }
}

fs.writeFileSync('blog-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Blog search completed');

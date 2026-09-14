import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'youtube-gamedev', url: 'https://www.youtube.com/results?search_query=game+development+tutorial' },
  { name: 'youtube-narrative', url: 'https://www.youtube.com/results?search_query=narrative+game+design+tutorial' },
  { name: 'youtube-3d-modeling', url: 'https://www.youtube.com/results?search_query=3d+game+modeling+tutorial' },
  { name: 'youtube-visual-novel', url: 'https://www.youtube.com/results?search_query=visual+novel+game+development' },
  { name: 'youtube-cozy-game', url: 'https://www.youtube.com/results?search_query=cozy+game+development+tutorial' },
];

const browser = await chromium.launch();
const page = await browser.newPage();
const results = [];

for (const s of searches) {
  try {
    await page.goto(s.url, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(3000);
    const links = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('a')).filter(a => 
        a.href && a.href.includes('/watch') && a.textContent.trim().length > 10
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

fs.writeFileSync('youtube-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('YouTube search completed');

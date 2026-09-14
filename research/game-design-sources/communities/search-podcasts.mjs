import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'gamedev-podcasts', url: 'https://www.google.com/search?q=game+development+podcast+list' },
  { name: 'gamedev-newsletters', url: 'https://www.google.com/search?q=game+development+newsletter+subscribe' },
  { name: 'indie-game-communities', url: 'https://www.google.com/search?q=indie+game+development+community+forum' },
  { name: 'game-design-blogs', url: 'https://www.google.com/search?q=game+design+blog+best' },
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

fs.writeFileSync('podcasts-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Podcasts search completed');

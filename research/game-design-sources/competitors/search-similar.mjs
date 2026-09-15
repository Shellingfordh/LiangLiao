import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'steam-narrative', url: 'https://store.steampowered.com/search/?tags=1664&category1=998' },
  { name: 'steam-visual-novel', url: 'https://store.steampowered.com/search/?tags=3799' },
  { name: 'steam-cozy', url: 'https://store.steampowered.com/search/?tags=1654&category1=998' },
  { name: 'steam-anime', url: 'https://store.steampowered.com/search/?tags=4085&category1=998' },
  { name: 'steam-gift', url: 'https://store.steampowered.com/search/?tags=5350&category1=998' },
  { name: 'steam-dating-sim', url: 'https://store.steampowered.com/search/?tags=4947&category1=998' },
  { name: 'playstore-narrative', url: 'https://play.google.com/store/search?q=narrative%20game&c=apps&hl=en' },
  { name: 'playstore-visual-novel', url: 'https://play.google.com/store/search?q=visual%20novel&c=apps&hl=en' },
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

fs.writeFileSync('similar-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Similar games search completed');

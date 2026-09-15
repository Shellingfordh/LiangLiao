import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'unity-asset-store', url: 'https://assetstore.unity.com/search?orderBy=1&q=narrative+system' },
  { name: 'unreal-marketplace', url: 'https://www.unrealengine.com/marketplace/en-US/search?query=narrative' },
  { name: 'itch-io-tools', url: 'https://itch.io/tools' },
  { name: 'gameassets', url: 'https://gameassets.com/' },
  { name: 'opengameart', url: 'https://opengameart.org/' },
  { name: 'kenney-assets', url: 'https://kenney.nl/assets' },
  { name: 'mixamo-animations', url: 'https://www.mixamo.com/' },
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

fs.writeFileSync('tools-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Tools search completed');

import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'taptap-maker-games', url: 'https://www.taptap.cn/category/maker' },
  { name: 'taptap-creative', url: 'https://www.taptap.cn/category/creative' },
  { name: 'taptap-showcase', url: 'https://maker.taptap.cn/' },
  { name: 'tripo-showcase', url: 'https://www.tripo3d.ai/' },
  { name: 'unity-learn', url: 'https://learn.unity.com/search?query=narrative+game' },
  { name: 'unreal-tutorials', url: 'https://dev.epicgames.com/community/search/?query=3d+game+design' },
  { name: 'godot-tutorials', url: 'https://docs.godotengine.org/en/stable/getting_started/first_2d_game/index.html' },
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

fs.writeFileSync('community-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Community search completed');

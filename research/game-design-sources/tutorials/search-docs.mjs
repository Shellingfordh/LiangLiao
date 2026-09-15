import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'gameprogrammingpatterns', url: 'https://gameprogrammingpatterns.com/' },
  { name: 'roguebasin', url: 'https://roguebasin.com/index.php/Main_Page' },
  { name: 'gamedesignskills', url: 'https://www.gamesdesignskills.com/' },
  { name: 'docs-unity-3d', url: 'https://docs.unity3d.com/Manual/Creating3DContent.html' },
  { name: 'docs-godot-3d', url: 'https://docs.godotengine.org/en/stable/tutorials/3d/index.html' },
  { name: 'ink-narrative', url: 'https://www.inklestudios.com/ink/' },
  { name: 'yarn-spinner', url: 'https://yarnspinner.dev/' },
  { name: 'renpy-docs', url: 'https://www.renpy.org/doc/html/' },
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

fs.writeFileSync('docs-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Docs search completed');

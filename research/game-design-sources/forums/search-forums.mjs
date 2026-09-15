import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'reddit-gamedev', url: 'https://www.reddit.com/r/gamedev/search/?q=narrative+game+design&sort=top&t=all' },
  { name: 'reddit-indiegaming', url: 'https://www.reddit.com/r/IndieGaming/search/?q=cozy+game+design&sort=top&t=all' },
  { name: 'gamedev-net', url: 'https://www.gamedev.net/search/?q=visual+novel+engine&type=forums_topic' },
  { name: 'tigsource', url: 'https://forums.tigsource.com/index.php?action=search2' },
  { name: 'itch-io-forums', url: 'https://itch.io/search?q=visual+novel+game+jam' },
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
        a.href && !a.href.includes('javascript:') && a.textContent.trim().length > 10
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

fs.writeFileSync('forum-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Forum search completed');

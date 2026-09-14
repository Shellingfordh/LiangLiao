import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'amazon-gamedev', url: 'https://www.amazon.com/s?k=game+development+book&i=stripbooks' },
  { name: 'goodreads-gamedev', url: 'https://www.goodreads.com/search?q=game+design' },
  { name: 'springer-gamedev', url: 'https://link.springer.com/search?query=game+design&facet-discipline=%22Computer+Science%22' },
  { name: 'arxiv-gamedev', url: 'https://arxiv.org/search/?query=game+design&searchtype=all' },
  { name: 'wikipedia-gamedev', url: 'https://en.wikipedia.org/wiki/Video_game_development' },
  { name: 'wikia-games', url: 'https://gaming.fandom.com/wiki/Video_game' },
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
      })).slice(0, 100);
    });
    results.push({ source: s.name, count: links.length, links });
    console.log(`${s.name}: ${links.length} links`);
  } catch (e) {
    console.log(`${s.name}: ERROR - ${e.message.slice(0, 50)}`);
  }
}

fs.writeFileSync('books-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Books search completed');

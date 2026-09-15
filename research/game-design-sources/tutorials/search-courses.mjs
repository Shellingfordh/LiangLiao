import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'udemy-gamedev', url: 'https://www.udemy.com/courses/search/?q=game+development&src=ukw' },
  { name: 'coursera-gamedev', url: 'https://www.coursera.org/search?query=game+development' },
  { name: 'skillshare-gamedev', url: 'https://www.skillshare.com/search?query=game+development' },
  { name: 'edx-gamedev', url: 'https://www.edx.org/search?q=game+development' },
  { name: 'khan-academy-gamedev', url: 'https://www.khanacademy.org/search?search_again=1&page_search_query=game+development' },
  { name: 'codecademy-gamedev', url: 'https://www.codecademy.com/search?query=game+development' },
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

fs.writeFileSync('courses-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Courses search completed');

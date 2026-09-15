import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'bocchi-wiki', url: 'https://bocchi-the-rock.fandom.com/wiki/Bocchi_the_Rock!_Wiki' },
  { name: 'yamada-ryo-wiki', url: 'https://bocchi-the-rock.fandom.com/wiki/Ryo_Yamada' },
  { name: 'myanimelist-bocchi', url: 'https://myanimelist.net/anime/50477/Bocchi_the_Rock' },
  { name: 'crunchyroll-bocchi', url: 'https://www.crunchyroll.com/series/G4PH0WXVJ/bocchi-the-rock' },
  { name: 'anime-game-design', url: 'https://www.animenewsnetwork.com/search?q=game+design' },
  { name: 'anime-news-network', url: 'https://www.animenewsnetwork.com/search?q=bocchi+the+rock' },
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

fs.writeFileSync('bocchi-anime-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Bocchi/Anime search completed');

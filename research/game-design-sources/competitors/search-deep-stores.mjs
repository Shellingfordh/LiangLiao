import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'steam-life-sim-p2', url: 'https://store.steampowered.com/search/?tags=1667&category1=998&page=2' },
  { name: 'steam-life-sim-p3', url: 'https://store.steampowered.com/search/?tags=1667&category1=998&page=3' },
  { name: 'steam-interactive-fiction-p2', url: 'https://store.steampowered.com/search/?tags=28681&category1=998&page=2' },
  { name: 'steam-interactive-fiction-p3', url: 'https://store.steampowered.com/search/?tags=28681&category1=998&page=3' },
  { name: 'steam-walking-sim-p2', url: 'https://store.steampowered.com/search/?tags=4195&category1=998&page=2' },
  { name: 'steam-walking-sim-p3', url: 'https://store.steampowered.com/search/?tags=4195&category1=998&page=3' },
  { name: 'steam-emotional-p2', url: 'https://store.steampowered.com/search/?tags=1868&category1=998&page=2' },
  { name: 'steam-emotional-p3', url: 'https://store.steampowered.com/search/?tags=1868&category1=998&page=3' },
  { name: 'steam-story-rich-p2', url: 'https://store.steampowered.com/search/?tags=1664&category1=998&page=2' },
  { name: 'steam-story-rich-p3', url: 'https://store.steampowered.com/search/?tags=1664&category1=998&page=3' },
  { name: 'steam-choices-matter-p2', url: 'https://store.steampowered.com/search/?tags=6426&category1=998&page=2' },
  { name: 'steam-choices-matter-p3', url: 'https://store.steampowered.com/search/?tags=6426&category1=998&page=3' },
  { name: 'steam-cozy-p2', url: 'https://store.steampowered.com/search/?tags=1654&category1=998&page=2' },
  { name: 'steam-cozy-p3', url: 'https://store.steampowered.com/search/?tags=1654&category1=998&page=3' },
  { name: 'steam-sandbox-p2', url: 'https://store.steampowered.com/search/?tags=6608&category1=998&page=2' },
  { name: 'steam-sandbox-p3', url: 'https://store.steampowered.com/search/?tags=6608&category1=998&page=3' },
  { name: 'steam-survival-p2', url: 'https://store.steampowered.com/search/?tags=1662&category1=998&page=2' },
  { name: 'steam-survival-p3', url: 'https://store.steampowered.com/search/?tags=1662&category1=998&page=3' },
  { name: 'steam-management-p2', url: 'https://store.steampowered.com/search/?tags=12472&category1=998&page=2' },
  { name: 'steam-management-p3', url: 'https://store.steampowered.com/search/?tags=12472&category1=998&page=3' },
  { name: 'itch-life-sim-p2', url: 'https://itch.io/games/tag-life-sim?page=2' },
  { name: 'itch-life-sim-p3', url: 'https://itch.io/games/tag-life-sim?page=3' },
  { name: 'itch-cozy-p2', url: 'https://itch.io/games/tag-cozy?page=2' },
  { name: 'itch-cozy-p3', url: 'https://itch.io/games/tag-cozy?page=3' },
  { name: 'itch-narrative-p2', url: 'https://itch.io/games/tag-narrative?page=2' },
  { name: 'itch-narrative-p3', url: 'https://itch.io/games/tag-narrative?page=3' },
  { name: 'itch-visual-novel-p2', url: 'https://itch.io/games/tag-visual-novel?page=2' },
  { name: 'itch-visual-novel-p3', url: 'https://itch.io/games/tag-visual-novel?page=3' },
  { name: 'itch-relationship-p2', url: 'https://itch.io/games/tag-relationship?page=2' },
  { name: 'itch-relationship-p3', url: 'https://itch.io/games/tag-relationship?page=3' },
  { name: 'itch-simulation-p2', url: 'https://itch.io/games/tag-simulation?page=2' },
  { name: 'itch-simulation-p3', url: 'https://itch.io/games/tag-simulation?page=3' },
  { name: 'itch-rpg-p2', url: 'https://itch.io/games/tag-rpg?page=2' },
  { name: 'itch-rpg-p3', url: 'https://itch.io/games/tag-rpg?page=3' },
  { name: 'itch-story-rich-p2', url: 'https://itch.io/games/tag-story-rich?page=2' },
  { name: 'itch-story-rich-p3', url: 'https://itch.io/games/tag-story-rich?page=3' },
  { name: 'itch-anime-p2', url: 'https://itch.io/games/tag-anime?page=2' },
  { name: 'itch-anime-p3', url: 'https://itch.io/games/tag-anime?page=3' },
  { name: 'itch-pixel-art-p2', url: 'https://itch.io/games/tag-pixel-art?page=2' },
  { name: 'itch-pixel-art-p3', url: 'https://itch.io/games/tag-pixel-art?page=3' },
  { name: 'itch-low-poly-p2', url: 'https://itch.io/games/tag-low-poly?page=2' },
  { name: 'itch-low-poly-p3', url: 'https://itch.io/games/tag-low-poly?page=3' },
  { name: 'itch-3d-p2', url: 'https://itch.io/games/tag-3d?page=2' },
  { name: 'itch-3d-p3', url: 'https://itch.io/games/tag-3d?page=3' },
  { name: 'itch-open-world-p2', url: 'https://itch.io/games/tag-open-world?page=2' },
  { name: 'itch-open-world-p3', url: 'https://itch.io/games/tag-open-world?page=3' },
  { name: 'itch-survival-p2', url: 'https://itch.io/games/tag-survival?page=2' },
  { name: 'itch-survival-p3', url: 'https://itch.io/games/tag-survival?page=3' },
  { name: 'itch-crafting-p2', url: 'https://itch.io/games/tag-crafting?page=2' },
  { name: 'itch-crafting-p3', url: 'https://itch.io/games/tag-crafting?page=3' },
  { name: 'itch-farming-p2', url: 'https://itch.io/games/tag-farming?page=2' },
  { name: 'itch-farming-p3', url: 'https://itch.io/games/tag-farming?page=3' },
  { name: 'itch-dating-sim-p2', url: 'https://itch.io/games/tag-dating-sim?page=2' },
  { name: 'itch-dating-sim-p3', url: 'https://itch.io/games/tag-dating-sim?page=3' },
  { name: 'itch-romance-p2', url: 'https://itch.io/games/tag-romance?page=2' },
  { name: 'itch-romance-p3', url: 'https://itch.io/games/tag-romance?page=3' },
  { name: 'itch-gift-p2', url: 'https://itch.io/games/tag-gift?page=2' },
  { name: 'itch-gift-p3', url: 'https://itch.io/games/tag-gift?page=3' },
  { name: 'itch-letter-p2', url: 'https://itch.io/games/tag-letter?page=2' },
  { name: 'itch-letter-p3', url: 'https://itch.io/games/tag-letter?page=3' },
  { name: 'itch-memory-p2', url: 'https://itch.io/games/tag-memory?page=2' },
  { name: 'itch-memory-p3', url: 'https://itch.io/games/tag-memory?page=3' },
  { name: 'itch-time-loop-p2', url: 'https://itch.io/games/tag-time-loop?page=2' },
  { name: 'itch-time-loop-p3', url: 'https://itch.io/games/tag-time-loop?page=3' },
  { name: 'itch-slice-of-life-p2', url: 'https://itch.io/games/tag-slice-of-life?page=2' },
  { name: 'itch-slice-of-life-p3', url: 'https://itch.io/games/tag-slice-of-life?page=3' }
];

const browser = await chromium.launch();
const page = await browser.newPage();
const results = [];

for (const s of searches) {
  try {
    await page.goto(s.url, { waitUntil: 'domcontentloaded', timeout: 25000 });
    await page.waitForTimeout(3000);
    const links = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('a')).filter(a => 
        a.href && !a.href.includes('javascript:') && a.textContent.trim().length > 5
      ).map(a => ({
        text: a.textContent.trim().slice(0, 120),
        href: a.href
      })).slice(0, 120);
    });
    results.push({ source: s.name, count: links.length, links });
    console.log(`${s.name}: ${links.length} links`);
  } catch (e) {
    console.log(`${s.name}: ERROR - ${e.message.slice(0, 80)}`);
  }
}

fs.writeFileSync('deep-stores-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Deep stores search completed');

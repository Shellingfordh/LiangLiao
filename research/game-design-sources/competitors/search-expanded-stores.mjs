import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'steam-life-sim', url: 'https://store.steampowered.com/search/?tags=1667&category1=998' },
  { name: 'steam-interactive-fiction', url: 'https://store.steampowered.com/search/?tags=28681&category1=998' },
  { name: 'steam-walking-sim', url: 'https://store.steampowered.com/search/?tags=4195&category1=998' },
  { name: 'steam-emotional', url: 'https://store.steampowered.com/search/?tags=1868&category1=998' },
  { name: 'steam-exploration', url: 'https://store.steampowered.com/search/?tags=3834&category1=998' },
  { name: 'steam-relaxing', url: 'https://store.steampowered.com/search/?tags=1664&category1=998' },
  { name: 'steam-atmospheric', url: 'https://store.steampowered.com/search/?tags=1664&category1=998' },
  { name: 'steam-story-rich', url: 'https://store.steampowered.com/search/?tags=1664&category1=998' },
  { name: 'steam-choices-matter', url: 'https://store.steampowered.com/search/?tags=6426&category1=998' },
  { name: 'steam-character-customization', url: 'https://store.steampowered.com/search/?tags=6638&category1=998' },
  { name: 'steam-sandbox', url: 'https://store.steampowered.com/search/?tags=6608&category1=998' },
  { name: 'steam-open-world', url: 'https://store.steampowered.com/search/?tags=1695&category1=998' },
  { name: 'steam-survival', url: 'https://store.steampowered.com/search/?tags=1662&category1=998' },
  { name: 'steam-base-building', url: 'https://store.steampowered.com/search/?tags=33680&category1=998' },
  { name: 'steam-management', url: 'https://store.steampowered.com/search/?tags=12472&category1=998' },
  { name: 'itch-life-sim', url: 'https://itch.io/games/tag-life-sim' },
  { name: 'itch-cozy', url: 'https://itch.io/games/tag-cozy' },
  { name: 'itch-narrative', url: 'https://itch.io/games/tag-narrative' },
  { name: 'itch-visual-novel', url: 'https://itch.io/games/tag-visual-novel' },
  { name: 'itch-relationship', url: 'https://itch.io/games/tag-relationship' },
  { name: 'itch-simulation', url: 'https://itch.io/games/tag-simulation' },
  { name: 'itch-rpg', url: 'https://itch.io/games/tag-rpg' },
  { name: 'itch-puzzle', url: 'https://itch.io/games/tag-puzzle' },
  { name: 'itch-story-rich', url: 'https://itch.io/games/tag-story-rich' },
  { name: 'itch-2d', url: 'https://itch.io/games/tag-2d' },
  { name: 'itch-3d', url: 'https://itch.io/games/tag-3d' },
  { name: 'itch-anime', url: 'https://itch.io/games/tag-anime' },
  { name: 'itch-pixel-art', url: 'https://itch.io/games/tag-pixel-art' },
  { name: 'itch-low-poly', url: 'https://itch.io/games/tag-low-poly' },
  { name: 'itch-first-person', url: 'https://itch.io/games/tag-first-person' },
  { name: 'itch-third-person', url: 'https://itch.io/games/tag-third-person' },
  { name: 'itch-open-world', url: 'https://itch.io/games/tag-open-world' },
  { name: 'itch-survival', url: 'https://itch.io/games/tag-survival' },
  { name: 'itch-crafting', url: 'https://itch.io/games/tag-crafting' },
  { name: 'itch-farming', url: 'https://itch.io/games/tag-farming' },
  { name: 'itch-management', url: 'https://itch.io/games/tag-management' },
  { name: 'itch-base-building', url: 'https://itch.io/games/tag-base-building' },
  { name: 'itch-choices-matter', url: 'https://itch.io/games/tag-choices-matter' },
  { name: 'itch-multiple-endings', url: 'https://itch.io/games/tag-multiple-endings' },
  { name: 'itch-romance', url: 'https://itch.io/games/tag-romance' },
  { name: 'itch-dating-sim', url: 'https://itch.io/games/tag-dating-sim' },
  { name: 'itch-gift', url: 'https://itch.io/games/tag-gift' },
  { name: 'itch-letter', url: 'https://itch.io/games/tag-letter' },
  { name: 'itch-mail', url: 'https://itch.io/games/tag-mail' },
  { name: 'itch-diary', url: 'https://itch.io/games/tag-diary' },
  { name: 'itch-memory', url: 'https://itch.io/games/tag-memory' },
  { name: 'itch-time-loop', url: 'https://itch.io/games/tag-time-loop' },
  { name: 'itch-parallel', url: 'https://itch.io/games/tag-parallel' },
  { name: 'itch-slice-of-life', url: 'https://itch.io/games/tag-slice-of-life' }
];

const browser = await chromium.launch();
const page = await browser.newPage();
const results = [];

for (const s of searches) {
  try {
    await page.goto(s.url, { waitUntil: 'domcontentloaded', timeout: 20000 });
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

fs.writeFileSync('expanded-stores-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Expanded stores search completed');

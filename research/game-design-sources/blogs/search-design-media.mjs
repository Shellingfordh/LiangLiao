import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'gdc-vault-design', url: 'https://www.gdcvault.com/search.php?category=first&search=game+design&x=0&y=0' },
  { name: 'gdc-vault-ai', url: 'https://www.gdcvault.com/search.php?category=first&search=npc+ai&x=0&y=0' },
  { name: 'gdc-vault-narrative', url: 'https://www.gdcvault.com/search.php?category=first&search=narrative&x=0&y=0' },
  { name: 'gdc-vault-cozy', url: 'https://www.gdcvault.com/search.php?category=first&search=cozy&x=0&y=0' },
  { name: 'gdc-vault-life-sim', url: 'https://www.gdcvault.com/search.php?category=first&search=life+simulation&x=0&y=0' },
  { name: 'gamasutra-design', url: 'https://www.gamasutra.com/search.php?search=game+design&x=0&y=0' },
  { name: 'gamasutra-postmortem', url: 'https://www.gamasutra.com/search.php?search=postmortem&x=0&y=0' },
  { name: 'gamasutra-narrative', url: 'https://www.gamasutra.com/search.php?search=narrative&x=0&y=0' },
  { name: 'gamasutra-ai', url: 'https://www.gamasutra.com/search.php?search=ai&x=0&y=0' },
  { name: 'gamasutra-cozy', url: 'https://www.gamasutra.com/search.php?search=cozy&x=0&y=0' },
  { name: 'gamedev-postmortems', url: 'https://www.gamedeveloper.com/keyword/postmortem' },
  { name: 'gamedev-design', url: 'https://www.gamedeveloper.com/keyword/game-design' },
  { name: 'gamedev-narrative', url: 'https://www.gamedeveloper.com/keyword/narrative' },
  { name: 'gamedev-ai', url: 'https://www.gamedeveloper.com/keyword/ai' },
  { name: 'gamedev-production', url: 'https://www.gamedeveloper.com/keyword/production' },
  { name: 'youtube-gmtk', url: 'https://www.youtube.com/user/McBacon1337/videos' },
  { name: 'youtube-design-doc', url: 'https://www.youtube.com/c/DesignDoc/videos' },
  { name: 'youtube-game-makers-notebook', url: 'https://www.youtube.com/c/GDCChannel/videos' },
  { name: 'youtube-brackeys', url: 'https://www.youtube.com/c/Brackeys/videos' },
  { name: 'youtube-syphon', url: 'https://www.youtube.com/c/SyphonGameDev/videos' },
  { name: 'youtube-cozy-game', url: 'https://www.youtube.com/results?search_query=cozy+game+design' },
  { name: 'youtube-npc-ai', url: 'https://www.youtube.com/results?search_query=npc+ai+game' },
  { name: 'youtube-life-sim', url: 'https://www.youtube.com/results?search_query=life+sim+game' },
  { name: 'youtube-visual-novel', url: 'https://www.youtube.com/results?search_query=visual+novel+engine' },
  { name: 'youtube-narrative-design', url: 'https://www.youtube.com/results?search_query=narrative+design' }
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

fs.writeFileSync('design-media-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Design media search completed');

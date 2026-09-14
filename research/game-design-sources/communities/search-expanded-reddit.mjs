import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'reddit-gamedev-npc', url: 'https://www.reddit.com/r/gamedev/search/?q=npc+ai&sort=top&t=all' },
  { name: 'reddit-gamedev-dialogue', url: 'https://www.reddit.com/r/gamedev/search/?q=dialogue+system&sort=top&t=all' },
  { name: 'reddit-gamedev-persistence', url: 'https://www.reddit.com/r/gamedev/search/?q=save+system&sort=top&t=all' },
  { name: 'reddit-gamedev-life-sim', url: 'https://www.reddit.com/r/gamedev/search/?q=life+sim&sort=top&t=all' },
  { name: 'reddit-gamedev-cozy', url: 'https://www.reddit.com/r/gamedev/search/?q=cozy&sort=top&t=all' },
  { name: 'reddit-gamedev-narrative', url: 'https://www.reddit.com/r/gamedev/search/?q=narrative&sort=top&t=all' },
  { name: 'reddit-gamedev-postmortem', url: 'https://www.reddit.com/r/gamedev/search/?q=postmortem&sort=top&t=all' },
  { name: 'reddit-indiegaming-life', url: 'https://www.reddit.com/r/IndieGaming/search/?q=life+sim&sort=top&t=all' },
  { name: 'reddit-indiegaming-cozy', url: 'https://www.reddit.com/r/IndieGaming/search/?q=cozy&sort=top&t=all' },
  { name: 'reddit-indiegaming-narrative', url: 'https://www.reddit.com/r/IndieGaming/search/?q=narrative&sort=top&t=all' },
  { name: 'reddit-visualnovels-engine', url: 'https://www.reddit.com/r/visualnovels/search/?q=engine&sort=top&t=all' },
  { name: 'reddit-interactivefiction-tools', url: 'https://www.reddit.com/r/interactivefiction/search/?q=tools&sort=top&t=all' },
  { name: 'reddit-ludumdare-postmortem', url: 'https://www.reddit.com/r/ludumdare/search/?q=postmortem&sort=top&t=all' },
  { name: 'reddit-solodev-mechanics', url: 'https://www.reddit.com/r/SoloDevelopment/search/?q=mechanics&sort=top&t=all' },
  { name: 'reddit-solodev-npc', url: 'https://www.reddit.com/r/SoloDevelopment/search/?q=npc&sort=top&t=all' },
  { name: 'reddit-cozygames-mechanics', url: 'https://www.reddit.com/r/cozygames/search/?q=mechanics&sort=top&t=all' },
  { name: 'reddit-cozygames-npc', url: 'https://www.reddit.com/r/cozygames/search/?q=npc&sort=top&t=all' },
  { name: 'reddit-gamedesign-mechanics', url: 'https://www.reddit.com/r/gamedesign/search/?q=mechanics&sort=top&t=all' },
  { name: 'reddit-gamedesign-npc', url: 'https://www.reddit.com/r/gamedesign/search/?q=npc&sort=top&t=all' },
  { name: 'reddit-gamedesign-narrative', url: 'https://www.reddit.com/r/gamedesign/search/?q=narrative&sort=top&t=all' },
  { name: 'reddit-gamedesign-cozy', url: 'https://www.reddit.com/r/gamedesign/search/?q=cozy&sort=top&t=all' },
  { name: 'tigsource-specific', url: 'https://forums.tigsource.com/search.php?q=game+design' }
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
        a.href && !a.href.includes('javascript:') && a.textContent.trim().length > 10
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

fs.writeFileSync('expanded-reddit-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Expanded reddit search completed');

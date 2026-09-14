import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'reddit-gamedesign', url: 'https://www.reddit.com/r/gamedesign/search/?q=cozy+game&sort=top&t=all' },
  { name: 'reddit-cozygames', url: 'https://www.reddit.com/r/cozygames/search/?q=narrative&sort=top&t=all' },
  { name: 'reddit-visualnovels', url: 'https://www.reddit.com/r/visualnovels/search/?q=mechanics&sort=top&t=all' },
  { name: 'reddit-interactivefiction', url: 'https://www.reddit.com/r/interactivefiction/search/?q=design&sort=top&t=all' },
  { name: 'reddit-ludumdare', url: 'https://www.reddit.com/r/ludumdare/search/?q=postmortem&sort=top&t=all' },
  { name: 'reddit-solodev', url: 'https://www.reddit.com/r/SoloDevelopment/search/?q=game+design&sort=top&t=all' },
  { name: 'tigsource-cozy', url: 'https://forums.tigsource.com/forumdisplay.php?f=33' },
  { name: 'tigsource-wip', url: 'https://forums.tigsource.com/forumdisplay.php?f=34' },
  { name: 'tigsource-creativity', url: 'https://forums.tigsource.com/forumdisplay.php?f=35' },
  { name: 'tigsource-business', url: 'https://forums.tigsource.com/forumdisplay.php?f=36' },
  { name: 'steam-community-discussions', url: 'https://steamcommunity.com/app/413150/discussions/search/?gidforum=594821068&include_deleted=1&gidforum=594821068&include_deleted=1&include_deleted=1&gidforum=594821068&text=cozy&include_deleted=1&gidforum=594821068&gidforum=594821068' },
  { name: 'rpgmaker-forums', url: 'https://forums.rpgmakerweb.com/search?q=narrative+system' },
  { name: 'lemma-soft-forums', url: 'https://lemmasoft.renai.us/forums/search.php?keywords=visual+novel+engine' },
  { name: 'gamedev-net-forums', url: 'https://www.gamedev.net/forums/search/?q=game+design+mechanics&type=forums_topic' },
  { name: 'indiedb-forums', url: 'https://www.indiedb.com/forums/search?q=game+design' }
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

fs.writeFileSync('expanded-forums-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Expanded forums search completed');

import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve('./');
const BOCCHI_DIR = path.join(ROOT, 'bocchi');

function buildExistingUrlSet() {
  const dirs = ['github','forums','blogs','communities','competitors','tutorials','game-jams','chinese-community'];
  const urls = new Set();
  for (const dir of dirs) {
    const dirPath = path.join(ROOT, dir);
    if (!fs.existsSync(dirPath)) continue;
    for (const file of fs.readdirSync(dirPath).filter(f => f.endsWith('.json'))) {
      try {
        const data = JSON.parse(fs.readFileSync(path.join(dirPath, file), 'utf8'));
        const items = Array.isArray(data) ? data : (data.items || []);
        for (const item of items) {
          const candidates = [];
          if (item.links && Array.isArray(item.links)) {
            for (const l of item.links) if (l.href) candidates.push(l.href);
          }
          if (item.html_url) candidates.push(item.html_url);
          if (item.url) candidates.push(item.url);
          for (const u of candidates) {
            if (u && !u.includes('javascript:') && !u.startsWith('http://localhost')) urls.add(u);
          }
        }
      } catch (e) {}
    }
  }
  if (fs.existsSync(BOCCHI_DIR)) {
    for (const file of fs.readdirSync(BOCCHI_DIR).filter(f => f.endsWith('.json') && !f.startsWith('restore-'))) {
      try {
        const data = JSON.parse(fs.readFileSync(path.join(BOCCHI_DIR, file), 'utf8'));
        const items = Array.isArray(data) ? data : (data.items || []);
        for (const item of items) {
          const u = item.url || item.arcurl || item.html_url || '';
          if (u && !u.includes('javascript:') && !u.startsWith('http://localhost')) urls.add(u);
        }
      } catch (e) {}
    }
  }
  return urls;
}

const existingUrls = buildExistingUrlSet();
console.log(`Existing unique URLs loaded: ${existingUrls.size}`);

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function main() {
  const browser = await chromium.launch();
  const context = await browser.newContext({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' });
  const page = await context.newPage();

  const targets = [
    { url: 'https://bocchi-the-rock.fandom.com/wiki/Bocchi_the_Rock!_Wiki', name: 'fandom-main' },
    { url: 'https://bocchi-the-rock.fandom.com/wiki/Category:Characters', name: 'fandom-characters' },
    { url: 'https://bocchi-the-rock.fandom.com/wiki/Category:Episodes', name: 'fandom-episodes' },
    { url: 'https://bocchi-the-rock.fandom.com/wiki/Category:Music', name: 'fandom-music' },
    { url: 'https://bocchi-the-rock.fandom.com/wiki/Category:Merchandise', name: 'fandom-merchandise' },
    { url: 'https://bocchi-the-rock.fandom.com/wiki/Category:Collaborations', name: 'fandom-collabs' },
  ];

  for (const t of targets) {
    const outFile = path.join(BOCCHI_DIR, `restore-${t.name}.json`);
    if (fs.existsSync(outFile)) {
      console.log(`Skipping ${t.name}, restore file exists`);
      continue;
    }
    await page.goto(t.url, { waitUntil: 'domcontentloaded', timeout: 20000 });
    await page.waitForTimeout(2000);
    const links = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('a')).filter(a =>
        a.href && !a.href.includes('javascript:') && a.textContent.trim().length > 3
      ).map(a => ({
        text: a.textContent.trim().slice(0, 120),
        href: a.href
      })).slice(0, 300);
    });
    const filtered = links.filter(l => !existingUrls.has(l.href));
    const items = filtered.map(l => ({ source: t.name, text: l.text, url: l.href }));
    fs.writeFileSync(outFile, JSON.stringify({ items }, null, 2));
    console.log(`${t.name}: ${links.length} raw, ${filtered.length} new -> restore-${t.name}.json`);
    await sleep(1000);
  }

  await browser.close();
  console.log('Restore complete');
}

main().catch(e => { console.error(e); process.exit(1); });

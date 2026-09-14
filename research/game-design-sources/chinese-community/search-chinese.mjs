import { chromium } from 'playwright';
import fs from 'fs';

const searches = [
  { name: 'bilibili-独立游戏', url: 'https://search.bilibili.com/all?keyword=%E7%8B%AC%E7%AB%8B%E6%B8%B8%E6%88%8F' },
  { name: 'bilibili-游戏设计', url: 'https://search.bilibili.com/all?keyword=%E6%B8%B8%E6%88%8F%E8%AE%BE%E8%AE%A1' },
  { name: 'bilibili-NPC设计', url: 'https://search.bilibili.com/all?keyword=NPC%E8%AE%BE%E8%AE%A1' },
  { name: 'bilibili-治愈系游戏', url: 'https://search.bilibili.com/all?keyword=%E6%B2%BB%E6%84%88%E7%B3%BB%E6%B8%B8%E6%88%8F' },
  { name: 'bilibili-互动叙事', url: 'https://search.bilibili.com/all?keyword=%E4%BA%92%E5%8A%A8%E5%8F%99%E4%BA%8B' },
  { name: 'bilibili-Tripo', url: 'https://search.bilibili.com/all?keyword=Tripo' },
  { name: 'bilibili-TapTap Maker', url: 'https://search.bilibili.com/all?keyword=TapTap+Maker' },
  { name: 'bilibili-itch.io', url: 'https://search.bilibili.com/all?keyword=itch.io' },
  { name: 'zhihu-独立游戏', url: 'https://www.zhihu.com/search?type=content&q=%E7%8B%AC%E7%AB%8B%E6%B8%B8%E6%88%8F' },
  { name: 'zhihu-游戏设计', url: 'https://www.zhihu.com/search?type=content&q=%E6%B8%B8%E6%88%8F%E8%AE%BE%E8%AE%A1' },
  { name: 'zhihu-NPC', url: 'https://www.zhihu.com/search?type=content&q=NPC%E8%AE%BE%E8%AE%A1' },
  { name: 'zhihu-叙事设计', url: 'https://www.zhihu.com/search?type=content&q=%E5%8F%99%E4%BA%8B%E8%AE%BE%E8%AE%A1' },
  { name: 'zhihu-情感化设计', url: 'https://www.zhihu.com/search?type=content&q=%E6%83%85%E6%84%9F%E5%8C%96%E6%B8%B8%E6%88%8F' },
  { name: 'zhihu-3D游戏开发', url: 'https://www.zhihu.com/search?type=content&q=3D%E6%B8%B8%E6%88%8F%E5%BC%80%E5%8F%91' },
  { name: 'indienova-搜索', url: 'https://indienova.com/search?q=%E6%B8%B8%E6%88%8F' },
  { name: 'indienova-设计', url: 'https://indienova.com/search?q=%E8%AE%BE%E8%AE%A1' },
  { name: 'indienova-NPC', url: 'https://indienova.com/search?q=NPC' },
  { name: 'nga-独立游戏', url: 'https://nga.cn/app/search.php?q=%E7%8B%AC%E7%AB%8B%E6%B8%B8%E6%88%8F' },
  { name: 'nga-游戏设计', url: 'https://nga.cn/app/search.php?q=%E6%B8%B8%E6%88%8F%E8%AE%BE%E8%AE%A1' },
  { name: 'gcores-游戏设计', url: 'https://www.gcores.com/search?q=%E6%B8%B8%E6%88%8F%E8%AE%BE%E8%AE%A1' },
  { name: 'gcores-独立游戏', url: 'https://www.gcores.com/search?q=%E7%8B%AC%E7%AB%8B%E6%B8%B8%E6%88%8F' },
  { name: 'taptap-开发者', url: 'https://www.taptap.cn/developers/search?q=%E6%B8%B8%E6%88%8F' }
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

fs.writeFileSync('chinese-community-results.json', JSON.stringify(results, null, 2));
await browser.close();
console.log('Chinese community search completed');

import fs from 'fs';
import path from 'path';

const audit = JSON.parse(fs.readFileSync('unique-url-audit.json', 'utf8'));
const count = JSON.parse(fs.readFileSync('source-summary.json', 'utf8'));

const baselineUnique = 6168;
const baselineTotal = 17946;

const netNewUnique = audit.total_unique - baselineUnique;
const netNewTotal = count.total - baselineTotal;

console.log('=== Final Research Summary ===');
console.log(`Total source count: ${count.total}`);
console.log(`Total unique URLs : ${audit.total_unique}`);
console.log(`Baseline unique   : ${baselineUnique}`);
console.log(`Net new unique    : ${netNewUnique}`);
console.log(`Baseline total    : ${baselineTotal}`);
console.log(`Net new total     : ${netNewTotal}`);
console.log('---');

// Top domains
const domainCount = {};
for (const u of audit.sample || []) {
  try {
    const host = new URL(u).hostname;
    domainCount[host] = (domainCount[host] || 0) + 1;
  } catch (e) {}
}
const topDomains = Object.entries(domainCount)
  .sort((a, b) => b[1] - a[1])
  .slice(0, 20);
console.log('Top domains (from sample):');
for (const [d, c] of topDomains) {
  console.log(`  ${d}: ${c}`);
}

// Save final summary
fs.writeFileSync('final-research-summary.json', JSON.stringify({
  total_sources: count.total,
  total_unique_urls: audit.total_unique,
  baseline_unique_urls: baselineUnique,
  net_new_unique_urls: netNewUnique,
  baseline_total_sources: baselineTotal,
  net_new_total_sources: netNewTotal,
  breakdown: audit.breakdown,
  top_domains_sample: topDomains
}, null, 2));
console.log('\nSaved final-research-summary.json');

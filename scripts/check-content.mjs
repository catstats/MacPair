import assert from 'node:assert/strict';
import fs from 'node:fs';

const page = fs.readFileSync('src/components/macpair/MacPairPage.astro', 'utf8');
const copy = fs.readFileSync('src/data/copy.ts', 'utf8').replace(/\s+/g, ' ');
const layout = fs.readFileSync('src/layouts/Layout.astro', 'utf8');
assert(
  fs.readFileSync('src/data/product.ts', 'utf8').includes("github: 'https://github.com/catstats/MacPair'") &&
    page.includes('href={product.github}'),
  'Link to the verified public MacPair repository'
);
assert(
  fs.readFileSync('public/robots.txt', 'utf8').includes('Allow: /') &&
    !copy.includes('A public GitHub repository has not been published yet'),
  'Keep the public release accessible and remove the unpublished-repository placeholder'
);
assert(
  copy.includes('Standalone operation') &&
    copy.includes('two-Mac retest') &&
    copy.includes('独立运行仍未确认') &&
    copy.includes('两台真实 Mac 上复测'),
  'Keep the actual prototype verification limits in both languages'
);
for (const file of [
  'public/screenshots/macpair-host-0.1.9.png',
  'public/screenshots/macpair-display-0.1.9.png',
  'public/screenshots/macpair-host-0.1.9-zh.png',
  'public/screenshots/macpair-display-0.1.9-zh.png',
]) {
  assert(fs.statSync(file).size > 1000, file + ' is missing or empty');
}
const product = fs.readFileSync('src/data/product.ts', 'utf8');
for (const file of ['MacPair-0.1.9.zip', 'MacPair-0.1.9-source.zip']) {
  assert(
    product.includes('https://github.com/catstats/MacPair/releases/download/v0.1.9/' + file),
    'Downloads must use the verified GitHub Release, independently of the website host'
  );
}

assert.deepEqual(
  fs.readdirSync('src/pages').sort(),
  ['404.astro', 'index.astro', 'zh'],
  'Do not ship AstroWind demo/blog/pricing routes'
);
assert.deepEqual(fs.readdirSync('src/pages/zh'), ['index.astro'], 'Keep the Chinese site focused');
assert(fs.readFileSync('src/pages/index.astro', 'utf8').includes('locale="en"'));
assert(fs.readFileSync('src/pages/zh/index.astro', 'utf8').includes('locale="zh-CN"'));
assert(
  layout.includes('<html lang={t.lang}>') && layout.includes('hreflang="zh-CN"'),
  'Localize page language and alternate links'
);
assert(page.includes('data-language-switch'), 'Keep an explicit language switch');
console.log('PASS: bilingual routes, actual release and screenshots, verification notes and language metadata');

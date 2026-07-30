// Kiem tra asset da fan-out ra tung nen tang.
// Chay: node assets/branding/verify.mjs
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { pngMeta, decodeRgba, hasAnyTransparent } from './pnginfo.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const failures = [];

function check(label, fn) {
  try {
    fn();
    console.log(`  OK    ${label}`);
  } catch (err) {
    failures.push(`${label}: ${err.message}`);
    console.log(`  FAIL  ${label} -- ${err.message}`);
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

console.log('Android:');

const MIPMAPS = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
for (const [dpi, size] of Object.entries(MIPMAPS)) {
  check(`mipmap-${dpi}/ic_launcher.png la ${size}x${size}`, () => {
    const p = join(ROOT, 'android/app/src/main/res', `mipmap-${dpi}`, 'ic_launcher.png');
    assert(existsSync(p), 'khong ton tai');
    const m = pngMeta(p);
    assert(m.width === size && m.height === size, `gap ${m.width}x${m.height}`);
  });
}

check('mipmap-anydpi-v26/ic_launcher.xml khai bao du 3 layer', () => {
  const p = join(ROOT, 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml');
  assert(existsSync(p), 'khong ton tai — Android se im lang tut ve icon legacy');
  const xml = readFileSync(p, 'utf8');
  for (const layer of ['background', 'foreground', 'monochrome']) {
    assert(xml.includes(`<${layer}`), `thieu the <${layer}>`);
  }
});

console.log('iOS:');

const ICONSET = join(ROOT, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');

check('moi file khai bao trong Contents.json deu ton tai', () => {
  const contents = JSON.parse(readFileSync(join(ICONSET, 'Contents.json'), 'utf8'));
  const names = contents.images.map((i) => i.filename).filter(Boolean);
  assert(names.length > 0, 'Contents.json khong khai bao file nao');
  const missing = names.filter((n) => !existsSync(join(ICONSET, n)));
  assert(missing.length === 0, `thieu ${missing.join(', ')}`);
});

check('icon 1024x1024 khong co kenh alpha trong suot', () => {
  const p = join(ICONSET, 'Icon-App-1024x1024@1x.png');
  assert(existsSync(p), 'khong ton tai');
  const m = pngMeta(p);
  assert(m.width === 1024 && m.height === 1024, `gap ${m.width}x${m.height}`);
  assert(
    !hasAnyTransparent(decodeRgba(p)),
    'con pixel trong suot — App Store Connect se tu choi binary',
  );
});

console.log('Web:');

for (const rel of ['web/favicon.png', 'web/icons/Icon-192.png', 'web/icons/Icon-512.png']) {
  check(`${rel} ton tai`, () => {
    assert(existsSync(join(ROOT, rel)), 'khong ton tai');
  });
}

console.log('');
if (failures.length > 0) {
  console.error(`${failures.length} muc that bai.`);
  process.exit(1);
}
console.log('Tat ca kiem tra deu dat.');

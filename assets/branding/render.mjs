// Render cac layer SVG thanh PNG 1024x1024 bang Chrome headless.
// Chay: node assets/branding/render.mjs
import { readFileSync, writeFileSync, mkdirSync, existsSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, 'generated');
const TMP = join(HERE, '.render-tmp');
const ANDROID_RES = join(HERE, '..', '..', 'android', 'app', 'src', 'main', 'res');
const SIZE = 1024;

export const LAYERS = ['icon_full', 'icon_foreground', 'icon_background', 'icon_monochrome'];

/// Icon thong bao Android: 24dp, fan-out ra tung mat do man hinh. Khac cac
/// layer o tren, no di thang vao res/ chu khong qua flutter_launcher_icons —
/// package do chi sinh launcher icon.
export const NOTIFICATION_ICON = 'ic_stat_aegis';
export const NOTIFICATION_DENSITIES = {
  mdpi: 24,
  hdpi: 36,
  xhdpi: 48,
  xxhdpi: 72,
  xxxhdpi: 96,
};

function findChrome() {
  const candidates = [
    process.env.CHROME_PATH,
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
  ].filter(Boolean);

  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  throw new Error(
    'Khong tim thay Chrome hoac Edge. Dat bien moi truong CHROME_PATH tro toi chrome.exe roi chay lai.',
  );
}

// Boc SVG vao HTML kich thuoc co dinh. Render thang file .svg se de bi Chrome
// tu can le / scale theo mac dinh cua trinh duyet.
function wrap(svgSource, size) {
  return `<!doctype html>
<meta charset="utf-8">
<style>
  html, body { margin: 0; padding: 0; background: transparent; }
  svg { display: block; width: ${size}px; height: ${size}px; }
</style>
${svgSource}`;
}

/// Chup mot SVG ra PNG kich thuoc [size]. Chrome la cong cu render duy nhat o
/// day, nen moi duong deu di qua ham nay.
function shoot(chrome, svgName, outPath, size, tag) {
  const svgPath = join(HERE, `${svgName}.svg`);
  if (!existsSync(svgPath)) throw new Error(`Thieu file nguon: ${svgPath}`);

  const htmlPath = join(TMP, `${svgName}-${size}.html`);
  writeFileSync(htmlPath, wrap(readFileSync(svgPath, 'utf8'), size), 'utf8');

  execFileSync(
    chrome,
    [
      '--headless',
      '--disable-gpu',
      '--hide-scrollbars',
      `--user-data-dir=${join(TMP, 'profile')}`,
      `--window-size=${size},${size}`,
      '--force-device-scale-factor=1',
      '--default-background-color=00000000',
      `--screenshot=${outPath}`,
      pathToFileURL(htmlPath).href,
    ],
    { stdio: 'pipe' },
  );

  if (!existsSync(outPath)) {
    throw new Error(`Chrome khong tao duoc ${outPath}. Thu dat CHROME_PATH sang trinh duyet khac.`);
  }
  console.log(`OK  ${tag}`);
}

export function renderAll() {
  const chrome = findChrome();
  mkdirSync(OUT, { recursive: true });
  mkdirSync(TMP, { recursive: true });

  for (const name of LAYERS) {
    shoot(chrome, name, join(OUT, `${name}.png`), SIZE, `${name}.png`);
  }

  for (const [dpi, size] of Object.entries(NOTIFICATION_DENSITIES)) {
    const dir = join(ANDROID_RES, `drawable-${dpi}`);
    mkdirSync(dir, { recursive: true });
    shoot(
      chrome,
      'icon_notification',
      join(dir, `${NOTIFICATION_ICON}.png`),
      size,
      `drawable-${dpi}/${NOTIFICATION_ICON}.png (${size}px)`,
    );
  }

  // Chrome tren Windows co the con giu lock tren user-data-dir mot luc sau khi
  // thoat, khien rmSync nem EBUSY. Don dep that bai khong phai la loi render.
  try {
    rmSync(TMP, { recursive: true, force: true });
  } catch {
    console.log(`(Khong xoa duoc thu muc tam ${TMP} — bo qua, da duoc gitignore.)`);
  }
}

renderAll();

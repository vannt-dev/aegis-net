import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { pngMeta, decodeRgba, alphaAt, hasAnyTransparent } from './pnginfo.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const GEN = join(HERE, 'generated');

const SIZE = 1024;
const CENTER = 512;
const SAFE_RADIUS = 312; // 66/108 cua canvas, xem spec 3.4

const TRANSPARENT_BG = ['icon_foreground', 'icon_monochrome'];
const OPAQUE = ['icon_full', 'icon_background'];
const ALL = [...OPAQUE, ...TRANSPARENT_BG];

test('ca 4 layer deu ton tai o dung 1024x1024', () => {
  for (const name of ALL) {
    const p = join(GEN, `${name}.png`);
    assert.ok(
      existsSync(p),
      `Thieu file ${name}.png — da chay "node assets/branding/render.mjs" chua?`,
    );
    const m = pngMeta(p);
    assert.equal(m.width, SIZE, `${name}.png sai chieu rong`);
    assert.equal(m.height, SIZE, `${name}.png sai chieu cao`);
  }
});

test('layer foreground va monochrome co goc trong suot', () => {
  for (const name of TRANSPARENT_BG) {
    const img = decodeRgba(join(GEN, `${name}.png`));
    for (const [x, y] of [
      [0, 0],
      [SIZE - 1, 0],
      [0, SIZE - 1],
      [SIZE - 1, SIZE - 1],
    ]) {
      assert.equal(
        alphaAt(img, x, y),
        0,
        `${name}.png co goc (${x},${y}) khong trong suot — Chrome da chen nen trang?`,
      );
    }
  }
});

test('layer full va background duc hoan toan', () => {
  for (const name of OPAQUE) {
    const img = decodeRgba(join(GEN, `${name}.png`));
    assert.equal(hasAnyTransparent(img), false, `${name}.png con pixel trong suot`);
  }
});

test('monochrome nam gon trong safe zone 312px', () => {
  const img = decodeRgba(join(GEN, 'icon_monochrome.png'));
  const limitSq = SAFE_RADIUS * SAFE_RADIUS;
  let worstSq = 0;
  let worstAt = null;

  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) {
      if (alphaAt(img, x, y) === 0) continue;
      const dx = x - CENTER;
      const dy = y - CENTER;
      const dSq = dx * dx + dy * dy;
      if (dSq > worstSq) {
        worstSq = dSq;
        worstAt = [x, y];
      }
    }
  }

  assert.ok(
    worstSq <= limitSq,
    `Pixel xa nhat (${worstAt}) cach tam ${Math.sqrt(worstSq).toFixed(1)}px, vuot safe zone ${SAFE_RADIUS}px`,
  );
});

test('monochrome la anh don sac trang', () => {
  const img = decodeRgba(join(GEN, 'icon_monochrome.png'));
  for (let i = 0; i < img.data.length; i += 4) {
    if (img.data[i + 3] === 0) continue;
    assert.equal(img.data[i], 255, 'monochrome phai la mau trang thuan');
    assert.equal(img.data[i + 1], 255, 'monochrome phai la mau trang thuan');
    assert.equal(img.data[i + 2], 255, 'monochrome phai la mau trang thuan');
  }
});

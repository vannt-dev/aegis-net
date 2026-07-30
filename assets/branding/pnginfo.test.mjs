import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { pngMeta, decodeRgba, hasAnyTransparent, alphaAt } from './pnginfo.mjs';

const SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}

// rawScanlines: buffer da bao gom byte filter dau moi dong.
function assemblePng(width, height, rawScanlines) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type RGBA
  return Buffer.concat([
    SIG,
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(rawScanlines)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// Moi dong dung filter 0 (None).
function makePng(width, height, pixelFn) {
  const raw = Buffer.alloc(height * (1 + width * 4));
  let p = 0;
  for (let y = 0; y < height; y++) {
    raw[p++] = 0;
    for (let x = 0; x < width; x++) {
      const [r, g, b, a] = pixelFn(x, y);
      raw[p++] = r;
      raw[p++] = g;
      raw[p++] = b;
      raw[p++] = a;
    }
  }
  return assemblePng(width, height, raw);
}

const DIR = mkdtempSync(join(tmpdir(), 'pnginfo-'));
function writeTemp(name, buf) {
  const p = join(DIR, name);
  writeFileSync(p, buf);
  return p;
}

test('pngMeta doc dung kich thuoc va color type', () => {
  const p = writeTemp('meta.png', makePng(7, 3, () => [1, 2, 3, 255]));
  const m = pngMeta(p);
  assert.equal(m.width, 7);
  assert.equal(m.height, 3);
  assert.equal(m.bitDepth, 8);
  assert.equal(m.colorType, 6);
  assert.equal(m.interlace, 0);
});

test('decodeRgba tra ve dung gia tri pixel', () => {
  const p = writeTemp(
    'pixels.png',
    makePng(2, 2, (x, y) => [x * 10, y * 20, 30, x === y ? 255 : 0]),
  );
  const img = decodeRgba(p);
  assert.equal(img.width, 2);
  assert.equal(img.height, 2);
  assert.deepEqual([...img.data.slice(0, 4)], [0, 0, 30, 255]); // (0,0)
  assert.deepEqual([...img.data.slice(4, 8)], [10, 0, 30, 0]); // (1,0)
  assert.equal(alphaAt(img, 1, 1), 255);
  assert.equal(alphaAt(img, 0, 1), 0);
});

test('decodeRgba go dung filter type 2 (Up)', () => {
  // Dong 0: filter None, pixel (10,20,30,40).
  // Dong 1: filter Up, delta (5,5,5,5) -> ket qua phai la (15,25,35,45).
  const raw = Buffer.from([0, 10, 20, 30, 40, 2, 5, 5, 5, 5]);
  const p = writeTemp('up.png', assemblePng(1, 2, raw));
  const img = decodeRgba(p);
  assert.deepEqual([...img.data.slice(0, 4)], [10, 20, 30, 40]);
  assert.deepEqual([...img.data.slice(4, 8)], [15, 25, 35, 45]);
});

test('hasAnyTransparent phan biet dung anh duc va anh co alpha', () => {
  const opaque = writeTemp('opaque.png', makePng(3, 3, () => [0, 0, 0, 255]));
  const holed = writeTemp('holed.png', makePng(3, 3, (x) => [0, 0, 0, x === 1 ? 0 : 255]));
  assert.equal(hasAnyTransparent(decodeRgba(opaque)), false);
  assert.equal(hasAnyTransparent(decodeRgba(holed)), true);
});

test('decodeRgba bao loi ro rang voi file khong phai PNG', () => {
  const p = writeTemp('bad.bin', Buffer.from('day khong phai png'));
  assert.throws(() => decodeRgba(p), /khong phai file PNG/i);
});

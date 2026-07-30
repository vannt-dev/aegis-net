// Doc PNG bang thu vien chuan cua Node. Chi ho tro dung tap con ma Chrome
// headless xuat ra: bit depth 8, khong interlace, color type 2 (RGB) hoac 6 (RGBA).
import { readFileSync } from 'node:fs';
import { inflateSync } from 'node:zlib';

const SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function readChunks(buf, filePath) {
  if (buf.length < 8 || !buf.subarray(0, 8).equals(SIG)) {
    throw new Error(`Khong phai file PNG hop le: ${filePath}`);
  }
  const chunks = [];
  let off = 8;
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('ascii', off + 4, off + 8);
    chunks.push({ type, data: buf.subarray(off + 8, off + 8 + len) });
    off += 12 + len;
    if (type === 'IEND') break;
  }
  return chunks;
}

export function pngMeta(filePath) {
  const chunks = readChunks(readFileSync(filePath), filePath);
  const ihdr = chunks.find((c) => c.type === 'IHDR');
  if (!ihdr) throw new Error(`Thieu chunk IHDR: ${filePath}`);
  return {
    width: ihdr.data.readUInt32BE(0),
    height: ihdr.data.readUInt32BE(4),
    bitDepth: ihdr.data[8],
    colorType: ihdr.data[9],
    interlace: ihdr.data[12],
  };
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

export function decodeRgba(filePath) {
  const buf = readFileSync(filePath);
  const chunks = readChunks(buf, filePath);
  const meta = pngMeta(filePath);

  if (meta.bitDepth !== 8) {
    throw new Error(`Chi ho tro bit depth 8, gap ${meta.bitDepth}: ${filePath}`);
  }
  if (meta.interlace !== 0) {
    throw new Error(`Khong ho tro PNG interlaced: ${filePath}`);
  }
  if (meta.colorType !== 2 && meta.colorType !== 6) {
    throw new Error(`Chi ho tro color type 2 hoac 6, gap ${meta.colorType}: ${filePath}`);
  }

  const bpp = meta.colorType === 6 ? 4 : 3;
  const idat = chunks.filter((c) => c.type === 'IDAT').map((c) => c.data);
  if (idat.length === 0) throw new Error(`Thieu chunk IDAT: ${filePath}`);
  const raw = inflateSync(Buffer.concat(idat));

  const stride = meta.width * bpp;
  const out = new Uint8Array(meta.width * meta.height * 4);
  let prev = Buffer.alloc(stride);
  let pos = 0;

  for (let y = 0; y < meta.height; y++) {
    const ft = raw[pos++];
    const line = Buffer.from(raw.subarray(pos, pos + stride));
    pos += stride;

    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? line[i - bpp] : 0;
      const b = prev[i];
      const c = i >= bpp ? prev[i - bpp] : 0;
      let v = line[i];
      if (ft === 1) v += a;
      else if (ft === 2) v += b;
      else if (ft === 3) v += (a + b) >> 1;
      else if (ft === 4) v += paeth(a, b, c);
      else if (ft !== 0) {
        throw new Error(`Filter type ${ft} khong hop le tai dong ${y}: ${filePath}`);
      }
      line[i] = v & 0xff;
    }

    for (let x = 0; x < meta.width; x++) {
      const s = x * bpp;
      const d = (y * meta.width + x) * 4;
      out[d] = line[s];
      out[d + 1] = line[s + 1];
      out[d + 2] = line[s + 2];
      out[d + 3] = bpp === 4 ? line[s + 3] : 255;
    }
    prev = line;
  }

  return { width: meta.width, height: meta.height, data: out };
}

export function alphaAt(img, x, y) {
  return img.data[(y * img.width + x) * 4 + 3];
}

export function hasAnyTransparent(img) {
  for (let i = 3; i < img.data.length; i += 4) {
    if (img.data[i] !== 255) return true;
  }
  return false;
}

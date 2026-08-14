// Generate a 1024x1024 app icon (dark rounded square + cyan ring & dot),
// written as raw PNG using only Node built-ins (zlib).
import zlib from 'node:zlib';
import fs from 'node:fs';

const SIZE = 1024;
const rgba = new Uint8Array(SIZE * SIZE * 4);

const cx = SIZE / 2, cy = SIZE / 2;
const R_OUT = 430, R_IN = 330, DOT_R = 95;
const CORNER = 185;
const BG_TOP = [13, 20, 32], BG_BOT = [26, 38, 58];
const ACCENT = [70, 205, 255];

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

for (let y = 0; y < SIZE; y++) {
  const dy = y - cy + 0.5;
  const t = y / (SIZE - 1);
  const bg = [
    BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t,
    BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t,
    BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t,
  ];
  for (let x = 0; x < SIZE; x++) {
    const dx = x - cx + 0.5;
    const d = Math.hypot(dx, dy);

    // rounded-rect coverage
    const hx = SIZE / 2 - CORNER, hy = SIZE / 2 - CORNER;
    const qx = Math.max(Math.abs(dx) - hx, 0), qy = Math.max(Math.abs(dy) - hy, 0);
    const rectCov = clamp01(CORNER - Math.hypot(qx, qy) + 0.5);

    // ring coverage (smooth 1px edges) + center dot
    const ringCov = clamp01(d - R_IN + 0.5) * clamp01(R_OUT - d + 0.5);
    const dotCov = clamp01(DOT_R - d + 0.5);

    const cov = Math.min(1, rectCov);
    const accentCov = Math.min(1, ringCov + dotCov);
    const r = bg[0] + (ACCENT[0] - bg[0]) * accentCov;
    const g = bg[1] + (ACCENT[1] - bg[1]) * accentCov;
    const b = bg[2] + (ACCENT[2] - bg[2]) * accentCov;

    const i = (y * SIZE + x) * 4;
    rgba[i] = Math.round(r);
    rgba[i + 1] = Math.round(g);
    rgba[i + 2] = Math.round(b);
    rgba[i + 3] = Math.round(255 * cov);
  }
}

// --- PNG encoder ---------------------------------------------------------------
function crc32(buf) {
  let table = crc32.table;
  if (!table) {
    table = crc32.table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c;
    }
  }
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = table[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const t = Buffer.from(type, 'ascii');
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([t, data])));
  return Buffer.concat([len, t, data, crcBuf]);
}
function encodePNG(w, h, px) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  const stride = w * 4;
  const raw = Buffer.alloc((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    Buffer.from(px.buffer, y * stride, stride).copy(raw, y * (stride + 1) + 1);
  }
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

const out = process.argv[2];
fs.writeFileSync(out, encodePNG(SIZE, SIZE, rgba));
console.log('wrote', out, encodePNG.length, 'bytes');

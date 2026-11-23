#!/usr/bin/env node
// 《王国余烬》战场地面纹理烘焙：64px 像素瓷砖（草地/土路/塔位基座/路缘）。
// 种子噪声 + 手工色板，暗黑幻想调，与单位色系一致。
//   node tools/bake_ground.mjs
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdirSync, writeFileSync } from "node:fs";
import zlib from "node:zlib";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "assets", "ground");
mkdirSync(OUT, { recursive: true });

// ---- PNG 编码 ----
const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
  return t;
})();
const crc32 = (b) => { let c = 0xffffffff; for (let i = 0; i < b.length; i++) c = CRC[(c ^ b[i]) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
function chunk(type, data) {
  const len = Buffer.alloc(4), crc = Buffer.alloc(4), t = Buffer.from(type, "ascii");
  len.writeUInt32BE(data.length); crc.writeUInt32BE(crc32(Buffer.concat([t, data])));
  return Buffer.concat([len, t, data, crc]);
}
function png(w, h, px) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) Buffer.from(px.buffer, px.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}
const hex = (s) => [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16), 255];
function mulberry(seed) { return () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

function tile(w, h, seed, base, paint) {
  const px = new Uint8ClampedArray(w * h * 4), rnd = mulberry(seed);
  const B = hex(base);
  for (let i = 0; i < w * h; i++) px.set(B, i * 4);
  paint(px, w, h, rnd);
  return png(w, h, px);
}
const speck = (px, w, h, rnd, colors, density) => {
  const n = Math.round(w * h * density);
  for (let i = 0; i < n; i++) {
    const x = (rnd() * w) | 0, y = (rnd() * h) | 0;
    px.set(hex(colors[(rnd() * colors.length) | 0]), (y * w + x) * 4);
  }
};

// 草地：苔绿底 + 草叶 + 暗斑
writeFileSync(join(OUT, "grass.png"), tile(64, 64, 11, "#232a22", (px, w, h, rnd) => {
  speck(px, w, h, rnd, ["#1e241d", "#272f26", "#20261f"], 0.10);
  for (let i = 0; i < 46; i++) {
    const x = (rnd() * w) | 0, y = (rnd() * h) | 0;
    const c = rnd() < 0.5 ? "#2c3629" : "#31402e";
    px.set(hex(c), (y * w + x) * 4);
    if (rnd() < 0.6 && y > 0) px.set(hex(c), ((y - 1) * w + x) * 4);
  }
  for (let i = 0; i < 5; i++) {
    const cx = rnd() * w, cy = rnd() * h, r = 4 + rnd() * 6;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const dx = Math.min(Math.abs(x - cx), w - Math.abs(x - cx)), dy = y - cy;
      if (dx * dx * 0.4 + dy * dy < r * r && rnd() < 0.5) px.set(hex("#1d231c"), (y * w + x) * 4);
    }
  }
}));

// 土路：暖土底 + 碎石 + 车辙暗纹
writeFileSync(join(OUT, "path.png"), tile(64, 64, 23, "#382e22", (px, w, h, rnd) => {
  speck(px, w, h, rnd, ["#2f271d", "#403526", "#332a20"], 0.12);
  for (let i = 0; i < 3; i++) {
    const y0 = 12 + i * 18 + ((rnd() * 6) | 0);
    for (let x = 0; x < w; x++) {
      const y = (y0 + ((rnd() * 2) | 0)) % h;
      if (rnd() < 0.75) px.set(hex("#2c241b"), (y * w + x) * 4);
    }
  }
  for (let i = 0; i < 14; i++) {
    const x = (rnd() * w) | 0, y = (rnd() * h) | 0, c = rnd() < 0.5 ? "#4d4536" : "#5a5142";
    px.set(hex(c), (y * w + x) * 4);
    if (rnd() < 0.5) px.set(hex(c), (y * w + Math.min(w - 1, x + 1)) * 4);
  }
}));

// 塔位基座：石板圆盘 44×44
{
  const w = 44, h = 44, px = new Uint8ClampedArray(w * h * 4), rnd = mulberry(31);
  for (let i = 0; i < w * h; i++) px.set([0, 0, 0, 0], i * 4);
  const cx = 21.5, cy = 21.5, R = 20;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const d = Math.hypot(x - cx, y - cy);
    if (d > R) continue;
    let c = "#3a3f4b";
    if (d > R - 2.2) c = "#23272f";
    else if (d > R - 3.4) c = "#4a505e";
    else if ((x + y) % 7 === 0 && rnd() < 0.5) c = "#343945";
    px.set(hex(c), (y * w + x) * 4);
  }
  for (const [bx, by] of [[8, 8], [34, 8], [8, 34], [34, 34]]) {
    px.set(hex("#565d6b"), (by * w + bx) * 4);
    px.set(hex("#6a7180"), (by * w + bx + 1) * 4);
  }
  writeFileSync(join(OUT, "slot.png"), png(w, h, px));
}

// 路缘石窄条 64×10
writeFileSync(join(OUT, "path_edge.png"), tile(64, 10, 47, "#232a22", (px, w, h, rnd) => {
  for (let x = 0; x < w; x++) {
    if (rnd() < 0.45) { const y = 2 + ((rnd() * 2) | 0); px.set(hex(rnd() < 0.5 ? "#453e30" : "#50483a"), (y * w + x) * 4); }
    if (rnd() < 0.3) { const y = 5 + ((rnd() * 3) | 0); px.set(hex("#2c241b"), (y * w + x) * 4); }
  }
}));

console.log("ground tiles ->", OUT);

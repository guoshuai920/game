#!/usr/bin/env node
// 《王国余烬》音效合成器：纯手写波形 → assets/sfx/*.wav + index.json。
// 复古芯片风：方波/锯齿滑音、噪声爆、ADSR 包络；环境音为低频锯齿堆叠加缓慢呼吸。
//   node tools/gen_sfx.mjs
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdirSync, writeFileSync } from "node:fs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const OUT = join(ROOT, "assets", "sfx");
mkdirSync(OUT, { recursive: true });

const RATE = 22050;

// ---------- 合成基元 ----------
const sec = (n) => Math.round(n * RATE);
function osc(type, f0, f1, dur, { vol = 1, vib = 0, vibHz = 6, duty = 0.5 } = {}) {
  const n = sec(dur), out = new Float32Array(n);
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const k = i / n;
    const f = f0 + (f1 - f0) * k + Math.sin(2 * Math.PI * vibHz * k) * vib;
    ph += f / RATE;
    const x = ph % 1;
    let v;
    if (type === "square") v = x < duty ? 1 : -1;
    else if (type === "saw") v = 2 * x - 1;
    else if (type === "tri") v = 4 * Math.abs(x - 0.5) - 1;
    else v = Math.sin(2 * Math.PI * x);
    out[i] = v * vol;
  }
  return out;
}
function noise(dur, { vol = 1, lp = 1, seed = 1 } = {}) {
  const n = sec(dur), out = new Float32Array(n);
  let s = seed * 9301, y = 0;
  for (let i = 0; i < n; i++) {
    s = (s * 9301 + 49297) % 233280;
    const w = (s / 233280) * 2 - 1;
    y += lp * (w - y); // 一阶低通，lp∈(0,1] 越小越闷
    out[i] = y * vol;
  }
  return out;
}
function env(x, { a = 0.005, r = 0.08, curve = 2 } = {}) {
  const nA = sec(a), nR = sec(r), n = x.length;
  for (let i = 0; i < n; i++) {
    let g = 1;
    if (i < nA) g = i / nA;
    const tail = n - i;
    if (tail < nR) g *= Math.pow(tail / nR, curve);
    x[i] *= g;
  }
  return x;
}
function mix(...layers) {
  const n = Math.max(...layers.map((l) => l.buf.length));
  const out = new Float32Array(n);
  for (const { buf, gain = 1, at = 0 } of layers) {
    const off = sec(at);
    for (let i = 0; i < buf.length && off + i < n; i++) out[off + i] += buf[i] * gain;
  }
  return out;
}
function normalize(x, peak = 0.6) {
  let m = 0;
  for (const v of x) m = Math.max(m, Math.abs(v));
  if (m > 0) for (let i = 0; i < x.length; i++) x[i] *= peak / m;
  return x;
}
function wav(x) {
  const n = x.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write("RIFF", 0);
  buf.writeUInt32LE(36 + n * 2, 4);
  buf.write("WAVEfmt ", 8);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20); // PCM
  buf.writeUInt16LE(1, 22); // mono
  buf.writeUInt32LE(RATE, 24);
  buf.writeUInt32LE(RATE * 2, 28);
  buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34);
  buf.write("data", 36);
  buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) buf.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(x[i] * 32767))), 44 + i * 2);
  return buf;
}
const NOTE = (p) => 440 * Math.pow(2, (p - 69) / 12); // MIDI → Hz

// ---------- 音色表 ----------
const SFX = {};

// UI / 流程
SFX.ui_click = () => env(mix({ buf: osc("square", 1100, 880, 0.05, { vol: 0.5 }) }), { r: 0.03 });
SFX.build = () => env(mix(
  { buf: osc("tri", NOTE(52), NOTE(59), 0.16, { vol: 0.7 }) },
  { buf: osc("square", NOTE(71), NOTE(76), 0.1, { vol: 0.25 }), at: 0.05 },
), { r: 0.1 });
SFX.sell = () => env(mix(
  { buf: osc("square", NOTE(76), NOTE(71), 0.07, { vol: 0.4 }) },
  { buf: osc("square", NOTE(71), NOTE(64), 0.09, { vol: 0.4 }), at: 0.07 },
), { r: 0.05 });
SFX.merge = () => env(mix(
  { buf: osc("sine", NOTE(64), NOTE(71), 0.18, { vol: 0.5 }) },
  { buf: osc("sine", NOTE(71), NOTE(79), 0.18, { vol: 0.5 }), at: 0.09 },
  { buf: osc("sine", NOTE(79), NOTE(84), 0.2, { vol: 0.5 }), at: 0.18 },
), { r: 0.12 });
SFX.evolve = () => env(mix(
  { buf: osc("square", NOTE(60), NOTE(67), 0.16, { vol: 0.4 }) },
  { buf: osc("square", NOTE(67), NOTE(74), 0.16, { vol: 0.4 }), at: 0.12 },
  { buf: osc("square", NOTE(74), NOTE(81), 0.22, { vol: 0.45 }), at: 0.24 },
  { buf: noise(0.3, { vol: 0.12, lp: 0.5 }), at: 0.24 },
), { r: 0.15 });
SFX.wave_start = () => env(mix(
  { buf: osc("saw", NOTE(45), NOTE(45), 0.5, { vol: 0.4, vib: 3, vibHz: 5 }) },
  { buf: osc("saw", NOTE(52), NOTE(52), 0.5, { vol: 0.28, vib: 3, vibHz: 5.5 }) },
  { buf: noise(0.15, { vol: 0.1, lp: 0.2 }) },
), { a: 0.04, r: 0.2 });
SFX.wave_clear = () => env(mix(
  { buf: osc("tri", NOTE(72), NOTE(72), 0.1, { vol: 0.45 }) },
  { buf: osc("tri", NOTE(76), NOTE(76), 0.1, { vol: 0.45 }), at: 0.1 },
  { buf: osc("tri", NOTE(79), NOTE(84), 0.18, { vol: 0.5 }), at: 0.2 },
), { r: 0.12 });
SFX.victory = () => env(mix(
  { buf: osc("square", NOTE(60), NOTE(60), 0.14, { vol: 0.4 }) },
  { buf: osc("square", NOTE(64), NOTE(64), 0.14, { vol: 0.4 }), at: 0.13 },
  { buf: osc("square", NOTE(67), NOTE(67), 0.14, { vol: 0.4 }), at: 0.26 },
  { buf: osc("square", NOTE(72), NOTE(72), 0.4, { vol: 0.5 }), at: 0.39 },
  { buf: osc("saw", NOTE(48), NOTE(48), 0.7, { vol: 0.2, vib: 2 }), at: 0.39 },
), { r: 0.3 });
SFX.defeat = () => env(mix(
  { buf: osc("saw", NOTE(57), NOTE(56), 0.3, { vol: 0.4, vib: 2 }) },
  { buf: osc("saw", NOTE(52), NOTE(49), 0.35, { vol: 0.4, vib: 2 }), at: 0.28 },
  { buf: osc("saw", NOTE(45), NOTE(40), 0.6, { vol: 0.42, vib: 3 }), at: 0.6 },
), { r: 0.4 });

// 塔开火（按元素）
SFX.fire_arrow = () => env(mix({ buf: osc("square", 900, 500, 0.08, { vol: 0.35 }) }, { buf: noise(0.05, { vol: 0.2, lp: 0.8 }) }), { r: 0.04 });
SFX.fire_frost = () => env(mix({ buf: osc("sine", 1400, 900, 0.12, { vol: 0.4 }) }, { buf: osc("sine", 2100, 1400, 0.08, { vol: 0.2 }) }), { r: 0.06 });
SFX.fire_thunder = () => env(mix({ buf: noise(0.1, { vol: 0.4, lp: 0.9, seed: 7 }) }, { buf: osc("saw", 300, 90, 0.1, { vol: 0.3 }) }), { r: 0.05 });
SFX.fire_flame = () => env(mix({ buf: noise(0.18, { vol: 0.35, lp: 0.25, seed: 3 }) }, { buf: osc("saw", 140, 70, 0.18, { vol: 0.25 }) }), { a: 0.02, r: 0.1 });
SFX.fire_bomb = () => env(mix({ buf: osc("saw", 120, 45, 0.2, { vol: 0.55 }) }, { buf: noise(0.12, { vol: 0.3, lp: 0.3 }) }), { r: 0.1 });
SFX.fire_venom = () => env(mix({ buf: osc("sine", 500, 260, 0.14, { vol: 0.4, vib: 40, vibHz: 22 }) }), { r: 0.06 });

// 命中 / 爆炸 / 死亡
SFX.hit = () => env(mix({ buf: noise(0.07, { vol: 0.4, lp: 0.6, seed: 11 }) }, { buf: osc("square", 320, 180, 0.06, { vol: 0.22 }) }), { r: 0.04 });
SFX.hit_crit = () => env(mix(
  { buf: noise(0.09, { vol: 0.35, lp: 0.7, seed: 13 }) },
  { buf: osc("square", NOTE(84), NOTE(91), 0.14, { vol: 0.35 }) },
  { buf: osc("square", NOTE(88), NOTE(96), 0.14, { vol: 0.25 }), at: 0.03 },
), { r: 0.08 });
SFX.explode = () => env(mix(
  { buf: noise(0.5, { vol: 0.6, lp: 0.28, seed: 17 }) },
  { buf: osc("saw", 90, 32, 0.45, { vol: 0.5 }) },
  { buf: noise(0.2, { vol: 0.3, lp: 0.9, seed: 19 }) },
), { a: 0.008, r: 0.2, curve: 3 });
SFX.enemy_die = () => env(mix({ buf: osc("square", 520, 160, 0.16, { vol: 0.3 }) }, { buf: noise(0.12, { vol: 0.18, lp: 0.5 }) }), { r: 0.08 });
SFX.coin = () => env(mix(
  { buf: osc("square", NOTE(88), NOTE(88), 0.06, { vol: 0.3 }) },
  { buf: osc("square", NOTE(95), NOTE(95), 0.1, { vol: 0.3 }), at: 0.06 },
), { r: 0.05 });
SFX.boss_die = () => env(mix(
  { buf: noise(0.8, { vol: 0.55, lp: 0.3, seed: 23 }) },
  { buf: osc("saw", 70, 24, 0.8, { vol: 0.55 }) },
  { buf: osc("saw", 140, 200, 0.6, { vol: 0.25, vib: 6, vibHz: 9 }), at: 0.1 },
  { buf: osc("square", NOTE(72), NOTE(60), 0.5, { vol: 0.2 }), at: 0.3 },
), { a: 0.01, r: 0.35, curve: 3 });

// 元素反应
SFX.rx_steam = () => env(mix({ buf: noise(0.45, { vol: 0.5, lp: 0.45, seed: 29 }) }, { buf: osc("sine", 700, 250, 0.4, { vol: 0.2 }) }), { a: 0.03, r: 0.2 });
SFX.rx_super = () => env(mix(
  { buf: noise(0.3, { vol: 0.3, lp: 0.95, seed: 31 }) },
  { buf: osc("square", 1800, 700, 0.22, { vol: 0.25 }) },
  { buf: osc("square", 1200, 2600, 0.18, { vol: 0.2 }), at: 0.1 },
), { r: 0.12 });
SFX.rx_overload = () => env(mix(
  { buf: noise(0.35, { vol: 0.5, lp: 0.5, seed: 37 }) },
  { buf: osc("saw", 110, 40, 0.35, { vol: 0.5 }) },
  { buf: osc("square", NOTE(79), NOTE(84), 0.25, { vol: 0.25 }), at: 0.04 },
), { r: 0.15 });

// 城堡 / 瘫痪 / Boss
SFX.castle_hit = () => env(mix(
  { buf: noise(0.4, { vol: 0.55, lp: 0.25, seed: 41 }) },
  { buf: osc("saw", 80, 30, 0.4, { vol: 0.5 }) },
  { buf: osc("square", NOTE(64), NOTE(57), 0.3, { vol: 0.3 }), at: 0.08 },
), { r: 0.2, curve: 3 });
SFX.tower_disabled = () => env(mix(
  { buf: osc("saw", 400, 90, 0.35, { vol: 0.35, vib: 30, vibHz: 14 }) },
  { buf: osc("square", 200, 60, 0.3, { vol: 0.2 }), at: 0.05 },
), { r: 0.12 });
SFX.boss_intro = () => env(mix(
  { buf: osc("saw", 48, 40, 1.1, { vol: 0.5, vib: 5, vibHz: 4 }) },
  { buf: osc("saw", 55, 47, 1.1, { vol: 0.4, vib: 6, vibHz: 5 }) },
  { buf: noise(1.0, { vol: 0.22, lp: 0.18, seed: 43 }) },
  { buf: osc("square", NOTE(40), NOTE(36), 0.8, { vol: 0.3 }), at: 0.25 },
), { a: 0.05, r: 0.4 });

// ---------- 环境音：灰烬低鸣 8 秒循环 ----------
SFX.ambient = () => {
  const dur = 8, n = sec(dur), out = new Float32Array(n);
  // 两台失谐锯齿低鸣 + 一层极闷噪声 + 慢呼吸包络
  const ph = [0, 0, 0];
  const fs = [55, 55.7, 110.3];
  let y = 0, s = 777;
  for (let i = 0; i < n; i++) {
    const k = i / n;
    const breathe = 0.6 + 0.4 * Math.sin(2 * Math.PI * (k / dur) * 2 - Math.PI / 2);
    let v = 0;
    for (let j = 0; j < 3; j++) {
      ph[j] += fs[j] / RATE;
      v += (2 * (ph[j] % 1) - 1) * (j === 2 ? 0.12 : 0.2);
    }
    s = (s * 9301 + 49297) % 233280;
    y += 0.06 * ((s / 233280) * 2 - 1 - y);
    out[i] = (v * 0.5 + y * 0.6) * breathe;
  }
  // 首尾交叉淡化保证无缝循环
  const nf = sec(0.5);
  for (let i = 0; i < nf; i++) {
    const g = i / nf;
    out[i] *= g;
    out[n - 1 - i] *= g;
  }
  return normalize(out, 0.4);
};

// ---------- 烘焙 ----------
const manifest = {};
for (const [name, gen] of Object.entries(SFX)) {
  const data = normalize(gen());
  writeFileSync(join(OUT, `${name}.wav`), wav(data));
  manifest[name] = { file: `${name}.wav`, dur: +(data.length / RATE).toFixed(2) };
  process.stdout.write(`✓ ${name} (${manifest[name].dur}s)\n`);
}
writeFileSync(join(OUT, "index.json"), JSON.stringify(manifest, null, 1));
console.log(`\n${Object.keys(manifest).length} sounds -> ${OUT}`);

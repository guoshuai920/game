// 《王国余烬》专属元素反应特效 · 蒸汽爆发（火+冰）
// 叙事：橙红余烬骤然内吸（火被扑灭），白热闪现，蒸汽团两波炸开并升腾，
// 地面荡开湿痕涟漪，冰晶碎屑汽化坠落。 AOE 读感：一圈内的敌人都被烫着的白汽吞没。
import { Rng, fit, clamp, ease, mix, hex, TAU, WHITE } from "../../../../reference/pixelfx/src/core/index.js";

export const meta = {
  name: "Steam burst",
  desc: "Embers get snuffed and sucked in, a white-hot flash, two waves of steam balls burst out and billow up, a wet ripple rolls on the floor, ice shards flash to vapor.",
  tags: ["reaction", "steam", "fire", "ice", "custom", "one-shot"],
  size: [168, 118],
  origin: [84, 96],
  duration: 1.15,
  loop: false,
  fps: 30,
  bg: "ground",
  options: {
    steam: ["#3a4148", "#5c666e", "#8b949b", "#bcc4c9", "#e8ecef"],
    hot: ["#7a2a12", "#c8501e", "#ff8a2a", "#ffd25a"],
    seed: 7,
  },
};

const FLASH = 0.1, WAVE1 = 0.16, WAVE2 = 0.34;

export function create(o) {
  const S = fit(o.steam, 5), HOT = fit(o.hot, 4), R = new Rng(o.seed);
  const X = 0, Y = -8;
  let t = 0;

  // 内吸的火粒子：从外圈向中心加速，被吸干
  const embers = Array.from({ length: 14 }, (_, i) => {
    const a = (i / 14) * TAU + R.range(-0.2, 0.2);
    const r0 = R.range(38, 56);
    return { a, r: r0, r0, sp: R.range(90, 150), y: -R.range(4, 16), life: R.range(0.1, 0.22) };
  });
  // 两波蒸汽团：先横向后上升，白→灰渐冷
  const mk = (n, t0, sp0, up) => Array.from({ length: n }, (_, i) => {
    const a = (i / n) * TAU + R.range(-0.15, 0.15);
    const side = Math.abs(Math.cos(a));
    return {
      x: X + Math.cos(a) * 5, y: Y + Math.sin(a) * 3 - 2,
      vx: Math.cos(a) * R.range(sp0 * 0.5, sp0) * (0.55 + 0.45 * side),
      vy: Math.sin(a) * R.range(sp0 * 0.3, sp0 * 0.6) - up,
      r: R.range(3, 6.5) * (0.8 + 0.3 * side), t0: t0 + R.range(0, 0.05),
      life: R.range(0.45, 0.8), lift: R.range(18, 42),
    };
  });
  const puffs = [...mk(22, WAVE1, 130, 10), ...mk(16, WAVE2, 95, 34)];
  for (const q of puffs) q.max = q.life;
  // 中央升腾的汽柱粒子
  const cols = Array.from({ length: 10 }, () => ({
    x: X + R.range(-6, 6), y: Y - R.range(2, 8), vx: R.range(-9, 9), vy: -R.range(46, 90),
    r: R.range(2.4, 4.6), life: R.range(0.5, 0.85), max: 0, t0: R.range(0.08, 0.3),
  }));
  for (const q of cols) q.max = q.life;
  // 地面涟漪：两圈湿痕，快进快出
  const rings = [
    { t0: WAVE1, v: 150, r: 0, w: 2.2, a: 0.6, max: 26 },
    { t0: WAVE2 + 0.05, v: 105, r: 0, w: 1.6, a: 0.42, max: 20 },
  ];
  // 汽化的冰屑：闪一下就没了
  const ice = Array.from({ length: 8 }, (_, i) => {
    const a = R.range(0, TAU), v = R.range(50, 110);
    return { x: X + Math.cos(a) * 8, y: Y - 6 + Math.sin(a) * 4, vx: Math.cos(a) * v, vy: Math.sin(a) * v * 0.5 - 26, life: R.range(0.2, 0.34), max: 0 };
  });
  for (const q of ice) q.max = q.life;

  return {
    update(dt) {
      t += dt;
      for (const e of embers) {
        e.r -= e.sp * dt * (1 + 3 * clamp(1 - e.life / 0.22));
        e.life -= dt;
      }
      for (const q of [...puffs, ...cols]) {
        if (t < q.t0) continue;
        q.life -= dt;
        q.vx -= q.vx * 3.2 * dt;
        q.vy -= (q.vy - q.lift) * 3.2 * dt;
        q.x += q.vx * dt;
        q.y += q.vy * dt;
      }
      for (const g of rings) if (t >= g.t0) g.r += g.v * dt;
      for (const q of ice) {
        q.life -= dt;
        q.vy += 60 * dt;
        q.x += q.vx * dt;
        q.y += q.vy * dt;
      }
    },
    draw(p, t) {
      // 地面涟漪（先画，垫底）
      for (const g of rings) {
        if (t < g.t0 || g.r <= 1) continue;
        const k = clamp(1 - g.r / g.max);
        p.ellipse(X, 0, g.r, g.r * 0.22, mix(hex(S[2]), WHITE, 0.4), g.a * k);
      }
      // 内吸余烬
      for (const e of embers) {
        if (e.life <= 0 || e.r < 2) continue;
        const k = clamp(e.life / 0.22);
        const ci = e.r > 24 ? 1 : e.r > 10 ? 2 : 3;
        p.disc(X + Math.cos(e.a) * e.r, Y + e.y + Math.sin(e.a) * e.r * 0.4, 1.6 + k, hex(HOT[ci]), 0.9 * k);
      }
      // 白热闪现
      if (t < FLASH) {
        const k = 1 - t / FLASH;
        p.disc(X, Y, 12 * k + 5, WHITE, k);
        p.glow(X, Y, 32 * k + 10, hex(HOT[3]), 0.6 * k);
      }
      // 蒸汽团：白芯灰皮，随生命变淡变灰
      for (const q of [...puffs, ...cols]) {
        if (t < q.t0) continue;
        const k = q.life / q.max;
        if (k <= 0) continue;
        const r = q.r * (0.65 + (1 - k) * 1.1);
        const a = Math.pow(k, 1.2) * Math.min(1, (t - q.t0) / 0.04);
        const c1 = mix(hex(S[1]), hex(S[3]), clamp(1.2 - k * 1.6));
        p.disc(q.x, q.y, r, c1, 0.62 * a);
        p.disc(q.x - r * 0.2, q.y - r * 0.3, r * 0.55, k > 0.45 ? hex(S[4]) : hex(S[3]), 0.62 * a);
      }
      // 冰屑闪白
      for (const q of ice) {
        if (q.life <= 0) continue;
        const k = q.life / q.max;
        p.disc(q.x, q.y, 1.4 + k * 1.2, WHITE, 0.85 * k);
      }
      // 顶部余温
      const warm = Math.exp(-t / 0.3);
      if (warm > 0.03) p.glow(X, Y - 6, 30, hex(HOT[2]), 0.45 * warm);
    },
  };
}

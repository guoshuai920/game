// 《王国余烬》状态特效 · 塔瘫痪（挂塔循环，无主体）
// 叙事：灰烟缕从塔顶飘出，橙色小火花噼啪，一枚红色"!"在塔顶明灭——故障警示。
import { Rng, clamp, mix, hex, TAU, WHITE } from "../../../../reference/pixelfx/src/core/index.js";

export const meta = {
  name: "Disabled",
  desc: "Grey smoke wisps drift off the tower, orange sparks snap, a red exclamation mark blinks on top. Loop.",
  tags: ["status", "disabled", "custom", "loop"],
  size: [36, 46],
  origin: [18, 42],
  duration: 1.2,
  loop: true,
  fps: 30,
  bg: "ground",
  options: {
    smoke: "#8a8f9c",
    spark: "#ff8a2a",
    warn: "#ff4a3a",
    seed: 12,
  },
};

export function create(o) {
  const DUR = meta.duration;
  const R = new Rng(o.seed);
  const S = hex(o.smoke), K = hex(o.spark), W = hex(o.warn);
  const puffs = Array.from({ length: 4 }, (_, i) => ({
    x: R.range(-4, 4), t0: i * 0.3, life: 0.9, vy: -R.range(16, 24), r: R.range(2, 3.4),
  }));
  const sparks = Array.from({ length: 3 }, (_, i) => ({
    t0: 0.15 + i * 0.38, life: 0.12, x: R.range(-5, 5), y: -R.range(8, 18),
  }));
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p, t) {
      const u = t;
      // 烟缕
      for (const q of puffs) {
        const u2 = (u - q.t0 + DUR) % DUR;
        if (u2 > q.life) continue;
        const k = 1 - u2 / q.life;
        const r = q.r * (0.7 + (1 - k) * 0.8);
        p.disc(q.x + Math.sin(u2 * 4 + q.t0 * 8) * 2, -q.r - u2 * 22, r, S, 0.4 * k);
      }
      // 火花
      for (const q of sparks) {
        const u2 = (u - q.t0 + DUR) % DUR;
        if (u2 > q.life) continue;
        const k = 1 - u2 / q.life;
        p.disc(q.x, q.y, 1 + k * 0.8, k > 0.5 ? WHITE : K, 0.85 * k);
        p.line(q.x, q.y, q.x + 3, q.y - 3, K, 0.5 * k);
      }
      // 红色"!"：明灭
      const blink = Math.sin(u * 9) > -0.2;
      if (blink) {
        p.disc(0, -26, 1.8, W, 0.95);
        p.poly([[-1.8, -22], [1.8, -22], [1.2, -16], [-1.2, -16]], W, 0.95);
        p.glow(0, -22, 8, W, 0.25 + 0.1 * Math.sin(u * 9));
      }
    },
  };
}

// 《王国余烬》状态特效 · 狂暴（一次性触发演出，无主体）
// 叙事：红色怒气双环自脚下炸开，4 条红色热浪线上升，目标位置留一层短促红光脉动。
import { Rng, clamp, ease, mix, hex, TAU } from "../../../../reference/pixelfx/src/core/index.js";

export const meta = {
  name: "Rage",
  desc: "Twin red rage rings burst from the feet, heat lines rush up, a short red pulse lingers. One-shot.",
  tags: ["status", "rage", "custom", "one-shot"],
  size: [72, 72],
  origin: [36, 62],
  duration: 1.1,
  loop: false,
  fps: 30,
  bg: "ground",
  options: {
    ramp: ["#4a0e14", "#8a1a1e", "#c8322a", "#ff6a4a"],
    seed: 8,
  },
};

export function create(o) {
  const R = new Rng(o.seed);
  const C = o.ramp.map(hex);
  const wisps = Array.from({ length: 4 }, (_, i) => ({
    x: -9 + i * 6, t0: 0.1 + i * 0.06, life: R.range(0.4, 0.6), vy: -R.range(38, 60), max: 0,
  }));
  for (const q of wisps) q.max = q.life;
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p, t) {
      // 双环炸开
      const ring = (t0, v, col) => {
        const u = t - t0;
        if (u < 0 || u > 0.42) return;
        const r = v * ease.outCubic(u / 0.42);
        const a = clamp(1 - u / 0.42);
        p.ellipse(0, 0, r, r * 0.3, col, 0.7 * a);
      };
      ring(0.03, 26, C[2]);
      ring(0.12, 20, C[3]);
      // 热浪线上升
      for (const q of wisps) {
        const u = t - q.t0;
        if (u < 0 || u > q.life) continue;
        const k = 1 - u / q.life;
        const x = q.x + Math.sin(u * 10 + q.t0 * 20) * 1.5;
        p.line(x, -4 - u * 40 / (q.life * 60), x + 2, -10 - u * 40, C[2], 0.6 * k);
        p.disc(x, -8 - u * (40 / q.max) * q.max * 0.7, 1.4 * k + 0.6, C[3], 0.8 * k);
      }
      // 红光脉动余韵
      const g = Math.exp(-Math.max(0, t - 0.3) / 0.3) * clamp(t / 0.15);
      if (g > 0.03) p.glow(0, -10, 20, C[2], 0.4 * g);
    },
  };
}

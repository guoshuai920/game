// 《王国余烬》状态特效 · 燃烧（挂身循环，无主体）
// 叙事：目标脚下到半身有 2-3 条火舌舔动，火星上飘，偶有烟缕。无任何身体轮廓。
import { Rng, clamp, mix, hex, TAU, WHITE } from "../../../../reference/pixelfx/src/core/index.js";

export const meta = {
  name: "Burning",
  desc: "Two or three flame licks lap up from the ground at the target, embers drift up, an occasional smoke wisp. Loop.",
  tags: ["status", "burning", "fire", "custom", "loop"],
  size: [44, 56],
  origin: [22, 52],
  duration: 0.9,
  loop: true,
  fps: 30,
  bg: "ground",
  options: {
    ramp: ["#5e1c12", "#c8501a", "#ff8a2a", "#ffd25a", "#fff3c8"],
    seed: 5,
  },
};

export function create(o) {
  const DUR = meta.duration;
  const R = new Rng(o.seed);
  const C = o.ramp.map(hex);
  // 火舌：底部锚点，宽度/高度各自呼吸，相位错开
  const licks = Array.from({ length: 3 }, (_, i) => ({
    x: -5 + i * 5 + R.range(-1.5, 1.5),
    h: R.range(16, 26) + i * 2,
    w: R.range(2.6, 4),
    ph: R.range(0, TAU),
    sp: R.range(7, 10),
  }));
  // 火星
  const embers = Array.from({ length: 9 }, () => ({
    x: R.range(-7, 7), t0: R.range(0, 0.9), life: R.range(0.4, 0.8),
    vy: -R.range(26, 52), vx: R.range(-5, 5), r: R.range(0.7, 1.4), max: 0,
  }));
  for (const q of embers) q.max = q.life;
  let t = 0;
  return {
    update(dt) {
      t += dt;
    },
    draw(p, t) {
      const u = t;
      for (const L of licks) {
        // 火舌高度随时间呼吸，顶端摆动
        const sway = Math.sin(L.ph + u * L.sp);
        const k = 0.75 + 0.25 * Math.sin(L.ph * 2 + u * L.sp * 0.7);
        const h = L.h * k, w = L.w * k;
        const x = L.x + sway * 2.2;
        // 三段色：根部暗红→中段橙→顶黄白，用叠层 disc 近似
        p.disc(x, -h * 0.25, w * 1.15, C[1], 0.85);
        p.disc(x + sway, -h * 0.55, w * 0.85, C[2], 0.9);
        p.disc(x + sway * 1.6, -h * 0.82, w * 0.5, C[3], 0.95);
        p.disc(x + sway * 1.8, -h * 0.95, w * 0.26, C[4], 0.9);
      }
      p.glow(0, -8, 16, C[2], 0.22 + 0.08 * Math.sin(u * 9));
      for (const q of embers) {
        const u2 = (u - q.t0 + DUR) % DUR;
        if (u2 > q.life) continue;
        const k = 1 - u2 / q.life;
        p.disc(q.x + q.vx * u2, -6 + q.vy * u2, q.r * (0.5 + k * 0.7), k > 0.5 ? C[3] : C[2], 0.85 * k);
      }
    },
  };
}

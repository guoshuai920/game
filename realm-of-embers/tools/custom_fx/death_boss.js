// 《王国余烬》死亡特效 · Boss 陨落（一次性，无主体）
// 叙事：暗红冲击环自爆点荡开 → 白闪 → 大股余烬光粒被吸上天空（BOSS 之魂升腾）→ 灰烬落下，余红一点。
import { Rng, clamp, ease, mix, hex, TAU, WHITE } from "../../../../reference/pixelfx/src/core/index.js";

export const meta = {
  name: "Boss death",
  desc: "A dark-red shock ring bursts, white flash, then a thick column of ember motes is sucked up to the sky as ash drifts down, leaving a fading red glow. One-shot.",
  tags: ["death", "boss", "custom", "one-shot"],
  size: [180, 150],
  origin: [90, 128],
  duration: 1.8,
  loop: false,
  fps: 30,
  bg: "ground",
  options: {
    ramp: ["#2a0d08", "#5e1c12", "#c8501a", "#ff8a2a", "#ffd94d"],
    seed: 30,
  },
};

const FLASH = 0.12;

export function create(o) {
  const R = new Rng(o.seed);
  const C = o.ramp.map(hex);
  // 上升余烬柱：从爆点被吸向天空，越升越散
  const ups = Array.from({ length: 46 }, () => {
    const t0 = R.range(0.05, 0.6);
    return {
      x: R.range(-10, 10), t0, life: R.range(0.7, 1.2),
      vy: -R.range(70, 130), sway: R.range(6, 16), ph: R.range(0, TAU),
      r: R.range(0.8, 2), max: 0,
    };
  });
  for (const q of ups) q.max = q.life;
  // 落灰
  const ash = Array.from({ length: 14 }, () => ({
    x: R.range(-50, 50), t0: R.range(0.5, 1.1), life: R.range(0.5, 0.7),
    vy: R.range(16, 30), r: R.range(0.6, 1.2),
  }));
  // 外抛碎屑：先炸出再落
  const bits = Array.from({ length: 12 }, () => {
    const a = R.range(0, TAU), v = R.range(50, 130);
    return {
      x: 0, y: -6, vx: Math.cos(a) * v, vy: Math.sin(a) * v * 0.6 - 30,
      life: R.range(0.35, 0.6), max: 0,
    };
  });
  for (const q of [...ash, ...bits]) q.max = q.life;
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p, t) {
      // 暗红冲击环
      const u = t - 0.02;
      if (u >= 0 && u < 0.5) {
        const r = 62 * ease.outCubic(u / 0.5);
        const a = clamp(1 - u / 0.5);
        p.ellipse(0, 0, r, r * 0.28, C[2], 0.6 * a);
        p.ellipse(0, 0, r * 0.7, r * 0.2, C[1], 0.4 * a);
      }
      // 白闪
      if (t < FLASH) {
        const k = 1 - t / FLASH;
        p.disc(0, -12, 26 * k + 8, WHITE, k);
        p.glow(0, -12, 60 * k + 18, C[3], 0.7 * k);
      }
      // 上升余烬柱
      for (const q of ups) {
        const u2 = t - q.t0;
        if (u2 <= 0 || u2 > q.life) continue;
        const k = 1 - u2 / q.life;
        const x = q.x + Math.sin(u2 * 5 + q.ph) * q.sway * (u2 / q.life);
        const y = -10 + q.vy * u2;
        const ci = k > 0.66 ? 4 : k > 0.33 ? 3 : 2;
        p.disc(x, y, q.r * (0.6 + k * 0.7), C[ci], 0.9 * k);
        if (k > 0.8) p.disc(x, y, q.r * 0.4, WHITE, k);
      }
      p.glow(0, -30, 30, C[2], 0.3 * Math.exp(-Math.max(0, t - 0.4) / 0.5));
      // 外抛碎屑
      for (const q of bits) {
        if (t > q.max || q.life <= 0) continue;
        const k = q.life / q.max;
        q.vy += 140 * (1 / 60);
        q.x += q.vx * (1 / 60);
        q.y += q.vy * (1 / 60);
        q.life -= 1 / 60;
        if (q.life <= 0) continue;
        p.disc(q.x, q.y, 1.3 * k + 0.5, C[2], 0.85 * k);
      }
      // 落灰
      for (const q of ash) {
        const u2 = t - q.t0;
        if (u2 <= 0 || u2 > q.life) continue;
        const k = 1 - u2 / q.life;
        p.disc(q.x + Math.sin(u2 * 3) * 3, -20 + q.vy * u2, q.r, mix(C[1], C[0], 0.5), 0.55 * k);
      }
    },
  };
}

// 《王国余烬》状态特效 · 冻结（挂身循环，无主体）
// 叙事：目标底部一圈霜晶菱形缓缓明灭，细雪飘落，偶有冰芒闪过——被寒气罩住而非变成雕像。
import { Rng, clamp, mix, hex, TAU, WHITE } from "../../../../reference/pixelfx/src/core/index.js";

export const meta = {
  name: "Frozen",
  desc: "A ring of frost crystals around the feet glinting in turn, fine snow drifting down, an icy glint sweeping up now and then. Loop.",
  tags: ["status", "frozen", "ice", "custom", "loop"],
  size: [40, 44],
  origin: [20, 40],
  duration: 1.3,
  loop: true,
  fps: 30,
  bg: "ground",
  options: {
    ramp: ["#12293e", "#1d4d74", "#2f7fb8", "#63b8e8", "#dff4ff"],
    seed: 9,
  },
};

export function create(o) {
  const DUR = meta.duration;
  const R = new Rng(o.seed);
  const C = o.ramp.map(hex);
  // 脚下霜晶：8 颗菱形，轮流亮起
  const gems = Array.from({ length: 8 }, (_, i) => {
    const a = (i / 8) * TAU;
    return {
      x: Math.cos(a) * 13, y: -1 - Math.abs(Math.sin(a)) * 2,
      r: R.range(1.6, 2.6), ph: (i / 8),
    };
  });
  // 飘雪
  const snow = Array.from({ length: 10 }, () => ({
    x: R.range(-14, 14), t0: R.range(0, 1.3), life: R.range(0.7, 1.2),
    vy: R.range(14, 26), drift: R.range(-4, 4), r: R.range(0.6, 1.1),
  }));
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p, t) {
      const u = t;
      // 地面霜圈
      p.ellipse(0, 0, 14, 4.4, C[2], 0.35 + 0.08 * Math.sin(u * 5));
      // 轮流亮起的霜晶菱形
      for (const g of gems) {
        const k = clamp(Math.sin((u * 0.9 + g.ph) * TAU) * 0.5 + 0.5);
        const s = g.r * (0.8 + k * 0.5);
        p.poly([[g.x, g.y - s], [g.x + s * 0.7, g.y], [g.x, g.y + s], [g.x - s * 0.7, g.y]], k > 0.6 ? C[4] : C[3], 0.9);
        if (k > 0.85) p.glow(g.x, g.y, 6, C[3], 0.4);
      }
      // 向上的冰芒扫过（1.3s 内两次）
      const sweep = (u % 0.65) / 0.65;
      const sy = -4 - sweep * 26;
      const fade = Math.sin(sweep * Math.PI);
      p.line(-8 + Math.sin(u * 3) * 2, sy, 8 + Math.sin(u * 3) * 2, sy - 3, mix(C[3], WHITE, 0.5), 0.5 * fade);
      // 飘雪
      for (const q of snow) {
        const u2 = (u - q.t0 + DUR) % DUR;
        if (u2 > q.life) continue;
        const k = 1 - u2 / q.life;
        p.disc(q.x + q.drift * u2 + Math.sin(u2 * 6 + q.t0 * 9) * 1.5, -30 + q.vy * u2, q.r, WHITE, 0.7 * k);
      }
    },
  };
}

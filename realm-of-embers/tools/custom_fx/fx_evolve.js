// 《王国余烬》流程特效 · 合成进化（一次性，无主体无文字）
// 叙事：金色法阵旋亮 → 光柱升起、三道金环攀升 → 顶端金星迸裂 + 金屑飘落。替代上游带
// "LEVEL UP!" 英文横幅与小人剪影的 ui/level-up。
import { Rng, clamp, ease, mix, hex, TAU, WHITE } from "../../../../reference/pixelfx/src/core/index.js";

export const meta = {
  name: "Evolve",
  desc: "A gold circle spins bright, a light pillar rises with three climbing rings, a star burst cracks at the top and gold dust settles. One-shot.",
  tags: ["ui", "evolve", "custom", "one-shot"],
  size: [110, 130],
  origin: [55, 112],
  duration: 1.4,
  loop: false,
  fps: 30,
  bg: "ground",
  options: {
    ramp: ["#5e4010", "#a8781e", "#e0a82a", "#ffd94d", "#fff8c8"],
    seed: 17,
  },
};

const PILLAR = 0.28, BURST = 0.85;

export function create(o) {
  const R = new Rng(o.seed);
  const C = o.ramp.map(hex);
  const dust = Array.from({ length: 16 }, () => {
    const a = R.range(0, TAU), v = R.range(20, 60);
    return {
      x: 0, y: -74, vx: Math.cos(a) * v, vy: Math.sin(a) * v * 0.5 - 10,
      life: R.range(0.4, 0.7), max: 0,
    };
  });
  for (const q of dust) q.max = q.life;
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p, t) {
      // 地面法阵：旋亮
      const ck = clamp(t / 0.3);
      const rot = t * 2.2;
      for (let i = 0; i < 2; i++) {
        const r = 20 - i * 6;
        p.ellipse(0, 0, r, r * 0.3, C[3 - i], 0.5 * ck);
        // 刻痕：4 段弧线随旋转
        for (let k = 0; k < 4; k++) {
          const a = rot + (k / 4) * TAU + i * 0.4;
          const x1 = Math.cos(a) * r, y1 = Math.sin(a) * r * 0.3;
          const x2 = Math.cos(a + 0.5) * r, y2 = Math.sin(a + 0.5) * r * 0.3;
          p.line(x1, y1, x2, y2, C[4], 0.5 * ck);
        }
      }
      // 光柱
      if (t >= 0.1) {
        const pk = clamp((t - 0.1) / PILLAR);
        const h = 64 * ease.outCubic(pk);
        const w = 5 + 2 * Math.sin(t * 12);
        p.disc(0, -h * 0.5, w * 1.4, C[2], 0.35 * pk);
        p.disc(0, -h * 0.5, w * 0.7, C[3], 0.5 * pk);
        p.line(-w * 0.4, -2, -w * 0.4, -h, mix(C[3], WHITE, 0.4), 0.75 * pk);
        p.line(w * 0.4, -2, w * 0.4, -h, C[4], 0.75 * pk);
        p.glow(0, -h * 0.6, 18, C[3], 0.3 * pk);
      }
      // 三道攀升环
      for (let i = 0; i < 3; i++) {
        const u = t - 0.3 - i * 0.14;
        if (u < 0 || u > 0.55) continue;
        const k = u / 0.55;
        const y = -8 - 56 * ease.outCubic(k);
        const r = (16 - i * 3) * (0.8 + 0.3 * Math.sin(k * TAU));
        p.ellipse(0, y, r, r * 0.24, C[3], 0.7 * (1 - k));
      }
      // 顶端星裂
      if (t >= BURST) {
        const u = t - BURST;
        const fk = clamp(1 - u / 0.14);
        if (fk > 0) p.disc(0, -70, 10 * fk + 3, WHITE, fk);
        const rays = 8;
        for (let i = 0; i < rays; i++) {
          const a = (i / rays) * TAU + 0.3;
          const len = (5 + (i % 2) * 4) * clamp(u / 0.2);
          const fade = clamp(1 - u / 0.45);
          p.line(Math.cos(a) * 6, -70 + Math.sin(a) * 4, Math.cos(a) * (6 + len), -70 + Math.sin(a) * (4 + len * 0.6), C[4], 0.8 * fade);
        }
        for (const q of dust) {
          if (q.life <= 0) continue;
          const k = q.life / q.max;
          q.vy += 60 * (1 / 60);
          q.x += q.vx * (1 / 60);
          q.y += q.vy * (1 / 60);
          q.life -= 1 / 60;
          if (q.life <= 0) continue;
          p.disc(q.x, q.y, 1.1 * k + 0.5, k > 0.6 ? C[4] : C[3], 0.9 * k);
        }
      }
    },
  };
}

// 《王国余烬》状态特效 · 眩晕（挂身循环，无主体）
// 叙事：三颗小星在目标头顶打转（与过载反应的星环同一语言），两侧偶有细小电花噼啪。
import { Rng, clamp, mix, hex, TAU, WHITE } from "../../../../reference/pixelfx/src/core/index.js";

export const meta = {
  name: "Stunned",
  desc: "Three small stars orbit above the target, tiny sparks snap at the sides now and then. Loop.",
  tags: ["status", "stun", "custom", "loop"],
  size: [40, 34],
  origin: [20, 30],
  duration: 1.0,
  loop: true,
  fps: 30,
  bg: "ground",
  options: {
    gold: "#ffd94d",
    volt: "#b88fff",
    seed: 3,
  },
};

export function create(o) {
  const DUR = meta.duration;
  const R = new Rng(o.seed);
  const G = hex(o.gold), V = hex(o.volt);
  const stars = [0, 1, 2].map((i) => ({ ph: (i / 3) * TAU, r: 8 + (i % 2) * 2 }));
  const snaps = Array.from({ length: 3 }, () => ({
    side: R.chance(0.5) ? -1 : 1, t0: R.range(0, 1.0), life: 0.14,
    y: -R.range(6, 16),
  }));
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p, t) {
      const u = t;
      // 头顶星环：半径随呼吸收张，星点拖短尾
      const rr = 8 + Math.sin(u * 5) * 1.2;
      for (const s of stars) {
        const a = u * 6.5 + s.ph;
        const x = Math.cos(a) * s.r, y = -20 + Math.sin(a) * 3.2;
        const x2 = Math.cos(a - 0.5) * s.r, y2 = -20 + Math.sin(a - 0.5) * 3.2;
        p.line(x2, y2, x, y, mix(G, WHITE, 0.35), 0.5);
        p.disc(x, y, 1.3, G, 0.95);
        p.disc(x, y, 0.55, WHITE, 0.9);
      }
      p.glow(0, -20, 8, G, 0.18);
      // 两侧电花
      for (const q of snaps) {
        const u2 = (u - q.t0 + DUR) % DUR;
        if (u2 > q.life) continue;
        const k = 1 - u2 / q.life;
        const x = q.side * (11 - u2 * 18);
        p.disc(x, q.y, 1 + k, k > 0.5 ? WHITE : V, 0.8 * k);
        p.line(x, q.y, x - q.side * 3, q.y + 2, V, 0.6 * k);
      }
    },
  };
}

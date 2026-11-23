// 《王国余烬》专属元素反应特效 · 超导（冰+雷）
// 叙事：目标被冰晶棱环封住（六棱晶体从地面拔起合拢），电弧沿晶体棱边爬行点亮，
// 晶体内部透出紫电，最后棱面碎裂为冰尘、残余电花噼啪。
// 读感："目标变成了一只被通电的导体"。
import { Rng, fit, clamp, ease, mix, hex, TAU, WHITE } from "../../../../reference/pixelfx/src/core/index.js";

export const meta = {
  name: "Superconductor",
  desc: "Ice prisms ring up around the target, lightning crawls along their edges lighting them face by face, violet charge glows inside, then the prisms shatter into frost dust with snapping sparks.",
  tags: ["reaction", "superconductor", "ice", "lightning", "custom", "one-shot"],
  size: [150, 130],
  origin: [75, 106],
  duration: 1.7,
  loop: false,
  fps: 30,
  bg: "ground",
  options: {
    ice: ["#12293e", "#1d4d74", "#2f7fb8", "#63b8e8", "#b8e6ff"],
    volt: ["#2a1d5e", "#4a2f9e", "#7a4fe8", "#b88fff", "#efe0ff"],
    seed: 11,
  },
};

const RISE = 0.28, CRAWL = 0.95, BREAK = 1.28;

export function create(o) {
  const I = fit(o.ice, 5), V = fit(o.volt, 5), R = new Rng(o.seed);
  const X = 0, Y = -14;
  // 棱环：六根棱柱围一圈，各自升起时间/高度
  const prisms = Array.from({ length: 6 }, (_, i) => {
    const a = (i / 6) * TAU + 0.26;
    return {
      a, x: X + Math.cos(a) * 26, yB: Y + 12 + Math.sin(a) * 5,
      h: R.range(26, 36), w: R.range(4, 6),
      t0: (i % 2) * 0.06 + R.range(0, 0.05), face: R.range(0, 1),
    };
  });
  // 棱边电弧：爬行亮线段（沿相邻棱柱连线）
  const arcs = [];
  let nextArc = 0.3;
  // 碎裂冰尘
  const dust = [];
  let broke = false;
  // 内部紫电辉光脉动
  let t = 0;

  const arcSeg = (rr, x0, y0, x1, y1, col, glowCol) => {
    // 折线电弧：中点位移细分
    const pts = [[x0, y0], [x1, y1]];
    for (let d = 0; d < 2; d++) {
      const nxt = [];
      for (let i = 0; i < pts.length - 1; i++) {
        const [ax, ay] = pts[i], [bx, by] = pts[i + 1];
        const mx = (ax + bx) / 2 + rr.range(-5, 5), my = (ay + by) / 2 + rr.range(-4, 4);
        nxt.push([ax, ay], [mx, my]);
      }
      nxt.push(pts[pts.length - 1]);
      pts.length = 0;
      pts.push(...nxt);
    }
    return { pts, col, glowCol, life: R.range(0.1, 0.2), max: 0, w: rr.chance(0.3) ? 2 : 1 };
  };

  return {
    update(dt) {
      t += dt;
      // 电弧生成节奏：爬行期密集，破碎前变稀
      if (t > nextArc && t < BREAK) {
        const rr = new Rng(o.seed * 131 + Math.floor(t * 60));
        const i = Math.floor(rr.range(0, 6)), j = (i + 1) % 6;
        const A = prisms[i], B2 = prisms[j];
        const ay = A.yB - A.h * ease.outCubic(clamp((t - A.t0) / RISE));
        const by = B2.yB - B2.h * ease.outCubic(clamp((t - B2.t0) / RISE));
        const g = arcSeg(rr, A.x, ay + rr.range(-8, 0), B2.x, by + rr.range(-8, 0), hex(V[4]), hex(V[2]));
        g.max = g.life;
        arcs.push(g);
        if (rr.chance(0.4)) {
          const g2 = arcSeg(rr, A.x, ay - A.h * 0.5, A.x + rr.range(-8, 8), ay - A.h, WHITE, hex(V[3]));
          g2.max = g2.life;
          arcs.push(g2);
        }
        nextArc = t + (t < CRAWL ? 0.05 : 0.11);
      }
      for (const g of arcs) g.life -= dt;
      // 破碎瞬间：棱柱炸成冰尘
      if (t >= BREAK && !broke) {
        broke = true;
        for (const pr of prisms) {
          const top = pr.yB - pr.h;
          for (let k = 0; k < 7; k++) {
            const a = R.range(0, TAU), v = R.range(24, 90);
            dust.push({
              x: pr.x + R.range(-3, 3), y: top + R.range(0, pr.h),
              vx: Math.cos(a) * v, vy: Math.sin(a) * v * 0.6 - R.range(10, 40),
              r: R.range(1, 2.6), life: R.range(0.3, 0.62), max: 0,
              lit: R.chance(0.3),
            });
          }
        }
      }
      for (const q of dust) {
        if (q.max === 0) q.max = q.life;
        q.life -= dt;
        q.vy += 90 * dt;
        q.x += q.vx * dt;
        q.y += q.vy * dt;
      }
    },
    draw(p) {
      if (t < BREAK) {
        for (const pr of prisms) {
          const k = ease.outCubic(clamp((t - pr.t0) / RISE));
          if (k <= 0) continue;
          const h = pr.h * k, w = pr.w, x = pr.x, yB = pr.yB;
          // 棱柱体：左暗面/右亮面/白棱线
          p.poly([[x - w, yB], [x, yB - h * 0.18], [x, yB - h], [x - w, yB - h * 0.86]], hex(I[1]));
          p.poly([[x + w, yB], [x, yB - h * 0.18], [x, yB - h], [x + w, yB - h * 0.86]], hex(I[2]));
          p.line(x, yB - h * 0.18, x, yB - h, hex(I[4]));
          // 爬行点亮的面：面亮度按时间从下往上扫过
          const sweep = clamp((t - CRAWL * pr.face) / 0.5);
          if (sweep > 0) {
            const fh = h * sweep;
            p.poly([[x - w, yB - fh * 0.7], [x, yB - fh * 0.8 - h * 0.05], [x, yB - Math.min(h, fh + h * 0.2)], [x - w, yB - Math.min(h * 0.86, fh * 0.7 + h * 0.16)]], hex(V[3]), 0.5);
            p.poly([[x + w, yB - fh * 0.7], [x, yB - fh * 0.8 - h * 0.05], [x, yB - Math.min(h, fh + h * 0.2)], [x + w, yB - Math.min(h * 0.86, fh * 0.7 + h * 0.16)]], hex(V[2]), 0.5);
          }
        }
        // 内部紫电辉光
        const pulse = 0.5 + 0.5 * Math.sin(t * 22);
        p.glow(X, Y - 12, 26 + 6 * pulse, hex(V[2]), 0.3 + 0.25 * pulse * clamp(t / 0.4));
      } else {
        // 破碎白闪
        const fk = clamp(1 - (t - BREAK) / 0.09);
        if (fk > 0) p.disc(X, Y - 14, 20, WHITE, 0.8 * fk);
      }
      // 电弧折线
      for (const g of arcs) {
        if (g.life <= 0) continue;
        const k = g.life / g.max;
        for (let i = 0; i < g.pts.length - 1; i++) {
          const [ax, ay] = g.pts[i], [bx, by] = g.pts[i + 1];
          p.line(ax, ay, bx, by, k > 0.5 ? WHITE : g.col, g.w > 1 ? 1 : 0.85);
        }
        const [tx, ty] = g.pts[g.pts.length - 1];
        p.glow(tx, ty, 8, g.glowCol, 0.5 * k);
      }
      // 冰尘
      for (const q of dust) {
        if (q.life <= 0) continue;
        const k = q.life / q.max;
        p.disc(q.x, q.y, q.r * (0.6 + k * 0.6), q.lit ? hex(V[4]) : hex(I[3]), 0.85 * k);
      }
      if (broke) {
        const warm = Math.exp(-(t - BREAK) / 0.25);
        if (warm > 0.03) p.glow(X, Y - 12, 24, hex(V[3]), 0.4 * warm);
      }
    },
  };
}

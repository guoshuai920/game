// 《王国余烬》专属元素反应特效 · 感电过载（火+雷，眩晕）
// 叙事：白热爆闪 → 金橙+电紫双色冲击双环炸开 → 电火混合火花四溅
// → 顶端转出星形眩晕环转两圈（点出 stun 机制）。
import { Rng, fit, clamp, ease, mix, hex, TAU, WHITE } from "../../../../reference/pixelfx/src/core/index.js";

export const meta = {
  name: "Overload",
  desc: "A white-hot overload flash, twin shock rings in molten orange and volt violet, electric-fire sparks cascade, then a spinning star dizzy-ring wobbles on top.",
  tags: ["reaction", "overload", "fire", "lightning", "stun", "custom", "one-shot"],
  size: [160, 128],
  origin: [80, 104],
  duration: 1.3,
  loop: false,
  fps: 30,
  bg: "ground",
  options: {
    fire: ["#7a2a12", "#c8501e", "#ff8a2a", "#ffd25a"],
    volt: ["#2a1d5e", "#4a2f9e", "#7a4fe8", "#b88fff"],
    seed: 21,
  },
};

const FLASH = 0.09, STUN_AT = 0.55;

export function create(o) {
  const F = fit(o.fire, 4), V = fit(o.volt, 4), R = new Rng(o.seed);
  const X = 0, Y = -10;
  let t = 0;
  // 双色火花：电紫与火橙各半，爆发后受重力
  const sparks = Array.from({ length: 26 }, (_, i) => {
    const a = R.range(0, TAU), v = R.range(60, 170);
    return {
      x: X, y: Y, vx: Math.cos(a) * v, vy: Math.sin(a) * v * 0.7 - R.range(20, 60),
      life: R.range(0.3, 0.7), max: 0, hot: i % 2 === 0,
    };
  });
  for (const q of sparks) q.max = q.life;
  // 三道锯齿电弧从中心劈出
  const bolts = Array.from({ length: 3 }, (_, i) => {
    const a = (i / 3) * TAU + 0.5, v = R.range(120, 180);
    return { a, len: R.range(30, 46), t0: 0.04 + i * 0.03, life: 0.16 };
  });
  const star = { r: 0, rot: 0 };
  const STAR_R = 8;

  const jag = (x0, y0, x1, y1, rr) => {
    const pts = [[x0, y0]];
    const n = 6;
    for (let i = 1; i < n; i++) {
      const k = i / n;
      const mx = x0 + (x1 - x0) * k + rr.range(-4, 4);
      const my = y0 + (y1 - y0) * k + rr.range(-4, 4);
      pts.push([mx, my]);
    }
    pts.push([x1, y1]);
    return pts;
  };

  return {
    update(dt) {
      t += dt;
      for (const q of sparks) {
        if (q.life <= 0) continue;
        q.life -= dt;
        q.vy += 130 * dt;
        q.vx -= q.vx * 1.6 * dt;
        q.x += q.vx * dt;
        q.y += q.vy * dt;
      }
      // 星环：STUN_AT 后从顶端弹出并旋转
      if (t >= STUN_AT) {
        const k = clamp((t - STUN_AT) / 0.3);
        star.r = STAR_R * ease.outBack(k);
        star.rot += dt * 7.0 * (1 - clamp((t - 0.9) / 0.4) * 0.6);
      }
    },
    draw(p, t) {
      // 白热爆闪
      if (t < FLASH) {
        const k = 1 - t / FLASH;
        p.disc(X, Y, 18 * k + 6, WHITE, k);
        p.glow(X, Y, 40 * k + 14, hex(F[3]), 0.7 * k);
      }
      // 双色冲击环：橙先紫后，小而快，膨胀即淡
      const ring = (t0, v, col) => {
        const u = t - t0;
        if (u < 0 || u > 0.34) return;
        const r = v * ease.outCubic(u / 0.34);
        const a = clamp(1 - u / 0.34);
        p.ellipse(X, Y + 6, r, r * 0.3, col, 0.7 * a);
        p.ellipse(X, Y + 6, r - 1.6, (r - 1.6) * 0.3, mix(col, WHITE, 0.5), 0.35 * a);
      };
      ring(0.05, 46, hex(F[2]));
      ring(0.13, 38, hex(V[3]));
      // 电弧劈线
      for (const b of bolts) {
        const u = t - b.t0;
        if (u < 0 || u > b.life) continue;
        const k = 1 - u / b.life;
        const rr = new Rng(o.seed * 57 + Math.floor(u * 45) + b.a * 10);
        const ex = X + Math.cos(b.a) * b.len, ey = Y + Math.sin(b.a) * b.len * 0.7;
        const pts = jag(X, Y, ex, ey, rr);
        const col = k > 0.5 ? WHITE : hex(V[3]);
        for (let i = 0; i < pts.length - 1; i++) p.line(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], col, 1);
        p.glow(ex, ey, 10, hex(V[2]), 0.5 * k);
      }
      // 电火混合火花
      for (const q of sparks) {
        if (q.life <= 0) continue;
        const k = q.life / q.max;
        const col = q.hot ? (k > 0.6 ? hex(F[3]) : hex(F[2])) : (k > 0.6 ? hex(V[3]) : hex(V[2]));
        p.disc(q.x, q.y, 1 + k * 1.4, col, 0.9 * k);
        if (k > 0.7) p.disc(q.x, q.y, 0.5, WHITE, k);
      }
      // 眩晕星环：五颗小星点绕顶轻转，不叠辉
      if (t >= STUN_AT) {
        const fade = clamp(1 - (t - 0.95) / 0.35);
        if (fade > 0) {
          const sx = X + Math.sin(t * 6) * 2, sy = Y - 32;
          for (let i = 0; i < 5; i++) {
            const a = star.rot + (i / 5) * TAU;
            const px = sx + Math.cos(a) * star.r, py = sy + Math.sin(a) * star.r * 0.55;
            p.disc(px, py, 1.1, i % 2 ? hex(F[3]) : WHITE, 0.85 * fade);
          }
          p.glow(sx, sy - star.r * 0.4, 6, hex(F[2]), 0.3 * fade);
        }
      }
      // 中心余温
      const warm = Math.exp(-t / 0.22);
      if (warm > 0.03 && t >= FLASH) p.glow(X, Y, 26, hex(F[2]), 0.4 * warm);
    },
  };
}

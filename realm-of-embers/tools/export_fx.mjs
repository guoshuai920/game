#!/usr/bin/env node
// 《王国余烬》特效导出器：从 pixelfx 检出目录渲染选定特效为精灵图（透明 PNG + TexturePacker JSON），
// 并生成 Godot 侧读取的 assets/fx/index.json。
//
//   node tools/export_fx.mjs            # 导出全部
//   node tools/export_fx.mjs --review   # 同时输出暗底预览图到 review/（供人工/AI 目检）
//
// pixelfx 目录默认取 ../../../reference/pixelfx，可用环境变量 PIXELFX_ROOT 覆盖。
// 用法参照 pixelfx 的 skills/pixelfx/SKILL.md：改 LIST 表即改游戏特效；speed=播放加速，scale=显示缩放。

import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { mkdirSync } from "node:fs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const PX = process.env.PIXELFX_ROOT ?? join(ROOT, "..", "..", "reference", "pixelfx");
const { loadEffect, renderFrames, spriteSheet, save, contactSheet, upscale, canvas } = await import(
	pathToFileURL(join(PX, "tools", "lib", "fxlib.mjs")).href
);
const { PAL } = await import(pathToFileURL(join(PX, "src", "core", "color.js")).href);
const OUT = join(ROOT, "assets", "fx");
const REVIEW = join(ROOT, "review");
const REVIEW_MODE = process.argv.includes("--review");

// name=输出名  id=pixelfx 特效  options=效果参数(色板等)  speed=播放倍速  scale=显示缩放  anchor=center|ground
const LIST = [
	// —— 命中反馈（同一impact换色板，形成全元素统一语言）——
	{ name: "hit_arrow", id: "impacts/blunt-hit", speed: 1.6, anchor: "center" },
	{ name: "hit_fire", id: "impacts/blunt-hit", options: { palette: PAL.fire }, speed: 1.6, anchor: "center" },
	{ name: "hit_ice", id: "impacts/blunt-hit", options: { palette: PAL.ice }, speed: 1.6, anchor: "center" },
	{ name: "hit_lightning", id: "impacts/blunt-hit", options: { palette: PAL.volt }, speed: 1.6, anchor: "center" },
	{ name: "hit_poison", id: "impacts/blunt-hit", options: { palette: PAL.poison }, speed: 1.6, anchor: "center" },
	{ name: "hit_crit", id: "impacts/blunt-hit", options: { palette: PAL.gold }, speed: 1.2, scale: 1.3, anchor: "center" },
	// —— AOE ——
	{ name: "aoe_bomb", id: "explosions/dirt-explosion", speed: 1.7, scale: 0.6, anchor: "ground" },
	{ name: "aoe_fire", id: "explosions/big-explosion", speed: 1.7, scale: 0.6, anchor: "ground" },
	{ name: "aoe_venom", id: "nature/acid-splash", options: { palette: PAL.poison }, speed: 1.6, scale: 0.6, anchor: "ground" },
	// —— 死亡 ——
	{ name: "death_coin", id: "spawn/coin-drop", speed: 1.4, anchor: "ground" },
	{ name: "death_poof", id: "spawn/poof", speed: 1.3, anchor: "center" },
	{ name: "death_boss", id: "death_boss", custom: true, scale: 0.75, anchor: "ground" },
	// —— 状态（循环，挂身；全部定制无主体版）——
	{ name: "st_burn", id: "st_burn", custom: true, scale: 0.9, anchor: "ground" },
	{ name: "st_slow", id: "st_slow", custom: true, scale: 0.9, anchor: "ground" },
	{ name: "st_poison", id: "nature/poison-cloud", scale: 0.18, anchor: "ground" },
	{ name: "st_stun", id: "st_stun", custom: true, scale: 0.9, anchor: "ground" },
	// —— 元素反应（专属定制，tools/custom_fx/ 手写）——
	{ name: "rx_steam", id: "rx_steam", custom: true, scale: 0.55, anchor: "ground" },
	{ name: "rx_superconductor", id: "rx_superconductor", custom: true, scale: 0.55, anchor: "center" },
	{ name: "rx_overload", id: "rx_overload", custom: true, scale: 0.6, anchor: "center" },
	// —— 支援 / 流程 ——
	{ name: "fx_heal", id: "holy/heal-aoe", speed: 1.4, scale: 0.55, anchor: "ground" },
	{ name: "fx_summon", id: "spawn/summon-rise", speed: 1.7, scale: 0.45, anchor: "ground" },
	{ name: "fx_merge", id: "arcane/magic-circle-cast", speed: 2.0, scale: 0.42, anchor: "ground" },
	{ name: "fx_evolve", id: "fx_evolve", custom: true, scale: 0.7, anchor: "ground" },
	{ name: "fx_rage", id: "fx_rage", custom: true, scale: 0.9, anchor: "ground" },
	{ name: "fx_disable", id: "fx_disable", custom: true, scale: 0.9, anchor: "ground" },
	{ name: "fx_screen", id: "transitions/pixel-dissolve", speed: 1.6, scale: 4.0, anchor: "center" },
];

mkdirSync(OUT, { recursive: true });
if (REVIEW_MODE) mkdirSync(REVIEW, { recursive: true });

const index = [];
for (const e of LIST) {
	try {
		// custom=true：加载 tools/custom_fx/ 下的手写特效（相对 core 导入已就位）
		const fx = e.custom
			? await loadEffect(e.id, join(HERE, "custom_fx"))
			: await loadEffect(e.id);
		const r = renderFrames(fx, { bg: "none", options: e.options });
		const s = spriteSheet(fx, r, e.name);
		save(join(OUT, `${e.name}.png`), s.png);
		save(join(OUT, `${e.name}.json`), JSON.stringify(s.json));
		const meta = s.json.meta.pixelfx;
		const [fw, fh] = meta.frameSize;
		const pivot = e.anchor === "ground" ? [Math.round(fw / 2), Math.round(fh * 0.75)] : [Math.round(fw / 2), Math.round(fh / 2)];
		index.push({
			name: e.name, id: e.id, image: `${e.name}.png`, atlas: `${e.name}.json`,
			fw, fh, frames: meta.frames, fps: meta.fps, loop: !!meta.loop,
			speed: e.speed ?? 1.0, scale: e.scale ?? 1.0, pivot,
		});
		if (REVIEW_MODE) {
			const rc = renderFrames(fx, { bg: "dark", options: e.options });
			save(join(REVIEW, `${e.name}.png`), contactSheet(fx, rc, { max: 12, zoom: 3 }));
			// 真实精灵预览：用 clear 缓冲（无背景无演员）拼帧——和游戏里看到的完全一致
			const k = 3, pad = 6, n = Math.min(r.n, 10);
			const step = Math.max(1, Math.floor(r.frames.length / n));
			const pw = r.w * k, ph = r.h * k;
			const img = canvas((pw + pad) * Math.min(n, 5) + pad, (ph + pad + 14) * Math.ceil(n / 5) + pad);
			for (let i = 0; i < n; i++) {
				const fr = r.frames[Math.min(r.frames.length - 1, i * step)];
				const cx = pad + (i % 5) * (pw + pad), cy = pad + Math.floor(i / 5) * (ph + pad + 14);
				img.paste(upscale(fr.clear, r.w, r.h, k), pw, ph, cx, cy);
				img.text(`${(fr.t).toFixed(2)}s`, cx, cy + ph + 2, 2, [150, 150, 160]);
			}
			save(join(REVIEW, `${e.name}.sprite.png`), img.png());
		}
		process.stdout.write(`✓ ${e.name} (${e.id})\n`);
	} catch (err) {
		console.error(`✗ ${e.name} (${e.id}): ${err.message}`);
	}
}
save(join(OUT, "index.json"), JSON.stringify(index, null, 1));
console.log(`\n${index.length}/${LIST.length} effects -> ${OUT}`);

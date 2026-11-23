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
const { loadEffect, renderFrames, spriteSheet, save, contactSheet } = await import(
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
	{ name: "hit_flash", id: "impacts/hit-flash", speed: 1.4, anchor: "center" },
	// —— AOE ——
	{ name: "aoe_bomb", id: "explosions/dirt-explosion", speed: 1.7, scale: 0.6, anchor: "ground" },
	{ name: "aoe_fire", id: "explosions/big-explosion", speed: 1.7, scale: 0.6, anchor: "ground" },
	{ name: "aoe_venom", id: "nature/acid-splash", options: { palette: PAL.poison }, speed: 1.6, scale: 0.6, anchor: "ground" },
	// —— 死亡 ——
	{ name: "death_coin", id: "spawn/coin-drop", speed: 1.4, anchor: "ground" },
	{ name: "death_poof", id: "spawn/poof", speed: 1.3, anchor: "center" },
	{ name: "death_boss", id: "spawn/disintegrate", speed: 1.3, scale: 1.2, anchor: "center" },
	// —— 状态（循环，挂在单位身上）——
	{ name: "st_burn", id: "status/burning", scale: 0.5, anchor: "center" },
	{ name: "st_slow", id: "status/frozen", scale: 0.45, anchor: "center" },
	{ name: "st_poison", id: "nature/poison-cloud", scale: 0.22, anchor: "ground" },
	{ name: "st_stun", id: "lightning/electrified", scale: 0.45, anchor: "center" },
	// —— 元素反应 ——
	{ name: "rx_steam", id: "water/geyser", speed: 2.2, scale: 0.45, anchor: "ground",
		options: { palette: ["#24272e", "#4a4f58", "#767d88", "#a6adb6", "#d7dce2", "#fff3e0"] } },  // 蒸汽灰白+暖芯
	{ name: "rx_superconductor", id: "ice/frost-nova", options: { palette: PAL.volt }, speed: 1.5, scale: 0.42, anchor: "center" },
	{ name: "rx_overload", id: "scifi/emp-blast", options: { palette: PAL.volt }, speed: 1.5, anchor: "center" },
	// —— 支援 / 流程 ——
	{ name: "fx_heal", id: "holy/heal-aoe", speed: 1.4, scale: 0.55, anchor: "ground" },
	{ name: "fx_summon", id: "spawn/summon-rise", speed: 1.7, scale: 0.45, anchor: "ground" },
	{ name: "fx_merge", id: "arcane/magic-circle-cast", speed: 2.0, scale: 0.42, anchor: "ground" },
	{ name: "fx_evolve", id: "ui/level-up", speed: 1.6, scale: 0.6, anchor: "ground" },
	{ name: "fx_rage", id: "status/rage", scale: 0.45, anchor: "center" },
	{ name: "fx_disable", id: "scifi/glitch", scale: 0.4, anchor: "center" },
	{ name: "fx_screen", id: "transitions/pixel-dissolve", speed: 1.6, scale: 2.0, anchor: "center" },
];

mkdirSync(OUT, { recursive: true });
if (REVIEW_MODE) mkdirSync(REVIEW, { recursive: true });

const index = [];
for (const e of LIST) {
	try {
		const fx = await loadEffect(e.id);
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
		}
		process.stdout.write(`✓ ${e.name} (${e.id})\n`);
	} catch (err) {
		console.error(`✗ ${e.name} (${e.id}): ${err.message}`);
	}
}
save(join(OUT, "index.json"), JSON.stringify(index, null, 1));
console.log(`\n${index.length}/${LIST.length} effects -> ${OUT}`);

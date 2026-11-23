#!/usr/bin/env node
// 《王国余烬》角色烘焙器：手绘像素网格 → assets/units/<id>.png（横排帧条）+ units.json。
// 双足单位一张网格自动生成 4 帧走路循环（腿部错动+起伏）；飞行/软体手绘 A/B 两帧；
// 沙虫用行位移收缩。塔与弹道单帧。review/units.png 为暗底总览供目检。
//   node tools/bake_units.mjs

import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdirSync, writeFileSync } from "node:fs";
import zlib from "node:zlib";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const OUT = join(ROOT, "assets", "units");
const REVIEW = join(ROOT, "review");
mkdirSync(OUT, { recursive: true });
mkdirSync(REVIEW, { recursive: true });

// ---------- 极简 PNG 编码 ----------
const CRC = (() => {
	const t = new Uint32Array(256);
	for (let n = 0; n < 256; n++) {
		let c = n;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		t[n] = c >>> 0;
	}
	return t;
})();
const crc32 = (b) => {
	let c = 0xffffffff;
	for (let i = 0; i < b.length; i++) c = CRC[(c ^ b[i]) & 0xff] ^ (c >>> 8);
	return (c ^ 0xffffffff) >>> 0;
};
function chunk(type, data) {
	const len = Buffer.alloc(4), crc = Buffer.alloc(4), t = Buffer.from(type, "ascii");
	len.writeUInt32BE(data.length);
	crc.writeUInt32BE(crc32(Buffer.concat([t, data])));
	return Buffer.concat([len, t, data, crc]);
}
function png(w, h, px) {
	const raw = Buffer.alloc((w * 4 + 1) * h);
	for (let y = 0; y < h; y++) Buffer.from(px.buffer, px.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
	return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}
const hex = (s) => [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16), 255];

// ---------- 网格工具 ----------
function validate(id, grids) {
	for (const g of grids) {
		const w = g[0].length;
		g.forEach((row, y) => {
			if (row.length !== w) throw new Error(`${id}: 第 ${y} 行宽度 ${row.length} != ${w}`);
		});
	}
}
function gridRGBA(grid, pal) {
	const h = grid.length, w = grid[0].length;
	const px = new Uint8ClampedArray(w * h * 4);
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const c = pal[grid[y][x]];
			if (c) px.set(hex(c), (y * w + x) * 4);
		}
	}
	return { w, h, px };
}
function shiftRowsX(grid, rows, dx) {
	const w = grid[0].length;
	return grid.map((row, y) => {
		if (!rows.includes(y)) return row;
		const out = new Array(w).fill(".");
		for (let x = 0; x < w; x++) {
			const t = x + dx;
			if (t >= 0 && t < w) out[t] = row[x];
		}
		return out.join("");
	});
}
const bobUp = (g) => [".".repeat(g[0].length), ...g.slice(0, -1)];
function autoWalk(g, legRows) {
	return [g, bobUp(shiftRowsX(g, legRows, 1)), g, bobUp(shiftRowsX(g, legRows, -1))];
}

// ---------- 敌人网格 ----------
const U = {};

U.goblin = { // 12×14
	pal: { o: "#161022", a: "#5da03e", b: "#3a7028", c: "#8cc95e", e: "#ffdf6e", p: "#201407", t: "#7a4b2a", T: "#5b3419", m: "#c9ccd4", n: "#7c828c" },
	legs: [10, 11, 12],
	grid: [
		"....oo......",
		"..ooccao....",
		"..ocaepo....",
		"..ocaaao....",
		"...oTTto....",
		"..otttto....",
		".otatttto...",
		".otatttomn..",
		"..otttto.n..",
		"..obttbo....",
		"..oa..oa....",
		"..oa..oa....",
		".oo....oo...",
		"............",
	],
};

U.orc = { // 14×16
	pal: { o: "#161022", a: "#6f9b46", b: "#4a6f2e", c: "#96c268", e: "#ffdf6e", p: "#201407", m: "#c9ccd4", t: "#6e3b20", T: "#4c2814", w: "#8a5a2b" },
	legs: [12, 13, 14],
	grid: [
		".....oooo.....",
		"....occaao....",
		"...ocaaepo....",
		"...ocaaaao....",
		"....omaamo....",
		"..otttttto....",
		".otattttto....",
		".otatttttomw..",
		".otattttto.m..",
		".otatttttomw..",
		"..otttttto....",
		"..obtttbo.....",
		"..oa....oa....",
		"..oa....oa....",
		".oo......oo...",
		"..............",
	],
};

U.wolf = { // 16×12 带红披风骑手
	pal: { o: "#161022", a: "#7b8494", b: "#565e6e", c: "#a8b0be", e: "#ffdf6e", p: "#201407", g: "#5da03e", r: "#c03a2e", R: "#8a1f1a" },
	frames2: true,
	gridA: [
		"..gg.oooooo.....",
		"..rr.oocccccoo..",
		"..rRr.ocaeppo...",
		"...rroocccccco..",
		"....occcccccao..",
		"...obbbbcccbao..",
		"..oba..ob..obo..",
		"..ob...ob...ob..",
		".oo....oo....oo.",
		"................",
		"................",
		"................",
	],
	gridB: [
		"..gg.oooooo.....",
		"..rr.oocccccoo..",
		"..rRr.ocaeppo...",
		"...rroocccccco..",
		"....occcccccao..",
		"...obbbbcccbao..",
		"...ob..ob..obo..",
		"...ob..ob...ob..",
		"..oo...oo....oo.",
		"................",
		"................",
		"................",
	],
};

U.shield = { // 14×16 塔盾卫
	pal: { o: "#161022", a: "#8d94a5", b: "#5f6675", c: "#b8bfcd", m: "#c9ccd4", n: "#7c828c", e: "#ffdf6e", T: "#332340" },
	legs: [13, 14, 15],
	grid: [
		"....oooooo....",
		"...ommmmmmo...",
		"...omnmmnmo...",
		"...ommmmmmo...",
		"....oaaaao....",
		"...oaaaaaao...",
		"..ommmmmmo....",
		"..omnaaano....",
		"..omnaoTno....",
		"..omnaoTno....",
		"..omnaaano....",
		"..omnmmmno....",
		"...oaooTTno...",
		"...oa...oa....",
		"...oa...oa....",
		"..oo.....oo...",
	],
};

U.bat = { // 14×9
	pal: { o: "#161022", a: "#6b5a86", b: "#463a5e", c: "#9482b4", e: "#ff6e6e", p: "#201407" },
	frames2: true,
	gridA: [
		".oo........oo.",
		"oaco......oaco",
		".ocao....oaco.",
		"..ocaoeeoaco..",
		"...ocaaaaco...",
		"....ocabao....",
		"....oabbo.....",
		".....oo.......",
		"..............",
	],
	gridB: [
		"..............",
		"..............",
		"......oo......",
		"..ocaoeeoaco..",
		"...ocaaaaco...",
		".ocaoabboaco..",
		"..oco.oo.oco..",
		"......oo......",
		"..............",
	],
};

U.shaman = { // 12×16 治疗萨满（亮绿袍+金色法球）
	pal: { o: "#161022", a: "#46a05e", b: "#2f7a44", c: "#8fe09a", e: "#ffdf6e", p: "#201407", T: "#7a6420", n: "#7c828c", g: "#ffd94d" },
	legs: [13, 14, 15],
	grid: [
		".....oo.....",
		"....occao...",
		"...ocaepo...",
		"...ocaaao...",
		"..ottttto.n.",
		".otatttttogg",
		".otattttton.",
		".otattttto..",
		".otattttto..",
		"..oTttttTo..",
		"..oTttttTo..",
		"...oTTTTo...",
		"...oTTTTo...",
		"....o..o....",
		"....o..o....",
		"...oo..oo...",
	],
};

U.slime = { // 14×9
	pal: { o: "#161022", a: "#54b84e", b: "#337a31", c: "#8ce880", w: "#e8fff0" },
	frames2: true,
	gridA: [
		"....oooooo....",
		"..ooccccccoo..",
		".occccwacccco.",
		"occcaawwaaccco",
		"occaaawwaaccco",
		"occaaaaaaaacco",
		".obaaaaaaaabo.",
		"..obbbbbbbbo..",
		"...oooooooo...",
	],
	gridB: [
		"..............",
		"....oooooo....",
		"..ooccccccoo..",
		".occccwacccco.",
		"occcaawwaaccco",
		"ocaaaaaaaaccco",
		"obaaaaaaaaaabo",
		".obbbbbbbbbo..",
		"..oooooooooo..",
	],
};

U.slimelet = { // 9×6
	pal: { o: "#161022", a: "#54b84e", b: "#337a31", c: "#8ce880", w: "#e8fff0" },
	frames2: true,
	gridA: [
		"..oooo...",
		".occcco..",
		"ocwaacco.",
		"ocaaaaco.",
		".obaabo..",
		"..oooo...",
	],
	gridB: [
		".........",
		"..oooo...",
		".occcco..",
		"ocwaacco.",
		"oaaaaaco.",
		".obbbo...",
	],
};

U.gargoyle = { // 18×18 石像鬼 Boss
	pal: { o: "#161022", a: "#8a8f9c", b: "#5c6270", c: "#b4bac6", e: "#ffb84d", p: "#201407" },
	frames2: true,
	gridA: [
		"..oo..........oo..",
		".ocao........oaco.",
		".occao......oacco.",
		"..ocaoooooooacco..",
		"...ocaaaaaaaaco...",
		"...ocaepeaaco.....",
		"...ocaaaaaaco.....",
		"....ocabbaaco.....",
		"..oocaaaaaacoo....",
		".obccaaaaaaccbo...",
		".obccaaaaaaccbo...",
		"..oocaaaaaacoo....",
		"...ocaa..aaco.....",
		"...oba....abo.....",
		"...ob......bo.....",
		"..obb......bbo....",
		"..oo........oo....",
		"..................",
	],
	gridB: [
		"..................",
		"...oo........oo...",
		"...ocao....oaco...",
		"..ocaoooooooacco..",
		"...ocaaaaaaaaco...",
		"...ocaepeaaco.....",
		"...ocaaaaaaco.....",
		"....ocabbaaco.....",
		"..oocaaaaaacoo....",
		".obccaaaaaaccbo...",
		".obccaaaaaaccbo...",
		"..oocaaaaaacoo....",
		"...ocaa..aaco.....",
		"...oba....abo.....",
		"...ob......bo.....",
		"..obb......bbo....",
		"..oo........oo....",
		"..................",
	],
};

U.necro = { // 12×16 亡灵法师（提亮紫袍+绿光法杖）
	pal: { o: "#0e0a18", a: "#6a5a95", b: "#463a68", c: "#8d7cb8", m: "#dddce4", n: "#b8b6c6", e: "#7CF03D", g: "#7CF03D" },
	legs: [14, 15],
	grid: [
		".....oooo...",
		"....ommmmo..",
		"....omeemo..",
		"....ommmmo..",
		".....ommo...",
		"..oaaaaaao..",
		".oaatttaaao.",
		".oaatttaaao.",
		".oaatttaaao.",
		".oaatttaaao.",
		"..oaattaao..",
		"..oTaaaaTo..",
		"...oaaaaao..",
		"....oTTTo...",
		"....o..o....",
		"...oo..oo...",
	],
};

U.skeleton = { // 11×13
	pal: { o: "#161022", m: "#dddce4", n: "#9a98a8", e: "#7CF03D", t: "#6e5a3a" },
	legs: [9, 10, 11],
	grid: [
		"...oooo...",
		"..ommmmo..",
		"..omeemo..",
		"..ommmmo..",
		"...ommo...",
		"..omnnmo..",
		".omnmmnmo.",
		".omnmtnmo.",
		"..omnnmo..",
		"..om..mo..",
		"..om..mo..",
		"..on..no..",
		".oo....oo.",
	],
};

U.sandworm = { // 16×12 拱背虫身
	pal: { o: "#161022", a: "#d4ab60", b: "#97703a", c: "#eccf96", d: "#4a2f16", e: "#ff6e6e", p: "#201407" },
	shiftRows: [4, 5, 6],
	grid: [
		"......oooooo....",
		"....ooccccccoo..",
		"...occbccbccco..",
		"..occcccccbcco..",
		".occbbccccccao..",
		".occccccccaepo..",
		".occbcccccdddo..",
		"..occccccoddbo..",
		"...ooccccccoo...",
		"....ooooooo.....",
		"................",
		"................",
	],
};

U.shadowking = { // 15×17（提亮+金冠+红眼）
	pal: { o: "#0e0a18", a: "#4a4462", b: "#322c48", c: "#6e6690", g: "#ffd94d", e: "#ff5a5a", t: "#8a2a5a" },
	legs: [14, 15, 16],
	grid: [
		"...g..g..g.....",
		"..og.og.og.....",
		"...oooooo......",
		"...occcao......",
		"..ocaeeao......",
		"..ocaaaao......",
		"...ocaao.......",
		"..oaaaaaao.....",
		".oatttttaao....",
		".oattttttaao...",
		".oaatttttaao...",
		".oaatttttaao...",
		"..oaattttaao...",
		"...oaattoao....",
		"...oa....oa....",
		"...oa....oa....",
		"..oo......oo...",
	],
};

U.inferno = { // 18×18 炎魔 Boss
	pal: { o: "#2a0d08", a: "#8f2f1e", b: "#5e1c12", c: "#c8502a", f: "#ffd94d", F: "#ff7b2e", e: "#fff3b0" },
	frames2: true,
	gridA: [
		"....F.f..f.F......",
		"...Ff.Ff.Ff.F.....",
		"..Fff.oo.fffF.....",
		"..fFoccccoFf......",
		"...occcccco.......",
		"...ocaeeaco.......",
		"...ocaaaaco.......",
		"..oocabbbaoo......",
		".oaccaaaaaccoo....",
		".oaccaaaaaccoo....",
		".oaccaaaaaacco....",
		"..occaaaaaco......",
		"...ocaaaaco.......",
		"...oa...oao.......",
		"...oa...oa........",
		"..oba...abo.......",
		"..oo.....oo.......",
		"..................",
	],
	gridB: [
		"..................",
		"...f..F.f..F......",
		"..fF.Ff.Ff.fF.....",
		"..fFoccccoFf......",
		"...occcccco.......",
		"...ocaeeaco.......",
		"...ocaaaaco.......",
		"..oocabbbaoo......",
		".oaccaaaaaccoo....",
		".oaccaaaaaccoo....",
		".oaccaaaaaacco....",
		"..occaaaaaco......",
		"...ocaaaaco.......",
		"...oa...oao.......",
		"...oa...oa........",
		"..oba...abo.......",
		"..oo.....oo.......",
		"..................",
	],
};

// ---------- 塔（单帧） ----------
const T = {};
T.arrow = {
	pal: { o: "#161022", m: "#c9ccd4", n: "#7c828c", w: "#8a5a2b", s: "#8d94a5", S: "#5f6675" },
	grid: [
		"...oo..oo.....",
		"..omoooooom...",
		"...owwwwo.....",
		"...owwwwo.....",
		"...owwnwo.....",
		"....owwo......",
		"...osssso.....",
		"..oSssssSo....",
		"..oSssssSo....",
		".oSssssssSo...",
		".oSssssssSo...",
		"oSssssssssSo..",
		"oSssssssssSo..",
		"oooooooooooo..",
		"..............",
		"..............",
	],
};
T.frost = {
	pal: { o: "#161022", i: "#7fd4ff", I: "#3a8fd4", j: "#d4f2ff", s: "#8d94a5", S: "#5f6675" },
	grid: [
		".....ojj......",
		"....ojjjo.....",
		"....ojiijo....",
		"...ojiiijo....",
		"...ojiIiijo...",
		"...ojiiijo....",
		"....ojiijo....",
		".....ojjo.....",
		"...osssso.....",
		"..oSssssSo....",
		"..oSssssSo....",
		".oSssssssSo...",
		".oSssssssSo...",
		"oSssssssssSo..",
		"oSssssssssSo..",
		"oooooooooooo..",
	],
};
T.thunder = {
	pal: { o: "#161022", m: "#c9ccd4", n: "#7c828c", y: "#ffe25e", s: "#8d94a5", S: "#5f6675" },
	grid: [
		".....oyy......",
		"....onnno.....",
		"...onmmnno....",
		"...onmnnno....",
		"..onnmmmnno...",
		"...onmnnno....",
		"...onmmnno....",
		"..onnmmmnno...",
		"....onno......",
		"...osssso.....",
		"..oSssssSo....",
		"..oSssssSo....",
		".oSssssssSo...",
		".oSssssssSo...",
		"oSssssssssSo..",
		"oooooooooooo..",
	],
};
T.flame = {
	pal: { o: "#2a0d08", s: "#8d94a5", S: "#5f6675", F: "#ff7b2e", f: "#ffd94d", d: "#3d110a" },
	grid: [
		".....ff.......",
		"....fFFf......",
		"....fFFf......",
		"...dooooo.....",
		"...dssssd.....",
		"..dsssssd.....",
		"..dsssssd.....",
		"...dsssd......",
		"...dsssd......",
		"...osssso.....",
		"..oSssssSo....",
		"..oSssssSo....",
		".oSssssssSo...",
		".oSssssssSo...",
		"oSssssssssSo..",
		"oooooooooooo..",
	],
};
T.bomb = {
	pal: { o: "#161022", m: "#c9ccd4", n: "#7c828c", r: "#c03a2e", s: "#8d94a5", S: "#5f6675" },
	grid: [
		"..............",
		"...oooo.......",
		"..ommmmo......",
		".ommmmmo......",
		".omnrnmmo.....",
		".ommmmmo......",
		".ommmmon......",
		"..ommmo.......",
		"...osssso.....",
		"..oSssssSo....",
		"..oSssssSo....",
		".oSssssssSo...",
		".oSssssssSo...",
		"oSssssssssSo..",
		"oSssssssssSo..",
		"oooooooooooo..",
	],
};
T.venom = {
	pal: { o: "#161022", k: "#3f4a58", v: "#7CF03D", s: "#8d94a5", S: "#5f6675" },
	grid: [
		"....v..vv.....",
		".....vvv......",
		"..ooovvooo....",
		".okkkkkkkko...",
		"okvkkkkkvko...",
		"okkkkkkkkko...",
		"okvkkkkkvko...",
		".okkkkkkkko...",
		"..okkkkkko....",
		"...osssso.....",
		"..oSssssSo....",
		".oSssssssSo...",
		".oSssssssSo...",
		"oSssssssssSo..",
		"oSssssssssSo..",
		"oooooooooooo..",
	],
};

// ---------- 城堡（18×14，3x 显示） ----------
const C = {};
C.castle = {
	pal: { o: "#161022", m: "#8d94a5", a: "#b8bfcd", t: "#5b3419", S: "#5f6675", g: "#c03a2e" },
	grid: [
		"........g.........",
		"........o.........",
		".oooo....oooo.....",
		".ommo....ommo.....",
		".ommo....ommo.....",
		".ommoaaaaommo.....",
		".ommaaaaaaamo.....",
		".ommaaaaaaamo.....",
		".ommaatttaamo.....",
		".ommaatttaamo.....",
		".ommaatttaamo.....",
		".ommaaaaaaamo.....",
		".oSmmmmmmmSmo.....",
		".oooooooooooo.....",
	],
};

// ---------- 弹道（9×9，朝右上） ----------
const P = {};
P.none = { pal: { o: "#161022", s: "#8d94a5", S: "#5f6675" }, grid: [
	"...ooo...",
	"..osso...",
	".osssso..",
	".osssso..",
	".oSsSso..",
	"..osso...",
	"...ooo...",
	".........",
	".........",
] };
P.arrow = { pal: { o: "#161022", m: "#c9ccd4", w: "#8a5a2b" }, grid: [
	"......om.",
	".....omm.",
	"....omm..",
	"...omm...",
	"wwomm....",
	".wwo.....",
	"ww.......",
	".........",
	".........",
] };
P.ice = { pal: { o: "#161022", i: "#7fd4ff", j: "#d4f2ff" }, grid: [
	"....j....",
	"....ij...",
	"...jjo...",
	"...ijo...",
	"..ojjo...",
	"..ojo....",
	".oo......",
	".........",
	".........",
] };
P.fire = { pal: { o: "#2a0d08", F: "#ff7b2e", f: "#ffd94d" }, grid: [
	"....f....",
	"...fFf...",
	"...FFf...",
	"..fFFf...",
	"..fFFf...",
	"...fF....",
	"...F.....",
	".........",
	".........",
] };
P.volt = { pal: { o: "#161022", y: "#ffe25e", Y: "#fff8c0" }, grid: [
	"..YY.....",
	"...YY....",
	"....YY...",
	"...yy....",
	"..yy.....",
	".yy......",
	".y.......",
	".........",
	".........",
] };
P.bomb = { pal: { o: "#161022", d: "#3d424e", D: "#22262e", r: "#c03a2e", C: "#b8bfcd" }, grid: [
	"...oo....",
	"..oddo...",
	".odCddo..",
	"odCrddo..",
	"oddddDo..",
	"odddDDo..",
	".oDDo....",
	".........",
	".........",
] };
P.venom = { pal: { o: "#161022", v: "#7CF03D", V: "#4a9425" }, grid: [
	"....v....",
	"...vVv...",
	"..vVVVv..",
	"..vVVVv..",
	"...vVv...",
	"....v....",
	".........",
	".........",
	".........",
] };

// ---------- 烘焙 ----------
function framesOf(id, def) {
	if (def.frames2) return { grids: [def.gridA, def.gridB], fps: 5 };
	if (def.shiftRows) {
		return { grids: [def.grid, shiftRowsX(def.grid, def.shiftRows, 1)], fps: 5 };
	}
	validate(id, [def.grid]);
	return { grids: autoWalk(def.grid, def.legs), fps: 8 };
}
function bake(id, def, kind) {
	let grids, fps;
	if (kind === "static") {
		validate(id, [def.grid]);
		grids = [def.grid];
		fps = 1;
	} else {
		const r = framesOf(id, def);
		grids = r.grids;
		fps = r.fps;
		if (def.frames2) validate(id, grids);
	}
	const g0 = gridRGBA(grids[0], def.pal);
	const w = g0.w, h = g0.h;
	const sheet = new Uint8ClampedArray(w * grids.length * h * 4);
	grids.forEach((g, i) => sheet.set(gridRGBA(g, def.pal).px, i * w * h * 4));
	return { png: png(w * grids.length, h, sheet), fw: w, fh: h, frames: grids.length, fps };
}

const manifest = {};
const defs = {};
function bakeSet(set, kind, scale, prefix) {
	for (const [id, def] of Object.entries(set)) {
		const name = prefix + id;
		const r = bake(name, def, kind);
		writeFileSync(join(OUT, `${name}.png`), r.png);
		manifest[name] = { image: `${name}.png`, fw: r.fw, fh: r.fh, frames: r.frames, fps: r.fps, scale, kind };
		defs[name] = def;
		process.stdout.write(`✓ ${name} (${r.fw}x${r.fh} ×${r.frames}f)\n`);
	}
}
bakeSet(U, "unit", 2.0, "");
bakeSet(T, "static", 2.0, "tower_");
bakeSet(C, "static", 3.0, "");
bakeSet(P, "static", 1.6, "proj_");

// 暗底总览（2x），按烘焙顺序 6 列摆放
{
	const k = 2, cellW = 44, cellH = 46, cols = 6;
	const ids = Object.keys(manifest);
	const rows = Math.ceil(ids.length / cols);
	const tw = cols * cellW, th = rows * cellH;
	const bg = new Uint8ClampedArray(tw * th * 4);
	for (let i = 0; i < tw * th; i++) bg.set([40, 44, 52, 255], i * 4);
	ids.forEach((id, idx) => {
		const g = gridRGBA(defs[id].frames2 ? defs[id].gridA : defs[id].grid, defs[id].pal);
		const cx = (idx % cols) * cellW + Math.floor((cellW - g.w * k) / 2);
		const cy = (Math.floor(idx / cols) + 1) * cellH - g.h * k - 4;
		for (let y = 0; y < g.h; y++) for (let x = 0; x < g.w; x++) {
			const s = (y * g.w + x) * 4;
			if (g.px[s + 3] === 0) continue;
			for (let dy = 0; dy < k; dy++) for (let dx = 0; dx < k; dx++) {
				const px = cx + x * k + dx, py = cy + y * k + dy;
				if (px >= 0 && px < tw && py >= 0 && py < th) bg.set([g.px[s], g.px[s + 1], g.px[s + 2], 255], (py * tw + px) * 4);
			}
		}
	});
	writeFileSync(join(REVIEW, "units.png"), png(tw, th, bg));
}

writeFileSync(join(OUT, "units.json"), JSON.stringify(manifest, null, 1));
console.log(`\n${Object.keys(manifest).length} sprites -> ${OUT}`);

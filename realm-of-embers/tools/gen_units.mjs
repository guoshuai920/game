// ComfyUI(Qwen-Image GGUF) 单位立绘批量生成器
// 用法: node tools/gen_units.mjs [id ...]     缺省生成全部缺失的
// 产出: D:/AI/gens/<id>.png（1024 白底原图），之后用 tools/chroma_remove.gd 抠底接入
// 前置: ComfyUI 已运行于 http://127.0.0.1:8188（Qwen_Image-Q3_K_M + Lightning 8步）

import { writeFileSync, existsSync } from "node:fs";

const HOST = "http://127.0.0.1:8188";
const OUT_DIR = "D:/AI/gens";

// id → [主体描述, 目标显示高度px]
const UNITS = {
	goblin: ["绿色皮肤的小哥布林战士，大耳朵尖牙，挥舞小木棒", 40],
	orc: ["壮硕的绿色兽人战士，穿皮甲，手持大斧头", 44],
	wolf: ["一头巨大的灰色座狼，鬃毛竖起，龇牙低吼，凶猛野性", 40],
	shield: ["全身银色重甲的盾卫兵，举一面巨大的铁塔盾", 40],
	bat: ["一只深紫色大蝙蝠，展翅，尖牙小眼", 36],
	shaman: ["治疗萨满法师，穿羽毛皮袍，持木质图腾法杖", 40],
	slime: ["一只大大的绿色史莱姆凝胶怪物，半透明果冻质感，圆润身体，大眼睛，可爱", 40],
	slimelet: ["一只迷你绿色史莱姆宝宝，水滴形，大眼睛，非常可爱", 30],
	gargoyle: ["灰色石质石像鬼怪物，蹲伏姿势，展开石翅，石头纹理", 44],
	necro: ["亡灵法师，黑紫色连帽法袍，兜帽阴影里只有两点绿光眼睛，持白骨法杖", 42],
	skeleton: ["白色骷髅战士，举一把骨剑，眼窝里橙色光点", 40],
	sandworm: ["巨大棕色沙虫怪物，环状节肢身体，从沙坑里立起，满口獠牙大嘴", 46],
	shadowking: ["暗影国王，黑紫色斗篷幽灵帝王，头戴金色王冠，眼睛发紫光，下半身化为影子", 46],
	inferno: ["炎魔领主，岩浆与火焰构成的恶魔，橙红色燃烧身体，双犄角，眼睛白热", 46],
	tower_arrow: ["木质瞭望箭塔防御塔，方形塔楼顶部架着一具弩炮", 56],
	tower_frost: ["冰霜魔法防御塔，顶部一颗巨大蓝色冰晶，寒气环绕", 56],
	tower_thunder: ["雷电防御塔，顶部一颗金色电球，缠绕铜线圈和电弧", 56],
	tower_bomb: ["黑色臼炮防御塔，粗短炮管斜指天空，炮身一圈红色饰带", 56],
	tower_flame: ["火焰防御塔，顶部一个燃烧的巨大火盆，喷着橙红火焰", 56],
	tower_venom: ["毒液防御塔，一个玻璃毒液罐，绿色毒水冒泡冒烟", 56],
	castle: ["奇幻王国城堡，浅灰石墙红瓦尖塔，蓝色旗帜，金色大门", 78],
};

const STYLE =
	"，游戏单位立绘，卡通风格，粗深色描边，色彩鲜艳，单个主体，居中构图，纯白色背景，无阴影无投影，全身完整可见";
const NEGATIVE = "多个物体，群体，文字，水印，边框，画框，装饰框，卡片，格子，棋盘格，透明底样式，方块背景，照片背景，阴影，投影，模糊，倾斜，裁切";

const wf = (subject, seed) => ({
	"1": { class_type: "UnetLoaderGGUF", inputs: { unet_name: "Qwen_Image-Q3_K_M.gguf" } },
	"2": { class_type: "CLIPLoaderGGUF", inputs: { clip_name: "Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf", type: "qwen_image" } },
	"3": { class_type: "VAELoader", inputs: { vae_name: "qwen_image_vae.safetensors" } },
	"4": { class_type: "LoraLoaderModelOnly", inputs: { model: ["1", 0], lora_name: "Qwen-Image-Lightning-8steps-V1.1-bf16.safetensors", strength_model: 1.0 } },
	"5": { class_type: "CLIPTextEncode", inputs: { clip: ["2", 0], text: subject + STYLE } },
	"6": { class_type: "CLIPTextEncode", inputs: { clip: ["2", 0], text: NEGATIVE } },
	"7": { class_type: "EmptySD3LatentImage", inputs: { width: 1024, height: 1024, batch_size: 1 } },
	"8": { class_type: "KSampler", inputs: { model: ["4", 0], positive: ["5", 0], negative: ["6", 0], latent_image: ["7", 0], seed, steps: 8, cfg: 1.0, sampler_name: "euler", scheduler: "simple", denoise: 1.0 } },
	"9": { class_type: "VAEDecode", inputs: { samples: ["8", 0], vae: ["3", 0] } },
	"10": { class_type: "SaveImage", inputs: { images: ["9", 0], filename_prefix: `unit_${seed}` } },
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function gen(id, subject, seed) {
	const r = await fetch(`${HOST}/prompt`, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify({ prompt: wf(subject, seed), client_id: "gen_units" }),
	});
	const j = await r.json();
	if (j.error) throw new Error(JSON.stringify(j));
	const pid = j.prompt_id;
	for (let i = 0; i < 300; i++) {
		await sleep(2000);
		const h = await (await fetch(`${HOST}/history/${pid}`)).json();
		const st = h[pid];
		if (!st) continue;
		if (st.status?.str_error) throw new Error(st.status.str_error);
		if (st.status?.completed) {
			const imgs = st.outputs["10"]?.images || [];
			if (!imgs.length) throw new Error("no image output");
			const { filename, subfolder } = imgs[0];
			const bin = await (await fetch(`${HOST}/view?filename=${encodeURIComponent(filename)}&subfolder=${encodeURIComponent(subfolder)}&type=output`)).arrayBuffer();
			writeFileSync(`${OUT_DIR}/${id}.png`, Buffer.from(bin));
			return;
		}
	}
	throw new Error("timeout");
}

const args = process.argv.slice(2);
const targets = args.length ? args : Object.keys(UNITS).filter((id) => !existsSync(`${OUT_DIR}/${id}.png`));
console.log("targets:", targets.join(", "));
let ok = 0;
for (let i = 0; i < targets.length; i++) {
	const id = targets[i];
	const spec = UNITS[id];
	if (!spec) {
		console.log(`skip unknown id ${id}`);
		continue;
	}
	const seed = 7000 + i * 13;
	process.stdout.write(`[${i + 1}/${targets.length}] ${id} (seed ${seed}) ... `);
	try {
		await gen(id, spec[0], seed);
		console.log("OK");
		ok++;
	} catch (e) {
		console.log("FAIL:", String(e).slice(0, 200));
	}
}
console.log(`done ok=${ok}/${targets.length}`);

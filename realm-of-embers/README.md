# 王国余烬（原型）

经典奇幻合成守城 · Godot 4 · 单机 · 单图 15 波 · 单局 12~18 分钟 · 零美术素材（Emoji + 纯色）

## 运行

1. 安装 **Godot 4.2+**（推荐 4.3，中文与 Emoji 依赖系统字体回退）。
2. Godot → Import → 选择本目录 `project.godot` → 运行（F5）。启动进**主菜单**（新冒险/继续/设置）。
3. 自动化冒烟测试：`godot --headless --path 本目录 -- --autotest`（10 倍速跑完整局并输出结果）。

## v0.3 更新（UX 与场景）

主菜单与存档选择 · 设置页（音量分总线，持久化 `user://settings.json`）· 1x/2x/3x 加速与暂停 · **提前召唤下一波奖励金币** · 程序化战场地面（草地/土路/塔位石板，`tools/bake_ground.mjs`）· 六步新手引导（可跳过）

## v0.4 更新（主动技能 + Boss 阶段 + 图鉴）

吸收 Kingdom Rush 的"波内主动性"，按 roguelite 身份改造（借骨架不抄结构）：
- **主动技能**：☄️陨星术（点地 AOE+点燃）/ 🌀时滞领域（全场减速）/ 🛡️王室民兵（空投驻军**阻截**地面敌人，站桩互殴）。KR 式免费+冷却+点地释放；**陨星术开局自带 Lv1**（老档无技能会自动补发），更多技能与升级走三选一（`skill_*` 强化牌，可叠加升等级）——技能免费保成熟手感，随机构筑是我们的差异
- **Boss 阶段脚本**：`enemies.json` 新增 `phases`（血量阈值触发）：石像鬼半空增甲+瘫痪塔、炎魔召唤爪牙+狂暴、暗影国王召唤座狼亲卫
- **敌人图鉴**：全敌人一句描述；**首见弹窗**介绍特性（`user://bestiary.json` 记录）

## 玩法与操作

- 点**下方商店**选塔 → 点发光**格位**放置；右键取消选择；
- 点塔选中（显示射程圈）：点空位**免费移动**；拖到**同族同星**塔上**合成升星**（3 级随机进化分支）；
- 选中塔可**卖出**（返还累计造价 70%）或切换**目标优先级**（前排/高血/低血）；
- **波次收入** = 击杀赏金 + 波次奖励 + 存款利息（10%，上限 8 金）——省钱还是铺塔是全局胜负手；
- 每波结束**三选一强化**；不同元素 2 秒内命中同一敌人触发**连锁反应**；
- 城堡 20 耐久：漏小怪 -1 / 精英 -3 / Boss -10；守住 15 波即胜利，空格重开。

## 元素反应表（data/reactions.json）

| 反应 | 组合 | 效果 |
|---|---|---|
| ⚗️ 蒸汽爆发 | 火 + 冰 | 小范围 AOE |
| 🧲 超导 | 冰 + 雷 | 护甲减半 5 秒 |
| 💥 感电过载 | 火 + 雷 | 眩晕 0.5 秒 |

反应伤害无视护甲与免疫；重甲怪需物理+超导或纯元素线；石像鬼免疫物理、炎魔免疫火。

## 改数值 = 改玩法（data/）

| 文件 | 内容 | 关键字段 |
|---|---|---|
| `data/rules.json` | 全局规则+地图 | `startGold` / `lives` / `interestRate` / `interestCap` / `sellRatio` / `path` / `slots`（第 3 位 1=高台） |
| `data/towers.json` | 6 塔族 ×3 级 ×2 分支 | `dmg` / `range` / `rate` / `aoe` / `slow` / `burn` / `poison` / `branches` |
| `data/enemies.json` | 14 种敌人 | `hp` / `speed` / `armor` / `fly` / `immune` / `heal` / `split` / `summon` / `disable` / `rage` |
| `data/waves.json` | 15 波编排 | `hpMul` / `groups`（`count` / `interval` / `delay`） |
| `data/upgrades.json` | 21 条强化池 | `mod` / `amount` / `rarity`（权重 common60/rare30/epic10） |
| `data/reactions.json` | 元素反应 | `pair` / `dmg` / `armorMul` / `stun` |

## 结构

```
scenes/  Main.tscn（战场+全部 UI）· Tower / Enemy / Projectile（纯脚本节点）
scripts/ main.gd（主循环/经济/UI）· tower.gd · enemy.gd · projectile.gd
         path_view.gd（路径绘制层）· data_loader.gd（autoload 数据源）
```

## 文档

- [开发路线图 ROADMAP.md](docs/ROADMAP.md)：版本阶梯、待办任务、验收标准（唯一排期来源）
- [多地图规划 multi-map-plan.md](docs/multi-map-plan.md)
- 技能/音效等管线说明见上方"视觉与特效管线"章节

- [docs/multi-map-plan.md](docs/multi-map-plan.md) —— 真·多地图计划（草地/雪山/熔岩三图递进，待实施）

## 安卓移植清单（规划）

**结论**：逻辑层零改动可移植（Godot 内置安卓导出），工作量集中在触控输入与导出配置。渲染器 gl_compatibility、拉伸模式 canvas_items+expand、user:// 存档、触摸模拟点击/拖拽均已天然就绪。

### 环境搭建（一次性，约 1~2 小时，下载 2~3GB）

- [ ] JDK 17（Godot 4.3 安卓导出硬性要求）
- [ ] Android SDK（platform-tools/adb + API level）
- [ ] Godot 安卓导出模板（编辑器内下载）
- [ ] 测试机开启 USB 调试，或安卓模拟器

### 项目适配（约半天，真正的工作量）

- [ ] 锁定横屏 + 全屏沉浸（`display/window/handheld/orientation`）
- [ ] **右键操作的触控替代**：右键取消选塔/取消拖拽 → 拖拽时显示「✕ 取消」按钮
- [ ] 商店按钮 tooltip 在触屏不可见 → 塔说明移入界面常驻区域
- [ ] 触控目标 ≥ 80px：重开/退出（64×30）、卖出/目标（110×56）需放大
- [ ] **导出过滤器加 `*.json`**：data/ 全靠 FileAccess 读取，漏了 APK 里就没有任何数值
- [ ] 打包一款免费中文字体（如思源黑体）兜底杂牌 ROM 缺字；Emoji 依赖系统 Noto Color Emoji，主流安卓无碍
- [ ] 字号整体上调一档（720p 逻辑分辨率在手机屏偏小）

### 测试与发布

- [ ] 导出 debug APK → adb 安装真机实测（重点：触控拖拽手感、字体渲染、存档读写）
- [ ] 渠道选择：APK 侧载（免费）/ Google Play（$25 账号费）/ 国内商店（软著+备案，正式商业化再议）
- 低成本替代：**Web 导出**免安装分享链接（兼容渲染器已满足要求），适合先验证再上安卓

## 已知设计取舍

- 合成需要手动拖放，目标反馈靠选中射程圈与日志行；
- 沙虫瘫痪塔、暗影国王死亡狂化属于轻量特殊规则，未做动画；
- 自动测试只覆盖"能跑通"，平衡性需人工体感调整（重点：`interestCap`、塔成本、Boss `hpMul`）。

## 视觉与特效管线（PixelFX + 手绘像素）

全量特效与单位精灵均为**开发期烘焙**，运行时只播放纹理，玩家侧零 JS 依赖：

- **特效**：`tools/export_fx.mjs` 从 [pixelfx](https://github.com/patch-gg/pixelfx)（MIT）检出目录渲染 27 个效果（命中/AOE/死亡/状态/流程反馈），支持色板变体与播放倍速；**三个元素反应（蒸汽/超导/过载）为 `tools/custom_fx/` 手写专属特效**，走“打稿→渲染→看图→打磨”循环；改 `LIST` 表 → `node tools/export_fx.mjs` 重新烘焙。环境变量 `PIXELFX_ROOT` 指定检出位置（默认 `../../reference/pixelfx`）。
- **单位**：`tools/bake_units.mjs` 把手绘像素网格（14 敌人 / 6 塔 / 城堡 / 7 弹道）烘成精灵图，双足自动生成 4 帧走路循环；改网格 → 重跑即可。
- **emoji 高清层**：`tools/bake_emoji.gd`（窗口模式跑一次）把系统彩色 emoji 字体里的单位符号（弓箭/雪花/闪电/城堡/哥布林…21 个）渲染成 96px PNG + `emoji.json`，`UnitsBank` 加载时覆盖像素稿条目；某台机器缺对应字体则该条目不产出，自动回落到像素稿。弹道保持像素稿（要旋转贴角）。
- **两个管线坑（踩过实录）**：① 重烘贴图/音效后必须先 `godot --headless --path . --import` 刷新导入缓存，窗口运行才会加载到新资源；② 纹理不能在 `_draw()` 里首次 `load()`（GPU 上传不生效，永远渲染白色占位块）——一律 `_ready` 预载或经 `UnitsBank.make()` 在节点 ready 路径创建。
- **视觉回归**：`tools/shot.gd` 窗口模式自动摆塔放波并截图 `review/shot_main.png`，目检塔/城堡/弹道/特效是否渲染（`Godot_console.exe --path . --script res://tools/shot.gd -- --shot`）。
- **运行时**：`scripts/fx/fx_bank.gd`（SpriteFrames 惰性构建 + 按锚点播放）、`scripts/fx/units_bank.gd`（单位锚定精灵）、`scripts/fx/ambient.gd`（余烬/火星氛围粒子）。
- 目检循环：`--review` / bake 自带 `review/units.png` 暗底总览（该目录不入库，可随时重生成）。
- **声音**：`tools/gen_sfx.mjs` 纯代码合成 28 个复古音效（方波/锯齿滑音+噪声爆+ADSR）+ 8 秒无缝环境低鸣，WAV 输出到 `assets/sfx/`；`scripts/fx/sfx_bank.gd`（autoload `Sfx`）8 路播放池、随机微变调、M 键静音。改音色 → `node tools/gen_sfx.mjs` 重新生成。

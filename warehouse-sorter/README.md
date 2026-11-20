# 爆仓分拣员（原型）

2D 背包管理 + 轻肉鸽 · Godot 4 · 单机 · 单局 8~15 分钟 · 零美术素材（Emoji + 纯色）

## 运行

1. 安装 **Godot 4.2+**（推荐 4.3+，中文与 Emoji 依赖系统字体回退）。
2. Godot → Import → 选择本目录的 `project.godot` → 运行（F5）。无菜单，直接进游戏。

## 玩法与操作

- 传送带按波次间隔出件，**左键拖拽**包裹进 6×4 背包（拖动时格子红绿预览）；
- **右键 / 悬停按 R** 旋转包裹（拖拽过程中不旋转，避免预览与实际形状脱节）；
- 同 `tag` 包裹**面积合计 ≥ 4 格**自动打包得分；3 秒内连续打包触发连击倍率（+0.2/层）；
- 特殊规则：🧊 易碎件相邻包裹 ≥2 个持续 3 秒破损；🍎 生鲜 / ⚡ 加急带倒计时，超时扣分；📺 大件占 2×2、得分 ×3；
- 传送带堆满 6 个 → 失败；10 波分数达标 → 胜利；结束后**空格 / 按钮**重开。

## 改数值 = 改玩法（data/）

| 文件 | 内容 | 关键字段 |
|---|---|---|
| `data/parcels.json` | 20 种包裹 | `shape` / `tag` / `timer` / `rule` / `multiplier` / `score` |
| `data/waves.json` | 10 波 | `spawnInterval` / `weights` / `targetScore`（累计目标分） |
| `data/game_rules.json` | 全局规则 | `gridWidth` / `gridHeight` / `beltCapacity` / `matchCount` / `comboWindow` / `comboMultiplier` / `baseScoreFail` |

**已知平衡提示**：打包按"同 tag 面积 ≥ matchCount"判定，因此任何 2×2 大件一落包就自动打包（自身 4 格）。若嫌太赚，把 `matchCount` 调到 6，或后续给 `big` 单独加 `packCount` 字段。

## 结构

```
res://
├─ scenes/   Main.tscn（根：HUD+Belt+Grid+Overlay） Parcel.tscn GridCell.tscn
├─ scripts/  game.gd（主循环/波次/胜负） grid.gd（占位/拖放/高亮）
│            parcel.gd（形状/计时/破损/拖拽数据） belt.gd（传送带） data_loader.gd（JSON）
├─ data/     parcels.json waves.json game_rules.json
└─ assets/   空（零素材）
```

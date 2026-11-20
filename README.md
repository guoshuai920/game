# TestGit · Godot 4 游戏原型集

两个可直接运行的 Godot 4 单机原型，均为数据驱动（JSON 配置表）、零美术素材（纯色 UI + Emoji），打开即玩、无菜单。

| 项目 | 类型 | 一句话玩法 | 单局时长 |
|---|---|---|---|
| [warehouse-sorter/](./warehouse-sorter) | 2D 背包管理 + 轻肉鸽 | 传送带出件 → 拖进 6×4 背包 → 同类面积凑满 4 格自动打包，易碎/生鲜/加急件带特殊规则，撑过 10 波 | 8~15 分钟 |
| [office-battle-royale/](./office-battle-royale) | 肉鸽卡牌（杀戮尖塔 like） | 管理精力/压力/行动点，打牌削“工作量”，12 节点后击败老板终面，3/6/9 节点三选一加卡 | 8~15 分钟 |

## 运行

1. 安装 [Godot 4.2+](https://godotengine.org/download)（推荐 4.3+，中文与 Emoji 显示依赖系统字体回退）；
2. Godot → Import → 选择对应项目子目录里的 `project.godot` → F5 运行。

## 改数值 = 改玩法

两个项目的卡牌/包裹、敌人/波次、全局规则全部放在各自 `data/` 目录的 JSON 里，改表即改玩法，无需动代码：

- `warehouse-sorter/data/`：`parcels.json`（20 种包裹）、`waves.json`（10 波）、`game_rules.json`
- `office-battle-royale/data/`：`cards.json`（20 张卡）、`enemies.json`（10 个敌人）、`nodes.json`（12 节点编排，含“加强”倍率）

各项目目录内有更详细的 README（玩法规则、字段说明、已知平衡提示）。

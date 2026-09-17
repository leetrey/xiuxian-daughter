# 内容填写指南

当前分工：程序负责通用流程、配置读取和校验；作者负责具体内容、配方、数值与文案。示例用于说明怎么填，不是正式平衡方案，也不要求采用“青蕴草必须作为辅材”等丹方规则。

本次可填写已运行的物品、种植、加工、建筑和培养活动。剧情、战斗、比赛、继承等尚未实现的系统不能仅通过这里的表启用，参见 [开发进度](05-development-progress.md)。

## 1. 文件入口

| 文件 | 填写内容 | 当前例子 |
|---|---|---|
| [items.json](../data/items.json) | 物品 ID、显示名、分类、描述 | 清心草、青蕴草、清心丹、木材、石料 |
| [recipes.json](../data/recipes.json) | 种植、采集、加工的投入与产出 | 两种药材种植、采木采石、清心丹加工 |
| [cave.json](../data/cave.json) | 建筑、允许产物分类、可用配方 ID、御灵与景观 | 灵田、丹炉等七种建筑 |
| [cultivation.json](../data/cultivation.json) | 日程、自由活动、物品使用效果、初始库存与培养数值 | 服草减压、服丹减压、习剑等 |

不需要为每株药材建立脚本或场景。引用关系为：`物品 ID <- 配方投入/产出 <- 建筑可用配方列表`。同一种建筑可以建多栋，每栋各选一个生产任务。

表中的键是稳定 ID，建议用小写英文和下划线。中文名只用于显示，更名只改 `name`；要改 ID，则必须同步所有引用。JSON 同一对象内不要重复使用相同键，当前解析器不会报告重复对象键。

## 2. 添加一种药材

在 `items.json` 的 `items` 对象内添加条目，与已有物品并列。下面是条目示例，不是整个文件：

```json
"example_herb": {
  "name": "填写药材名称",
  "category": "herb",
  "description": "填写药材文案。"
}
```

| 字段 | 要求 |
|---|---|
| 条目键 | 唯一、非空的物品 ID；其他表引用它 |
| name | 必填，非空字符串 |
| category | 必填：`resource` 基础资源、`herb` 药材、`product` 制品 |
| description | 可选字符串，目前只保存为内容资料，不自动生成详情界面或效果 |

青蕴草虽然是基础药材，分类仍是 `herb`，不是 `resource`。灵田只产药材，不能挂载产出木材、食材或丹药的配方。

## 3. 添加种植任务

在 `recipes.json` 的 `recipes` 对象内添加：

```json
"grow_example": {
  "name": "种植示例药材",
  "inputs": {},
  "outputs": {"example_herb": 4}
}
```

然后把 `grow_example` 加入 `cave.json` 的 `buildings.herb_field.recipes` 数组。保留已有任务时，该字段形如：

```json
"recipes": ["grow_clearheart", "grow_qingyun", "grow_example"]
```

灵田同时保留 `"output_categories": ["herb"]`。有生产任务的建筑必须声明非空的允许产物分类，程序会检查配方的每一种产物，包括副产物。建筑的 `category: "production"` 是建筑分类，不等于物品属于基础资源。

仅定义配方不会自动放进建筑菜单，必须挂入建筑的 `recipes` 列表。修改后重启，选择灵田即可看到新任务。

## 4. 添加加工配方

下面仅演示两个原料加工成一个制品。所有物品必须先在 `items.json` 定义；可以使用已有物品，也可以自行添加 `category: "product"` 的制品。

```json
"make_example": {
  "name": "示例双原料加工",
  "inputs": {"qingyun_grass": 2, "example_herb": 3},
  "outputs": {"clearheart_pill": 1}
}
```

把 `make_example` 加入 `cave.json` 的 `buildings.alchemy.recipes`。丹炉当前的 `output_categories` 为 `["product"]`。

数字和组合都可改，不是固定丹方，也不自动修改原有 `make_clearheart`。当前原有配方仍是 4 清心草加工成 2 清心丹。

| 配方字段 | 含义与校验 |
|---|---|
| name | 界面显示的生产任务名称，必填 |
| inputs | 物品 ID 到正整数数量；不耗材料时填 `{}` |
| outputs | 物品 ID 到正整数数量，至少一种产物 |

数量指一栋建筑一个回合执行一批。实际产出乘上御灵、景观倍率后按洞天配置取整，投入不随倍率增加。

第 N 回合种植产物在回合末入库，最早第 N+1 回合参与加工。多个原料必须同时足够；缺一种时整批停产，不会先扣另一种。这是当前试作行为，不新增成熟倒计时、手动收获或多层加工规则。

## 5. 让制品可以使用

物品分类本身不产生效果。当前“使用物品”复用 `cultivation.json` 中的自由活动，参考现有 `clearheart` 和 `clearheart_pill` 条目。

例如添加一个 `example_pill` 制品后，可在 `activities` 数组添加以下独立示例：

```json
{
  "id": "use_example_pill",
  "kind": "free",
  "name": "服用示例丹药",
  "min_phase": 0,
  "energy_cost": 0,
  "pressure": -30,
  "growth": {},
  "costs": {"example_pill": 1}
}
```

`example_pill` 必须有对应物品定义和获取途径。这段示例不会自动创建它，也不要求把上一节的产物改成它。

`pressure` 为压力增减，`growth` 为已有属性 ID 到成长数值，`costs` 为实际消耗物品。效果示例 -30 可改；负压力活动在压力为零时不会消耗物品。`kind: "free"` 不占培养槽，`energy_cost` 决定是否消耗自由精力。

新增同类培养活动可参考 `kind: "schedule"` 的现有条目；`min_phase` 为 0/1/2 三个内部阶段。不要用它给灵田绑定女儿年龄或属性门槛。

战斗恢复、冷却、送礼好感和剧情解锁尚未接入这里的运行流程。自行添加这些字段不会自动实现对应行为，需要后续接入相关系统。

## 6. 初始库存与检查

`cultivation.json` 的 `initial_inventory` 只列需要在开局显示或持有的物品，数量为非负整数。未列出的新物品视为持有零个，首次产出时自动加入库存，无需改 GDScript。

修改后重启游戏，当前没有热更新或存档迁移。作者检查配置可运行以下命令，或在 Godot 中单独运行 `scenes/validate_content.tscn`：

```bash
godot --headless --path "/Users/leet/WorkBuddy/独立" res://scenes/validate_content.tscn
```

成功输出 `CONTENT_CONFIG_OK`，失败返回非零退出码，并指出文件、条目或字段。例如：

```text
data/recipes.json recipes.make_example.inputs.unknown_herb: 未知物品，请先在 data/items.json 定义
```

检查覆盖 JSON 读取、物品分类、投入产出数量、初始库存及活动/建筑/配方的物品引用、建筑产物分类等。它不是经济平衡验证，也不会穷举所有未列出的字段或玩法条件。

`smoke_test.tscn` 是程序回归测试，包含固定示例数值断言；作者更改正式数值后，不应把这些断言失败当成填表错误。只检查内容时使用上面的专用入口。

## 7. 代码阅读

1. [content_tables.gd](../scripts/content_tables.gd)：读取文件、检查类型、数量与跨表引用。
2. [game_state.gd](../scripts/game_state.gd)：组合四份配置、校验后初始化本局状态。
3. [cave_rules.gd](../scripts/cave_rules.gd)：按物品 ID 通用计算投入产出，不判断具体药材名称。
4. [cave_ui.gd](../scripts/cave_ui.gd)：按建筑配方列表生成菜单，显示预测与实际库存。

运行时仍通过 `GameState.config.items` 和 `GameState.cave_config.recipes` 查询，源文件分别是 `items.json` 和 `recipes.json`。不要在 `cultivation.json` 或 `cave.json` 根节点重新放回这两张表，启动检查会拒绝重复定义入口。

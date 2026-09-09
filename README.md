# 山河养成录 · Godot 原型

> 当前代码是旧规则原型，不代表最新玩法设计。最新设计入口见 [设计文档索引](docs/README.md)。
> 本轮只整理设计与交互方案，尚未将新规则迁入代码；下面的运行说明与验证范围仍对应旧原型。
> `v0.5` 是设计基线标签，记录主体规则、交互草案、核心实体与 Godot 常规目录方案，不代表新规则已经实现或全部验收。

这是依据《修仙养女儿游戏设计文档 GDD》制作的阶段三纵向切片，当前跑通：

- 每月 10 点父女共享精力与行动队列
- 女儿修炼、技艺、破境及即时成长反馈
- 父亲重修、采集、做工，以及筑基后解锁洞天种田
- 羁绊、心魔、复仇倾向与真相公开度
- 月份推进、家庭开销、宗门身份与原型结局判定

## 运行

使用 Godot 4.7 或兼容的 Godot 4.x 版本打开本目录，然后运行主场景；也可在终端执行：

```bash
godot --path "/Users/leet/WorkBuddy/独立"
```

## 验证

```bash
godot --headless --path "/Users/leet/WorkBuddy/独立" res://scenes/smoke_test.tscn
```

看到 `SMOKE_TEST_OK` 表示行动消耗、女儿成长、父亲筑基和洞天解锁等关键逻辑通过。

## 推荐阅读顺序

1. `project.godot`：查看主场景和两个全局单例如何注册。
2. `scripts/game_state.gd`：了解时间、资源、人物数值和结局如何保存。
3. `scripts/schedule_manager.gd`：了解行动如何解锁、扣除精力并结算收益。
4. `scripts/main.gd`：了解界面如何生成，以及按钮如何把行动 id 交给规则层。
5. `scripts/smoke_test.gd`：用几个断言快速理解核心规则应满足什么结果。

一次完整的调用链是：点击行动按钮 -> `_queue_activity()` 加入队列 ->
`_execute_schedule()` 逐项提交 -> `ScheduleManager.execute_activity()` 修改状态 ->
`GameState.state_changed` 发出信号 -> `Main._refresh()` 更新界面。

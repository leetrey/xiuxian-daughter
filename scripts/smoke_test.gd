extends Node

# 这是无需打开窗口的最小逻辑测试场景。
# 运行方式写在 README 中；任一 assert 失败都会在 Godot 输出中报错。

func _ready() -> void:
	_run()


func _run() -> void:
	# 1. 普通修炼必须同时消耗共享精力并增加女儿修为。
	GameState.reset_game()
	var energy_before := GameState.energy
	var cultivation_before := GameState.daughter_progress
	var result := ScheduleManager.execute_activity("daughter_cultivate")
	assert(result["ok"])
	assert(GameState.energy == energy_before - 3)
	assert(GameState.daughter_progress > cultivation_before)

	# 2. 父亲重筑道基后，洞天种田的锁定条件应立即解除。
	GameState.father_progress = 100
	GameState.spirit_stones = 100
	GameState.herbs = 3
	result = ScheduleManager.execute_activity("father_breakthrough")
	assert(result["ok"])
	assert(GameState.father_realm == 1)
	assert(ScheduleManager.lock_reason("cave_farm").is_empty())

	# 3. 谈心只推进真相公开度，不能顺带改变复仇倾向。
	var truth_before := GameState.truth_revealed
	GameState.energy = 10
	result = ScheduleManager.execute_activity("family_talk")
	assert(result["ok"])
	assert(GameState.truth_revealed > truth_before)
	assert(GameState.vengeance == 35)

	# 4. 休息恢复精力，但同一个月不能重复使用。
	var energy_after_talk := GameState.energy
	result = ScheduleManager.execute_activity("rest")
	assert(result["ok"])
	assert(GameState.energy == mini(GameState.max_energy, energy_after_talk + 3))
	assert(not ScheduleManager.lock_reason("rest").is_empty())

	# 5. 进入下个月时恢复精力；心魔满值时道陨优先收束游戏。
	GameState.energy = 1
	GameState.advance_month()
	assert(GameState.energy == GameState.max_energy)

	GameState.heart_demon = 100
	GameState.advance_month()
	assert(GameState.game_finished)
	assert(GameState.ending_title == "道陨")

	print("SMOKE_TEST_OK")
	get_tree().quit(0)

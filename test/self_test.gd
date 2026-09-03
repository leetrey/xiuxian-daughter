extends SceneTree
## 自测脚本：headless 下模拟「排日程→属性/境界变化→女儿反馈」闭环。
## 运行：godot --headless -s res://test/self_test.gd
## 用途：验证 GameState 数值逻辑（不依赖渲染）。


func _initialize() -> void:
	print("========== 修仙养女儿 · 逻辑自测 ==========")
	var gs = load("res://scripts/game_state.gd").new()
	gs._ready()

	var breaks: Array = []
	gs.realm_broken.connect(func(from_r, to_r): breaks.append("%s→%s" % [from_r, to_r]))

	print("初始：境界=%s 精力=%d 灵石=%d 心魔=%d 情缘=%d" % [
		gs.get_realm()["name"], gs.energy, gs.spirit_stones, gs.heart_demon, gs.bond])

	# 1) 连续闭关，验证属性/境界/心魔/精力扣减 + 突破
	for i in range(12):
		var r: Dictionary = gs.do_activity("seclusion")
		if r["ok"]:
			print("  [%02d] 闭关 OK  境界条=%3d  心魔=%d  反馈=%s" % [
				i, gs.realm_progress, gs.heart_demon, r["feedback_text"]])
		else:
			print("  [%02d] 闭关拒绝：%s（精力=%d）" % [i, r["reason"], gs.energy])
		if gs.energy < 5:
			gs.next_month()

	print("闭关后：境界=%s 突破=%s 道法主属性=%d" % [
		gs.get_realm()["name"], "，".join(breaks), gs.get_main_stat("道法")])

	# 2) 精力不足拒绝
	gs.energy = 0
	var r_energy: Dictionary = gs.do_activity("adventure")
	print("精力不足拒绝：ok=%s reason=%s" % [r_energy["ok"], r_energy["reason"]])

	# 3) 灵石不足拒绝
	gs.energy = 10
	gs.spirit_stones = 0
	var r_stones: Dictionary = gs.do_activity("alchemy")
	print("灵石不足拒绝：ok=%s reason=%s" % [r_stones["ok"], r_stones["reason"]])

	# 4) 谈心降心魔 + 涨情缘
	gs.heart_demon = 30
	gs.bond = 20
	gs.do_activity("bond_talk")
	print("谈心后：心魔=%d 情缘=%d" % [gs.heart_demon, gs.bond])

	# 5) 时间推进
	gs.next_month()
	print("下月：%s 精力=%d" % [gs.time_text(), gs.energy])

	# 6) 境界突破验证：从 60 推到 130，跨过筑基门槛 120
	var broke_realm: Array = []
	gs.realm_broken.connect(func(fr, tr): broke_realm.append("%s→%s" % [fr, tr]))
	gs.debug_grow(70)
	print("突破验证：境界=%s 本次突破=%s" % [gs.get_realm()["name"], "，".join(broke_realm)])

	print("========== 自测结束 ==========")
	gs.free()
	quit()

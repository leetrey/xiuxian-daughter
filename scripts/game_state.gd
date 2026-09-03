extends Node
## GameState —— 全局状态单例（Autoload）
## 管理女儿属性 / 境界 / 精力 / 心魔 / 情缘 / 灵石 / 时间，以及核心动作 do_activity()。
## UI 通过信号刷新，不直接轮询。


# ---------- 信号 ----------
signal state_changed                       # 任意状态变化（UI 全量刷新）
signal realm_broken(from_realm: String, to_realm: String)   # 境界突破
signal feedback(text: String)              # 女儿反馈文案（用于日志/气泡）
signal month_passed                        # 月推进


# ---------- 女儿基础 ----------
var daughter_name: String = "阿凝"
var age: int = 10                          # 起始年龄（岁）
var month_in_year: int = 1                 # 年内月序 1~12
var total_months: int = 0                  # 累计行动月（10 岁起）

# ---------- 16 细分属性（key → 0~100）----------
var sub_stats: Dictionary = {
	"lidao": 5, "gengu": 5, "shenfa": 5, "yizhi": 5,
	"zhenyuan": 5, "shufa": 5, "wuxing": 5, "huti": 5,
	"ziyi": 5, "renyuan": 5, "lijie": 5, "yunshi": 5,
	"dandao": 5, "lianqi": 5, "danqing": 5, "yinlv": 5,
}

# ---------- 横切属性 ----------
var energy: int = 10                       # 本月剩余精力（行动点）
const ENERGY_MAX: int = 10                 # [PLACEHOLDER] 精力上限
var heart_demon: int = 0                   # 心魔 0~100
var bond: int = 20                         # 情缘 0~100
var spirit_stones: int = 50                # 灵石（货币）

# ---------- 境界 ----------
var realm_progress: int = 0                # 境界累积条（用于突破判定）
var realm_index_cache: int = 0             # 缓存当前境界阶位，用于检测突破

# ---------- 主角隐藏值（双线，最小闭环先落变量，不显示数字）----------
var blood_revenge: int = 0                 # 血仇/隐忍：-100 血仇 ←→ +100 隐忍


func _ready() -> void:
	# 让随机种子来自系统，Godot 4 已自动处理，这里显式留空即可。
	realm_index_cache = GameData.realm_index(realm_progress)


# ---------- 查询 ----------
func get_realm() -> Dictionary:
	return GameData.realm_of(realm_progress)

func get_realm_index() -> int:
	return GameData.realm_index(realm_progress)

## 主属性汇总值（4 细分之和）
func get_main_stat(main: String) -> int:
	var total := 0
	for key in GameData.MAIN_TO_SUB[main]:
		total += sub_stats[key]
	return total

## 当前年龄的字符串（含年/月）
func time_text() -> String:
	return "第 %d 年 · %d 月 · %s（%d 岁）" % [total_months / 12 + 1, month_in_year, daughter_name, age]


# ---------- 核心动作：执行一项活动 ----------
## 返回 Dictionary：{ok, reason, gains_summary, realm_broken, feedback_text}
func do_activity(activity_id: String) -> Dictionary:
	var act: Dictionary = {}
	for a in GameData.ACTIVITIES:
		if a["id"] == activity_id:
			act = a
			break
	if act.is_empty():
		return {"ok": false, "reason": "未知活动"}

	# 精力检查
	if energy < act["energy"]:
		return {"ok": false, "reason": "精力不足"}

	# 灵石检查（支出类活动，付不起则拒绝）
	if act["stones"] < 0 and spirit_stones + act["stones"] < 0:
		return {"ok": false, "reason": "灵石不足"}

	# ---- 结算 ----
	energy -= act["energy"]

	var gains_summary: Array[String] = []
	for key in act["gains"]:
		var rng: Array = act["gains"][key]
		var delta: int = randi_range(rng[0], rng[1])
		sub_stats[key] = clampi(sub_stats[key] + delta, 0, 100)
		if delta > 0:
			gains_summary.append("%s +%d" % [GameData.sub_name(key), delta])

	if act["realm"] > 0:
		realm_progress += act["realm"]

	heart_demon = clampi(heart_demon + act["demon"], 0, 100)
	bond = clampi(bond + act["bond"], 0, 100)
	spirit_stones += act["stones"]

	# ---- 境界突破检测 ----
	var new_idx: int = GameData.realm_index(realm_progress)
	var broken := false
	var from_realm := ""
	var to_realm := ""
	if new_idx > realm_index_cache:
		broken = true
		from_realm = GameData.REALMS[realm_index_cache]["name"]
		to_realm = GameData.REALMS[new_idx]["name"]
		realm_index_cache = new_idx
		# 突破奖励：境界提升伴随精力回满的「大反馈」
		energy = ENERGY_MAX

	# ---- 女儿反馈 ----
	var fb_pool: Array = act["feedback"]
	var fb_text: String = fb_pool[randi_range(0, fb_pool.size() - 1)]

	state_changed.emit()
	if broken:
		realm_broken.emit(from_realm, to_realm)
	feedback.emit(fb_text)

	return {
		"ok": true,
		"gains_summary": gains_summary,
		"realm_broken": broken,
		"feedback_text": fb_text,
	}


# ---------- 时间推进 ----------
## 结束本月，精力回满，月/年龄推进。
func next_month() -> void:
	energy = ENERGY_MAX
	month_in_year += 1
	total_months += 1
	if month_in_year > 12:
		month_in_year = 1
		age += 1
	month_passed.emit()
	state_changed.emit()


# ---------- 调试用：快速成长（playtest 手感时用）----------
func debug_grow(amount: int = 20) -> void:
	realm_progress += amount
	var new_idx: int = GameData.realm_index(realm_progress)
	if new_idx > realm_index_cache:
		realm_index_cache = new_idx
		realm_broken.emit(GameData.REALMS[new_idx - 1]["name"], GameData.REALMS[new_idx]["name"])
	state_changed.emit()

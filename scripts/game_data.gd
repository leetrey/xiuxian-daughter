class_name GameData
## GameData —— 静态数据表（属性 / 境界 / 活动）
## 所有数值遵循 GDD §10 约定：未经 playtest 的一律标 [PLACEHOLDER]，
## 并附 rationale 与验证路径。最小闭环先保证「能跑通」，手感后调。


# ------------------------------------------------------------------
# 一、16 细分属性定义
# 结构：{key, name(中文显示), main(所属主属性)}
# 四大主属性 = 各自 4 个细分之和，用于结局判定与事件门槛；细分用于具体结算。
# ------------------------------------------------------------------
const SUB_STATS: Array[Dictionary] = [
	# —— 体魄（身）——
	{"key": "lidao",   "name": "力道", "main": "体魄"},
	{"key": "gengu",   "name": "根骨", "main": "体魄"},
	{"key": "shenfa",  "name": "身法", "main": "体魄"},
	{"key": "yizhi",   "name": "意志", "main": "体魄"},
	# —— 道法（法）——
	{"key": "zhenyuan","name": "真元", "main": "道法"},
	{"key": "shufa",   "name": "术法", "main": "道法"},
	{"key": "wuxing",  "name": "悟性", "main": "道法"},
	{"key": "huti",    "name": "护体", "main": "道法"},
	# —— 仙缘（缘）——
	{"key": "ziyi",    "name": "姿仪", "main": "仙缘"},
	{"key": "renyuan", "name": "人缘", "main": "仙缘"},
	{"key": "lijie",   "name": "礼节", "main": "仙缘"},
	{"key": "yunshi",  "name": "运势", "main": "仙缘"},
	# —— 杂学（艺）——
	{"key": "dandao",  "name": "丹道", "main": "杂学"},
	{"key": "lianqi",  "name": "炼器", "main": "杂学"},
	{"key": "danqing", "name": "丹青", "main": "杂学"},
	{"key": "yinlv",   "name": "音律", "main": "杂学"},
]

const MAIN_STATS: Array[String] = ["体魄", "道法", "仙缘", "杂学"]

# 主属性 → 该主属性下的细分 key 列表（用于 UI 展开显示）
const MAIN_TO_SUB: Dictionary = {
	"体魄": ["lidao", "gengu", "shenfa", "yizhi"],
	"道法": ["zhenyuan", "shufa", "wuxing", "huti"],
	"仙缘": ["ziyi", "renyuan", "lijie", "yunshi"],
	"杂学": ["dandao", "lianqi", "danqing", "yinlv"],
}


# ------------------------------------------------------------------
# 二、境界表（5 阶）
# threshold = 境界累积条达到该值即突破到本阶。
# rationale：练气 0 起，逐阶门槛 ×3 递增，配合单次修炼 realm 增益 +2~5，
#           约 20~40 次修炼突破一阶，使 8 年（96 月）内有望摸到化神（快节奏验证手感）。
#           [PLACEHOLDER] 阈值与单次增益的比例需 playtest 校准（H1 失败信号：10 分钟无成长反馈）。
# ------------------------------------------------------------------
const REALMS: Array[Dictionary] = [
	{"name": "练气", "threshold": 0,    "emoji": "🌱", "color": "#7d8a5a", "desc": "初入仙途，气感初生"},
	{"name": "筑基", "threshold": 120,  "emoji": "🌿", "color": "#5f9e6b", "desc": "道基初成，脱胎换骨"},
	{"name": "金丹", "threshold": 360,  "emoji": "🔶", "color": "#c9973f", "desc": "金丹一粒，寿数大增"},
	{"name": "元婴", "threshold": 720,  "emoji": "🟣", "color": "#8b5fbf", "desc": "元婴出窍，神游千里"},
	{"name": "化神", "threshold": 1200, "emoji": "✨", "color": "#d4c24f", "desc": "化神证道，超脱凡尘"},
]


# ------------------------------------------------------------------
# 三、活动表（12 个）
# 字段：
#   id / name / emoji —— 标识与显示
#   energy —— 消耗精力（行动点）
#   gains  —— {细分key: [min,max]}，执行时随机取 min~max 增益
#   realm  —— 境界累积条增量
#   demon  —— 心魔变化（+ 增 / - 减）
#   bond   —— 情缘变化
#   stones —— 灵石变化（+ 收入 / - 支出）
#   desc   —— 活动说明
#   feedback —— 女儿反馈文案池（随机挑一句）
#
# rationale 总则：精力上限 10 点/月 [PLACEHOLDER]，活动耗 2~5 点，玩家每月约做 2~4 件事，
#         形成「排日程」的取舍感；每件事都给「能看见的变化」。
# ------------------------------------------------------------------
const ACTIVITIES: Array[Dictionary] = [
	{
		"id": "train_body", "name": "修炼体魄", "emoji": "💪", "energy": 3,
		"gains": {"lidao": [2,4], "gengu": [2,4], "shenfa": [2,4], "yizhi": [2,4]},
		"realm": 2, "demon": 0, "bond": 0, "stones": 0,
		"desc": "打熬筋骨，淬炼肉身",
		"feedback": [
			"今天的功课做完了，爹。",
			"我好像力气又大了一点！",
			"蹲马步好累，但我会坚持。",
		],
	},
	{
		"id": "train_dao", "name": "参悟道法", "emoji": "📜", "energy": 3,
		"gains": {"zhenyuan": [2,4], "shufa": [2,4], "wuxing": [2,4], "huti": [2,4]},
		"realm": 2, "demon": 0, "bond": 0, "stones": 0,
		"desc": "研读功法，参悟大道",
		"feedback": [
			"这一句口诀，我好像懂了。",
			"真元在经脉里转得好顺畅。",
			"道法自然，我悟到了一点。",
		],
	},
	{
		"id": "train_xianyuan", "name": "修心养性", "emoji": "🪷", "energy": 3,
		"gains": {"ziyi": [2,4], "renyuan": [2,4], "lijie": [2,4], "yunshi": [2,4]},
		"realm": 1, "demon": -1, "bond": 0, "stones": 0,
		"desc": "修心养性，涵养仙缘",
		"feedback": [
			"心静下来了。",
			"待人接物，我好像更从容了。",
			"娘……不，爹教我的道理，我记下了。",
		],
	},
	{
		"id": "alchemy", "name": "研习丹道", "emoji": "⚗️", "energy": 2,
		"gains": {"dandao": [3,5]},
		"realm": 1, "demon": 0, "bond": 0, "stones": -5,
		"desc": "开炉炼丹，消耗药材",
		"feedback": [
			"这一炉丹药，成色不错。",
			"药性拿捏得刚刚好。",
			"炸炉了……好在没伤着。",
		],
	},
	{
		"id": "smithing", "name": "研习炼器", "emoji": "🔨", "energy": 2,
		"gains": {"lianqi": [3,5]},
		"realm": 1, "demon": 0, "bond": 0, "stones": -5,
		"desc": "锻器炼宝，消耗矿材",
		"feedback": [
			"这把小剑，我炼成了。",
			"火候还差一点，下次再来。",
			"器有灵，我在慢慢懂了。",
		],
	},
	{
		"id": "painting", "name": "研习丹青", "emoji": "🖌️", "energy": 2,
		"gains": {"danqing": [3,5]},
		"realm": 1, "demon": -1, "bond": 0, "stones": -3,
		"desc": "符画丹青，妙笔生花",
		"feedback": [
			"这幅画，我想送给爹。",
			"笔意还差点火候。",
			"画里藏着灵韵，你看见了吗？",
		],
	},
	{
		"id": "music", "name": "研习音律", "emoji": "🎵", "energy": 2,
		"gains": {"yinlv": [3,5]},
		"realm": 1, "demon": -2, "bond": 1, "stones": 0,
		"desc": "抚琴吹箫，以乐入道",
		"feedback": [
			"爹，你听这首曲子，像不像山里的风？",
			"音律能安抚心神。",
			"我新学了一支曲子。",
		],
	},
	{
		"id": "adventure", "name": "外出历练", "emoji": "⚔️", "energy": 4,
		"gains": {"lidao": [3,5], "shenfa": [3,5]},
		"realm": 4, "demon": 2, "bond": 0, "stones": 10,
		"desc": "斩妖历练，实战精进",
		"feedback": [
			"那头妖兽，我打赢了！",
			"实战和练功，果然不一样。",
			"好险，差点受伤。",
		],
	},
	{
		"id": "seclusion", "name": "闭关苦修", "emoji": "🧘", "energy": 5,
		"gains": {"wuxing": [4,6], "zhenyuan": [4,6]},
		"realm": 5, "demon": 4, "bond": -1, "stones": 0,
		"desc": "闭死关，境界精进却易生心魔",
		"feedback": [
			"闭关多日，境界又精进一分。",
			"独坐太久，有些恍惚了……",
			"我突破在即！",
		],
	},
	{
		"id": "work", "name": "打零工", "emoji": "🪙", "energy": 3,
		"gains": {},
		"realm": 0, "demon": 1, "bond": 0, "stones": 20,
		"desc": "替人跑腿做工，赚取灵石",
		"feedback": [
			"这是今天赚的灵石，给爹。",
			"工钱不多，但能贴补家用。",
			"爹，你别太累了。",
		],
	},
	{
		"id": "bond_talk", "name": "与父谈心", "emoji": "🫂", "energy": 2,
		"gains": {"yizhi": [1,2]},
		"realm": 0, "demon": -5, "bond": 3, "stones": 0,
		"desc": "与父亲说说话，解开心结",
		"feedback": [
			"爹，你年轻时候是什么样？",
			"跟你聊完，心里舒服多了。",
			"以后我养你，换我保护你。",
		],
	},
	{
		"id": "travel", "name": "游历散心", "emoji": "🏔️", "energy": 3,
		"gains": {"yunshi": [2,3], "renyuan": [2,3]},
		"realm": 0, "demon": -3, "bond": 1, "stones": -5,
		"desc": "云游四方，增长见闻",
		"feedback": [
			"外面的世界，好大呀。",
			"路上遇见的人，都挺有意思。",
			"山河壮阔，心胸也开阔了。",
		],
	},
]


# ------------------------------------------------------------------
# 工具函数
# ------------------------------------------------------------------
## 根据 key 返回细分属性的中文名
static func sub_name(key: String) -> String:
	for s in SUB_STATS:
		if s["key"] == key:
			return s["name"]
	return key

## 返回当前境界索引（0~4）
static func realm_index(progress: int) -> int:
	var idx := 0
	for i in REALMS.size():
		if progress >= REALMS[i]["threshold"]:
			idx = i
	return idx

## 返回当前境界数据
static func realm_of(progress: int) -> Dictionary:
	return REALMS[realm_index(progress)]

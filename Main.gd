extends Node

# UIはこれらのシグナルを接続してログや表示を更新できます。
signal world_log_added(message: String)
signal character_log_added(person: Character, message: String)
signal year_advanced(current_year: int)

class Character:
	extends RefCounted

	var name: String
	var camp: String
	var character: String
	var job: String = "無職"
	var age: int
	var is_alive: bool = true
	var history_log: Array[String] = []

	func _init(
		p_name: String,
		p_camp: String,
		p_character: String,
		p_age: int = 0
	) -> void:
		name = p_name
		camp = p_camp
		character = p_character
		age = p_age


@export var seconds_per_year: float = 2.0
@export var birth_probability: float = 0.15
@export var max_living_characters: int = 30

@onready var game_timer: Timer = $GameTimer

var year: int = 0
var hero_influence: float = 0.5
var demon_influence: float = 0.5
var world_history: Array[String] = []
var characters: Array[Character] = []

var _rng := RandomNumberGenerator.new()
var _next_character_id: int = 1
var relationship: float = 10.0
var diplomacy: String = "緊張"
var generation: int = 1
var reincarnated: Array[Character] = []
var regions: Array[Dictionary] = [
	{"name": "白暁の王都", "camp": "hero", "prosperity": 65},
	{"name": "翠葉の里", "camp": "hero", "prosperity": 70},
	{"name": "星霜の聖域", "camp": "neutral", "prosperity": 50},
	{"name": "紫宵の魔城", "camp": "demon", "prosperity": 65},
	{"name": "紅砂の交易市", "camp": "demon", "prosperity": 55},
	{"name": "銀嶺の関所", "camp": "neutral", "prosperity": 45},
]
var last_encounter: String = "二人の魂が、まだ見ぬ未来へ降り立った。"

const PERSONALITIES: Array[String] = ["勇敢", "野心家", "穏やか"]
const HERO_JOBS: Array[String] = ["騎士", "僧侶", "冒険者"]
const DEMON_JOBS: Array[String] = ["魔術師", "魔王軍兵士", "暗殺者"]
const NEUTRAL_JOBS: Array[String] = ["商人", "農民", "職人"]


func _ready() -> void:
	_rng.randomize()

	reincarnated.append(_create_character("アレン", "hero", "勇敢", 18))
	reincarnated.append(_create_character("リゼ", "demon", "穏やか", 18))
	_add_world_log("勇者陣営と魔王陣営の歴史が始まった。")

	# エディタで同じコールバックを接続済みでも重複接続しません。
	if not game_timer.timeout.is_connected(_on_game_timer_timeout):
		game_timer.timeout.connect(_on_game_timer_timeout)

	game_timer.wait_time = maxf(seconds_per_year, 0.1)
	game_timer.one_shot = false
	game_timer.start()
	var interface = preload("res://scripts/WorldUI.gd").new()
	interface.world = self
	add_child(interface)


func _on_game_timer_timeout() -> void:
	advance_one_year()


func advance_one_year() -> void:
	year += 1
	var previous_hero_influence := hero_influence

	# 全員の加齢を完了してからイベントを処理します。
	# ログのシグナルを受け取るUIにも、同じ年の年齢を渡せます。
	for person in characters:
		if person.is_alive:
			person.age += 1

	for person in characters:
		if person.is_alive:
			_process_character_year(person)

	# 新生児は誕生した年には加齢・行動しません。
	_try_birth()
	_update_diplomacy()
	_check_balance_change(previous_hero_influence)
	year_advanced.emit(year)


func _process_character_year(person: Character) -> void:
	# 死亡判定を先に行い、死亡後の行動を防ぎます。
	var death_probability := 0.005
	if person.age >= 60:
		death_probability += float(person.age - 59) * 0.015

	if _rng.randf() < clampf(death_probability, 0.0, 1.0):
		person.is_alive = false
		_add_character_log(person, "%d歳で死亡した。" % person.age)
		_add_world_log("%sが%d歳で亡くなった。" % [person.name, person.age])
		_shift_influence(person.camp, -0.02)
		return

	if person.age < 16:
		return

	_try_employment(person)
	_try_camp_change(person)
	_try_action(person)


func _try_employment(person: Character) -> void:
	if person.job != "無職":
		return

	var probability := 0.25
	if person.character == "野心家":
		probability = 0.45

	if _rng.randf() >= probability:
		return

	person.job = _choose_job(person.camp)
	_add_character_log(person, "%sに就職した。" % person.job)
	_shift_influence(person.camp, 0.005)


func _try_camp_change(person: Character) -> void:
	var probability := 0.02
	if person.character == "野心家":
		probability = 0.08
	elif person.character == "穏やか":
		probability = 0.04

	if _rng.randf() >= probability:
		return

	var old_camp := person.camp
	var new_camp := old_camp

	match person.character:
		"野心家":
			new_camp = "hero" if hero_influence >= demon_influence else "demon"
		"穏やか":
			new_camp = "neutral"
		_:
			new_camp = "demon" if old_camp == "hero" else "hero"

	if new_camp == old_camp:
		return

	person.camp = new_camp
	# 陣営固有の職業を持ち越さず、次年以降に再就職します。
	person.job = "無職"

	_shift_influence(old_camp, -0.015)
	_shift_influence(new_camp, 0.015)

	_add_character_log(
		person,
		"%sから%sへ陣営を変更し、職業を無職に戻した。"
		% [_camp_label(old_camp), _camp_label(new_camp)]
	)
	_add_world_log(
		"%sが%sへ移った。" % [person.name, _camp_label(new_camp)]
	)


func _try_action(person: Character) -> void:
	var probability := 0.3
	if person.character == "勇敢":
		probability = 0.55
	elif person.character == "穏やか":
		probability = 0.15

	if _rng.randf() >= probability:
		return

	if person.camp == "neutral":
		_add_character_log(person, "地域の復興を助けた。")
		# 中立の活動は両陣営の極端な勢力差を緩和します。
		hero_influence = move_toward(hero_influence, 0.5, 0.005)
		demon_influence = 1.0 - hero_influence
		return

	var success := _rng.randf() < 0.65
	var impact := 0.01 if person.job != "無職" else 0.005

	if success:
		_shift_influence(person.camp, impact)
		_add_character_log(person, "陣営の活動に成功し、勢力を広げた。")
	else:
		_shift_influence(person.camp, -impact)
		_add_character_log(person, "陣営の活動に失敗し、勢力を失った。")


func _try_birth() -> void:
	var living_count := 0
	for person in characters:
		if person.is_alive:
			living_count += 1

	# 全滅後も新しい世代が誕生し、シミュレーションが続きます。
	if living_count >= max_living_characters:
		return
	if living_count > 0 and _rng.randf() >= clampf(birth_probability, 0.0, 1.0):
		return

	var camp := "neutral"
	if _rng.randf() < 0.8:
		camp = "hero" if _rng.randf() < hero_influence else "demon"

	var personality := PERSONALITIES[
		_rng.randi_range(0, PERSONALITIES.size() - 1)
	]
	var person := _create_character(
		"転生者%d" % _next_character_id,
		camp,
		personality
	)
	_next_character_id += 1

	_shift_influence(camp, 0.005)
	_add_world_log(
		"%sが%sに誕生した。" % [person.name, _camp_label(camp)]
	)


func _create_character(
	p_name: String,
	p_camp: String,
	p_character: String,
	p_age: int = 0
) -> Character:
	var person := Character.new(p_name, p_camp, p_character, p_age)
	characters.append(person)
	_add_character_log(
		person,
		"%sとして歴史に登場した（%d歳）。" % [_camp_label(p_camp), p_age]
	)
	return person


func _choose_job(camp: String) -> String:
	var jobs: Array[String] = NEUTRAL_JOBS
	match camp:
		"hero":
			jobs = HERO_JOBS
		"demon":
			jobs = DEMON_JOBS
	return jobs[_rng.randi_range(0, jobs.size() - 1)]


func _shift_influence(camp: String, amount: float) -> void:
	# 両陣営の勢力比率は常に合計1.0とします。
	# neutralは独立した勢力比率を持ちません。
	match camp:
		"hero":
			hero_influence += amount
		"demon":
			hero_influence -= amount

	hero_influence = clampf(hero_influence, 0.0, 1.0)
	demon_influence = 1.0 - hero_influence


func _check_balance_change(previous: float) -> void:
	if previous < 0.75 and hero_influence >= 0.75:
		_add_world_log("勇者陣営が世界の主導権を握った。")
	elif previous > 0.25 and hero_influence <= 0.25:
		_add_world_log("魔王陣営が世界の主導権を握った。")


func _add_character_log(person: Character, message: String) -> void:
	var entry := "[%d年] %s" % [year, message]
	person.history_log.append(entry)
	character_log_added.emit(person, entry)


func _add_world_log(message: String) -> void:
	var entry := "[%d年] %s" % [year, message]
	world_history.append(entry)
	print(entry)
	world_log_added.emit(entry)


func _camp_label(camp: String) -> String:
	match camp:
		"hero":
			return "勇者陣営"
		"demon":
			return "魔王陣営"
		_:
			return "中立陣営"


func _update_diplomacy() -> void:
	if not reincarnated[0].is_alive and not reincarnated[1].is_alive:
		generation += 1
		reincarnated.clear()
		reincarnated.append(_create_character("アレン・%d世" % generation, "hero", PERSONALITIES[_rng.randi_range(0, 2)], 18))
		reincarnated.append(_create_character("リゼ・%d世" % generation, "demon", PERSONALITIES[_rng.randi_range(0, 2)], 18))
		relationship = 0.0
		_add_world_log("第%d世代の二人が転生した。領土と歴史は受け継がれる。" % generation)
	if reincarnated[0].is_alive and reincarnated[1].is_alive:
		var encounters: Array[String] = ["国境の祭りで語り合った", "交易路を共同で守った", "領土を巡って対立した", "民の救済に協力した", "互いの使節を拒んだ"]
		var event_index := _rng.randi_range(0, encounters.size() - 1)
		var delta: float = [12.0, 9.0, -18.0, 14.0, -15.0][event_index]
		for person in reincarnated:
			if person.character == "穏やか":
				delta += 3.0
			elif person.character == "野心家":
				delta -= 3.0
		relationship = clampf(relationship + delta, -100.0, 100.0)
		last_encounter = "%sと%sは%s。" % [reincarnated[0].name, reincarnated[1].name, encounters[event_index]]
		for person in reincarnated:
			_add_character_log(person, last_encounter)
		_add_world_log(last_encounter)
	_resolve_diplomacy()
	if diplomacy == "戦争":
		var region_index := _rng.randi_range(0, regions.size() - 1)
		var winner := "hero" if _rng.randf() < hero_influence else "demon"
		var region: Dictionary = regions[region_index]
		region.prosperity = maxi(0, int(region.prosperity) - 8)
		if region.camp != winner:
			region.camp = winner
			_shift_influence(winner, 0.03)
			_add_world_log("%sが%sを制圧した。" % [_camp_label(winner), region.name])
	elif diplomacy in ["和平", "共生"]:
		for region in regions:
			region.prosperity = mini(100, int(region.prosperity) + 2)


func _resolve_diplomacy() -> void:
	var previous := diplomacy
	# 閾値に幅を持たせ、毎年の戦争・和平の振動を防ぎます。
	if relationship <= -30.0:
		diplomacy = "戦争"
	elif relationship >= 60.0:
		diplomacy = "共生"
	elif relationship >= 20.0:
		diplomacy = "和平"
	elif diplomacy == "戦争" and relationship < 0.0:
		diplomacy = "戦争"
	else:
		diplomacy = "緊張"
	if previous != diplomacy:
		_add_world_log("両陣営の関係が「%s」から「%s」へ変化した。" % [previous, diplomacy])

extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.game_timer.stop()
	world._rng.seed = 20261016
	assert(world.reincarnated.size() == 2)
	assert(world.reincarnated[0].age == 18)
	var ui = world.get_child(world.get_child_count() - 1)
	assert(ui.cards.size() == 2)
	assert(ui.cards[0].text.contains("アレン"))
	ui.pause_button.pressed.emit()
	assert(world.game_timer.paused)
	ui.pause_button.pressed.emit()
	assert(not world.game_timer.paused)
	ui.speed_button.pressed.emit()
	assert(world.game_timer.wait_time == world.seconds_per_year / 2.0)
	ui._select_region(3)
	assert(ui.detail.text.contains("紫宵"))
	ui._toggle_library()
	assert(ui.detail.text.contains("アレン"))
	world.relationship = -60.0
	world._resolve_diplomacy()
	assert(world.diplomacy == "戦争")
	world.reincarnated[1].is_alive = false
	world.hero_influence = 1.0
	world.demon_influence = 0.0
	for region in world.regions:
		region.camp = "demon"
	world._update_diplomacy()
	var conquered := 0
	for region in world.regions:
		if region.camp == "hero":
			conquered += 1
	assert(conquered == 1, "War must update an actual region")
	assert(world.world_history[-1].contains("制圧"))
	world.relationship = 30.0
	world._resolve_diplomacy()
	assert(world.diplomacy == "和平")
	var prosperity: int = world.regions[0].prosperity
	world._update_diplomacy()
	assert(world.regions[0].prosperity == prosperity + 2)
	world.relationship = 80.0
	world._resolve_diplomacy()
	assert(world.diplomacy == "共生")
	var old_hero = world.reincarnated[0]
	old_hero.is_alive = false
	world._update_diplomacy()
	assert(world.generation == 2)
	assert(world.reincarnated[0] != old_hero)
	assert(world.characters.has(old_hero), "Prior lives remain in the library")
	for i in range(100):
		world.advance_one_year()
		assert(is_equal_approx(world.hero_influence + world.demon_influence, 1.0))
		assert(world.hero_influence >= 0.0 and world.hero_influence <= 1.0)
	assert(ui.year_label.text.contains("0100"))
	assert(world.reincarnated[0].history_log.size() > 0)
	print("PASS: UI controls, portraits, logs, war conquest, peace recovery, coexistence, succession, 100 years")
	quit(0)

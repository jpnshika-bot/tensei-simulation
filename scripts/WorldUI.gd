extends CanvasLayer

var world: Node
var year_label: Label
var relation_label: Label
var encounter_label: Label
var influence: ProgressBar
var cards: Array[RichTextLabel] = []
var map_sprites: Array[TextureRect] = []
var elapsed: float = 0.0
var chronicles: RichTextLabel
var detail: RichTextLabel
var map: Control
var territory_overlay: Control
var pause_button: Button
var speed_button: Button
var selected_region: int = 2
var speed_index: int = 0
var show_library: bool = false
const GOLD := Color("d6bd85")
const INK := Color("0c1525")
const TEXT := Color("e7e5da")
const MUTED := Color("8fa6b8")
const POINTS: Array[Vector2] = [Vector2(215, 105), Vector2(220, 315), Vector2(450, 215), Vector2(755, 110), Vector2(700, 325), Vector2(485, 52)]

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var theme := Theme.new()
	theme.default_font = load("res://assets/Japanese.ttf")
	theme.default_font_size = 16
	root.theme = theme
	var bg := ColorRect.new()
	bg.color = INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_label(root, "REINCARNATION  /  THE CHRONICLES OF TWO SOULS", Vector2(32, 20), 12, GOLD)
	_label(root, "転生シミュレーション", Vector2(30, 42), 32, TEXT)
	_label(root, "女神の観測室     ─     世界に託した、ふたつの魂の物語", Vector2(32, 89), 14, MUTED)
	year_label = _label(root, "", Vector2(870, 35), 24, GOLD)
	pause_button = _button(root, "Ⅱ  一時停止", Rect2(1110, 40, 140, 40), _toggle_pause)
	speed_button = _button(root, "時間 ×1", Rect2(1260, 40, 145, 40), _cycle_speed)
	_panel(root, Rect2(24, 126, 900, 570))
	map = Control.new()
	map.position = Vector2(25, 127)
	map.size = Vector2(898, 568)
	map.clip_contents = true
	root.add_child(map)
	var art := TextureRect.new()
	art.texture = load("res://assets/world_map.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.size = map.size
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.add_child(art)
	var shade := ColorRect.new()
	shade.size = map.size
	shade.color = Color(0.02, 0.05, 0.10, 0.13)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.add_child(shade)
	territory_overlay = Control.new()
	territory_overlay.size = map.size
	territory_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.add_child(territory_overlay)
	territory_overlay.draw.connect(_draw_map)
	for i in range(2):
		var sprite := TextureRect.new()
		sprite.texture = load("res://assets/allen.svg" if i == 0 else "res://assets/lize.svg")
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.size = Vector2(28, 32)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map.add_child(sprite)
		map_sprites.append(sprite)
	_label(map, "A S T E R I A   /   星霜大陸", Vector2(22, 17), 17, TEXT)
	_label(map, "● 勇者領    ● 魔王領    ◇ 中立領  /  地名を選択して詳細", Vector2(22, 535), 13, TEXT)
	for i in range(POINTS.size()):
		var button := _button(map, str(world.regions[i].name), Rect2(POINTS[i] - Vector2(68, 5), Vector2(136, 34)), _select_region.bind(i))
		button.tooltip_text = "地域の支配陣営と繁栄度を確認"
	_panel(root, Rect2(944, 126, 472, 136))
	_label(root, "DIPLOMACY  /  二人が紡ぐ関係", Vector2(964, 139), 13, GOLD)
	relation_label = _label(root, "", Vector2(964, 168), 22, TEXT)
	encounter_label = _label(root, "", Vector2(964, 208), 13, MUTED)
	encounter_label.size = Vector2(430, 42)
	encounter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in range(2):
		var pos := Vector2(944, 278 + i * 174)
		_panel(root, Rect2(pos, Vector2(472, 160)))
		var portrait := Control.new()
		var portrait_sheet: Texture2D = load("res://assets/portraits.png")
		var half_width: float = portrait_sheet.get_width() / 2.0
		var source_rect := Rect2(half_width * i, 0, half_width, portrait_sheet.get_height())
		portrait.position = pos + Vector2(8, 8)
		portrait.size = Vector2(96, 144)
		portrait.clip_contents = true
		portrait.draw.connect(func() -> void:
			portrait.draw_texture_rect_region(portrait_sheet, Rect2(0, 0, 96, 144), source_rect))
		root.add_child(portrait)
		var card := _rich(root, Rect2(pos + Vector2(112, 12), Vector2(344, 136)))
		cards.append(card)
	_panel(root, Rect2(944, 626, 472, 70))
	_label(root, "領土とは別に変わる、陣営の影響力", Vector2(962, 635), 12, MUTED)
	influence = ProgressBar.new()
	influence.position = Vector2(962, 663)
	influence.size = Vector2(436, 12)
	influence.show_percentage = false
	influence.add_theme_stylebox_override("background", _style(Color("73558f"), Color("73558f")))
	influence.add_theme_stylebox_override("fill", _style(Color("56bcb8"), Color("56bcb8")))
	root.add_child(influence)
	_panel(root, Rect2(24, 714, 900, 160))
	_label(root, "CHRONICLE  /  世界の年代記", Vector2(44, 725), 14, GOLD)
	chronicles = _rich(root, Rect2(44, 757, 858, 100))
	chronicles.scroll_following = true
	_panel(root, Rect2(944, 714, 472, 160))
	detail = _rich(root, Rect2(964, 728, 430, 126))
	_button(root, "図書館 / 人物の生涯", Rect2(700, 722, 202, 29), _toggle_library)
	world.year_advanced.connect(_refresh.unbind(1))
	_refresh()

func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style

func _panel(parent: Node, rect: Rect2) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _style(Color("111e30"), Color("344557")))
	parent.add_child(panel)

func _label(parent: Node, text: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _rich(parent: Node, rect: Rect2) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.position = rect.position
	label.size = rect.size
	label.bbcode_enabled = true
	label.add_theme_color_override("default_color", TEXT)
	label.add_theme_font_size_override("normal_font_size", 15)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", _style(Color(0.04, 0.09, 0.16, 0.90), Color("8b7d62")))
	button.add_theme_stylebox_override("hover", _style(Color("304359"), GOLD))
	button.add_theme_stylebox_override("pressed", _style(Color("526078"), GOLD))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _refresh() -> void:
	year_label.text = "第 %d 世代  ·  %04d 年" % [world.generation, world.year]
	relation_label.text = "%s  /  友好度 %+d" % [world.diplomacy, int(world.relationship)]
	relation_label.modulate = Color("ef9c88") if world.diplomacy == "戦争" else Color("9edbcb")
	encounter_label.text = world.last_encounter
	influence.value = world.hero_influence * 100.0
	influence.tooltip_text = "勇者 %.0f%% / 魔王 %.0f%%" % [world.hero_influence * 100, world.demon_influence * 100]
	for i in range(2):
		var person = world.reincarnated[i]
		var color := "8fd9d3" if i == 0 else "c5a6ed"
		var recent: String = person.history_log[-1] if not person.history_log.is_empty() else ""
		cards[i].text = "[color=#%s][font_size=23]%s[/font_size][/color]\n%d歳 · %s · %s\n%s / %s\n[color=#98adbe]%s[/color]" % [color, person.name, person.age, person.character, person.job, world._camp_label(person.camp), "生存" if person.is_alive else "故人", recent]
	var logs: Array[String] = []
	for i in range(maxi(0, world.world_history.size() - 60), world.world_history.size()):
		logs.append(world.world_history[i])
	chronicles.text = "\n".join(logs)
	_refresh_detail()
	territory_overlay.queue_redraw()

func _draw_map() -> void:
	for i in range(POINTS.size()):
		var region: Dictionary = world.regions[i]
		var color := Color("70d9cb") if region.camp == "hero" else Color("bd8ae7")
		if region.camp == "neutral":
			color = GOLD
		var center := POINTS[i] + Vector2(0, 37)
		var territory := PackedVector2Array([
			center + Vector2(-62, -40), center + Vector2(12, -56),
			center + Vector2(68, -16), center + Vector2(55, 42),
			center + Vector2(-14, 55), center + Vector2(-70, 16)])
		territory_overlay.draw_colored_polygon(territory, Color(color, 0.19))
		territory.append(territory[0])
		territory_overlay.draw_polyline(territory, Color(color, 0.65), 1.5, true)
		territory_overlay.draw_circle(center, 28, Color(color, 0.18))
		territory_overlay.draw_arc(center, 28, 0, TAU, 32, color, 2, true)
		territory_overlay.draw_circle(center, 5, color)
		if world.diplomacy == "戦争":
			territory_overlay.draw_line(center + Vector2(-10, -12), center + Vector2(10, 12), Color("ffb199"), 3)
			territory_overlay.draw_line(center + Vector2(10, -12), center + Vector2(-10, 12), Color("ffb199"), 3)
		elif world.diplomacy in ["和平", "共生"] and i < POINTS.size() - 1:
			territory_overlay.draw_dashed_line(center, POINTS[i + 1] + Vector2(0, 37), Color(0.7, 0.9, 0.7, 0.55), 2, 8)
		if i == selected_region:
			territory_overlay.draw_arc(center, 34, 0, TAU, 32, Color("fff0c3"), 1, true)

func _select_region(index: int) -> void:
	selected_region = index
	show_library = false
	_refresh_detail()
	territory_overlay.queue_redraw()

func _refresh_detail() -> void:
	if show_library:
		var lines: Array[String] = ["[color=#d6bd85]魂の図書館 / 全世代の個人史[/color]"]
		for person in world.characters:
			lines.append("\n[b]%s · %d歳 · %s[/b]" % [person.name, person.age, "生存" if person.is_alive else "故人"])
			lines.append("\n".join(person.history_log))
		detail.text = "\n".join(lines)
	else:
		var region: Dictionary = world.regions[selected_region]
		detail.text = "[color=#d6bd85][font_size=21]%s[/font_size][/color]\n%s  /  繁栄度 %d\n%s\n地名をクリックして、移りゆく世界を観測。" % [region.name, world._camp_label(region.camp), region.prosperity, "交戦中：支配と繁栄が変化します" if world.diplomacy == "戦争" else "共生・和平で交易路が開き、繁栄が回復"]

func _toggle_pause() -> void:
	world.game_timer.paused = not world.game_timer.paused
	pause_button.text = "▶  再開" if world.game_timer.paused else "Ⅱ  一時停止"

func _cycle_speed() -> void:
	speed_index = (speed_index + 1) % 3
	var multiplier: int = [1, 2, 5][speed_index]
	world.game_timer.wait_time = world.seconds_per_year / multiplier
	speed_button.text = "時間 ×%d" % multiplier

func _toggle_library() -> void:
	show_library = not show_library
	_refresh_detail()


func _process(delta: float) -> void:
	elapsed += delta
	for i in range(map_sprites.size()):
		var person = world.reincarnated[i]
		var home: int = 0 if person.camp == "hero" else 3
		if person.camp == "neutral":
			home = 2
		map_sprites[i].position = POINTS[home] + Vector2(-14 + i * 25, 65 + sin(elapsed * 2.0 + i) * 2.0)
		map_sprites[i].modulate = Color.WHITE if person.is_alive else Color(0.5, 0.5, 0.5, 0.5)

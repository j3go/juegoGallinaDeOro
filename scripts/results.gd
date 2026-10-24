class_name ResultsScreen
extends Control
## End-of-match screen: winner (or tie), full ranking and a replay button.

signal play_again_pressed
signal menu_pressed

const MEDALS := [Color(1.0, 0.78, 0.22), Color(0.78, 0.8, 0.85), Color(0.86, 0.56, 0.32), Color(0.75, 0.7, 0.65)]

var _winner_label: Label
var _rows: VBoxContainer
var _panel: PanelContainer
var _again: Button
var _menu: Button


func _ready() -> void:
	_build()
	hide()


## `ranking` must be sorted by score, highest first.
func show_results(ranking: Array[CharacterBase]) -> void:
	for child in _rows.get_children():
		child.queue_free()

	var top := ranking[0].score
	var winners := ranking.filter(func(c: CharacterBase) -> bool: return c.score == top)
	if top == 0:
		_winner_label.text = "Nadie atrapó huevos… ¡empate!"
	elif winners.size() == 1:
		var w: CharacterBase = winners[0]
		_winner_label.text = "¡GANASTE!" if w.is_player else "Ganó %s" % w.display_name
	else:
		var names := PackedStringArray()
		for w: CharacterBase in winners:
			names.append(w.display_name)
		_winner_label.text = "¡Empate entre %s!" % _join_names(names)

	var place := 0
	for i in ranking.size():
		var c := ranking[i]
		if i == 0 or c.score != ranking[i - 1].score:
			place = i + 1
		_rows.add_child(_make_row(place, c))

	show()
	modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * 0.85
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 1.0, 0.3)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Ignore clicks for a moment so a stray click from the match doesn't skip the results.
	_again.disabled = true
	_menu.disabled = true
	await get_tree().create_timer(1.0, true, false, true).timeout
	_again.disabled = false
	_menu.disabled = false
	_again.grab_focus()


func set_map_change_available(available: bool) -> void:
	_menu.visible = available


func _make_row(place: int, c: CharacterBase) -> Control:
	var row_panel := PanelContainer.new()
	var bg := Color(UITheme.GOLD, 0.3) if c.is_player else Color(1, 1, 1, 0.5)
	row_panel.add_theme_stylebox_override("panel", UITheme.box_style(bg, 16, 14, Color(0, 0, 0, 0), 0, false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row_panel.add_child(row)

	var medal := PanelContainer.new()
	medal.custom_minimum_size = Vector2(44, 44)
	medal.add_theme_stylebox_override("panel", UITheme.box_style(MEDALS[mini(place - 1, 3)], 22, 0, Color(0, 0, 0, 0), 0, false))
	var num := UITheme.label(str(place), 24, UITheme.TEXT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	medal.add_child(num)
	row.add_child(medal)

	row.add_child(UITheme.dot(c.team_color, 20))
	var name_label := UITheme.label(c.display_name, 28)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var eggs := UITheme.label("%d %s" % [c.score, "huevo" if c.score == 1 else "huevos"], 26, UITheme.GOLD_DARK)
	row.add_child(eggs)
	UITheme.ignore_mouse(row_panel)
	return row_panel


func _join_names(names: PackedStringArray) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " y " + names[names.size() - 1]


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.25, 0.17, 0.1, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = UITheme.panel(UITheme.PANEL, 30, 34)
	_panel.custom_minimum_size.x = 560
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	var title := UITheme.label("¡Fin de la partida!", 26, UITheme.TEXT_SOFT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_winner_label = UITheme.label("", 52, UITheme.GOLD, 18, Color(0.45, 0.26, 0.1))
	_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_winner_label)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	box.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	_again = UITheme.button("Volver a jugar", 30)
	_again.custom_minimum_size.x = 250
	_again.pressed.connect(func() -> void: play_again_pressed.emit())
	buttons.add_child(_again)
	_menu = UITheme.button("Cambiar mapa", 30)
	_menu.custom_minimum_size.x = 230
	_menu.add_theme_stylebox_override("normal", UITheme.box_style(Color(1, 0.98, 0.93), 22, 28, Color(0.8, 0.7, 0.55), 7))
	_menu.add_theme_stylebox_override("hover", UITheme.box_style(Color(1, 1, 0.97), 22, 28, Color(0.8, 0.7, 0.55), 7))
	_menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_menu)

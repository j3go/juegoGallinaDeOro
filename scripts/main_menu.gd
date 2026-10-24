class_name MainMenu
extends Control
## Title screen shown over the live level.

signal play_pressed
signal sound_pressed
signal level_selected(index: int)

var _title: Label
var _play: Button
var _level_row: HBoxContainer


func _ready() -> void:
	_build()
	hide()


func show_menu() -> void:
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play.grab_focus()


## Builds one selectable card per map. Choosing another map emits `level_selected`.
func setup_levels(levels: Array, selected: int) -> void:
	# Nothing to choose with a single map.
	_level_row.get_parent().get_child(_level_row.get_index() - 1).visible = levels.size() > 1
	_level_row.visible = levels.size() > 1
	var group := ButtonGroup.new()
	for i in levels.size():
		var info: Dictionary = levels[i]
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = group
		card.button_pressed = i == selected
		card.text = "%s\n%s" % [info["name"], info["subtitle"]]
		card.custom_minimum_size = Vector2(250, 84)
		card.add_theme_font_override("font", UITheme.font())
		card.add_theme_font_size_override("font_size", 22)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			card.add_theme_color_override(state, UITheme.TEXT)
		var idle := UITheme.box_style(Color(1, 0.98, 0.93, 0.8), 18, 18, Color(0.8, 0.7, 0.55), 4)
		var hover := UITheme.box_style(Color(1, 0.98, 0.93, 0.95), 18, 18, Color(0.8, 0.7, 0.55), 4)
		var chosen := UITheme.box_style(UITheme.GOLD_LIGHT, 18, 18, UITheme.GOLD_DARK, 6)
		card.add_theme_stylebox_override("normal", idle)
		card.add_theme_stylebox_override("hover", hover)
		card.add_theme_stylebox_override("pressed", chosen)
		card.add_theme_stylebox_override("hover_pressed", chosen)
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.pressed.connect(func() -> void: level_selected.emit(i))
		_level_row.add_child(card)


func hide_menu() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(hide)


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(1.0, 0.95, 0.82, 0.3)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	_title = UITheme.label("Golden Chicken", 104, UITheme.GOLD, 30, Color(0.45, 0.26, 0.1))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	var subtitle := UITheme.label("Seis jugadores, una gallina con puntería. ¡Terminá con más huevos de oro que nadie!",
			24, UITheme.TEXT, 10, Color(1, 1, 1, 0.9))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	var pick := UITheme.label("Elegí el mapa", 20, UITheme.TEXT_SOFT, 8, Color(1, 1, 1, 0.9))
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pick)
	_level_row = HBoxContainer.new()
	_level_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_level_row.add_theme_constant_override("separation", 16)
	box.add_child(_level_row)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	box.add_child(spacer)
	_play = UITheme.button("¡JUGAR!", 38)
	_play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_play.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(_play)
	var sound := UITheme.button("Sonido", 26)
	sound.custom_minimum_size = Vector2(200, 56)
	sound.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sound.pressed.connect(func() -> void: sound_pressed.emit())
	box.add_child(sound)

	var help := UITheme.panel(Color(1, 0.98, 0.93, 0.85), 18, 18)
	help.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(help)
	var help_text := UITheme.label(
			"WASD mover  ·  E recoger  ·  F / clic izq. empujar  ·  G / clic der. agarrar  ·  Q usar objeto  ·  Esc sonido y pausa\nLa gallina le dispara al que tenga más huevos: ¡mirá el láser y esquivá!",
			19, UITheme.TEXT_SOFT)
	help_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_child(help_text)

	# Gentle floating title.
	var tw := create_tween().set_loops()
	tw.tween_property(_title, "position:y", -8.0, 1.2).as_relative().set_trans(Tween.TRANS_SINE)
	tw.tween_property(_title, "position:y", 8.0, 1.2).as_relative().set_trans(Tween.TRANS_SINE)

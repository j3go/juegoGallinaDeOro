class_name SoundMenu
extends Control
## Sound settings panel: general, music and effects volume sliders (0-150 %) and mute. Opens
## from the main menu or in game with O (the game pauses meanwhile). Changes apply live and are
## saved on close.

signal closed

const ROWS := [["Master", "General"], ["Music", "Música"], ["SFX", "Efectos"]]

## Bus name -> [slider, percent label].
var _sliders := {}
var _mute: CheckBox
var _paused_note: Label
var _done: Button
var _prev_mouse := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()


func open(paused: bool) -> void:
	for bus: String in _sliders:
		(_sliders[bus][0] as HSlider).set_value_no_signal(roundf(AudioSettings.get_volume(bus) * 100.0))
	_mute.set_pressed_no_signal(AudioSettings.muted)
	_refresh()
	_paused_note.visible = paused
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	_done.grab_focus()


func close() -> void:
	if not visible:
		return
	AudioSettings.save()
	hide()
	if _prev_mouse == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _input(event: InputEvent) -> void:
	# Esc / O close the panel (handled here so the same key press doesn't reopen it).
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_mouse") \
			or event.is_action_pressed("sound_menu")):
		get_viewport().set_input_as_handled()
		close()


func _refresh() -> void:
	for bus: String in _sliders:
		var slider: HSlider = _sliders[bus][0]
		var percent: Label = _sliders[bus][1]
		percent.text = "%d %%" % int(slider.value)
		slider.modulate.a = 0.45 if _mute.button_pressed else 1.0
		percent.modulate.a = slider.modulate.a


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.08, 0.05, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UITheme.panel(UITheme.PANEL, 26, 34)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)

	var title := UITheme.label("Sonido", 52, UITheme.GOLD, 16, Color(0.45, 0.26, 0.1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_paused_note = UITheme.label("Juego en pausa", 20, UITheme.TEXT_SOFT)
	_paused_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_paused_note)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	for row: Array in ROWS:
		_add_row(grid, row[0], row[1])

	_mute = CheckBox.new()
	_mute.text = "Silenciar todo"
	_mute.add_theme_font_override("font", UITheme.font())
	_mute.add_theme_font_size_override("font_size", 26)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_mute.add_theme_color_override(state, UITheme.TEXT)
	_mute.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mute.toggled.connect(func(on: bool) -> void:
		AudioSettings.set_muted(on)
		_refresh()
		if not on:
			Sfx.play(self, Sfx.COLLECT))
	box.add_child(_mute)

	var hint := UITheme.label("Se guarda solo  ·  Esc u O para cerrar", 18, UITheme.TEXT_SOFT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_done = UITheme.button("Listo", 30)
	_done.custom_minimum_size = Vector2(220, 64)
	_done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_done.pressed.connect(close)
	box.add_child(_done)


func _add_row(grid: GridContainer, bus: String, title: String) -> void:
	grid.add_child(UITheme.label(title, 28))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = AudioSettings.MAX_VOLUME * 100.0
	slider.step = 5.0
	slider.custom_minimum_size = Vector2(380, 44)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var track := UITheme.box_style(Color(0.85, 0.78, 0.66), 8, 0, Color(0, 0, 0, 0), 0, false)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var filled := UITheme.box_style(UITheme.GOLD, 8, 0, Color(0, 0, 0, 0), 0, false)
	filled.content_margin_top = 6
	filled.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	slider.value_changed.connect(func(value: float) -> void:
		AudioSettings.set_volume(bus, value / 100.0)
		_refresh())
	# Short sample when letting go, so you hear the new level (music is already playing).
	if bus != "Music":
		slider.drag_ended.connect(func(_changed: bool) -> void: Sfx.play(self, Sfx.COLLECT))
	grid.add_child(slider)
	var percent := UITheme.label("100 %", 28, UITheme.TEXT)
	percent.custom_minimum_size.x = 96
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(percent)
	_sliders[bus] = [slider, percent]

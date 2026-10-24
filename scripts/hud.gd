class_name HUD
extends Control
## In-match overlay: time left, player's eggs and rank, live leaderboard and messages.

const MAX_FEED := 3

var _player: CharacterBase
var _competitors: Array[CharacterBase] = []
var _rows := {}

var _eggs_label: Label
var _rank_label: Label
var _time_label: Label
var _time_panel: PanelContainer
var _board: VBoxContainer
var _feed: VBoxContainer
var _countdown: Label
var _last_second := -1
var _leader_label: Label
var _wave_label: Label
var _item_label: Label
var _grab_label: Label
var _push_label: Label
var _state_label: Label


func _ready() -> void:
	_build()
	UITheme.ignore_mouse(self)


func setup(competitors: Array[CharacterBase]) -> void:
	_competitors = competitors
	for c in competitors:
		if c.is_player:
			_player = c
		_add_row(c)
	refresh_scores()


func update_time(seconds_left: float) -> void:
	var total := int(ceil(seconds_left))
	_time_label.text = "%d:%02d" % [total / 60, total % 60]
	var urgent := total <= 10
	_time_label.add_theme_color_override("font_color", UITheme.DANGER if urgent else UITheme.TEXT)
	if urgent and total != _last_second and total > 0:
		_pop(_time_label, 1.25)
	_last_second = total


## Per-frame info for the player: item, grab/push state, protection, leader and next wave.
func update_status(player: CharacterBase, next_wave: float, leaders: Array[CharacterBase]) -> void:
	if leaders.is_empty():
		_leader_label.text = "Líder: nadie todavía"
	else:
		var names := PackedStringArray()
		for c in leaders:
			names.append(c.display_name)
		_leader_label.text = "Líder: %s (%d)" % [", ".join(names), leaders[0].score]
	_wave_label.text = "Objetos en %d s" % ceili(next_wave) if next_wave > 0.0 else ""
	_item_label.text = "[Q] %s" % CharacterBase.ITEM_NAMES[player.item]
	var now := GameClock.now
	if player.outgoing_link:
		_grab_label.text = "Agarrando %.1f s" % player.ctx.grab_system.time_left(player.outgoing_link)
		_grab_label.add_theme_color_override("font_color", UITheme.ACCENT)
	elif player.grab_cooldown_left() > 0.0:
		_grab_label.text = "[G] Agarre en %d s" % ceili(player.grab_cooldown_left())
		_grab_label.add_theme_color_override("font_color", UITheme.TEXT_SOFT)
	else:
		_grab_label.text = "[G] Agarre listo"
		_grab_label.add_theme_color_override("font_color", UITheme.TEXT)
	_push_label.text = "[F] Empujar" if now >= player.push_ready_at else "[F] ..."
	var state := ""
	var color := UITheme.TEXT
	if player.is_down():
		state = "¡Derribado!"
		color = UITheme.DANGER
	elif player.is_recovering():
		state = "Recuperándote"
		color = UITheme.TEXT_SOFT
	elif not player.incoming_links.is_empty():
		var longest := 0.0
		for l in player.incoming_links:
			longest = maxf(longest, player.ctx.grab_system.time_left(l))
		state = "¡Te agarran! %.1f s · no podés recoger" % longest
		color = UITheme.DANGER
	elif player.outgoing_link:
		state = "No podés recoger mientras agarrás"
		color = UITheme.ACCENT
	if player.is_immortal():
		state = ("Inmortal %.1f s" % player.immortal_time_left()) + ("  ·  " + state if state != "" else "")
		color = UITheme.GOLD_DARK
	_state_label.text = state if state != "" else "[E] Recoger"
	_state_label.add_theme_color_override("font_color", color)


func refresh_scores() -> void:
	if _player == null:
		return
	_eggs_label.text = str(_player.score)
	var rank := 1
	var tied := false
	for c in _competitors:
		if c == _player:
			continue
		if c.score > _player.score:
			rank += 1
		elif c.score == _player.score:
			tied = true
	_rank_label.text = "Posición: %dº de %d%s" % [rank, _competitors.size(), " (empate)" if tied else ""]

	var sorted: Array[CharacterBase] = []
	sorted.assign(_competitors)
	sorted.sort_custom(func(a: CharacterBase, b: CharacterBase) -> bool:
		return a.score > b.score or (a.score == b.score and a.is_player and not b.is_player))
	for i in sorted.size():
		var row: Dictionary = _rows[sorted[i]]
		_board.move_child(row.panel, i)
		var score_label: Label = row.score
		if score_label.text != str(sorted[i].score):
			score_label.text = str(sorted[i].score)
			_pop(score_label, 1.5)


func on_egg_collected(collector: CharacterBase) -> void:
	refresh_scores()
	if collector == _player:
		_pop(_eggs_label, 1.6)
		push_message("¡Recogiste un huevo!", UITheme.GOLD_DARK)
	else:
		push_message("%s recogió un huevo" % collector.display_name, collector.team_color.darkened(0.25))


func push_message(text: String, color: Color) -> void:
	var l := UITheme.label(text, 22, color, 8, Color(1, 1, 1, 0.9))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feed.add_child(l)
	while _feed.get_child_count() > MAX_FEED:
		_feed.get_child(0).free()
	var tw := l.create_tween()
	l.modulate.a = 0.0
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func show_countdown(text: String) -> void:
	_countdown.text = text
	_countdown.modulate.a = 1.0
	_countdown.pivot_offset = _countdown.size * 0.5
	_countdown.scale = Vector2.ONE * 2.2
	var tw := _countdown.create_tween()
	tw.tween_property(_countdown, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.4)
	tw.tween_property(_countdown, "modulate:a", 0.0, 0.25)


# --- Layout ----------------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)

	# Left: player's eggs and rank.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(left)
	var mine := UITheme.panel()
	mine.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(mine)
	var mine_box := HBoxContainer.new()
	mine_box.add_theme_constant_override("separation", 14)
	mine.add_child(mine_box)
	var icon := EggIcon.new()
	icon.custom_minimum_size = Vector2(46, 58)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mine_box.add_child(icon)
	var mine_text := VBoxContainer.new()
	mine_text.add_theme_constant_override("separation", -6)
	mine_box.add_child(mine_text)
	mine_text.add_child(UITheme.label("TUS HUEVOS", 15, UITheme.TEXT_SOFT))
	_eggs_label = UITheme.label("0", 46)
	mine_text.add_child(_eggs_label)
	_rank_label = UITheme.label("Posición: 1º de 4", 17, UITheme.ACCENT)
	mine_text.add_child(_rank_label)

	# Center: timer and message feed.
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 10)
	top.add_child(center)
	_time_panel = UITheme.panel(UITheme.PANEL, 26, 26)
	_time_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(_time_panel)
	_time_label = UITheme.label("3:00", 48)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.custom_minimum_size.x = 130
	_time_panel.add_child(_time_label)
	_leader_label = UITheme.label("Líder: nadie todavía", 18, UITheme.GOLD_DARK, 8, Color(1, 1, 1, 0.9))
	_leader_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_leader_label)
	_wave_label = UITheme.label("", 16, UITheme.TEXT_SOFT, 6, Color(1, 1, 1, 0.85))
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_wave_label)
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 2)
	center.add_child(_feed)

	# Right: leaderboard.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)
	var board_panel := UITheme.panel()
	board_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(board_panel)
	var board_box := VBoxContainer.new()
	board_box.add_theme_constant_override("separation", 6)
	board_panel.add_child(board_box)
	board_box.add_child(UITheme.label("CLASIFICACIÓN", 15, UITheme.TEXT_SOFT))
	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 4)
	board_box.add_child(_board)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	# Action bar: item, grab, push and the player's state (grabbed, down, immortal...).
	var bar := UITheme.panel(UITheme.PANEL, 20, 16)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bar)
	var bar_box := VBoxContainer.new()
	bar_box.add_theme_constant_override("separation", 2)
	bar.add_child(bar_box)
	_state_label = UITheme.label("[E] Recoger", 22)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_box.add_child(_state_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 26)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_box.add_child(actions)
	_item_label = UITheme.label("[Q] —", 18, UITheme.TEXT_SOFT)
	_grab_label = UITheme.label("[G] Agarre listo", 18)
	_push_label = UITheme.label("[F] Empujar", 18)
	for l in [_push_label, _grab_label, _item_label]:
		actions.add_child(l)

	_countdown = UITheme.label("", 150, UITheme.GOLD, 26, UITheme.TEXT)
	_countdown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.modulate.a = 0.0
	add_child(_countdown)


func _add_row(c: CharacterBase) -> void:
	var row_panel := PanelContainer.new()
	var highlight := Color(UITheme.GOLD, 0.35) if c.is_player else Color(0, 0, 0, 0)
	row_panel.add_theme_stylebox_override("panel", UITheme.box_style(highlight, 12, 10, Color(0, 0, 0, 0), 0, false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row_panel.add_child(row)
	row.add_child(UITheme.dot(c.team_color))
	var name_label := UITheme.label(c.display_name, 22)
	name_label.custom_minimum_size.x = 96
	row.add_child(name_label)
	var score_label := UITheme.label("0", 24)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.custom_minimum_size.x = 36
	row.add_child(score_label)
	_board.add_child(row_panel)
	UITheme.ignore_mouse(row_panel)
	_rows[c] = {"panel": row_panel, "score": score_label}


func _pop(control: Control, amount: float) -> void:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * amount
	var tw := control.create_tween()
	tw.tween_property(control, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

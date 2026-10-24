extends Node3D
## Runs the match flow: menu -> countdown -> 3 minute match -> results -> replay.
## Loads the map, places the six competitors on its spawn markers and wires the systems of
## design doc v0.1 (chicken shots, grab chains, item waves) through a shared MatchContext.

signal match_started
signal match_finished(ranking: Array[CharacterBase])

enum Phase { LOADING, MENU, COUNTDOWN, PLAYING, FINISHED }

## Playable maps. With a single entry the menu hides the map picker.
const LEVELS := [
	{"name": "Noche en la Granja", "subtitle": "Granja embrujada", "scene": "res://scenes/world/night_farm.tscn"},
]

## Survive scene reloads so "Volver a jugar" skips the title screen and keeps the map.
static var _skip_menu := false
static var selected_level := 0

@export var config: GameConfig

var phase: Phase = Phase.LOADING
var time_left := 0.0
var competitors: Array[CharacterBase] = []
var level: Level
var ctx := MatchContext.new()
var _crowns: Array[Node3D] = []
var sound_menu: SoundMenu

@onready var egg_manager: EggManager = $EggManager
@onready var item_manager: ItemManager = $ItemManager
@onready var grab_system: GrabSystem = $GrabSystem
@onready var chicken: Chicken = $Chicken
@onready var player: PlayerController = $Player
@onready var npc_root: Node3D = $NPCs
@onready var hud: HUD = $UI/HUD
@onready var main_menu: MainMenu = $UI/MainMenu
@onready var results: ResultsScreen = $UI/Results


func _ready() -> void:
	AudioSettings.load_and_apply()
	_start_music()
	sound_menu = SoundMenu.new()
	$UI.add_child(sound_menu)
	sound_menu.closed.connect(_on_sound_menu_closed)
	var args := OS.get_cmdline_user_args()
	if "--autotest" in args:
		_skip_menu = not "--show-menu" in args
		add_child(load("res://scripts/debug/dev_tools.gd").new())
	for arg in args:
		if arg.begins_with("--level="):
			selected_level = clampi(int(arg.trim_prefix("--level=")), 0, LEVELS.size() - 1)

	competitors.append(player)
	for child in npc_root.get_children():
		if child is CharacterBase:
			competitors.append(child)
	for c in competitors:
		c.score_changed.connect(_on_score_changed)
	egg_manager.egg_collected.connect(_on_egg_collected)
	main_menu.play_pressed.connect(start_match)
	main_menu.sound_pressed.connect(open_sound_menu)
	main_menu.level_selected.connect(_on_level_selected)
	main_menu.setup_levels(LEVELS, selected_level)
	results.play_again_pressed.connect(restart)
	results.menu_pressed.connect(go_to_menu)
	results.set_map_change_available(LEVELS.size() > 1)
	_load_level()

	hud.setup(competitors)
	hud.hide()
	time_left = config.match_duration
	hud.update_time(time_left)

	await level.wait_for_navigation()
	ctx.config = config
	ctx.level = level
	ctx.egg_manager = egg_manager
	ctx.item_manager = item_manager
	ctx.grab_system = grab_system
	ctx.chicken = chicken
	ctx.competitors = competitors
	ctx.world_root = self
	egg_manager.level = level
	item_manager.level = level
	grab_system.setup(config, competitors)
	chicken.setup(ctx)
	chicken.attack_started.connect(_on_attack_started)
	item_manager.wave_spawned.connect(func(count: int) -> void: hud.push_message("¡Llegaron %d objetos!" % count, UITheme.ACCENT))
	for c in competitors:
		c.setup_match(ctx)
		c.status_changed.connect(_on_status_changed)

	phase = Phase.MENU
	if _skip_menu:
		start_match()
	else:
		main_menu.show_menu()


func _process(delta: float) -> void:
	if phase != Phase.PLAYING:
		return
	time_left = maxf(time_left - delta, 0.0)
	hud.update_time(time_left)
	hud.update_status(player, item_manager.time_to_next_wave(), _leaders())
	_update_crowns()
	if time_left <= 0.0:
		_finish_match()


func _unhandled_input(event: InputEvent) -> void:
	# Esc or O: sound menu (frees the mouse and pauses the match until it is closed).
	if (event.is_action_pressed("sound_menu") or event.is_action_pressed("toggle_mouse")) and not sound_menu.visible:
		get_viewport().set_input_as_handled()
		open_sound_menu()


## Calm comic war march (tools/gen_audio.py), looping on the "Music" bus. It keeps playing while
## the game is paused so the music volume can be heard while adjusting it.
func _start_music() -> void:
	var path := "res://assets/music/battle_theme.ogg"
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStreamOggVorbis
	stream.loop = true
	var music := AudioStreamPlayer.new()
	music.name = "Music"
	music.stream = stream
	music.bus = "Music"
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music)
	music.play()


## Sound settings. During a match the game pauses until the panel is closed.
func open_sound_menu() -> void:
	var pause := phase == Phase.PLAYING or phase == Phase.COUNTDOWN
	get_tree().paused = pause
	sound_menu.open(pause)


func _on_sound_menu_closed() -> void:
	get_tree().paused = false
	if main_menu.visible:
		main_menu.show_menu()


func start_match() -> void:
	if phase != Phase.MENU:
		return
	phase = Phase.COUNTDOWN
	if main_menu.visible:
		main_menu.hide_menu()
	hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for i in range(config.countdown_seconds, 0, -1):
		hud.show_countdown(str(i))
		Sfx.play(self, Sfx.BEEP, -6.0)
		await get_tree().create_timer(1.0).timeout
	hud.show_countdown("¡YA!")
	Sfx.play(self, Sfx.GO, -4.0)

	phase = Phase.PLAYING
	for c in competitors:
		c.set_active(true)
	chicken.start_attacking()
	item_manager.start()
	match_started.emit()


func get_ranking() -> Array[CharacterBase]:
	var ranking: Array[CharacterBase] = []
	ranking.assign(competitors)
	ranking.sort_custom(func(a: CharacterBase, b: CharacterBase) -> bool:
		return a.score > b.score or (a.score == b.score and a.is_player and not b.is_player))
	return ranking


func restart() -> void:
	_skip_menu = true
	get_tree().reload_current_scene()


func go_to_menu() -> void:
	_skip_menu = false
	get_tree().reload_current_scene()


func _load_level() -> void:
	level = (load(LEVELS[selected_level]["scene"]) as PackedScene).instantiate() as Level
	level.name = "Level"
	add_child(level)
	move_child(level, 0)
	player.place_at(level.get_spawn("Player", player.global_position))
	var npcs := npc_root.get_children()
	for i in npcs.size():
		var npc := npcs[i] as Node3D
		npc.global_position = level.get_spawn("NPC%d" % (i + 1), npc.global_position)
	chicken.global_position = level.get_spawn("Chicken", chicken.global_position)


func _on_level_selected(index: int) -> void:
	if index == selected_level:
		return
	selected_level = index
	go_to_menu()


func _finish_match() -> void:
	phase = Phase.FINISHED
	chicken.stop_attacking()
	item_manager.stop()
	grab_system.release_all()
	for c in competitors:
		c.set_active(false)

	var ranking := get_ranking()
	var top := ranking[0].score
	for c in competitors:
		c.celebrate(top > 0 and c.score == top)
	hud.show_countdown("¡TIEMPO!")
	Sfx.play(self, Sfx.END, -4.0)
	match_finished.emit(ranking)

	await get_tree().create_timer(1.8).timeout
	hud.hide()
	for crown in _crowns:
		crown.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	results.show_results(ranking)


func _on_score_changed(_character: CharacterBase, _score: int) -> void:
	hud.refresh_scores()


func _on_egg_collected(_egg: GoldenEgg, collector: CharacterBase) -> void:
	hud.on_egg_collected(collector)


func _on_status_changed(character: CharacterBase) -> void:
	if character == player:
		hud.update_status(player, item_manager.time_to_next_wave(), _leaders())


func _on_attack_started(target: CharacterBase) -> void:
	if target == player:
		hud.push_message("¡La gallina te apunta!", UITheme.DANGER)


## Characters carrying the most eggs (none while nobody has eggs).
func _leaders() -> Array[CharacterBase]:
	var best := 0
	for c in competitors:
		best = maxi(best, c.score)
	var result: Array[CharacterBase] = []
	if best > 0:
		for c in competitors:
			if c.score == best:
				result.append(c)
	return result


## Small golden crown floating over each leader.
func _update_crowns() -> void:
	var leaders := _leaders()
	while _crowns.size() < competitors.size():
		_crowns.append(_make_crown())
	for i in _crowns.size():
		var crown := _crowns[i]
		crown.visible = i < leaders.size()
		if crown.visible:
			crown.global_position = leaders[i].global_position + Vector3.UP * 2.35
			crown.rotation.y += get_process_delta_time() * 2.0


func _make_crown() -> Node3D:
	var crown := Node3D.new()
	add_child(crown)
	var gold := Toon.gold()
	Toon.part(crown, Toon.cylinder(0.2, 0.2, 0.12, 16), gold, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	for i in 5:
		var a := TAU * i / 5.0
		Toon.part(crown, Toon.cylinder(0.0, 0.06, 0.16, 6), gold, Vector3(cos(a) * 0.17, 0.13, sin(a) * 0.17), Vector3.ZERO, Vector3.ONE, false)
	crown.visible = false
	return crown

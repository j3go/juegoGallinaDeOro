extends Node
## Command-line helpers for automated checks. Only loaded with `-- --autotest`.
##   godot --path . -- --autotest [--duration=30] [--timescale=3] [--overview]
##        [--screenshot=user://shot.png --shot-delay=6] [--keep-open]

var _game: Node
var _args := {}
var _report_timer := 0.0
var _crossed_cow := false
var _actions := {}


func _ready() -> void:
	_game = get_parent()
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "true"
	if _args.has("duration"):
		_game.config = _game.config.duplicate()
		_game.config.match_duration = float(_args["duration"])
	if _args.has("timescale"):
		Engine.time_scale = float(_args["timescale"])
	_game.match_finished.connect(_on_match_finished)
	_game.match_started.connect(func() -> void:
		for c in _game.competitors:
			c.action_performed.connect(func(_c: CharacterBase, action: String) -> void:
				_actions[action] = _actions.get(action, 0) + 1))
	if _args.has("overview"):
		_add_overview_camera.call_deferred()
	if _args.has("cam"):
		_add_fixed_camera.call_deferred(_args["cam"])
	if _args.has("chicken-cam"):
		_add_chicken_camera.call_deferred()
	if _args.has("screenshot"):
		_screenshot_later()
	if _args.has("walk"):
		_simulate_player_input()
	if _args.has("collision-audit"):
		_collision_audit()
	if _args.has("walk-test"):
		_walk_test()
	if _args.has("mechanics-test"):
		_mechanics_test()
	if _args.has("switch-map"):
		_switch_map_once()
	print("[autotest] started")


func _process(delta: float) -> void:
	_report_timer += delta
	if _report_timer < 2.0 or _game.phase != 3:
		return
	_report_timer = 0.0
	var line := "[autotest] t=%.0f eggs_on_ground=%d" % [_game.time_left, _game.egg_manager.get_egg_count()]
	for c in _game.competitors:
		line += " | %s=%d" % [c.display_name, c.score]
		if c is NPCAI:
			line += "(%s %.1f,%.1f v=%.1f)" % [c.get_state_name(), c.global_position.x, c.global_position.z, Vector2(c.velocity.x, c.velocity.z).length()]
	print(line)


func _on_match_finished(ranking: Array) -> void:
	var line := "[autotest] FINISHED:"
	for c in ranking:
		line += " %s=%d" % [c.display_name, c.score]
	print(line)
	print("[autotest] acciones: %s" % str(_actions))
	if not _args.has("keep-open") and not _args.has("screenshot"):
		await get_tree().create_timer(2.5).timeout
		get_tree().quit()


func _add_overview_camera() -> void:
	var cam := Camera3D.new()
	_game.add_child(cam)
	cam.global_position = Vector3(0, 30, 27)
	cam.look_at(Vector3(0, 0, 1), Vector3.UP)
	cam.fov = 55
	cam.current = true


## --cam=x,y,z,target_x,target_y,target_z
func _add_fixed_camera(spec: String) -> void:
	var v := spec.split_floats(",")
	var cam := Camera3D.new()
	_game.add_child(cam)
	cam.fov = 60
	cam.global_position = Vector3(v[0], v[1], v[2])
	cam.look_at(Vector3(v[3], v[4], v[5]), Vector3.UP)
	cam.current = true


func _add_chicken_camera() -> void:
	var cam := Camera3D.new()
	_game.add_child(cam)
	cam.fov = 40
	cam.current = true
	while is_instance_valid(cam):
		var target: Vector3 = _game.chicken.global_position + Vector3.UP * 0.5
		cam.global_position = target + Vector3(2.2, 1.2, 2.6)
		cam.look_at(target, Vector3.UP)
		await get_tree().process_frame


## Holds forward + sprint and jumps a few times, logging the player's position.
func _simulate_player_input() -> void:
	await _game.match_started
	var player: CharacterBody3D = _game.player
	var start := player.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in 3:
		await get_tree().create_timer(0.6).timeout
		Input.action_press("jump")
		await get_tree().physics_frame
		await get_tree().physics_frame
		print("[autotest] jump %d: y=%.2f vy=%.2f" % [i, player.global_position.y, player.velocity.y])
		Input.action_release("jump")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await get_tree().create_timer(0.5).timeout
	print("[autotest] player moved %.2f m (from %s to %s), speed now %.2f" % [
		start.distance_to(player.global_position), start, player.global_position, player.velocity.length()])


## Picks the other map from the menu once, then reports which map got loaded.
func _switch_map_once() -> void:
	await get_tree().create_timer(1.0).timeout
	print("[autotest] menu visible=%s level=%s" % [_game.main_menu.visible, _game.level.display_name])
	if _game.level.display_name == "La Granja":
		_game.main_menu.level_selected.emit(1)
	else:
		get_tree().quit()


## Casts physics rays at every landmark (must hit) and through every opening (must pass).
func _collision_audit() -> void:
	await _game.match_started
	var space: PhysicsDirectSpaceState3D = _game.get_world_3d().direct_space_state
	var solids := {
		"Pato/plataforma": Vector3(-11.5, 0, -10.0), "Molino": Vector3(-6.0, 0, -15.0),
		"Colina": Vector3(1.0, 0, -12.5), "Tanque de agua": Vector3(8.0, 0, -13.5),
		"Silo": Vector3(13.5, 0, -13.0), "Tractor": Vector3(13.5, 0, 1.5),
		"Pozo de lava": Vector3(-8.5, 0, 9.5),
		"Fogata": Vector3(1.5, 0, 11.5), "Vaca": Vector3(7.5, 0, 6.5),
		"Cajas": Vector3(-4.5, 0, -7.2), "Reflector": Vector3(-7.0, 0, -2.0),
		"Caño (lados)": Vector3(12.0, 0, 11.5), "Granero (pared)": Vector3(11.5, 0, -8.6),
	}
	var failures := 0
	for label: String in solids:
		var center: Vector3 = solids[label]
		var hits := 0
		# Sweep a character-sized capsule towards the centre from 8 directions.
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35
		capsule.height = 1.5
		for i in 8:
			var dir := Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0))
			if label == "Caño (lados)" and absf(dir.x) > 0.5:
				dir = Vector3(0, 0, signf(dir.z) if absf(dir.z) > 0.1 else 1.0)  # open ends: test the sides
			if label == "Granero (pared)":
				dir = Vector3(dir.x * 0.3, 0, -1.0).normalized()  # back wall, from outside
			var params := PhysicsShapeQueryParameters3D.new()
			params.shape = capsule
			params.collision_mask = 1
			params.transform = Transform3D(Basis.IDENTITY, center + dir * 7.0 + Vector3.UP * 0.8)
			params.motion = -dir * 7.0
			if space.cast_motion(params)[0] < 1.0:
				hits += 1
		print("[audit] solido %-16s barridos que chocan: %d/8" % [label, hits])
		if hits < 8:
			failures += 1
	var openings := {
		"Caño (adentro)": [Vector3(8.5, 1.0, 11.5), Vector3(15.5, 1.0, 11.5)],
		"Puerta granero": [Vector3(11.5, 1.0, -1.0), Vector3(11.5, 1.0, -6.5)],
		"Entrada mina": [Vector3(-11.5, 0.8, -5.0), Vector3(-11.5, 0.8, -7.2)],
		"Hueco cráter": [Vector3(0.5 + cos(TAU * 2.5 / 20.0) * 6.0, 0.3, sin(TAU * 2.5 / 20.0) * 6.0), Vector3(0.5 + cos(TAU * 2.5 / 20.0) * 2.6, 0.3, sin(TAU * 2.5 / 20.0) * 2.6)],
	}
	for label: String in openings:
		var seg: Array = openings[label]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(seg[0], seg[1], 1))
		var ok := hit.is_empty()
		print("[audit] abertura %-16s %s" % [label, "libre" if ok else "BLOQUEADA en %s" % hit.position])
		if not ok:
			failures += 1
	var level: Level = _game.level
	for label in ["Granero", "Caño", "Mina", "Cráter"]:
		var p: Vector3 = {"Granero": Vector3(11.5, 0, -6.5), "Caño": Vector3(12.0, 0, 11.5), "Mina": Vector3(-11.5, 0, -7.6), "Cráter": Vector3(2.2, 0, 1.8)}[label]
		print("[audit] navegable %-10s %s" % [label, level.is_reachable(level.snap_to_ground(p, p))])
	print("[audit] fallas: %d" % failures)
	get_tree().quit()


## Drives the real player (physics + input) along routes and checks where it ends up.
func _walk_test() -> void:
	await _game.match_started
	var player: PlayerController = _game.player
	# Only the player moves: rivals would shove and grab it during the routes.
	_game.chicken.stop_attacking()
	for c in _game.competitors:
		if c != player:
			c.set_active(false)
			c.global_position = Vector3(16.0 - _game.competitors.find(c) * 0.9, 0.1, 16.0)
	var routes := [
		# name, start, yaw (forward = -Z rotated), seconds, check
		["Atraviesa el caño", Vector3(8.4, 0.1, 11.5), -PI * 0.5, 1.4, func(p: Vector3) -> bool: return p.x > 14.5],
		["Entra al granero", Vector3(11.5, 0.1, -0.5), 0.0, 2.0, func(p: Vector3) -> bool: return p.z < -4.5 and p.z > -8.4],
		["Choca con el silo", Vector3(13.5, 0.1, -9.3), 0.0, 1.5, func(p: Vector3) -> bool: return p.z > -11.5],
		["Choca con la vaca", Vector3(7.5, 0.1, 3.0), PI, 1.5, func(p: Vector3) -> bool: return not _crossed_cow],
		["Sube a la colina", Vector3(1.0, 0.1, -4.5), 0.0, 2.2, func(p: Vector3) -> bool: return p.y > 2.0],
		["Sube al pato", Vector3(-3.4, 0.1, -11.0), PI * 0.5, 2.0, func(p: Vector3) -> bool: return p.y > 1.6],
		["La lava te expulsa", Vector3(-7.0, 1.0, 9.5), PI * 0.5, 1.2, func(p: Vector3) -> bool: return Vector2(p.x + 8.5, p.z - 9.5).length() > 3.0],
		["Entra a la mina", Vector3(-11.5, 0.1, -4.0), 0.0, 1.5, func(p: Vector3) -> bool: return p.z < -7.2 and p.z > -8.6],
	]
	var failures := 0
	for r: Array in routes:
		player.place_at(r[1])
		player._yaw = r[2]
		await get_tree().physics_frame
		Input.action_press("move_forward")
		Input.action_press("sprint")
		_crossed_cow = false
		var t := 0.0
		while t < r[3]:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			# The cow's body occupies roughly 1 m around (7.5, 6.5): the player must never be inside it.
			if Vector2(player.global_position.x - 7.5, player.global_position.z - 6.5).length() < 0.6:
				_crossed_cow = true
		Input.action_release("move_forward")
		Input.action_release("sprint")
		await get_tree().create_timer(0.3).timeout
		var pos := player.global_position
		var ok: bool = (r[4] as Callable).call(pos)
		if not ok:
			failures += 1
		print("[walk] %-20s %s  final=(%.1f, %.1f, %.1f)" % [r[0], "OK" if ok else "FALLA", pos.x, pos.y, pos.z])
	print("[walk] fallas: %d" % failures)
	get_tree().quit()


# --- Rule checks from design doc v0.1 -------------------------------------------------------------

var _checks_failed := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_checks_failed += 1
	print("[rules] %-58s %s %s" % [label, "OK" if ok else "FALLA", detail])


func _mechanics_test() -> void:
	await _game.match_started
	var g := _game
	g.chicken.stop_attacking()
	g.item_manager.stop()
	var cs: Array[CharacterBase] = g.competitors
	for c in cs:
		c.scripted = true
		c.move_input = Vector3.ZERO
	var a: CharacterBase = cs[1]
	var b: CharacterBase = cs[2]
	var c3: CharacterBase = cs[3]
	var spots := [Vector3(-6, 0.1, 6), Vector3(-5, 0.1, 6), Vector3(-4, 0.1, 6)]
	var put := func(chars: Array, start: Array) -> void:
		for i in chars.size():
			(chars[i] as CharacterBase).global_position = start[i]
			(chars[i] as CharacterBase).velocity = Vector3.ZERO
			(chars[i] as CharacterBase)._motion = Vector3.ZERO
	var gs: GrabSystem = g.grab_system
	var north := Vector3(0, 0, -1)

	# 1. Equal and opposite forces cancel.
	put.call([a, b], spots)
	await get_tree().physics_frame
	a.grab_ready_at = 0.0
	_check("Agarre iniciado", a.try_grab() or gs.create_link(a, b))
	var start_mid := (a.global_position + b.global_position) * 0.5
	a.move_input = north
	b.move_input = -north
	await get_tree().create_timer(1.0).timeout
	var moved := ((a.global_position + b.global_position) * 0.5).distance_to(start_mid)
	_check("Fuerzas iguales y opuestas se cancelan", moved < 0.2, "(%.2f m)" % moved)

	# 2. Same direction: the chain moves that way.
	b.move_input = north
	var before := a.global_position
	await get_tree().create_timer(1.0).timeout
	var dz := before.z - a.global_position.z
	_check("Fuerzas en la misma dirección mueven la cadena", dz > 2.5, "(%.2f m al norte)" % dz)
	_check("La suma no supera la velocidad máxima", a.chain_velocity.length() <= g.config.chain_max_speed + 0.01)
	gs.release_all()
	for c in cs:
		c.move_input = Vector3.ZERO
	await get_tree().create_timer(0.3).timeout

	# 3. Chain of three: two north, one south -> net north; the middle one counts once.
	put.call([a, b, c3], spots)
	await get_tree().physics_frame
	a.grab_ready_at = 0.0
	b.grab_ready_at = 0.0
	gs.create_link(a, b)
	gs.create_link(b, c3)
	a.move_input = north
	b.move_input = north
	c3.move_input = -north
	await get_tree().physics_frame
	var expected: float = g.config.pull_speed * 1.0
	_check("Cadena de 3 (2 norte, 1 sur): fuerza neta al norte", absf(a.chain_velocity.z + expected) < 0.3,
			"(vz=%.2f, esperado %.2f)" % [a.chain_velocity.z, -expected])
	var forces := gs.chain_force(gs.get_chains()[0])
	_check("El jugador intermedio aporta una sola vez", is_equal_approx(forces.length(), 1.0), "(|F|=%.2f)" % forces.length())
	gs.release_all()
	for c in cs:
		c.move_input = Vector3.ZERO

	# 4. Timings: 3 s link, next grab 13 s after starting; pickup blocked while linked.
	put.call([a, b], spots)
	await get_tree().physics_frame
	a.grab_ready_at = 0.0
	var t0 := GameClock.now
	gs.create_link(a, b)
	var egg: GoldenEgg = g.egg_manager.spawn_ground_egg(b.global_position + Vector3.UP, b.global_position + Vector3(0.6, 0, 0))
	await get_tree().create_timer(0.8).timeout
	_check("Agarrado no puede recoger huevos", not b.try_pickup() and egg.is_available())
	_check("Quien agarra no puede recoger huevos", not a.can_pick_eggs())
	_check("Quien agarra no puede empujar", not a.try_push())
	b._immortal_until = GameClock.now + 5.0
	_check("La inmortalidad no anula el bloqueo de recogida", not b.try_pickup())
	b._immortal_until = -1.0
	while a.outgoing_link != null:
		await get_tree().physics_frame
	var duration := GameClock.now - t0
	_check("El agarre dura 3 s", absf(duration - 3.0) < 0.05, "(%.2f s)" % duration)
	_check("Siguiente agarre a los 13 s del inicio", is_equal_approx(a.grab_ready_at - t0, 13.0), "(%.2f s)" % (a.grab_ready_at - t0))
	_check("No se puede volver a agarrar durante el enfriamiento", not a.try_grab())
	_check("Al quedar libre sí puede recoger", b.try_pickup() and b.score == 1)

	# 5. Push moves but never drops eggs.
	b.score = 3
	put.call([a, b, c3], [spots[0], spots[1], Vector3(-6, 0.1, 10)])
	await get_tree().physics_frame
	a.push_ready_at = 0.0
	a.model.rotation.y = atan2(1.0, 0.0)  # face +X, towards b
	var b_before := b.global_position
	_check("Empujón ejecutado", a.try_push())
	await get_tree().create_timer(0.4).timeout
	_check("El empujón desplaza al rival", b.global_position.distance_to(b_before) > 0.8, "(%.2f m)" % b.global_position.distance_to(b_before))
	_check("El empujón no hace soltar huevos", b.score == 3)

	# 6. Egg hit: knockdown + drops everything; hits during recovery don't cause new losses.
	var eggs_before: int = g.egg_manager.get_egg_count()
	b.hit_by_egg(Vector3(1, 0, 0))
	_check("El huevo derriba", b.is_down())
	_check("El huevo hace soltar los huevos", b.score == 0 and g.egg_manager.get_egg_count() == eggs_before + 3)
	b.score = 2
	_check("Sin nuevas pérdidas durante el derribo", not b.hit_by_egg(Vector3.RIGHT) and b.score == 2)
	_check("Derribado no puede actuar", not b.can_act())
	await get_tree().create_timer(g.config.knockdown_time + g.config.recovery_time + 0.1).timeout
	_check("Se levanta solo y vuelve a actuar", b.can_act())

	# 7. Immortality: no knockdown, no loss (egg or kunai); still pushable.
	b._immortal_until = GameClock.now + 5.0
	_check("Inmortal: el huevo no derriba ni quita", not b.hit_by_egg(Vector3.RIGHT) and not b.is_down() and b.score == 2)
	_check("Inmortal: el kunai no quita huevos", not b.hit_by_kunai(Vector3.RIGHT) and b.score == 2)
	b._immortal_until = -1.0
	_check("Kunai hace soltar huevos (sin derribo)", b.hit_by_kunai(Vector3.RIGHT) and b.score == 0 and not b.is_down())

	# 8. Chicken targets the leader; ties rotate in a stable order.
	for c in cs:
		c.score = 0
	cs[4].score = 5
	_check("La gallina apunta al líder", g.chicken.select_target() == cs[4])
	cs[2].score = 5
	var first: CharacterBase = g.chicken.select_target()
	g.chicken._last_target = first
	var second: CharacterBase = g.chicken.select_target()
	g.chicken._last_target = second
	var third: CharacterBase = g.chicken.select_target()
	_check("Empate: alterna entre los líderes", first != second and third == first and second.score == 5,
			"(%s, %s, %s)" % [first.display_name, second.display_name, third.display_name])

	# 9. A real shot: laser-locked egg hits the first character in the line.
	for c in cs:
		c.score = 0
		c._recover_until = -1.0
	var victim: CharacterBase = cs[5]
	var blocker: CharacterBase = cs[1]
	victim.score = 4
	victim.global_position = g.chicken.global_position + Vector3(0, 0.1, 6.0)
	blocker.global_position = g.chicken.global_position + Vector3(0, 0.1, 3.0)
	blocker.score = 1
	for c in cs:
		c.velocity = Vector3.ZERO
		c._motion = Vector3.ZERO
	await get_tree().physics_frame
	g.chicken.start_attacking()
	g.chicken._state_until = 0.0
	await get_tree().create_timer(g.config.aim_time + g.config.lock_time + 1.5).timeout
	_check("El disparo alcanza al primero en la línea (no al objetivo)", blocker.score == 0 and victim.score == 4,
			"(interpuesto=%d, líder=%d)" % [blocker.score, victim.score])

	print("[rules] fallas: %d" % _checks_failed)
	get_tree().quit()


func _screenshot_later() -> void:
	await get_tree().create_timer(float(_args.get("shot-delay", "5"))).timeout
	await RenderingServer.frame_post_draw
	var path: String = _args["screenshot"]
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[autotest] screenshot %s -> %s" % [path, error_string(err)])
	get_tree().quit()

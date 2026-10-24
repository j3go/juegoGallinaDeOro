class_name Chicken
extends CharacterBody3D
## The chicken in the centre of the farm (design doc v0.1).
## Each attack: pick the player carrying the most eggs (ties rotate in a stable order), track
## them with a warning laser, lock the laser for a moment (visual + sound), bend into the shooting
## pose and fire one egg out of its butt along the locked line, with recoil and a puff of gas.
## The laser only warns; the egg hits the first character in its way, whoever it is.
## Between attacks it roams the whole map: walks, runs around like crazy at changing speeds,
## stops to peck, and every now and then teleports somewhere else.

signal attack_started(target: CharacterBase)
signal shot_fired(direction: Vector3)

enum State { IDLE, AIM, LOCK, FIRE, RECOVER }
enum Roam { WANDER, CRAZY, PAUSE }

const SHOT_HEIGHT := 0.75
const TURN_SPEED := 8.0
const CRAZY_SHOUTS := ["¡COCOCÓ!", "¡CO-CO-COOO!", "¡KIKIRIKÍ!", "¡POCK POCK!"]

@export var config: GameConfig

var state: State = State.IDLE
var target: CharacterBase = null
var aim_direction := Vector3.FORWARD
var laser_length := 0.0
var roam: Roam = Roam.PAUSE
var teleporting := false

var _ctx: MatchContext
var _attacking := false
var _state_until := 0.0
var _last_target: CharacterBase = null
var _home := Vector3.ZERO
var _laser: Node3D
var _laser_core: MeshInstance3D
var _laser_band: MeshInstance3D
var _laser_dot: MeshInstance3D
var _laser_mat: StandardMaterial3D
var _band_mat: StandardMaterial3D
var _roam_until := 0.0
var _roam_speed := 0.0
var _speed_change_at := 0.0
var _next_teleport_at := 0.0
var _dust_at := 0.0
var _zigzag_seed := 0.0

@onready var model: ChickenModel = $Model
@onready var agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	_build_laser()


func setup(context: MatchContext) -> void:
	_ctx = context
	_home = global_position


func start_attacking() -> void:
	_attacking = true
	_enter(State.IDLE, 1.5)
	_roam_until = 0.0
	_schedule_teleport()


func stop_attacking() -> void:
	_attacking = false
	_enter(State.IDLE, 999.0)


func is_warning() -> bool:
	return state == State.AIM or state == State.LOCK


## Origin of the shot, in front of the chicken at the height of its butt in the pose.
func shot_origin() -> Vector3:
	return global_position + aim_direction * 0.55 + Vector3.UP * SHOT_HEIGHT


## Distance from `point` to the dangerous line (INF if it's behind the chicken or past the end).
func distance_to_line(point: Vector3) -> float:
	var o := shot_origin()
	var rel := Vector3(point.x - o.x, 0.0, point.z - o.z)
	var along := rel.dot(aim_direction)
	if along < -0.3 or along > laser_length + 0.5:
		return INF
	return (rel - aim_direction * along).length()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= config.gravity * delta
	var now := GameClock.now
	var walk := Vector3.ZERO
	if state == State.IDLE and _attacking and not teleporting:
		if now >= _next_teleport_at:
			_teleport()
		elif now < _state_until:
			walk = _roam_velocity(now)
	velocity.x = walk.x
	velocity.z = walk.z
	move_and_slide()
	model.frenzy_target = 1.0 if walk != Vector3.ZERO and roam == Roam.CRAZY else 0.0

	match state:
		State.IDLE:
			model.fire_pose_target = 0.0
			if _attacking and not teleporting and now >= _state_until:
				_begin_attack()
		State.AIM:
			model.fire_pose_target = 1.0
			if is_instance_valid(target):
				var to := target.global_position - global_position
				to.y = 0.0
				if to.length() > 0.1:
					aim_direction = to.normalized()
			if now >= _state_until:
				_enter(State.LOCK, config.lock_time)
				Sfx.play_3d(self, Sfx.LOCK, global_position, 0.0)
		State.LOCK:
			model.fire_pose_target = 1.0
			if now >= _state_until:
				_fire()
		State.FIRE:
			_enter(State.RECOVER, config.recover_time)
		State.RECOVER:
			model.fire_pose_target = 0.0
			if now >= _state_until:
				_enter(State.IDLE, randf_range(config.attack_interval_min, config.attack_interval_max))

	# Face the line of fire (the egg leaves towards the chicken's front).
	if state != State.IDLE:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(aim_direction.x, aim_direction.z), 1.0 - exp(-TURN_SPEED * delta))
	elif walk.length() > 0.1:
		var turn := TURN_SPEED * (2.0 if roam == Roam.CRAZY else 1.0)
		model.rotation.y = lerp_angle(model.rotation.y, atan2(walk.x, walk.z), 1.0 - exp(-turn * delta))
	model.animate(delta, Vector2(velocity.x, velocity.z).length())
	_update_laser()


## Leader = most eggs carried. With ties (including everyone at 0) rotate in a stable order.
func select_target() -> CharacterBase:
	if _ctx == null:
		return null
	var best := -1
	for c in _ctx.competitors:
		if c.is_active:
			best = maxi(best, c.score)
	var tied: Array[CharacterBase] = []
	for c in _ctx.competitors:
		if c.is_active and c.score == best:
			tied.append(c)
	if tied.is_empty():
		return null
	var start := 0
	if _last_target and tied.has(_last_target):
		start = (tied.find(_last_target) + 1) % tied.size()
	elif _last_target:
		# Continue from the previous target's place in the fixed competitor order.
		var order := _ctx.competitors.find(_last_target)
		for i in tied.size():
			if _ctx.competitors.find(tied[i]) > order:
				start = i
				break
	return tied[start]


func _begin_attack() -> void:
	target = select_target()
	if target == null:
		_enter(State.IDLE, 1.0)
		return
	_last_target = target
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() > 0.1:
		aim_direction = to.normalized()
	_enter(State.AIM, config.aim_time)
	attack_started.emit(target)


func _fire() -> void:
	_enter(State.FIRE, 0.0)
	var egg := EggProjectile.new()
	_ctx.world_root.add_child(egg)
	egg.launch(shot_origin(), aim_direction, _ctx, [get_rid()])
	model.play_shot()
	# Recoil: slide back opposite to the shot, then return to the centre.
	var back := -aim_direction * 0.7
	var tw := create_tween()
	tw.tween_property(model, "position", Vector3(back.x, 0.0, back.z), 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "position", Vector3.ZERO, 0.6).set_trans(Tween.TRANS_SINE)
	Effects.gas_puff(_ctx.world_root, global_position + aim_direction * 0.3 + Vector3.UP * 0.5, -aim_direction)
	Sfx.play_3d(self, Sfx.SHOOT, global_position, 2.0)
	shot_fired.emit(aim_direction)


# --- Roaming and teleports -----------------------------------------------------------------

## Horizontal velocity for this frame while roaming between attacks.
func _roam_velocity(now: float) -> Vector3:
	if now >= _roam_until or (roam != Roam.PAUSE and agent.is_navigation_finished()):
		_pick_roam(now)
	if roam == Roam.PAUSE:
		return Vector3.ZERO
	if roam == Roam.CRAZY and now >= _speed_change_at:
		# Crazy run: random bursts of speed and sudden changes of direction.
		_roam_speed = randf_range(config.roam_crazy_speed_min, config.roam_crazy_speed_max)
		_speed_change_at = now + randf_range(0.25, 0.7)
		if randf() < 0.3:
			agent.target_position = _ctx.level.random_point_in_map()
	var to := agent.get_next_path_position() - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return Vector3.ZERO
	var dir := to.normalized()
	if roam == Roam.CRAZY:
		dir = dir.rotated(Vector3.UP, sin(now * 9.0 + _zigzag_seed) * 0.6)
		if now >= _dust_at:
			_dust_at = now + 0.12
			Effects.dust_puff(_ctx.world_root, global_position, 3)
	return dir * _roam_speed


func _pick_roam(now: float) -> void:
	var roll := randf()
	if roll < config.roam_crazy_chance:
		roam = Roam.CRAZY
		_roam_until = now + randf_range(2.0, 4.5)
		_speed_change_at = 0.0
		_zigzag_seed = randf() * TAU
		agent.target_position = _ctx.level.random_point_in_map()
		model.play_hop()
		if randf() < 0.6:
			Effects.floating_text(_ctx.world_root, global_position + Vector3.UP * 1.6,
					CRAZY_SHOUTS.pick_random(), Color(1.0, 0.55, 0.3))
	elif roll < config.roam_crazy_chance + 0.2:
		roam = Roam.PAUSE
		_roam_until = now + randf_range(0.6, 1.4)
		model.peck()
	else:
		roam = Roam.WANDER
		_roam_until = now + randf_range(2.5, 5.0)
		_roam_speed = randf_range(config.roam_walk_speed_min, config.roam_walk_speed_max)
		agent.target_position = _ctx.level.random_point_near(global_position, 3.0, 9.0)


func _schedule_teleport() -> void:
	_next_teleport_at = GameClock.now + randf_range(config.teleport_interval_min, config.teleport_interval_max)


func _teleport() -> void:
	teleporting = true
	var destination := _ctx.level.random_point_in_map()
	for i in 4:
		if destination.distance_to(global_position) > 8.0:
			break
		destination = _ctx.level.random_point_in_map()
	Effects.teleport_flash(_ctx.world_root, global_position)
	Sfx.play_3d(self, Sfx.ITEM, global_position, 2.0)
	await model.play_teleport_out().finished
	global_position = destination
	velocity = Vector3.ZERO
	agent.target_position = destination
	await get_tree().create_timer(0.15).timeout
	Effects.teleport_flash(_ctx.world_root, destination)
	Sfx.play_3d(self, Sfx.ITEM, destination, 2.0)
	await model.play_teleport_in().finished
	teleporting = false
	_roam_until = 0.0
	_schedule_teleport()
	# Give everyone a moment to spot where it landed before the next attack.
	_state_until = maxf(_state_until, GameClock.now + 1.0)


func _enter(new_state: State, duration: float) -> void:
	state = new_state
	_state_until = GameClock.now + duration


# --- Warning laser -------------------------------------------------------------------------

func _build_laser() -> void:
	_laser = Node3D.new()
	_laser.top_level = true
	add_child(_laser)
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.9)
	_band_mat = _laser_mat.duplicate()
	_band_mat.albedo_color = Color(1.0, 0.2, 0.1, 0.18)
	_band_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_laser_core = _laser_part(Toon.box(Vector3(0.05, 0.05, 1.0)), _laser_mat)
	# Wide translucent band = the actual width of the egg's danger zone.
	_laser_band = _laser_part(Toon.box(Vector3(1.0, 0.02, 1.0)), _band_mat)
	_laser_dot = _laser_part(Toon.sphere(0.18, 12, 6), _laser_mat)
	_laser.visible = false


func _laser_part(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.add_child(mi)
	return mi


func _update_laser() -> void:
	var warning := is_warning()
	_laser.visible = warning
	if not warning:
		return
	var origin := shot_origin()
	var end := origin + aim_direction * config.egg_range
	# The line stops at the first obstacle (walls, props), not at characters.
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit.position
	laser_length = origin.distance_to(end)
	var basis := Basis.looking_at(aim_direction, Vector3.UP)
	var mid := (origin + end) * 0.5
	var locked := state == State.LOCK
	var thickness := 2.2 if locked else 1.0
	_laser_core.global_transform = Transform3D(basis.scaled(Vector3(thickness, thickness, laser_length)), mid)
	_laser_band.global_transform = Transform3D(basis.scaled(Vector3(config.egg_radius * 2.0, 1, laser_length)), mid)
	_laser_dot.global_position = end
	var pulse := 0.5 + 0.5 * sin(GameClock.now * (30.0 if locked else 10.0))
	if locked:
		_laser_mat.albedo_color = Color(1.0, 0.85, 0.8, 0.7 + 0.3 * pulse)
		_band_mat.albedo_color = Color(1.0, 0.3, 0.2, 0.25 + 0.15 * pulse)
	else:
		_laser_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.45 + 0.35 * pulse)
		_band_mat.albedo_color = Color(1.0, 0.2, 0.1, 0.12)

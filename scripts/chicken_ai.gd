class_name Chicken
extends CharacterBody3D
## The chicken in the centre of the farm (design doc v0.1).
## Each attack: pick the player carrying the most eggs (ties rotate in a stable order), track
## them with a warning laser, lock the laser for a moment (visual + sound), bend into the shooting
## pose and fire one egg out of its butt along the locked line, with recoil and a puff of gas.
## The laser only warns; the egg hits the first character in its way, whoever it is.
## Between attacks it roams the whole map: walks, runs around like crazy at changing speeds,
## stops to peck, flies across the map (sometimes dropping an explosive egg) and every now and
## then teleports somewhere else. Some attacks fire special eggs: explosive or erratic.

signal attack_started(target: CharacterBase)
signal shot_fired(direction: Vector3)

enum State { IDLE, AIM, LOCK, FIRE, RECOVER }
enum Roam { WANDER, CRAZY, PAUSE, FLY }

const SHOT_HEIGHT := 0.75
const TURN_SPEED := 8.0
const CRAZY_SHOUTS := ["¡COCOCÓ!", "¡CO-CO-COOO!", "¡KIKIRIKÍ!", "¡POCK POCK!"]
const EGG_SHOUTS := {
	EggProjectile.Kind.EXPLOSIVE: "¡HUEVO BOMBA!",
	EggProjectile.Kind.ERRATIC: "¡HUEVO LOCO!",
}

@export var config: GameConfig

var state: State = State.IDLE
var target: CharacterBase = null
var aim_direction := Vector3.FORWARD
var laser_length := 0.0
var roam: Roam = Roam.PAUSE
var teleporting := false
var flying := false
## Kind of egg the current attack will fire (picked when the attack starts).
var egg_kind := EggProjectile.Kind.NORMAL

var _ctx: MatchContext
var _attacking := false
var _state_until := 0.0
var _last_target: CharacterBase = null
var _home := Vector3.ZERO
var _laser: Node3D
var _laser_core: MeshInstance3D
var _laser_glow: MeshInstance3D
var _laser_band: MeshInstance3D
var _laser_dot: MeshInstance3D
var _laser_light: OmniLight3D
var _laser_motes: CPUParticles3D
var _core_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _band_mat: ShaderMaterial
var _dot_mat: ShaderMaterial
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
	var now := GameClock.now
	var walk := Vector3.ZERO
	if state == State.IDLE and _attacking and not _travelling():
		if now >= _next_teleport_at:
			_teleport()
		elif now < _state_until:
			walk = _roam_velocity(now)
	# While flying, `_fly` moves the chicken directly (no gravity or collisions).
	if not flying:
		if not is_on_floor():
			velocity.y -= config.gravity * delta
		velocity.x = walk.x
		velocity.z = walk.z
		move_and_slide()
	model.frenzy_target = 1.0 if walk != Vector3.ZERO and roam == Roam.CRAZY else 0.0

	match state:
		State.IDLE:
			model.fire_pose_target = 0.0
			if _attacking and not _travelling() and now >= _state_until:
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
	model.animate(delta, 0.0 if flying else Vector2(velocity.x, velocity.z).length())
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
	egg_kind = _pick_egg_kind()
	if EGG_SHOUTS.has(egg_kind):
		Effects.floating_text(_ctx.world_root, global_position + Vector3.UP * 1.6, EGG_SHOUTS[egg_kind],
				EggProjectile.KIND_COLORS[egg_kind])
	_enter(State.AIM, config.aim_time)
	attack_started.emit(target)


func _pick_egg_kind() -> EggProjectile.Kind:
	var roll := randf()
	if roll < config.explosive_egg_chance:
		return EggProjectile.Kind.EXPLOSIVE
	if roll < config.explosive_egg_chance + config.erratic_egg_chance:
		return EggProjectile.Kind.ERRATIC
	return EggProjectile.Kind.NORMAL


func _fire() -> void:
	_enter(State.FIRE, 0.0)
	var egg := EggProjectile.new()
	_ctx.world_root.add_child(egg)
	egg.launch(shot_origin(), aim_direction, _ctx, [get_rid()], egg_kind)
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
	if roam == Roam.PAUSE or flying:
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
	elif roll < config.roam_crazy_chance + config.fly_chance:
		roam = Roam.FLY
		_fly()
	elif roll < config.roam_crazy_chance + config.fly_chance + 0.2:
		roam = Roam.PAUSE
		_roam_until = now + randf_range(0.6, 1.4)
		model.peck()
	else:
		roam = Roam.WANDER
		_roam_until = now + randf_range(2.5, 5.0)
		_roam_speed = randf_range(config.roam_walk_speed_min, config.roam_walk_speed_max)
		agent.target_position = _ctx.level.random_point_near(global_position, 3.0, 9.0)


func _travelling() -> bool:
	return teleporting or flying


## Take off, fly in an arc to a far point of the map (maybe dropping a bomb on the way) and land.
func _fly() -> void:
	flying = true
	var start := global_position
	var destination := _ctx.level.random_point_in_map()
	for i in 4:
		if destination.distance_to(start) > 7.0:
			break
		destination = _ctx.level.random_point_in_map()
	var distance := start.distance_to(destination)
	var duration := clampf(distance / config.fly_speed, 1.5, 5.0)
	var height := config.fly_height + minf(distance * 0.05, 1.0)
	var will_bomb := randf() < config.fly_bomb_chance
	var flat := destination - start
	flat.y = 0.0
	model.rotation.y = atan2(flat.x, flat.z)
	model.fly_target = 1.0
	model.play_hop()
	Effects.dust_puff(_ctx.world_root, start, 10)
	Sfx.play_3d(self, Sfx.JUMP, start, 2.0)
	velocity = Vector3.ZERO
	var t := 0.0
	while t < 1.0:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		var before := t
		t = minf(t + get_physics_process_delta_time() / duration, 1.0)
		var along := smoothstep(0.0, 1.0, t)
		var bob := sin(t * duration * 9.0) * 0.12 * sin(PI * t)
		global_position = start.lerp(destination, along) + Vector3.UP * (height * sin(PI * t) + bob)
		if will_bomb and before < 0.5 and t >= 0.5:
			var bomb := EggProjectile.new()
			_ctx.world_root.add_child(bomb)
			bomb.drop(global_position + Vector3.DOWN * 0.3, _ctx, [get_rid()])
			model.play_shot()
			Effects.floating_text(_ctx.world_root, global_position + Vector3.UP * 1.2, "¡BOMBA VA!",
					EggProjectile.KIND_COLORS[EggProjectile.Kind.EXPLOSIVE])
	global_position = destination
	velocity = Vector3.ZERO
	model.fly_target = 0.0
	Effects.dust_puff(_ctx.world_root, destination, 12)
	flying = false
	_roam_until = 0.0
	agent.target_position = destination
	# A moment on the ground before the next attack.
	_state_until = maxf(_state_until, GameClock.now + 0.8)


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
# A thin bright core inside a soft halo, motes glinting in the beam, a glowing spot that lights
# up whatever it touches, and a faint strip on the ground showing the egg's danger width.

const LASER_COLOR := Color(1.0, 0.08, 0.04)
## Characters block the beam visually (collision layer 2), like a real laser would.
const LASER_VISUAL_MASK := 1 | 2

## Additive cylinder that fades towards its silhouette, so it reads as a soft glowing tube.
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float falloff = 2.0;
void fragment() {
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	ALBEDO = color.rgb;
	ALPHA = color.a * pow(facing, falloff);
}
"""

## Ground strip: soft edges across its width and a slow shimmer along its length.
const BAND_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float beam_length = 1.0;
void fragment() {
	float across = 1.0 - smoothstep(0.25, 0.5, abs(UV.x - 0.5));
	float shimmer = 0.75 + 0.25 * sin(UV.y * beam_length * 6.0 - TIME * 8.0);
	ALBEDO = color.rgb;
	ALPHA = color.a * across * shimmer;
}
"""

## Camera-facing radial glow for the spot where the beam lands.
const DOT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
			INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float halo = pow(max(1.0 - d, 0.0), 2.5);
	float core = smoothstep(0.25, 0.0, d);
	ALBEDO = mix(color.rgb, vec3(1.0), core);
	ALPHA = color.a * (halo + core);
}
"""


func _build_laser() -> void:
	_laser = Node3D.new()
	_laser.top_level = true
	add_child(_laser)
	_core_mat = _laser_shader(BEAM_SHADER)
	_glow_mat = _laser_shader(BEAM_SHADER)
	_glow_mat.set_shader_parameter("falloff", 3.0)
	_band_mat = _laser_shader(BAND_SHADER)
	_dot_mat = _laser_shader(DOT_SHADER)
	_laser_core = _laser_part(_open_tube(12), _core_mat)
	_laser_glow = _laser_part(_open_tube(16), _glow_mat)
	var strip := PlaneMesh.new()
	strip.size = Vector2.ONE
	_laser_band = _laser_part(strip, _band_mat)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_laser_dot = _laser_part(quad, _dot_mat)

	_laser_light = OmniLight3D.new()
	_laser_light.light_color = LASER_COLOR
	_laser_light.omni_range = 1.6
	_laser.add_child(_laser_light)

	# Dust motes catching the beam. Local coords so they stay inside it as it sweeps.
	_laser_motes = CPUParticles3D.new()
	_laser_motes.amount = 30
	_laser_motes.lifetime = 0.7
	_laser_motes.mesh = Toon.sphere(0.005, 6, 3)
	_laser_motes.material_override = Toon.emissive(Color(1.0, 0.4, 0.3), 1.2)
	_laser_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_laser_motes.direction = Vector3.UP
	_laser_motes.spread = 180.0
	_laser_motes.gravity = Vector3.ZERO
	_laser_motes.initial_velocity_min = 0.02
	_laser_motes.initial_velocity_max = 0.12
	_laser_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.add_child(_laser_motes)
	_laser.visible = false


## Unit cylinder without caps (caps would show up as bright discs at the ends of the beam).
func _open_tube(segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = segments
	m.rings = 1
	m.cap_top = false
	m.cap_bottom = false
	return m


func _laser_shader(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


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
	_laser_motes.emitting = warning
	if not warning:
		return
	var origin := shot_origin()
	var end := origin + aim_direction * config.egg_range
	var space := get_world_3d().direct_space_state
	# The danger line stops at the first obstacle (walls, props), not at characters...
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, end, 1, [get_rid()]))
	if not hit.is_empty():
		end = hit.position
	laser_length = origin.distance_to(end)
	# ...but the visible beam lands on whoever is standing in it.
	var beam_end := end
	var body_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, end, LASER_VISUAL_MASK, [get_rid()]))
	if not body_hit.is_empty():
		beam_end = body_hit.position
	var beam_length := maxf(origin.distance_to(beam_end), 0.01)

	var locked := state == State.LOCK
	var now := GameClock.now
	var flicker := randf_range(0.85, 1.0)
	var pulse := 0.5 + 0.5 * sin(now * (28.0 if locked else 9.0))
	var base: Color = LASER_COLOR if egg_kind == EggProjectile.Kind.NORMAL else EggProjectile.KIND_COLORS[egg_kind]
	var color := base.lerp(Color.WHITE, 0.5) if locked else base

	# Cylinders are Y-up: point their axis along the beam.
	var along := Basis.looking_at(aim_direction, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	var mid := (origin + beam_end) * 0.5
	var core_radius := 0.014 if locked else 0.009
	var glow_radius := (0.12 if locked else 0.07) * (0.9 + 0.2 * pulse)
	_laser_core.global_transform = Transform3D(along * Basis.from_scale(Vector3(core_radius, beam_length, core_radius)), mid)
	_laser_glow.global_transform = Transform3D(along * Basis.from_scale(Vector3(glow_radius, beam_length, glow_radius)), mid)
	_core_mat.set_shader_parameter("color", Color(Color(1.0, 0.9, 0.85).lerp(color, 0.3), flicker))
	_glow_mat.set_shader_parameter("color", Color(color, (0.55 if locked else 0.35) * flicker))

	var flat_mid := (origin + end) * 0.5
	flat_mid.y = global_position.y + 0.03
	var ground := Basis.looking_at(aim_direction, Vector3.UP)
	_laser_band.global_transform = Transform3D(ground * Basis.from_scale(Vector3(config.egg_radius * 2.0, 1.0, laser_length)), flat_mid)
	_band_mat.set_shader_parameter("beam_length", laser_length)
	_band_mat.set_shader_parameter("color", Color(color, (0.22 + 0.16 * pulse) if locked else 0.14))

	var dot_size := (0.55 if locked else 0.35) * (0.85 + 0.3 * flicker * pulse)
	_laser_dot.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * dot_size), beam_end - aim_direction * 0.04)
	_dot_mat.set_shader_parameter("color", Color(color, 0.9))
	_laser_light.global_position = beam_end - aim_direction * 0.15
	_laser_light.light_color = color
	_laser_light.light_energy = (3.0 if locked else 1.6) * flicker

	_laser_motes.global_transform = Transform3D(Basis.looking_at(aim_direction, Vector3.UP), mid)
	_laser_motes.emission_box_extents = Vector3(0.03, 0.03, beam_length * 0.5)

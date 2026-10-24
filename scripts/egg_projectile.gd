class_name EggProjectile
extends Projectile
## The egg the chicken shoots. While flying it is a hazard (knocks down and makes the victim drop
## eggs); when it hits something or runs out of range it falls and becomes a pickup.
## It can never hurt and be picked up at the same time.
## Special kinds: EXPLOSIVE blows up on impact and knocks down everyone in the blast radius;
## ERRATIC flies slower and keeps changing direction at random. Both still leave a pickup egg.

enum Kind { NORMAL, EXPLOSIVE, ERRATIC }

const KIND_COLORS := {
	Kind.NORMAL: Color(1.0, 0.6, 0.2),
	Kind.EXPLOSIVE: Color(1.0, 0.3, 0.08),
	Kind.ERRATIC: Color(0.7, 0.3, 1.0),
}

var kind := Kind.NORMAL
var _model: EggModel
var _trail: CPUParticles3D
var _spark: MeshInstance3D
var _turn_rate := 0.0
var _turn_at := 0.0
var _time := 0.0


func launch(from: Vector3, dir: Vector3, context: MatchContext, excluded: Array[RID], egg_kind: Kind = Kind.NORMAL) -> void:
	var cfg := context.config
	kind = egg_kind
	var egg_speed := cfg.egg_speed * (cfg.erratic_egg_speed_factor if kind == Kind.ERRATIC else 1.0)
	_start(from, dir, egg_speed, cfg.egg_range, cfg.egg_radius, context, excluded)
	_build_visuals()


## Explosive egg dropped from the air: falls straight down and blows up on the ground.
func drop(from: Vector3, context: MatchContext, excluded: Array[RID]) -> void:
	kind = Kind.EXPLOSIVE
	_start(from, Vector3.DOWN, 9.0, maxf(from.y - 0.3, 0.1), context.config.egg_radius, context, excluded, true)
	_build_visuals()


func _build_visuals() -> void:
	var color: Color = KIND_COLORS[kind]
	_model = EggModel.new()
	add_child(_model)
	_model.position.y = -EggModel.SHELL_Y
	# Flying eggs look different from pickups: a glow in the egg's colour and a sparkly trail.
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 2.5
	glow.omni_range = 3.0
	add_child(glow)
	_trail = CPUParticles3D.new()
	_trail.amount = 24
	_trail.lifetime = 0.4
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	_trail.mesh = quad
	_trail.material_override = Toon.glow_dot(color)
	_trail.gravity = Vector3.ZERO
	_trail.initial_velocity_min = 0.0
	_trail.initial_velocity_max = 0.2
	_trail.local_coords = false
	add_child(_trail)
	match kind:
		Kind.EXPLOSIVE:
			# Bomb egg: red band, a fuse on top and a flickering spark.
			var band := Toon.mat(Color(0.75, 0.08, 0.06), 0.5)
			Toon.part(_model.shell, Toon.cylinder(0.205, 0.205, 0.08, 24), band, Vector3(0, -0.02, 0))
			Toon.part(_model.shell, Toon.cylinder(0.015, 0.02, 0.12, 6), Toon.mat(Color(0.2, 0.15, 0.1), 0.9), Vector3(0, 0.27, 0))
			_spark = Toon.part(_model.shell, Toon.sphere(0.05, 8, 4), Toon.emissive(Color(1.0, 0.75, 0.3), 4.0), Vector3(0, 0.34, 0))
		Kind.ERRATIC:
			# Crazy egg: purple stripes.
			var stripe := Toon.emissive(Color(0.7, 0.3, 1.0), 1.5)
			for y: float in [-0.1, 0.06]:
				Toon.part(_model.shell, Toon.cylinder(0.2, 0.2, 0.04, 24), stripe, Vector3(0, y, 0))


func _on_flying(delta: float) -> void:
	_time += delta
	if not (_model and _model.shell):
		return
	_model.shell.rotation.x += delta * 18.0  # tumbling, unlike the calm bob of pickups
	match kind:
		Kind.EXPLOSIVE:
			if _spark:
				_spark.scale = Vector3.ONE * randf_range(0.6, 1.4)
		Kind.ERRATIC:
			_model.shell.rotation.z = sin(_time * 13.0) * 0.6
			# New random turn rate every fraction of a second, with the odd sharp kink.
			if _time >= _turn_at:
				_turn_at = _time + randf_range(0.15, 0.45)
				_turn_rate = randf_range(-5.0, 5.0)
				if randf() < 0.2:
					direction = direction.rotated(Vector3.UP, randf_range(-1.2, 1.2))
			direction = direction.rotated(Vector3.UP, _turn_rate * delta)


func _on_hit_character(character: CharacterBase) -> void:
	if kind == Kind.EXPLOSIVE:
		_explode()
		return
	character.hit_by_egg(direction)
	_fall_here(global_position - direction * 0.4)


func _on_hit_world() -> void:
	if kind == Kind.EXPLOSIVE:
		_explode()
		return
	Sfx.play_3d(ctx.world_root, Sfx.HIT, global_position, -6.0)
	_fall_here(global_position - direction * 0.6)


func _on_range_end() -> void:
	if kind == Kind.EXPLOSIVE:
		_explode()
		return
	_fall_here(global_position)


## Knocks down every character in the blast (pushed away from the centre); the egg survives
## the blast and drops as a pickup.
func _explode() -> void:
	var center := global_position
	var radius := ctx.config.explosion_radius
	Effects.explosion(ctx.world_root, center, radius)
	Sfx.play_3d(ctx.world_root, Sfx.HIT, center, 6.0)
	Sfx.play_3d(ctx.world_root, Sfx.SHOOT, center, 4.0)
	for c in ctx.competitors:
		var rel := c.global_position - center
		if not c.is_active or absf(rel.y) > 2.5 or Vector2(rel.x, rel.z).length() > radius:
			continue
		rel.y = 0.0
		c.hit_by_egg(rel.normalized() if rel.length() > 0.05 else direction)
	_fall_here(center)


func _fall_here(point: Vector3) -> void:
	var land := ctx.level.snap_to_ground(point, ctx.level.probe_point)
	ctx.egg_manager.spawn_ground_egg(global_position, land)
	Effects.sparkle_burst(ctx.world_root, global_position, KIND_COLORS[kind], 12)
	queue_free()

class_name EggProjectile
extends Projectile
## The egg the chicken shoots. While flying it is a hazard (knocks down and makes the victim drop
## eggs); when it hits something or runs out of range it falls and becomes a pickup.
## It can never hurt and be picked up at the same time.

var _model: EggModel
var _trail: CPUParticles3D


func launch(from: Vector3, dir: Vector3, context: MatchContext, excluded: Array[RID]) -> void:
	var cfg := context.config
	_start(from, dir, cfg.egg_speed, cfg.egg_range, cfg.egg_radius, context, excluded)
	_model = EggModel.new()
	add_child(_model)
	_model.position.y = -EggModel.SHELL_Y
	# Flying eggs look different from pickups: red-hot glow and a sparkly trail.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.2)
	glow.light_energy = 2.5
	glow.omni_range = 3.0
	add_child(glow)
	_trail = CPUParticles3D.new()
	_trail.amount = 24
	_trail.lifetime = 0.4
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	_trail.mesh = quad
	_trail.material_override = Toon.glow_dot(Color(1.0, 0.6, 0.2))
	_trail.gravity = Vector3.ZERO
	_trail.initial_velocity_min = 0.0
	_trail.initial_velocity_max = 0.2
	_trail.local_coords = false
	add_child(_trail)


func _on_flying(delta: float) -> void:
	if _model and _model.shell:
		_model.shell.rotation.x += delta * 18.0  # tumbling, unlike the calm bob of pickups


func _on_hit_character(character: CharacterBase) -> void:
	character.hit_by_egg(direction)
	_fall_here(global_position - direction * 0.4)


func _on_hit_world() -> void:
	Sfx.play_3d(ctx.world_root, Sfx.HIT, global_position, -6.0)
	_fall_here(global_position - direction * 0.6)


func _on_range_end() -> void:
	_fall_here(global_position)


func _fall_here(point: Vector3) -> void:
	var land := ctx.level.snap_to_ground(point, ctx.level.probe_point)
	ctx.egg_manager.spawn_ground_egg(global_position, land)
	Effects.sparkle_burst(ctx.world_root, global_position, Color(1.0, 0.6, 0.25), 12)
	queue_free()

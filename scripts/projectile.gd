class_name Projectile
extends Node3D
## Straight-flying hazard. Each physics step sweeps a sphere along its path and resolves the
## FIRST thing it touches: a character (any, not just the intended target) or a wall.
## It keeps the direction it was launched with (subclasses may steer it); it never homes in.

var direction := Vector3.FORWARD
var speed := 15.0
var radius := 0.3
var remaining := 20.0
var ctx: MatchContext
var _excluded: Array[RID] = []
var _shape := SphereShape3D.new()
var _done := false


## `keep_vertical` keeps the Y component of `dir` (e.g. an egg dropped from the air).
func _start(from: Vector3, dir: Vector3, proj_speed: float, proj_range: float, proj_radius: float,
		context: MatchContext, excluded: Array[RID], keep_vertical: bool = false) -> void:
	global_position = from
	direction = dir.normalized() if keep_vertical else Vector3(dir.x, 0.0, dir.z).normalized()
	speed = proj_speed
	remaining = proj_range
	radius = proj_radius
	ctx = context
	_excluded = excluded
	_shape.radius = radius


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := minf(speed * delta, remaining)
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _shape
	params.collision_mask = 1 | 2  # world + characters (the chicken is never hit)
	params.exclude = _excluded
	params.transform = Transform3D(Basis.IDENTITY, global_position)
	params.motion = direction * step
	var fractions := space.cast_motion(params)
	if fractions[1] < 1.0:
		var contact := global_position + direction * step * fractions[1]
		params.transform.origin = contact
		params.motion = Vector3.ZERO
		var info := space.get_rest_info(params)
		global_position = global_position + direction * step * fractions[0]
		var collider: Object = instance_from_id(info["collider_id"]) if info.has("collider_id") else null
		var character := collider as CharacterBase
		_done = true
		if character:
			_on_hit_character(character)
		else:
			_on_hit_world()
		return
	global_position += direction * step
	remaining -= step
	_on_flying(delta)
	if remaining <= 0.0:
		_done = true
		_on_range_end()


func _on_flying(_delta: float) -> void:
	pass


func _on_hit_character(_character: CharacterBase) -> void:
	queue_free()


func _on_hit_world() -> void:
	queue_free()


func _on_range_end() -> void:
	queue_free()

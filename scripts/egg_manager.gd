class_name EggManager
extends Node3D
## Golden eggs lying on the ground: the ones the chicken's shots leave behind and the ones
## knocked-out players drop. Eggs only enter an inventory through a pickup press.

signal egg_spawned(egg: GoldenEgg)
signal egg_collected(egg: GoldenEgg, collector: CharacterBase)

const EGG_SCENE: PackedScene = preload("res://scenes/items/golden_egg.tscn")

@export var config: GameConfig

var level: Level
var _eggs: Array[GoldenEgg] = []


## Drops one egg that hops from `from` and lands at `to` (already on reachable ground).
func spawn_ground_egg(from: Vector3, to: Vector3) -> GoldenEgg:
	var egg := EGG_SCENE.instantiate() as GoldenEgg
	egg.points = config.egg_points
	add_child(egg)
	egg.collected.connect(_on_egg_collected)
	egg.launch(from, to)
	_eggs.append(egg)
	egg_spawned.emit(egg)
	return egg


## Scatters `count` eggs around `origin` over reachable ground, biased along `direction`.
func scatter_eggs(origin: Vector3, count: int, direction: Vector3) -> void:
	var flat_dir := Vector3(direction.x, 0.0, direction.z).normalized()
	for i in count:
		var angle := randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.0, config.drop_scatter_radius)
		offset += flat_dir * randf_range(0.0, 1.2)
		var target := origin + offset
		var land := level.snap_to_ground(target, origin) if level else Vector3(target.x, 0.0, target.z)
		spawn_ground_egg(origin, land)


## Closest egg ready to be picked up within `radius`, or null.
func nearest_available(from_pos: Vector3, radius: float) -> GoldenEgg:
	var best: GoldenEgg = null
	var best_distance := radius
	for egg in _eggs:
		if not egg.is_available():
			continue
		var d := Vector2(egg.global_position.x - from_pos.x, egg.global_position.z - from_pos.z).length()
		if d <= best_distance:
			best = egg
			best_distance = d
	return best


func get_available_eggs() -> Array[GoldenEgg]:
	var result: Array[GoldenEgg] = []
	for egg in _eggs:
		if egg.is_available():
			result.append(egg)
	return result


func get_egg_count() -> int:
	return _eggs.size()


func _on_egg_collected(egg: GoldenEgg, collector: CharacterBase) -> void:
	_eggs.erase(egg)
	collector.add_eggs(egg.points)
	Sfx.play_3d(self, Sfx.COLLECT, egg.global_position, 0.0, 0.05)
	egg_collected.emit(egg, collector)

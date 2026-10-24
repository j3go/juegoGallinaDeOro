class_name ItemManager
extends Node3D
## Item waves: every `wave_interval` seconds a few items appear at reachable spots, without
## resetting eggs or the clock. Items stay on the ground until someone picks them up.

signal wave_spawned(count: int)

@export var config: GameConfig

var level: Level
var running := false
var _next_wave_at := 0.0
## Untyped on purpose: entries can be freed once taken.
var _items: Array = []


func start() -> void:
	running = true
	_next_wave_at = GameClock.now + config.first_wave_delay


func stop() -> void:
	running = false


func time_to_next_wave() -> float:
	return maxf(0.0, _next_wave_at - GameClock.now) if running else 0.0


func _physics_process(_delta: float) -> void:
	_items = Array(get_items())
	if running and GameClock.now >= _next_wave_at:
		_next_wave_at = GameClock.now + config.wave_interval
		_spawn_wave()


func nearest_item(from_pos: Vector3, radius: float) -> ItemPickup:
	var best: ItemPickup = null
	var best_distance := radius
	for item in _items:
		if not is_instance_valid(item) or not item.is_available():
			continue
		var d := Vector2(item.global_position.x - from_pos.x, item.global_position.z - from_pos.z).length()
		if d <= best_distance:
			best = item
			best_distance = d
	return best


func get_items() -> Array[ItemPickup]:
	var result: Array[ItemPickup] = []
	for item in _items:
		if is_instance_valid(item) and item.is_available():
			result.append(item)
	return result


func _spawn_wave() -> void:
	var spawned := 0
	for i in config.items_per_wave:
		if _items.size() >= config.max_ground_items:
			break
		var point := _free_point()
		var item := ItemPickup.new()
		add_child(item)
		item.global_position = point
		# Alternate kinds so every wave has both attack and protection.
		item.setup(CharacterBase.Item.KUNAI if (i % 2 == 0) else CharacterBase.Item.IMMORTALITY)
		_items.append(item)
		spawned += 1
	if spawned > 0:
		Sfx.play(self, Sfx.WAVE, -4.0)
		wave_spawned.emit(spawned)


func _free_point() -> Vector3:
	var best := level.random_point_in_map()
	for attempt in 12:
		var p := level.random_point_in_map()
		var ok := Vector2(p.x - 0.5, p.z).length() > 4.5  # away from the chicken
		for item in _items:
			if is_instance_valid(item) and item.global_position.distance_to(p) < 4.0:
				ok = false
		if ok:
			return p
		best = p
	return best

class_name Level
extends Node3D
## A playable map. Bakes the navigation mesh at startup from the props' colliders,
## exposes spawn points and offers helpers to pick reachable points on the ground.
## Each map scene (farm, war zone...) uses this script with its own props builder.

## Walkable half extent inside the fence (the fence sits at ±17 m).
const HALF_SIZE := 16.2
## Navmesh polygons this much above the ground level are on top of props (not reachable on foot).
const MAX_GROUND_OFFSET := 0.3

@export var display_name := "Mapa"
## An open spot of the map, used to detect when the navmesh is live.
@export var probe_point := Vector3(0, 0, 6)

## Height of the walkable navmesh surface on open ground (slightly above y = 0).
var _nav_ground_y := 0.0

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	# Props are built by their own script in _ready, which runs before this one.
	nav_region.bake_navigation_mesh(false)


## Waits until the navigation server has synced the baked mesh.
## Region updates are asynchronous, so poll until the probe point lands on this map's mesh
## (and the map query agrees, so no stale data from a previous map is used).
func wait_for_navigation() -> void:
	var region := nav_region.get_rid()
	for i in 600:
		await get_tree().physics_frame
		var probe := NavigationServer3D.region_get_closest_point(region, probe_point)
		if _flat(probe, probe_point) < 0.5 and _flat(_closest(probe_point), probe_point) < 0.5:
			_nav_ground_y = probe.y
			return
	push_warning("Navigation mesh did not become ready in time.")


## World position of the marker `Spawns/<marker_name>`, or `fallback` if the map has none.
func get_spawn(marker_name: String, fallback: Vector3) -> Vector3:
	var marker := get_node_or_null("Spawns/" + marker_name) as Node3D
	return marker.global_position if marker else fallback


func random_point_in_map() -> Vector3:
	for i in 16:
		var candidate := Vector3(randf_range(-HALF_SIZE, HALF_SIZE), 0.0, randf_range(-HALF_SIZE, HALF_SIZE))
		var point := _closest(candidate)
		if _is_ground(point) and _flat(point, candidate) < 2.5 and is_reachable(point):
			return _on_floor(point)
	return _on_floor(_closest(probe_point))


func random_point_near(center: Vector3, min_radius: float, max_radius: float) -> Vector3:
	for i in 16:
		var angle := randf() * TAU
		var radius := randf_range(min_radius, max_radius)
		var candidate := center + Vector3(cos(angle), 0.0, sin(angle)) * radius
		candidate.x = clampf(candidate.x, -HALF_SIZE, HALF_SIZE)
		candidate.z = clampf(candidate.z, -HALF_SIZE, HALF_SIZE)
		candidate.y = 0.0
		var point := _closest(candidate)
		if _is_ground(point) and _flat(point, candidate) < 2.0 and is_reachable(point):
			return _on_floor(point)
	return random_point_in_map()


## Closest reachable ground point to `point`, or `fallback` if there is none nearby.
func snap_to_ground(point: Vector3, fallback: Vector3) -> Vector3:
	var snapped_point := _closest(Vector3(point.x, 0.0, point.z))
	if _is_ground(snapped_point) and _flat(snapped_point, point) < 1.5 and is_reachable(snapped_point):
		return _on_floor(snapped_point)
	return _on_floor(_closest(Vector3(fallback.x, 0.0, fallback.z)))


## True if you can walk from the open probe point to `point` (rules out enclosed pockets).
func is_reachable(point: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map, _closest(probe_point), point, true)
	return not path.is_empty() and _flat(path[path.size() - 1], point) < 0.6


func _closest(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, point)


func _is_ground(point: Vector3) -> bool:
	return absf(point.y - _nav_ground_y) < MAX_GROUND_OFFSET \
			and absf(point.x) <= HALF_SIZE + 0.3 and absf(point.z) <= HALF_SIZE + 0.3


## Navmesh points float a few cm above the real floor; return them at floor level.
func _on_floor(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

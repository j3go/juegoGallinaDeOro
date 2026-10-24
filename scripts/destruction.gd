class_name Destruction
extends Node3D
## Explosions wreck the map: breakable props (marked by PropBuilder._breakable) lose loose
## pieces and get scorched on every nearby blast, and collapse into rubble when their hits run
## out. Blasts near the ground also leave craters. Colliders of collapsed props are removed and
## the level rebakes its navigation mesh.

const GROUP := "breakable"
## Visual pieces longer than this topple and sink instead of flying.
const BIG_PIECE := 2.4
const MAX_CRATERS := 30
const GRAVITY := 18.0

## Called when the navigation mesh must be rebaked (colliders were removed).
signal colliders_removed

var _debris: Array[Dictionary] = []
var _craters: Array[Node3D] = []
var _bounds := {}
var _scorch: Array[StandardMaterial3D] = []
var _crater_material: StandardMaterial3D


func _ready() -> void:
	for alpha: float in [0.3, 0.5, 0.68]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.035, 0.03, alpha)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_scorch.append(m)
	_crater_material = StandardMaterial3D.new()
	_crater_material.vertex_color_use_as_albedo = true
	_crater_material.vertex_color_is_srgb = true
	_crater_material.roughness = 1.0


## An explosion at `center`: damages breakable props in range and leaves a crater on the ground.
func blast(center: Vector3, radius: float) -> void:
	var removed := false
	for node in get_tree().get_nodes_in_group(GROUP):
		var prop := node as Node3D
		if prop == null or not prop.is_inside_tree() or prop.get_meta("broken", false):
			continue
		var box := _prop_bounds(prop)
		var closest := center.clamp(box.position, box.end)
		if closest.distance_to(center) > radius * 0.9:
			continue
		var hits: int = prop.get_meta("hits", 1) - 1
		prop.set_meta("hits", hits)
		if hits <= 0:
			_collapse(prop, center)
			removed = true
		else:
			_damage(prop, center, radius)
	_try_crater(center, radius)
	if removed:
		colliders_removed.emit()


func _process(delta: float) -> void:
	for i in range(_debris.size() - 1, -1, -1):
		var d := _debris[i]
		var node: Node3D = d["node"]
		if not is_instance_valid(node):
			_debris.remove_at(i)
			continue
		d["age"] += delta
		var age: float = d["age"]
		if d["topple"]:
			# Big walls and roofs keel over, fall and sink into the ground (which hides them).
			var vel: Vector3 = d["vel"]
			vel.y -= GRAVITY * 0.5 * delta
			d["vel"] = vel
			var w: float = d["spin"] * minf(age * 2.0, 1.0)
			node.global_basis = Basis(d["axis"], w * delta) * node.global_basis
			node.global_position += vel * delta
		else:
			var vel: Vector3 = d["vel"]
			vel.y -= GRAVITY * delta
			node.global_position += vel * delta
			if node.global_position.y < d["rest"] and vel.y < 0.0:
				node.global_position.y = d["rest"]
				vel = Vector3(vel.x * 0.5, -vel.y * 0.3, vel.z * 0.5)
				d["spin_rate"] *= 0.5
			d["vel"] = vel
			node.global_basis = Basis(d["axis"], d["spin_rate"] * delta) * node.global_basis
		var life: float = d["life"]
		if age > life:
			node.scale *= maxf(0.0, 1.0 - delta * 3.0)
			if age > life + 0.8:
				node.queue_free()
				_debris.remove_at(i)


# --- Props ---------------------------------------------------------------------------------

## Survived a blast: shake, scorch the side that took it and knock loose pieces off.
func _damage(prop: Node3D, center: Vector3, radius: float) -> void:
	var level: int = prop.get_meta("damage", 0) + 1
	prop.set_meta("damage", level)
	for mesh in _meshes(prop):
		var d := mesh.global_transform * mesh.get_aabb()
		if center.clamp(d.position, d.end).distance_to(center) > radius * 1.2:
			continue
		if not mesh.get_meta("solid", false) and _longest(d) < BIG_PIECE and randf() < 0.6:
			_launch(mesh, center, 1.0)
		else:
			mesh.material_overlay = _scorch[mini(level - 1, _scorch.size() - 1)]
	var origin: Vector3 = prop.get_meta("origin", prop.position)
	prop.set_meta("origin", origin)
	var tw := prop.create_tween()
	for i in 5:
		var jolt := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.08 * (1.0 - i / 5.0)
		tw.tween_property(prop, "position", origin + jolt, 0.04)
	tw.tween_property(prop, "position", origin, 0.05)
	_chips(prop, center)


## Out of hits: colliders go, every piece flies off or keels over, rubble stays behind.
func _collapse(prop: Node3D, center: Vector3) -> void:
	prop.set_meta("broken", true)
	var box := _prop_bounds(prop)
	var materials: Array[Material] = []
	for body in prop.find_children("*", "CollisionObject3D", true, false):
		body.get_parent().remove_child(body)
		body.queue_free()
	for light in prop.find_children("*", "Light3D", true, false):
		var l := light as Light3D
		l.create_tween().tween_property(l, "light_energy", 0.0, 0.4)
	for p in prop.find_children("*", "GPUParticles3D", true, false) + prop.find_children("*", "CPUParticles3D", true, false):
		p.set("emitting", false)
	for mesh in _meshes(prop):
		if mesh.material_override and materials.size() < 6 and not materials.has(mesh.material_override):
			materials.append(mesh.material_override)
		_launch(mesh, center, 1.4)
	_rubble(box, materials)
	Effects.dust_puff(get_parent(), Vector3(box.get_center().x, 0.2, box.get_center().z), 24)
	Sfx.play_3d(self, Sfx.HIT, box.get_center(), 2.0)
	get_tree().create_timer(3.0).timeout.connect(prop.queue_free)


## Detaches a visual piece and hands it to the debris simulation.
func _launch(mesh: GeometryInstance3D, center: Vector3, power: float) -> void:
	var box := mesh.global_transform * (mesh as VisualInstance3D).get_aabb()
	var away := box.get_center() - center
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	mesh.reparent(self, true)
	mesh.set_meta("solid", false)
	var big := _longest(box) >= BIG_PIECE
	var d := {"node": mesh, "age": 0.0, "topple": big, "life": randf_range(1.6, 2.6)}
	if big:
		d["axis"] = Vector3.UP.cross(away).normalized()
		d["spin"] = randf_range(0.9, 1.5)
		d["vel"] = away * 0.8
	else:
		d["vel"] = away * randf_range(2.5, 6.0) * power + Vector3.UP * randf_range(3.0, 7.0) * power
		d["axis"] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		d["spin_rate"] = randf_range(4.0, 12.0)
		d["rest"] = minf(box.size.y * 0.5, 0.3)
	_debris.append(d)


## Small chips of the prop's own material bursting out on a hit it survives.
func _chips(prop: Node3D, center: Vector3) -> void:
	var material: Material = null
	for mesh in _meshes(prop):
		if mesh.material_override:
			material = mesh.material_override
			break
	if material == null:
		return
	var box := _prop_bounds(prop)
	var at := center.clamp(box.position, box.end)
	for i in 8:
		var chip := Toon.part(self, Toon.box(Vector3.ONE * randf_range(0.08, 0.2)), material, Vector3.ZERO)
		chip.global_position = at
		var away := (at - center + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))).normalized()
		_debris.append({"node": chip, "age": 0.0, "topple": false, "life": randf_range(0.8, 1.4),
				"vel": away * randf_range(2.0, 5.0) + Vector3.UP * randf_range(2.0, 5.0),
				"axis": Vector3(randf(), randf(), randf()).normalized(), "spin_rate": 10.0, "rest": 0.05})


## Low pile of broken pieces (no collision, so it never blocks anyone) where the prop stood.
func _rubble(box: AABB, materials: Array[Material]) -> void:
	if materials.is_empty():
		return
	var pile := Node3D.new()
	pile.name = "Rubble"
	add_child(pile)
	var c := box.get_center()
	var half := Vector2(box.size.x, box.size.z) * 0.45
	var count := clampi(int(box.size.x * box.size.z * 1.5), 4, 30)
	for i in count:
		var s := Vector3(randf_range(0.2, 0.7), randf_range(0.06, 0.2), randf_range(0.2, 0.6))
		var p := Vector3(c.x + randf_range(-half.x, half.x), s.y * 0.4, c.z + randf_range(-half.y, half.y))
		var piece := Toon.part(pile, Toon.box(s), materials[i % materials.size()], p,
				Vector3(randf_range(-12, 12), randf() * 180.0, randf_range(-12, 12)))
		piece.material_overlay = _scorch[0]
	pile.scale = Vector3(1, 0.01, 1)
	pile.create_tween().tween_property(pile, "scale", Vector3.ONE, 0.6).set_delay(0.5).set_ease(Tween.EASE_OUT)


func _meshes(prop: Node3D) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for n in prop.find_children("*", "GeometryInstance3D", true, false):
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			out.append(n)
	return out


## World bounds of a prop's visible pieces (cached: props don't move).
func _prop_bounds(prop: Node3D) -> AABB:
	if _bounds.has(prop):
		return _bounds[prop]
	var box := AABB(prop.global_position, Vector3.ZERO)
	var first := true
	for mesh in _meshes(prop):
		var b := mesh.global_transform * (mesh as VisualInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	_bounds[prop] = box
	return box


func _longest(box: AABB) -> float:
	return maxf(box.size.x, maxf(box.size.y, box.size.z))


# --- Craters -------------------------------------------------------------------------------

## Leaves a crater if the blast was close enough to open ground.
func _try_crater(center: Vector3, radius: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 0.2, center + Vector3.DOWN * 2.5, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit["normal"].y < 0.85 or absf(hit["position"].y) > 0.15:
		return
	var ground: Vector3 = hit["position"]
	var height := center.y - ground.y
	var size := radius * 0.55 * clampf(1.2 - height / 2.5, 0.4, 1.0)
	_add_crater(Vector3(ground.x, 0.0, ground.z), size)


func _add_crater(at: Vector3, size: float) -> void:
	var crater := Node3D.new()
	crater.name = "Crater"
	add_child(crater)
	# Newer craters sit a hair higher so overlapping floors don't flicker.
	crater.global_position = at + Vector3.UP * 0.002 * (_craters.size() % 6)
	crater.rotation.y = randf() * TAU
	var mi := MeshInstance3D.new()
	mi.mesh = _crater_mesh(size)
	mi.material_override = _crater_material
	crater.add_child(mi)
	# Clods of dirt thrown around the rim.
	var clod := Toon.mat(Color(0.25, 0.19, 0.15), 1.0, 0.0, 0.0)
	for i in randi_range(6, 11):
		var a := randf() * TAU
		var r := size * randf_range(1.1, 1.7)
		var s := randf_range(0.06, 0.14) * clampf(size, 0.6, 1.6)
		Toon.part(crater, Toon.sphere(s, 8, 4), clod, Vector3(cos(a) * r, s * 0.3, sin(a) * r),
				Vector3(0, randf() * 180.0, 0), Vector3(1.0, 0.6, 1.2), false)
	# Glowing embers on the floor that cool down (additive, so fading to black makes them vanish).
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(1.0, 0.45, 0.12)
	var embers := Node3D.new()
	crater.add_child(embers)
	for i in 7:
		var a := randf() * TAU
		var r := randf_range(0.0, size * 0.5)
		var e := randf_range(0.1, 0.25) * clampf(size, 0.6, 1.5)
		Toon.part(embers, Toon.cylinder(e, e, 0.01, 10), glow, Vector3(cos(a) * r, 0.03, sin(a) * r),
				Vector3(0, randf() * 180.0, 0), Vector3(1.0, 1.0, randf_range(0.3, 0.8)), false)
	var tw := embers.create_tween()
	tw.tween_property(glow, "albedo_color", Color.BLACK, 3.0).set_ease(Tween.EASE_IN)
	tw.tween_callback(embers.queue_free)
	crater.scale = Vector3(0.3, 0.3, 0.3)
	crater.create_tween().tween_property(crater, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_craters.append(crater)
	if _craters.size() > MAX_CRATERS:
		var old: Node3D = _craters.pop_front()
		var fade := old.create_tween()
		fade.tween_property(old, "scale", Vector3(1, 0.01, 1), 1.0)
		fade.tween_callback(old.queue_free)


## Bowl with a raised, ragged rim: dark scorched floor, dirt walls, lip that sinks into the ground.
func _crater_mesh(size: float) -> ArrayMesh:
	const RINGS := 14
	const SEGMENTS := 40
	var seeds := Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array[PackedVector3Array] = []
	var colors: Array[PackedColorArray] = []
	for r in RINGS + 1:
		var u := float(r) / RINGS * 1.45
		var ring := PackedVector3Array()
		var ring_colors := PackedColorArray()
		for s in SEGMENTS:
			var a := TAU * s / SEGMENTS
			var ragged := 1.0 + 0.13 * sin(3.0 * a + seeds.x) + 0.07 * sin(7.0 * a + seeds.y) + 0.04 * sin(13.0 * a + seeds.z)
			var h := _crater_height(u) * clampf(size, 0.6, 1.5)
			ring.append(Vector3(cos(a), 0.0, sin(a)) * u * size * ragged + Vector3.UP * h)
			var grain := 0.85 + 0.3 * fposmod(sin(a * 17.0 + u * 23.0 + seeds.x) * 43758.5, 1.0)
			ring_colors.append(_crater_color(u) * grain)
		grid.append(ring)
		colors.append(ring_colors)
	for r in RINGS:
		for s in SEGMENTS:
			var s2 := (s + 1) % SEGMENTS
			var quad := [[r, s], [r + 1, s], [r + 1, s2], [r, s], [r + 1, s2], [r, s2]]
			for q: Array in quad:
				st.set_color(colors[q[0]][q[1]])
				st.add_vertex(grid[q[0]][q[1]])
	st.generate_normals()
	return st.commit()


## Height profile across the crater (u = distance / size): flat floor, steep inner wall,
## rim crest at u = 1, then a slope that ends just under the ground.
func _crater_height(u: float) -> float:
	if u < 0.7:
		return 0.012
	if u < 1.0:
		return lerpf(0.012, 0.17, smoothstep(0.7, 1.0, u))
	return lerpf(0.17, -0.03, smoothstep(1.0, 1.45, u))


func _crater_color(u: float) -> Color:
	var floor_col := Color(0.07, 0.055, 0.05)
	var wall := Color(0.2, 0.15, 0.12)
	var rim := Color(0.34, 0.26, 0.2)
	if u < 0.7:
		return floor_col.lerp(wall, smoothstep(0.3, 0.7, u) * 0.5)
	if u < 1.0:
		return wall.lerp(rim, smoothstep(0.75, 1.0, u))
	return rim.lerp(Color(0.27, 0.21, 0.17), smoothstep(1.0, 1.45, u))

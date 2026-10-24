@tool
class_name PropBuilder
extends Node3D
## Base for map builders: helpers to place primitive props and their colliders.
## Subclasses build everything in _ready (so it also shows up in the editor).

var _rng := RandomNumberGenerator.new()
var _fires: Array[Dictionary] = []


func _prop(parent: Node3D, pos: Vector3, rot_y: float = 0.0, prop_name: String = "Prop") -> Node3D:
	var n := Node3D.new()
	n.name = prop_name
	n.position = pos
	n.rotation_degrees.y = rot_y
	parent.add_child(n)
	return n


func _collider(parent: Node3D, shape: Shape3D, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation_degrees = rot_deg
	body.add_child(cs)
	parent.add_child(body)


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	return s


func _m(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	return Toon.mat(color, roughness, 0.0, 0.15)


## Many copies of one mesh in a single draw call (wire coils, rubble...).
func _multi(parent: Node3D, mesh: Mesh, material: Material, transforms: Array[Transform3D], cast_shadow: bool = true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	if not cast_shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


func _crate(parent: Node3D, pos: Vector3, rot_y: float, size: float, body_color: Color, frame_color: Color) -> Node3D:
	var c := _prop(parent, pos, rot_y, "Crate")
	var half := size * 0.5
	Toon.part(c, Toon.box(Vector3.ONE * size * 0.96), _m(body_color), Vector3(0, half, 0))
	var bar := size * 0.12
	var frame := _m(frame_color)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			Toon.part(c, Toon.box(Vector3(bar, size, bar)), frame, Vector3(x * (half - bar * 0.5), half, z * (half - bar * 0.5)))
		Toon.part(c, Toon.box(Vector3(bar, bar, size)), frame, Vector3(x * (half - bar * 0.5), size - bar * 0.5, 0))
		Toon.part(c, Toon.box(Vector3(size, bar, bar)), frame, Vector3(0, size - bar * 0.5, x * (half - bar * 0.5)))
	Toon.part(c, Toon.box(Vector3(size * 0.98, bar * 0.8, bar * 0.6)), frame, Vector3(0, half, half), Vector3(0, 0, 45))
	_collider(c, _box_shape(Vector3.ONE * size), Vector3(0, half, 0))
	return c


func _barrel(parent: Node3D, pos: Vector3, body_color: Color, ring_color: Color, top_color: Color) -> Node3D:
	var b := _prop(parent, pos, _rng.randf() * 360.0, "Barrel")
	Toon.part(b, Toon.cylinder(0.36, 0.36, 0.95, 18), _m(body_color), Vector3(0, 0.475, 0))
	Toon.part(b, Toon.cylinder(0.3, 0.3, 0.02, 18), _m(top_color), Vector3(0, 0.96, 0))
	for y: float in [0.2, 0.75]:
		Toon.part(b, Toon.cylinder(0.375, 0.375, 0.06, 18), _m(ring_color), Vector3(0, y, 0))
	_collider(b, _cyl_shape(0.4, 0.95), Vector3(0, 0.475, 0))
	return b


## Flames, embers and a flickering light. Call `_animate_fires` every frame.
func _fire(parent: Node3D, pos: Vector3, size: float, light_range: float = 6.0) -> void:
	var root := Toon.pivot(parent, pos, "Fire")
	var flames: Array = []
	var outer := Toon.emissive(Color(1.0, 0.45, 0.1), 5.0)
	var core := Toon.emissive(Color(1.0, 0.82, 0.35), 6.0)
	var specs := [[Vector3.ZERO, 0.24, 0.7, outer], [Vector3(0.1, 0, 0.06), 0.14, 0.5, core], [Vector3(-0.1, 0, -0.05), 0.12, 0.45, core]]
	for spec: Array in specs:
		var flame := Toon.pivot(root, spec[0] * size)
		Toon.part(flame, Toon.cylinder(0.0, spec[1] * size, spec[2] * size, 10), spec[3], Vector3(0, spec[2] * size * 0.5, 0), Vector3.ZERO, Vector3.ONE, false)
		flames.append(flame)
	var embers := CPUParticles3D.new()
	embers.amount = 10
	embers.lifetime = 1.3
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	embers.mesh = quad
	embers.material_override = Toon.glow_dot(Color(1.0, 0.55, 0.2))
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.2 * size
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.gravity = Vector3(0, 1.2, 0)
	embers.initial_velocity_min = 0.3
	embers.initial_velocity_max = 0.9
	embers.position.y = 0.3 * size
	root.add_child(embers)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = 2.2 * size
	light.omni_range = light_range * size
	light.position.y = 0.7 * size
	root.add_child(light)
	_fires.append({"light": light, "flames": flames, "energy": light.light_energy, "seed": _rng.randf() * TAU})


func _animate_fires(time: float) -> void:
	for fire in _fires:
		var seed_offset: float = fire.seed
		var light: OmniLight3D = fire.light
		light.light_energy = fire.energy * (0.8 + 0.22 * sin(time * 13.0 + seed_offset) + 0.12 * sin(time * 29.0 + seed_offset * 2.0))
		var flames: Array = fire.flames
		for i in flames.size():
			var flame: Node3D = flames[i]
			flame.scale.y = 1.0 + 0.25 * sin(time * (14.0 + i * 3.0) + seed_offset + i)

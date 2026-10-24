@tool
extends PropBuilder
## "Noche en la Granja" (based on reference/mapaNoche.png): a spooky farm at night with a
## giant rubber duck over a mine, a house on a hill linked by string lights to a water tower,
## a silo and a red barn, a smouldering crater where the chicken stands, a lava pit with a giant broken egg,
## a fire pit, a cow, a big concrete pipe and a UFO in the sky.
##
## Solid props are built with `_solid_*` helpers, which create the mesh AND a collider of the
## same shape, so what you see is what you bump into. The barn, the pipe and the mine alcove
## are hollow and can be entered; the hill and the duck platform have walkable stairs.
## Only tiny decoration (pebbles, grass, bulbs, things in the sky) has no collision.

const HALF := 17.0

const MUD := Color(0.27, 0.21, 0.17)
const MUD_DARK := Color(0.2, 0.16, 0.13)
const PATH := Color(0.36, 0.28, 0.21)
const GRASS := Color(0.2, 0.27, 0.16)
const STONE := Color(0.42, 0.4, 0.42)
const STONE_DARK := Color(0.3, 0.29, 0.31)
const ROCK := Color(0.36, 0.31, 0.29)
const WOOD := Color(0.45, 0.31, 0.21)
const WOOD_DARK := Color(0.3, 0.21, 0.15)
const WOOD_OLD := Color(0.38, 0.33, 0.28)
const METAL := Color(0.38, 0.38, 0.4)
const METAL_DARK := Color(0.22, 0.22, 0.24)
const BARN_RED := Color(0.55, 0.16, 0.13)
const ROOF_DARK := Color(0.25, 0.18, 0.17)
const DUCK := Color(0.93, 0.76, 0.22)
const DUCK_DIRT := Color(0.66, 0.5, 0.2)
const BEAK := Color(0.9, 0.42, 0.15)
const SILO := Color(0.72, 0.7, 0.66)
const HELI := Color(0.28, 0.32, 0.25)
const RUST := Color(0.45, 0.25, 0.16)
const TRACTOR := Color(0.6, 0.15, 0.12)
const RUBBER := Color(0.1, 0.1, 0.11)
const CONCRETE := Color(0.55, 0.54, 0.52)
const WARM := Color(1.0, 0.72, 0.35)
const TOXIC := Color(0.45, 1.0, 0.25)
const UFO_GREEN := Color(0.35, 1.0, 0.6)
const LAVA := Color(1.0, 0.28, 0.05)
const TREE_DEAD := Color(0.17, 0.14, 0.14)
const EGG_RADIUS := 1.3
const EGG_HALF_HEIGHT := 1.6
const EGG_CENTER_Y := 1.4

const CRATE_STACKS := [
	# x, z, rotation, layout (0 single, 1 pair, 2 pyramid)
	[-4.5, -7.2, 10.0, 2],
	[15.5, 6.5, 30.0, 1], [-13.5, -2.0, -10.0, 1], [-3.5, 13.5, 15.0, 2], [4.0, -8.0, 0.0, 0],
	[-15.2, 2.8, 80.0, 0], [10.0, 14.8, -20.0, 1],
]
const DEAD_TREES := [[-15.5, -15.0, 1.1], [-15.3, 13.8, 1.0], [15.8, -16.0, 0.9], [6.5, 15.6, 0.9], [-1.0, 15.9, 0.8]]
const OUTER_TREES := [
	[-21, -18, 1.4], [-8, -22, 1.2], [6, -21, 1.3], [21, -12, 1.2], [22, 4, 1.4],
	[20, 19, 1.1], [7, 22, 1.3], [-9, 21, 1.2], [-22, 8, 1.4], [-22, -5, 1.2],
]
const TOXIC_PUDDLES := [[15.2, 12.0, 1.0], [-13.5, 4.8, 1.1], [5.2, -6.0, 0.8]]

var _blades: Node3D
var _ufo: Node3D
var _ufo_bulbs: Array[MeshInstance3D] = []
var _lava_material: StandardMaterial3D
var _lava_lights: Array[OmniLight3D] = []
var _cow_head: Node3D
var _cow_tail: Node3D
var _time := 0.0


func _ready() -> void:
	_rng.seed = 33
	_lava_material = StandardMaterial3D.new()
	_lava_material.albedo_color = LAVA
	_lava_material.emission_enabled = true
	_lava_material.emission = LAVA
	_lava_material.emission_energy_multiplier = 3.0
	_lava_material.roughness = 0.4

	_build_ground()
	_build_perimeter()
	_build_background()
	_build_duck_platform(Vector3(-11.5, 0, -10.0))
	_build_windmill(Vector3(-6.0, 0, -15.0))
	_build_hill_house(Vector3(1.0, 0, -12.5))
	_build_water_tower(Vector3(8.0, 0, -13.5))
	_build_silo(Vector3(13.5, 0, -13.0))
	_build_barn(Vector3(11.5, 0, -6.0))
	_build_tractor(Vector3(13.5, 0, 1.5), -100.0)
	_build_crater(Vector3(0.5, 0, 0.0))
	_build_lava_pit(Vector3(-8.5, 0, 9.5))
	_build_fire_pit(Vector3(1.5, 0, 11.5))
	_build_cow(Vector3(7.5, 0, 6.5), 200.0)
	_build_pipe(Vector3(12.0, 0, 11.5))
	_build_pen_fence()
	_build_floodlight(Vector3(-7.0, 0, -2.0), 120.0)
	_build_floodlight(Vector3(16.0, 0, -1.0), -95.0)
	_build_string_lights()
	_build_ufo(Vector3(14.0, 10.0, -14.5))
	_build_moon()
	for c in CRATE_STACKS:
		_crate_stack(Vector3(c[0], 0, c[1]), c[2], c[3])
	for t in DEAD_TREES:
		_dead_tree(self, Vector3(t[0], 0, t[1]), t[2], true)
	for t in OUTER_TREES:
		_dead_tree(self, Vector3(t[0], 0, t[1]), t[2], false)
	for p in TOXIC_PUDDLES:
		_toxic_puddle(Vector3(p[0], 0, p[1]), p[2])
	_scatter_decor()


func _process(delta: float) -> void:
	_time += delta
	_animate_fires(_time)
	if is_instance_valid(_blades):
		_blades.rotation.z += delta * 0.8
	if _ufo:
		_ufo.position.y = 10.0 + sin(_time * 1.3) * 0.4
		_ufo.rotation.y += delta * 0.6
		for i in _ufo_bulbs.size():
			_ufo_bulbs[i].visible = int(_time * 6.0 + i) % 3 != 0
	if _lava_material:
		_lava_material.emission_energy_multiplier = 2.6 + sin(_time * 2.0) * 0.6
		for i in _lava_lights.size():
			_lava_lights[i].light_energy = 2.6 + sin(_time * 2.3 + i) * 0.5
	if _cow_head:
		_cow_head.rotation.x = 0.15 + sin(_time * 0.9) * 0.18
		_cow_tail.rotation.z = sin(_time * 2.4) * 0.4


# --- Solid helpers (mesh + matching collider) ---------------------------------------------

func _solid_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	_collider(parent, _box_shape(size), pos, rot_deg)
	return _solid_mesh(Toon.part(parent, Toon.box(size), material, pos, rot_deg))


func _solid_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material,
		top_radius: float = -1.0, segments: int = 16) -> MeshInstance3D:
	_collider(parent, _cyl_shape(radius, height), pos)
	var top := radius if top_radius < 0.0 else top_radius
	return _solid_mesh(Toon.part(parent, Toon.cylinder(top, radius, height, segments), material, pos))


func _solid_sphere(parent: Node3D, radius: float, pos: Vector3, material: Material, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var shape := SphereShape3D.new()
	# Colliders can't be squashed, so use the average radius of the ellipsoid.
	shape.radius = radius * (scl.x + scl.y + scl.z) / 3.0
	_collider(parent, shape, pos)
	return _solid_mesh(Toon.part(parent, Toon.sphere(radius, 24, 12), material, pos, Vector3.ZERO, scl))


## Marks the visible part of a collider: blasts scorch it but don't knock it off on its own.
func _solid_mesh(mesh: MeshInstance3D) -> MeshInstance3D:
	mesh.set_meta("solid", true)
	return mesh


## Straight ramp/stairs from `bottom` up to `top` (both local), walkable by everyone.
func _stairs(parent: Node3D, bottom: Vector3, top: Vector3, width: float, material: Material) -> void:
	var run := Vector2(top.x - bottom.x, top.z - bottom.z)
	var length := Vector3(run.x, top.y - bottom.y, run.y).length()
	var yaw := rad_to_deg(atan2(run.x, run.y))
	var pitch := -rad_to_deg(atan2(top.y - bottom.y, run.length()))
	var ramp := Toon.pivot(parent, (bottom + top) * 0.5, "Stairs")
	ramp.rotation_degrees = Vector3(pitch, yaw, 0)
	_collider(ramp, _box_shape(Vector3(width, 0.2, length)), Vector3(0, -0.1, 0))
	Toon.part(ramp, Toon.box(Vector3(width, 0.12, length)), _m(WOOD_DARK), Vector3(0, -0.06, 0))
	var steps := int(length / 0.35)
	for i in steps:
		Toon.part(ramp, Toon.box(Vector3(width, 0.1, 0.22)), material, Vector3(0, 0.03, -length * 0.5 + 0.2 + i * 0.35))
	for side: float in [-1.0, 1.0]:
		Toon.part(ramp, Toon.box(Vector3(0.08, 0.08, length)), _m(WOOD_DARK), Vector3(side * width * 0.5, 0.75, 0))
		_collider(ramp, _box_shape(Vector3(0.1, 0.8, length)), Vector3(side * width * 0.5, 0.4, 0))
		for i in 3:
			Toon.part(ramp, Toon.box(Vector3(0.08, 0.75, 0.08)), _m(WOOD_DARK), Vector3(side * width * 0.5, 0.37, -length * 0.4 + i * length * 0.4))


func _point_light(parent: Node3D, pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.position = pos
	parent.add_child(l)
	return l


func _additive(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m


## Pushes characters out (with a little hop) when they step on lava or fire.
func _hazard(parent: Node3D, pos: Vector3, radius: float) -> void:
	var area := Area3D.new()
	area.name = "Hazard"
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	var cs := CollisionShape3D.new()
	cs.shape = _cyl_shape(radius, 1.2)
	cs.position.y = 0.6
	area.add_child(cs)
	parent.add_child(area)
	area.position = pos
	if not Engine.is_editor_hint():
		area.body_entered.connect(_on_hazard_entered.bind(area))


func _on_hazard_entered(body: Node3D, area: Area3D) -> void:
	var character := body as CharacterBase
	if character == null:
		return
	var away := character.global_position - area.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	character.knockback(away * 9.0 + Vector3.UP * 8.0)
	Effects.sparkle_burst(self, character.global_position + Vector3.UP * 0.5, Color(1.0, 0.45, 0.15), 18)
	Effects.floating_text(self, character.global_position + Vector3.UP * 2.0, "¡Quema!", Color(1.0, 0.55, 0.25))


# --- Ground, border, sky -------------------------------------------------------------------

func _build_ground() -> void:
	var ground := _prop(self, Vector3.ZERO, 0.0, "Ground")
	Toon.part(ground, Toon.box(Vector3(46, 1, 46)), MapMaterials.ground(MUD, MUD_DARK, PATH, GRASS), Vector3(0, -0.5, 0))
	Toon.part(ground, Toon.cylinder(110, 110, 0.5, 48), Toon.mat(MUD_DARK, 1.0, 0.0, 0.0), Vector3(0, -0.6, 0), Vector3.ZERO, Vector3.ONE, false)
	_collider(ground, _box_shape(Vector3(40, 1, 40)), Vector3(0, -0.5, 0))
	# Tyre tracks curving around the crater.
	var track := Toon.mat(MUD_DARK, 1.0, 0.0, 0.0)
	for ring: float in [4.6, 5.2]:
		for i in 40:
			var a := TAU * i / 40.0
			var p := Vector3(0.5 + cos(a) * ring, 0.01, sin(a) * ring)
			Toon.part(ground, Toon.box(Vector3(0.22, 0.02, 0.8)), track, p, Vector3(0, -rad_to_deg(a), 0), Vector3.ONE, false)


func _build_perimeter() -> void:
	var root := _prop(self, Vector3.ZERO, 0.0, "Perimeter")
	var sides := [
		[Vector2(-HALF, -HALF), Vector2(HALF, -HALF), 2.2], [Vector2(-HALF, -HALF), Vector2(-HALF, HALF), 1.9],
		[Vector2(HALF, -HALF), Vector2(HALF, HALF), 1.9], [Vector2(-HALF, HALF), Vector2(HALF, HALF), 1.1],
	]
	for s: Array in sides:
		_plank_fence(root, s[0], s[1], s[2])
	# Tall invisible walls keep everyone inside even when jumping from props.
	for side: float in [-1.0, 1.0]:
		_collider(root, _box_shape(Vector3(35, 5, 0.6)), Vector3(0, 2.5, HALF * side))
		_collider(root, _box_shape(Vector3(0.6, 5, 35)), Vector3(HALF * side, 2.5, 0))


## Broken fence of vertical planks with uneven heights and a few gaps.
func _plank_fence(parent: Node3D, a: Vector2, b: Vector2, height: float) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var angle := rad_to_deg(atan2(-dir.y, dir.x))
	var count := int(length / 0.42)
	for i in count:
		if _rng.randf() < 0.08:
			continue
		var t := (i + 0.5) * length / count
		var p := a + dir * t
		var h := height * _rng.randf_range(0.6, 1.1)
		var tone := WOOD_OLD if _rng.randf() < 0.5 else WOOD_DARK
		Toon.part(parent, Toon.box(Vector3(0.36, h, 0.08)), _m(tone, 0.95), Vector3(p.x, h * 0.5, p.y),
				Vector3(_rng.randf_range(-4, 4), angle, _rng.randf_range(-5, 5)))
	var mid := (a + b) * 0.5
	Toon.part(parent, Toon.box(Vector3(length, 0.14, 0.08)), _m(WOOD_DARK), Vector3(mid.x, height * 0.5, mid.y), Vector3(0, angle, 0))


func _build_background() -> void:
	var root := _prop(self, Vector3.ZERO, 0.0, "Background")
	var hill := Toon.mat(Color(0.12, 0.1, 0.15), 1.0, 0.0, 0.0)
	for i in 14:
		var a := TAU * i / 14.0
		var r := _rng.randf_range(45.0, 60.0)
		var s := _rng.randf_range(8.0, 16.0)
		Toon.part(root, Toon.sphere(1.0, 16, 8), hill, Vector3(cos(a) * r, -1.0, sin(a) * r), Vector3.ZERO, Vector3(s * 1.6, s * 0.5, s), false)
	# Far ruined houses, some with a lit window.
	var house := Toon.mat(Color(0.16, 0.13, 0.17), 1.0, 0.0, 0.0)
	for i in 12:
		var a := TAU * i / 12.0 + 0.2
		var r := _rng.randf_range(30.0, 40.0)
		var h := _rng.randf_range(4.0, 9.0)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		var b := _prop(root, pos, rad_to_deg(-a), "FarHouse")
		Toon.part(b, Toon.box(Vector3(4, h, 3)), house, Vector3(0, h * 0.5, 0), Vector3.ZERO, Vector3.ONE, false)
		Toon.part(b, Toon.prism(Vector3(4.4, 1.8, 3.2)), house, Vector3(0, h + 0.9, 0), Vector3.ZERO, Vector3.ONE, false)
		if _rng.randf() < 0.6:
			Toon.part(b, Toon.box(Vector3(0.6, 0.6, 0.1)), Toon.emissive(WARM, 3.0), Vector3(_rng.randf_range(-1, 1), h * 0.6, 1.55), Vector3.ZERO, Vector3.ONE, false)


func _build_moon() -> void:
	var moon := Toon.pivot(self, Vector3(30, 70, -150), "Moon")
	Toon.part(moon, Toon.sphere(12.0, 32, 16), Toon.emissive(Color(0.92, 0.94, 1.0), 1.6), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(70, 70)
	halo.mesh = quad
	halo.material_override = Toon.glow_dot(Color(0.6, 0.65, 1.0, 0.35), false)
	(halo.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon.add_child(halo)


# --- Landmarks -----------------------------------------------------------------------------

func _build_duck_platform(pos: Vector3) -> void:
	var p := _prop(self, pos, 0.0, "DuckPlatform")
	var stone := MapMaterials.bricks(STONE, STONE_DARK.darkened(0.3))
	var h := 1.8
	# Built from pieces so the mine alcove at the front is a real, walkable recess.
	_solid_box(p, Vector3(6, h, 4.4), Vector3(0, h * 0.5, -0.8), stone)
	_solid_box(p, Vector3(2.1, h, 1.6), Vector3(-1.95, h * 0.5, 2.2), stone)
	_solid_box(p, Vector3(2.1, h, 1.6), Vector3(1.95, h * 0.5, 2.2), stone)
	_solid_box(p, Vector3(1.8, 0.15, 1.6), Vector3(0, h - 0.075, 2.2), stone)
	# Mine entrance: dark back wall, timber frame, lantern.
	Toon.part(p, Toon.box(Vector3(1.8, 1.65, 0.05)), Toon.mat(Color(0.05, 0.04, 0.04), 1.0, 0.0, 0.0), Vector3(0, 0.82, 1.42))
	for x: float in [-0.85, 0.85]:
		Toon.part(p, Toon.box(Vector3(0.15, 1.65, 0.15)), _m(WOOD), Vector3(x, 0.82, 2.95))
	Toon.part(p, Toon.box(Vector3(1.9, 0.15, 0.18)), _m(WOOD), Vector3(0, 1.6, 2.95))
	Toon.part(p, Toon.box(Vector3(0.16, 0.22, 0.16)), Toon.emissive(WARM, 4.0), Vector3(0.6, 1.3, 2.7))
	_point_light(p, Vector3(0.6, 1.2, 2.5), WARM, 1.2, 4.0)
	# Rail track coming out of the mine.
	for x: float in [-0.35, 0.35]:
		Toon.part(p, Toon.box(Vector3(0.06, 0.06, 3.0)), _m(METAL), Vector3(x, 0.05, 3.8), Vector3.ZERO, Vector3.ONE, false)
	for i in 6:
		Toon.part(p, Toon.box(Vector3(1.0, 0.05, 0.14)), _m(WOOD_DARK), Vector3(0, 0.025, 1.6 + i * 0.5), Vector3.ZERO, Vector3.ONE, false)
	# Stairs down the east side.
	_stairs(p, Vector3(5.8, 0, -1.0), Vector3(3.0, h, -1.0), 1.6, _m(WOOD))
	# Railing on top.
	for i in 7:
		Toon.part(p, Toon.box(Vector3(0.1, 0.8, 0.1)), _m(WOOD_DARK), Vector3(-3 + i, h + 0.4, 2.9))
	Toon.part(p, Toon.box(Vector3(6, 0.08, 0.08)), _m(WOOD_DARK), Vector3(0, h + 0.75, 2.9))
	_collider(p, _box_shape(Vector3(6, 0.8, 0.1)), Vector3(0, h + 0.4, 2.9))

	# Giant (slightly dirty) rubber duck sitting on the platform.
	var duck := _breakable(Toon.pivot(p, Vector3(-0.6, h, -1.0), "Duck"), 3)
	duck.rotation_degrees.y = 25.0
	var yellow := MapMaterials.spots(DUCK, DUCK_DIRT, 0.9, 0.16, 0.5, 0.0, 0.3, 0.08)
	_solid_sphere(duck, 2.0, Vector3(0, 1.5, -0.3), yellow, Vector3(1.0, 0.78, 1.25))
	_solid_sphere(duck, 1.25, Vector3(0, 3.2, 1.1), yellow)
	Toon.part(duck, Toon.sphere(0.7), yellow, Vector3(0, 2.2, -2.5), Vector3(40, 0, 0), Vector3(0.8, 1.0, 0.6))
	Toon.part(duck, Toon.sphere(0.6), Toon.mat(BEAK, 0.5), Vector3(0, 2.95, 2.25), Vector3(-8, 0, 0), Vector3(1.3, 0.45, 1.2))
	Toon.part(duck, Toon.sphere(0.5), Toon.mat(BEAK.darkened(0.3), 0.5), Vector3(0, 2.72, 2.1), Vector3(-8, 0, 0), Vector3(1.15, 0.3, 1.0))
	for side: float in [-1.0, 1.0]:
		var eye := Toon.pivot(duck, Vector3(0, 3.35, 1.1))
		eye.rotation_degrees.y = 38.0 * side
		Toon.part(eye, Toon.sphere(0.34), Toon.mat(Color(1, 1, 1), 0.3, 0.0, 0.0), Vector3(0, 0, 1.08), Vector3.ZERO, Vector3(1, 1, 0.4))
		Toon.part(eye, Toon.sphere(0.24), Toon.mat(Color(0.06, 0.06, 0.07), 0.2, 0.0, 0.0), Vector3(0, 0, 1.2), Vector3.ZERO, Vector3(1, 1, 0.35))
		Toon.part(eye, Toon.sphere(0.06, 8, 4), Toon.unshaded(Color(1, 1, 1)), Vector3(0.08, 0.09, 1.3))
		Toon.part(duck, Toon.sphere(0.6), yellow, Vector3(1.75 * side, 1.6, -0.4), Vector3(0, 0, 0), Vector3(0.3, 0.7, 1.1))
	_fire(self, Vector3(pos.x + 2.8, 0.05, pos.z + 5.6), 0.8)
	_collider(self, _cyl_shape(0.55, 0.3), Vector3(pos.x + 2.8, 0.15, pos.z + 5.6))
	for i in 6:
		var a := TAU * i / 6.0
		Toon.part(self, Toon.sphere(0.16, 8, 5), _m(STONE_DARK), Vector3(pos.x + 2.8 + cos(a) * 0.45, 0.08, pos.z + 5.6 + sin(a) * 0.45), Vector3.ZERO, Vector3(1, 0.6, 1))


func _build_windmill(pos: Vector3) -> void:
	var w := _breakable(_prop(self, pos, 15.0, "Windmill"), 3)
	var metal := _m(METAL_DARK)
	var height := 7.0
	for x: float in [-0.9, 0.9]:
		for z: float in [-0.9, 0.9]:
			_collider(w, _cyl_shape(0.12, height), Vector3(x * 0.75, height * 0.5, z * 0.75))
			var leg := Toon.part(w, Toon.box(Vector3(0.1, height, 0.1)), metal, Vector3(x * 0.75, height * 0.5, z * 0.75))
			leg.rotation_degrees = Vector3(-z * 4.0, 0, x * 4.0)
	for i in 4:
		var y := 1.2 + i * 1.5
		var span := 1.9 - i * 0.22
		for side: float in [-1.0, 1.0]:
			if y < 2.5:
				_solid_box(w, Vector3(span, 0.06, 0.06), Vector3(0, y, side * span * 0.5), metal)
				_solid_box(w, Vector3(0.06, 0.06, span), Vector3(side * span * 0.5, y, 0), metal)
			else:
				Toon.part(w, Toon.box(Vector3(span, 0.06, 0.06)), metal, Vector3(0, y, side * span * 0.5))
				Toon.part(w, Toon.box(Vector3(0.06, 0.06, span)), metal, Vector3(side * span * 0.5, y, 0))
	Toon.part(w, Toon.box(Vector3(0.5, 0.5, 0.9)), _m(RUST), Vector3(0, height + 0.2, 0))
	Toon.part(w, Toon.box(Vector3(0.05, 0.9, 1.3)), _m(RUST), Vector3(0, height + 0.3, -1.1))
	_blades = Toon.pivot(w, Vector3(0, height + 0.25, 0.55), "Blades")
	for i in 12:
		var blade := Toon.pivot(_blades)
		blade.rotation.z = TAU * i / 12.0
		Toon.part(blade, Toon.box(Vector3(0.22, 1.6, 0.03)), _m(METAL), Vector3(0, 1.0, 0), Vector3(0, 20, 0))


func _build_hill_house(pos: Vector3) -> void:
	var hill := _prop(self, pos, 0.0, "HillHouse")
	var rock := MapMaterials.spots(ROCK, ROCK.darkened(0.35), 0.8, 0.45, 1.0, 0.0, 0.1, 0.25)
	_solid_cyl(hill, 4.2, 1.2, Vector3(0, 0.6, 0), rock, 3.9, 20)
	_solid_cyl(hill, 3.7, 1.2, Vector3(0, 1.8, -0.2), rock, 3.4, 20)
	for i in 16:
		var a := TAU * i / 16.0 + _rng.randf_range(-0.1, 0.1)
		var r := _rng.randf_range(3.9, 4.2)
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.3:
			continue  # keep the stairs clear
		_solid_sphere(hill, 0.55, Vector3(cos(a) * r, _rng.randf_range(0.3, 1.6), sin(a) * r),
				MapMaterials.spots(ROCK.darkened(0.1), ROCK.darkened(0.45), 2.5, 0.45, 1.0, 0.0, 0.1, 0.25), Vector3(1.2, 0.8, 1.0))
	var top := 2.4
	# Stairs up the front of the hill.
	_stairs(hill, Vector3(0.0, 0, 7.6), Vector3(0.0, top, 3.4), 1.6, _m(WOOD))
	# House on top with lit windows.
	var house := _breakable(Toon.pivot(hill, Vector3(0, top, -0.8), "House"), 3)
	var wood := _m(WOOD)
	_solid_box(house, Vector3(3.6, 2.5, 2.8), Vector3(0, 1.25, 0), wood)
	for i in 6:
		Toon.part(house, Toon.box(Vector3(3.62, 0.04, 2.82)), _m(WOOD_DARK), Vector3(0, 0.3 + i * 0.4, 0))
	Toon.part(house, Toon.prism(Vector3(3.4, 1.6, 4.2)), _m(ROOF_DARK), Vector3(0, 3.3, 0), Vector3(0, 90, 0))
	Toon.part(house, Toon.box(Vector3(0.5, 1.0, 0.5)), _m(STONE_DARK), Vector3(1.0, 3.8, -0.6))
	for x: float in [-1.0, 1.0]:
		Toon.part(house, Toon.box(Vector3(0.65, 0.65, 0.06)), Toon.emissive(WARM, 3.5), Vector3(x, 1.5, 1.42))
		Toon.part(house, Toon.box(Vector3(0.08, 0.65, 0.08)), _m(WOOD_DARK), Vector3(x, 1.5, 1.45))
	Toon.part(house, Toon.box(Vector3(0.8, 1.6, 0.06)), _m(WOOD_DARK), Vector3(0, 0.8, 1.42))
	_point_light(house, Vector3(0, 1.4, 2.3), WARM, 1.6, 6.0)
	# Porch roof and posts.
	Toon.part(house, Toon.box(Vector3(3.8, 0.1, 1.2)), _m(WOOD_DARK), Vector3(0, 2.3, 2.0), Vector3(-10, 0, 0))
	for x: float in [-1.7, 1.7]:
		_solid_box(house, Vector3(0.12, 2.2, 0.12), Vector3(x, 1.1, 2.5), _m(WOOD_DARK))
	# Fence around the hill top (with an opening for the stairs).
	for i in 18:
		var a := TAU * i / 18.0
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.35:
			continue
		var p := Vector3(cos(a) * 3.3, top, sin(a) * 3.3 - 0.2)
		_solid_box(hill, Vector3(0.12, 0.9, 0.12), p + Vector3.UP * 0.45, _m(WOOD_DARK))


func _build_water_tower(pos: Vector3) -> void:
	var t := _breakable(_prop(self, pos, 0.0, "WaterTower"), 3)
	var height := 4.4
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			_solid_box(t, Vector3(0.18, height, 0.18), Vector3(x, height * 0.5, z), _m(WOOD_DARK))
	for y: float in [1.4, 3.0]:
		for side: float in [-1.0, 1.0]:
			_solid_box(t, Vector3(2.0, 0.08, 0.08), Vector3(0, y, side), _m(WOOD_DARK))
			_solid_box(t, Vector3(0.08, 0.08, 2.0), Vector3(side, y, 0), _m(WOOD_DARK))
	Toon.part(t, Toon.box(Vector3(2.6, 0.15, 2.6)), _m(WOOD), Vector3(0, height, 0))
	Toon.part(t, Toon.cylinder(1.25, 1.25, 2.0, 20), _m(WOOD), Vector3(0, height + 1.1, 0))
	for y: float in [0.4, 1.0, 1.6]:
		Toon.part(t, Toon.cylinder(1.28, 1.28, 0.06, 20), _m(METAL_DARK), Vector3(0, height + 0.1 + y, 0))
	Toon.part(t, Toon.cylinder(0.0, 1.45, 0.8, 20), _m(ROOF_DARK), Vector3(0, height + 2.5, 0))
	# Chicken emblem painted on the tank.
	_chicken_emblem(t, Vector3(0, height + 1.1, 1.26), 0.55)


func _build_silo(pos: Vector3) -> void:
	var s := _breakable(_prop(self, pos, -20.0, "Silo"), 4)
	var mat := MapMaterials.spots(SILO, RUST, 0.9, 0.25, 0.9, 0.1, 0.15, 0.06)
	_solid_cyl(s, 1.6, 7.0, Vector3(0, 3.5, 0), mat, -1.0, 24)
	Toon.part(s, Toon.sphere(1.6, 24, 12), Toon.mat(METAL, 0.6, 0.4, 0.2), Vector3(0, 7.0, 0), Vector3.ZERO, Vector3(1, 0.7, 1))
	for y: float in [1.5, 3.5, 5.5]:
		Toon.part(s, Toon.cylinder(1.63, 1.63, 0.08, 24), _m(METAL_DARK), Vector3(0, y, 0))
	_chicken_emblem(s, Vector3(0, 5.0, 1.62), 0.8)
	# Ladder.
	for x: float in [-0.25, 0.25]:
		Toon.part(s, Toon.box(Vector3(0.05, 6.8, 0.05)), _m(METAL_DARK), Vector3(x + 1.0, 3.4, 1.3))
	for i in 14:
		Toon.part(s, Toon.box(Vector3(0.5, 0.04, 0.04)), _m(METAL_DARK), Vector3(1.0, 0.3 + i * 0.48, 1.3))


func _chicken_emblem(parent: Node3D, pos: Vector3, size: float) -> void:
	var e := Toon.pivot(parent, pos, "Emblem")
	var white := Toon.mat(Color(0.95, 0.94, 0.9), 0.9, 0.0, 0.0)
	Toon.part(e, Toon.sphere(0.6 * size, 20, 10), white, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.1, 0.08))
	for side: float in [-1.0, 1.0]:
		Toon.part(e, Toon.sphere(0.12 * size, 10, 5), Toon.mat(Color(0.08, 0.08, 0.1), 0.5, 0.0, 0.0), Vector3(0.22 * side * size, 0.15 * size, 0.04), Vector3.ZERO, Vector3(1, 1.2, 0.3))
	Toon.part(e, Toon.sphere(0.13 * size, 10, 5), Toon.mat(Color(1.0, 0.75, 0.2), 0.5, 0.0, 0.0), Vector3(0, -0.08 * size, 0.05), Vector3.ZERO, Vector3(1.3, 0.6, 0.3))
	Toon.part(e, Toon.sphere(0.12 * size, 10, 5), Toon.mat(Color(0.85, 0.2, 0.18), 0.5, 0.0, 0.0), Vector3(0, 0.68 * size, 0.02), Vector3.ZERO, Vector3(0.8, 1.2, 0.2))


func _build_barn(pos: Vector3) -> void:
	var b := _breakable(_prop(self, pos, 0.0, "Barn"), 4)
	var red := Toon.mat(BARN_RED, 0.9, 0.0, 0.15)
	var w := 6.0
	var d := 5.0
	var h := 3.2
	var t := 0.2
	var door := 2.4
	# Hollow barn: four walls with a big door gap at the front, so you can walk inside.
	_solid_box(b, Vector3(w, h, t), Vector3(0, h * 0.5, -d * 0.5), red)
	for side: float in [-1.0, 1.0]:
		_solid_box(b, Vector3(t, h, d), Vector3(side * w * 0.5, h * 0.5, 0), red)
		var seg := (w - door) * 0.5
		_solid_box(b, Vector3(seg, h, t), Vector3(side * (door * 0.5 + seg * 0.5), h * 0.5, d * 0.5), red)
		# Open doors with white cross bracing.
		var leaf := Toon.pivot(b, Vector3(side * door * 0.5, 0, d * 0.5))
		leaf.rotation_degrees.y = -side * 70.0
		_solid_box(leaf, Vector3(1.2, h * 0.85, 0.1), Vector3(side * 0.6, h * 0.425, 0), red)
		for k: float in [-1.0, 1.0]:
			Toon.part(leaf, Toon.box(Vector3(0.08, 1.6, 0.12)), Toon.mat(Color(0.9, 0.88, 0.82), 0.9), Vector3(side * 0.6, h * 0.425, 0), Vector3(0, 0, 35 * k))
	Toon.part(b, Toon.box(Vector3(door, h - h * 0.85, t)), red, Vector3(0, h * 0.85 + (h - h * 0.85) * 0.5, d * 0.5))
	for i in 12:
		Toon.part(b, Toon.box(Vector3(0.04, h, 0.03)), _m(BARN_RED.darkened(0.3)), Vector3(-w * 0.5 + 0.25 + i * 0.5, h * 0.5, -d * 0.5 - 0.11))
	# Gambrel-like roof made of two slopes per side.
	var roof := _m(ROOF_DARK)
	for side: float in [-1.0, 1.0]:
		Toon.part(b, Toon.box(Vector3(1.9, 0.15, d + 0.6)), roof, Vector3(side * 2.3, h + 0.6, 0), Vector3(0, 0, -side * 55))
		Toon.part(b, Toon.box(Vector3(2.0, 0.15, d + 0.6)), roof, Vector3(side * 0.85, h + 1.65, 0), Vector3(0, 0, -side * 22))
	Toon.part(b, Toon.prism(Vector3(w, 2.0, 0.15)), red, Vector3(0, h + 1.0, d * 0.5 - 0.05))
	Toon.part(b, Toon.prism(Vector3(w, 2.0, 0.15)), red, Vector3(0, h + 1.0, -d * 0.5 + 0.05))
	Toon.part(b, Toon.box(Vector3(0.9, 0.9, 0.08)), Toon.emissive(WARM, 2.0), Vector3(0, h + 0.8, d * 0.5 + 0.05))
	Toon.part(b, Toon.box(Vector3(w - 0.4, 0.04, d - 0.4)), Toon.mat(Color(0.45, 0.36, 0.2), 1.0, 0.0, 0.0), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3.ONE, false)
	_point_light(b, Vector3(0, 2.2, 0), WARM, 2.0, 6.5)
	# Hay bales inside.
	var hay := Toon.mat(Color(0.75, 0.6, 0.3), 1.0, 0.0, 0.2)
	_solid_box(b, Vector3(1.2, 0.75, 0.8), Vector3(-2.1, 0.375, -1.6), hay)
	_solid_box(b, Vector3(1.2, 0.75, 0.8), Vector3(-2.1, 1.125, -1.6), hay)
	_solid_box(b, Vector3(0.8, 0.75, 1.2), Vector3(2.2, 0.375, -1.4), hay)


func _build_tractor(pos: Vector3, rot_y: float) -> void:
	var t := _breakable(_prop(self, pos, rot_y, "Tractor"), 2)
	var red := Toon.mat(TRACTOR, 0.7, 0.1, 0.2)
	_solid_box(t, Vector3(1.1, 0.8, 2.6), Vector3(0, 1.0, 0.3), red)
	_solid_box(t, Vector3(0.9, 0.6, 1.2), Vector3(0, 1.1, 1.6), red)
	Toon.part(t, Toon.box(Vector3(1.1, 0.08, 1.1)), _m(METAL_DARK), Vector3(0, 2.4, -0.4))
	for x: float in [-0.5, 0.5]:
		for z: float in [-0.9, 0.1]:
			Toon.part(t, Toon.box(Vector3(0.06, 1.0, 0.06)), _m(METAL_DARK), Vector3(x, 1.9, z))
	Toon.part(t, Toon.box(Vector3(0.5, 0.4, 0.4)), _m(RUBBER), Vector3(0, 1.6, -0.4))
	Toon.part(t, Toon.cylinder(0.06, 0.06, 0.9, 8), _m(METAL_DARK), Vector3(0.3, 1.85, 1.6))
	for side: float in [-1.0, 1.0]:
		var rear := Toon.part(t, Toon.cylinder(0.75, 0.75, 0.45, 20), _m(RUBBER, 0.9), Vector3(side * 0.85, 0.75, -0.5), Vector3(0, 0, 90))
		rear.name = "RearWheel"
		Toon.part(t, Toon.cylinder(0.35, 0.35, 0.47, 14), red, Vector3(side * 0.85, 0.75, -0.5), Vector3(0, 0, 90))
		Toon.part(t, Toon.cylinder(0.42, 0.42, 0.3, 16), _m(RUBBER, 0.9), Vector3(side * 0.7, 0.42, 1.7), Vector3(0, 0, 90))
		_collider(t, _cyl_shape(0.75, 0.45), Vector3(side * 0.85, 0.75, -0.5), Vector3(0, 0, 90))
		_collider(t, _cyl_shape(0.42, 0.3), Vector3(side * 0.7, 0.42, 1.7), Vector3(0, 0, 90))
		Toon.part(t, Toon.sphere(0.1, 10, 5), Toon.emissive(Color(1.0, 0.95, 0.75), 5.0), Vector3(side * 0.3, 1.25, 2.22))
	var beam := SpotLight3D.new()
	beam.light_color = Color(1.0, 0.92, 0.7)
	beam.light_energy = 5.0
	beam.spot_range = 14.0
	beam.spot_angle = 28.0
	beam.position = Vector3(0, 1.3, 2.3)
	beam.rotation_degrees = Vector3(-8, 180, 0)
	t.add_child(beam)


func _build_crater(pos: Vector3) -> void:
	var c := _prop(self, pos, 0.0, "Crater")
	Toon.part(c, Toon.cylinder(3.3, 3.3, 0.04, 32), Toon.mat(MUD_DARK.darkened(0.2), 1.0, 0.0, 0.0), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, false)
	# Ring of rocks with gaps so you can walk in and grab eggs next to the wreck.
	for i in 20:
		var a := TAU * i / 20.0
		if i % 5 == 2 or i % 5 == 3:
			continue  # wide gaps so everyone can get in
		# Low rocks: the chicken's shots (and its laser) fly over them.
		var s := _rng.randf_range(0.35, 0.55)
		var p := Vector3(cos(a) * 3.5, 0.15, sin(a) * 3.5)
		_solid_cyl(c, s, 0.3, p, MapMaterials.spots(ROCK, ROCK.darkened(0.4), 3.0, 0.45, 1.0, 0.0, 0.1, 0.25), s * 0.7, 8)
	# The chicken stands in the middle of the crater (design doc: visible centre, room around it).
	var smoke := CPUParticles3D.new()
	smoke.amount = 14
	smoke.lifetime = 4.0
	smoke.mesh = Toon.sphere(0.4, 8, 4)
	smoke.material_override = Toon.mat(Color(0.22, 0.2, 0.22), 1.0, 0.0, 0.0)
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.gravity = Vector3(0.2, 0.6, 0)
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 0.0))
	smoke.scale_amount_curve = curve
	smoke.position = Vector3(-2.6, 0.3, -2.4)
	c.add_child(smoke)


func _build_lava_pit(pos: Vector3) -> void:
	var p := _prop(self, pos, 0.0, "LavaPit")
	var r := 3.0
	var top := 0.5
	# Solid basin: the lava surface is a raised floor, so eggs never land inside.
	_collider(p, _cyl_shape(r + 0.25, top), Vector3(0, top * 0.5, 0))
	Toon.part(p, Toon.cylinder(r - 0.3, r - 0.3, 0.05, 32), _lava_material, Vector3(0, top - 0.02, 0), Vector3.ZERO, Vector3.ONE, false)
	for i in 22:
		var a := TAU * i / 22.0
		Toon.part(p, Toon.sphere(0.42, 9, 6), MapMaterials.spots(STONE_DARK, STONE_DARK.darkened(0.45), 3.0, 0.45, 1.0, 0.0, 0.0, 0.25),
				Vector3(cos(a) * (r - 0.15), 0.35, sin(a) * (r - 0.15)), Vector3(0, _rng.randf() * 90, 0), Vector3(1.0, 0.9, 1.0))
	for i in 5:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(0.5, 2.0)
		Toon.part(p, Toon.sphere(0.25, 8, 4), Toon.mat(Color(0.18, 0.1, 0.08), 1.0, 0.0, 0.0), Vector3(cos(a) * d, top + 0.02, sin(a) * d), Vector3.ZERO, Vector3(1.2, 0.3, 1.0))
	# Giant broken egg with X eyes in the middle.
	var egg := Toon.pivot(p, Vector3(0.3, top, -0.3), "BrokenEgg")
	egg.rotation_degrees = Vector3(-8, 25, 6)
	var shell := Toon.mat(Color(0.95, 0.92, 0.86), 0.7, 0.0, 0.3)
	_collider(egg, _cyl_shape(1.1, 2.8), Vector3(0, 1.4, 0))
	Toon.part(egg, Toon.ellipsoid(EGG_RADIUS, EGG_HALF_HEIGHT * 2.0, 32, 16), shell, Vector3(0, EGG_CENTER_Y, 0))
	# Face and crack drawn as strokes lying on the shell surface.
	var ink := Toon.mat(Color(0.12, 0.1, 0.1), 0.6, 0.0, 0.0)
	for side: float in [-1.0, 1.0]:
		var c := Vector2(0.42 * side, 0.6)
		_egg_stroke(egg, c + Vector2(-0.17, 0.17), c + Vector2(0.17, -0.17), 0.09, ink)
		_egg_stroke(egg, c + Vector2(-0.17, -0.17), c + Vector2(0.17, 0.17), 0.09, ink)
	Toon.part(egg, Toon.sphere(0.32, 16, 8), Toon.mat(Color(0.08, 0.05, 0.05), 1.0, 0.0, 0.0), _egg_surface(Vector2(0.05, -0.1)), Vector3.ZERO, Vector3(1.0, 0.75, 0.35))
	var crack := [Vector2(-1.15, 0.05), Vector2(-0.8, 0.25), Vector2(-0.55, -0.05), Vector2(-0.3, 0.2), Vector2(-0.05, -0.08),
			Vector2(0.25, 0.18), Vector2(0.5, -0.06), Vector2(0.8, 0.22), Vector2(1.1, 0.0)]
	var crack_mat := Toon.mat(Color(0.45, 0.36, 0.3), 0.8, 0.0, 0.0)
	for i in crack.size() - 1:
		_egg_stroke(egg, crack[i] + Vector2(0, -0.45), crack[i + 1] + Vector2(0, -0.45), 0.05, crack_mat)
	_hazard(p, Vector3(0, top, 0), r - 0.4)
	for i in 2:
		_lava_lights.append(_point_light(p, Vector3(i * 1.2 - 0.6, 1.2, 0.8), Color(1.0, 0.3, 0.1), 2.6, 8.0))
	var sparks := CPUParticles3D.new()
	sparks.amount = 16
	sparks.lifetime = 1.6
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	sparks.mesh = quad
	sparks.material_override = Toon.glow_dot(Color(1.0, 0.5, 0.15))
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(2.0, 0.05, 2.0)
	sparks.direction = Vector3.UP
	sparks.gravity = Vector3(0, 0.8, 0)
	sparks.initial_velocity_min = 0.3
	sparks.initial_velocity_max = 1.0
	sparks.position.y = top
	p.add_child(sparks)


## Point on the front of the giant egg's shell. `uv` = (x, height) relative to its centre.
func _egg_surface(uv: Vector2, lift: float = 0.015) -> Vector3:
	var ring := EGG_RADIUS * sqrt(maxf(0.0, 1.0 - pow(uv.y / EGG_HALF_HEIGHT, 2.0)))
	var z := sqrt(maxf(0.0, ring * ring - uv.x * uv.x))
	var normal := Vector3(uv.x / (EGG_RADIUS * EGG_RADIUS), uv.y / (EGG_HALF_HEIGHT * EGG_HALF_HEIGHT), z / (EGG_RADIUS * EGG_RADIUS)).normalized()
	return Vector3(uv.x, EGG_CENTER_Y + uv.y, z) + normal * lift


## Thin box lying on the shell between two surface points.
func _egg_stroke(egg: Node3D, a: Vector2, b: Vector2, width: float, material: Material) -> void:
	var pa := _egg_surface(a)
	var pb := _egg_surface(b)
	var mid := _egg_surface((a + b) * 0.5)
	var stroke := Toon.part(egg, Toon.box(Vector3(width, 0.03, pa.distance_to(pb) + width * 0.5)), material, mid, Vector3.ZERO, Vector3.ONE, false)
	var normal := (mid - Vector3(0, EGG_CENTER_Y, 0)).normalized()
	stroke.transform = Transform3D(Basis.looking_at(pb - pa, normal), mid)


func _build_fire_pit(pos: Vector3) -> void:
	var p := _prop(self, pos, 0.0, "FirePit")
	var r := 1.8
	var top := 0.45
	_collider(p, _cyl_shape(r + 0.1, top), Vector3(0, top * 0.5, 0))
	Toon.part(p, Toon.cylinder(r - 0.25, r - 0.25, 0.04, 28), Toon.mat(Color(0.14, 0.08, 0.06), 1.0, 0.0, 0.0), Vector3(0, top - 0.02, 0), Vector3.ZERO, Vector3.ONE, false)
	for i in 16:
		var a := TAU * i / 16.0
		Toon.part(p, Toon.box(Vector3(0.45, 0.5, 0.35)), MapMaterials.bricks(STONE if i % 2 == 0 else STONE_DARK, STONE_DARK.darkened(0.4), Vector2(0.5, 0.25)), Vector3(cos(a) * (r - 0.12), 0.25, sin(a) * (r - 0.12)),
				Vector3(0, -rad_to_deg(a), 0))
	for i in 4:
		Toon.part(p, Toon.cylinder(0.1, 0.1, 1.2, 8), _m(WOOD_DARK), Vector3(0, top + 0.08, 0), Vector3(90, 45 * i, 0))
	_fire(p, Vector3(0, top, 0), 1.6, 5.0)
	_hazard(p, Vector3(0, top, 0), r - 0.3)
	# Broken wooden fence around the back half.
	for i in 9:
		var a := PI + TAU * i / 16.0
		var h := _rng.randf_range(0.8, 1.3)
		_solid_box(p, Vector3(0.6, h, 0.1), Vector3(cos(a) * (r + 0.7), h * 0.5, sin(a) * (r + 0.7)), _m(WOOD_OLD), Vector3(0, -rad_to_deg(a) + 90, _rng.randf_range(-6, 6)))


func _build_cow(pos: Vector3, rot_y: float) -> void:
	var cow := _prop(self, pos, rot_y, "Cow")
	var white := Toon.mat(Color(0.92, 0.9, 0.86), 0.8, 0.0, 0.25)
	var black := Toon.mat(Color(0.12, 0.11, 0.12), 0.8, 0.0, 0.1)
	var hide := MapMaterials.spots(Color(0.93, 0.91, 0.87), Color(0.1, 0.09, 0.1), 2.6, 0.38, 0.8, 0.0, 0.25, 0.015)
	var pink := Toon.mat(Color(0.95, 0.65, 0.65), 0.7, 0.0, 0.1)
	Toon.part(cow, Toon.sphere(0.6, 32, 16), hide, Vector3(0, 1.05, 0), Vector3.ZERO, Vector3(0.95, 0.85, 1.5))
	for x: float in [-0.3, 0.3]:
		for z: float in [-0.6, 0.6]:
			Toon.part(cow, Toon.cylinder(0.09, 0.1, 0.65, 10), white, Vector3(x, 0.33, z))
			Toon.part(cow, Toon.cylinder(0.11, 0.11, 0.1, 10), black, Vector3(x, 0.05, z))
	Toon.part(cow, Toon.sphere(0.16, 10, 5), pink, Vector3(0, 0.62, -0.3), Vector3.ZERO, Vector3(1.0, 0.7, 1.2))
	_cow_head = Toon.pivot(cow, Vector3(0, 1.3, 0.85), "Head")
	Toon.part(_cow_head, Toon.sphere(0.32, 24, 12), hide, Vector3(0, 0, 0.2), Vector3.ZERO, Vector3(0.9, 0.95, 1.15))
	Toon.part(_cow_head, Toon.sphere(0.22, 14, 7), pink, Vector3(0, -0.12, 0.5), Vector3.ZERO, Vector3(1.2, 0.8, 0.8))
	for side: float in [-1.0, 1.0]:
		Toon.part(_cow_head, Toon.sphere(0.07, 10, 5), black, Vector3(0.16 * side, 0.1, 0.45))
		Toon.part(_cow_head, Toon.sphere(0.12, 10, 5), black, Vector3(0.32 * side, 0.1, 0.1), Vector3.ZERO, Vector3(1.2, 0.5, 0.8))
		Toon.part(_cow_head, Toon.cylinder(0.0, 0.05, 0.22, 8), Toon.mat(Color(0.9, 0.85, 0.7), 0.6), Vector3(0.18 * side, 0.3, 0.15), Vector3(0, 0, -35 * side))
	_cow_tail = Toon.pivot(cow, Vector3(0, 1.3, -0.85), "Tail")
	Toon.part(_cow_tail, Toon.cylinder(0.025, 0.025, 0.7, 6), white, Vector3(0, -0.35, -0.05))
	Toon.part(_cow_tail, Toon.sphere(0.07, 8, 4), black, Vector3(0, -0.72, -0.05))
	_collider(cow, _box_shape(Vector3(1.1, 1.4, 2.0)), Vector3(0, 0.7, 0))
	_collider(cow, _box_shape(Vector3(0.7, 0.7, 0.7)), Vector3(0, 1.3, 1.1))


func _build_pipe(pos: Vector3) -> void:
	var p := _breakable(_prop(self, pos, 0.0, "Pipe"), 3)
	var outer := 1.4
	var inner := 1.15
	var length := 4.5
	var concrete := Toon.mat(CONCRETE, 0.95, 0.0, 0.2)
	# Sunk into the ground so the inner floor is flush with the ground (no step to climb).
	var center_y := inner + 0.03
	# Visual tube: outer shell + dark inside + rims.
	Toon.part(p, _open_tube(outer, length), concrete, Vector3(0, center_y, 0), Vector3(0, 0, 90))
	var inside := StandardMaterial3D.new()
	inside.albedo_color = Color(0.2, 0.19, 0.19)
	inside.roughness = 1.0
	inside.cull_mode = BaseMaterial3D.CULL_FRONT
	Toon.part(p, _open_tube(inner, length + 0.02), inside, Vector3(0, center_y, 0), Vector3(0, 0, 90))
	for side: float in [-1.0, 1.0]:
		var rim := TorusMesh.new()
		rim.inner_radius = inner
		rim.outer_radius = outer + 0.05
		Toon.part(p, rim, Toon.mat(CONCRETE.darkened(0.15), 0.95), Vector3(side * length * 0.5, center_y, 0), Vector3(0, 0, 90))
	# Hollow collider: a ring of boxes (octagon) leaves a tunnel you can run through.
	var segments := 10
	var thickness := outer - inner
	var side_len := 2.0 * outer * tan(PI / segments) + 0.05
	for i in segments:
		var a := TAU * i / segments
		var offset := Vector3(0, cos(a), sin(a)) * (inner + thickness * 0.5)
		_collider(p, _box_shape(Vector3(length, thickness, side_len)), Vector3(0, center_y, 0) + offset, Vector3(rad_to_deg(a), 0, 0))
	Toon.part(p, Toon.box(Vector3(length, 0.03, 1.2)), Toon.mat(TOXIC.darkened(0.5), 0.3, 0.0, 0.0), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE, false)
	_toxic_puddle(Vector3(pos.x + length * 0.5 + 1.3, 0, pos.z + 0.2), 1.0)


## Cylinder without end caps, so the pipe is visibly open.
func _open_tube(radius: float, length: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = length
	m.radial_segments = 24
	m.cap_top = false
	m.cap_bottom = false
	return m


func _build_pen_fence() -> void:
	var root := _prop(self, Vector3.ZERO, 0.0, "PenFences")
	var lines := [
		[Vector2(5.0, 9.6), Vector2(10.0, 9.6)], [Vector2(-6.0, -1.0), Vector2(-3.5, -2.5)],
		[Vector2(5.5, -9.0), Vector2(7.5, -9.5)], [Vector2(-14.0, 12.0), Vector2(-11.5, 13.5)],
	]
	for line: Array in lines:
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var angle := rad_to_deg(atan2(-dir.y, dir.x))
		var mid := (a + b) * 0.5
		var posts := int(ceil(length / 1.2))
		var fence := _breakable(Toon.pivot(root, Vector3.ZERO, "Fence"), 1)
		for i in posts + 1:
			var p := a + dir * length * float(i) / posts
			Toon.part(fence, Toon.box(Vector3(0.14, 1.1, 0.14)), _m(WOOD_DARK), Vector3(p.x, 0.55, p.y), Vector3(_rng.randf_range(-6, 6), angle, _rng.randf_range(-6, 6)))
		for h: float in [0.4, 0.8]:
			Toon.part(fence, Toon.box(Vector3(length, 0.12, 0.07)), _m(WOOD_OLD), Vector3(mid.x, h, mid.y), Vector3(0, angle, _rng.randf_range(-3, 3)))
		_collider(fence, _box_shape(Vector3(length, 1.0, 0.25)), Vector3(mid.x, 0.5, mid.y), Vector3(0, angle, 0))


func _build_floodlight(pos: Vector3, aim_yaw: float) -> void:
	var f := _breakable(_prop(self, pos, aim_yaw, "Floodlight"), 2)
	_solid_cyl(f, 0.1, 4.5, Vector3(0, 2.25, 0), _m(METAL_DARK), -1.0, 8)
	Toon.part(f, Toon.box(Vector3(0.9, 0.5, 0.25)), _m(METAL_DARK), Vector3(0, 4.5, 0.2), Vector3(-25, 0, 0))
	for x: float in [-0.22, 0.22]:
		Toon.part(f, Toon.box(Vector3(0.36, 0.36, 0.05)), Toon.emissive(Color(1.0, 0.97, 0.9), 6.0), Vector3(x, 4.5, 0.33), Vector3(-25, 0, 0))
	var spot := SpotLight3D.new()
	spot.light_color = Color(0.95, 0.95, 1.0)
	spot.light_energy = 6.0
	spot.spot_range = 22.0
	spot.spot_angle = 38.0
	spot.spot_attenuation = 0.8
	spot.position = Vector3(0, 4.5, 0.4)
	spot.rotation_degrees = Vector3(-30, 180, 0)
	f.add_child(spot)


func _build_string_lights() -> void:
	var root := _prop(self, Vector3.ZERO, 0.0, "StringLights")
	var runs := [
		[Vector3(2.8, 4.9, -10.8), Vector3(7.0, 4.6, -12.4), 0.6],
		[Vector3(-0.8, 4.9, -10.8), Vector3(-5.6, 6.5, -14.4), 0.7],
		[Vector3(-1.6, 3.4, -9.7), Vector3(3.6, 3.4, -9.7), 0.25],
	]
	var bulb := Toon.emissive(Color(1.0, 0.8, 0.45), 6.0)
	var wire := _m(Color(0.1, 0.1, 0.1))
	for run: Array in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var sag: float = run[2]
		var count := int(a.distance_to(b) / 0.5)
		var prev := a
		for i in range(1, count + 1):
			var t := float(i) / count
			var p := a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
			var seg_len := prev.distance_to(p)
			var wire_seg := Toon.part(root, Toon.box(Vector3(0.02, 0.02, seg_len)), wire, (prev + p) * 0.5, Vector3.ZERO, Vector3.ONE, false)
			wire_seg.look_at_from_position((prev + p) * 0.5, p, Vector3.UP)
			Toon.part(root, Toon.sphere(0.06, 8, 4), bulb, p - Vector3.UP * 0.06, Vector3.ZERO, Vector3.ONE, false)
			prev = p
		_point_light(root, a.lerp(b, 0.5) - Vector3.UP * sag, Color(1.0, 0.75, 0.4), 1.0, 5.0)


func _build_ufo(pos: Vector3) -> void:
	_ufo = Toon.pivot(self, pos, "UFO")
	Toon.part(_ufo, Toon.sphere(2.2, 32, 12), Toon.mat(Color(0.55, 0.57, 0.62), 0.3, 0.7, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.22, 1.0), false)
	Toon.part(_ufo, Toon.sphere(0.9, 24, 12), Toon.emissive(UFO_GREEN, 1.5), Vector3(0, 0.35, 0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0), false)
	Toon.part(_ufo, Toon.cylinder(0.9, 1.3, 0.3, 24), Toon.mat(Color(0.3, 0.32, 0.36), 0.4, 0.6), Vector3(0, -0.4, 0), Vector3.ZERO, Vector3.ONE, false)
	for i in 12:
		var a := TAU * i / 12.0
		_ufo_bulbs.append(Toon.part(_ufo, Toon.sphere(0.1, 8, 4), Toon.emissive(Color(1.0, 0.9, 0.4) if i % 2 == 0 else UFO_GREEN, 6.0),
				Vector3(cos(a) * 2.05, -0.05, sin(a) * 2.05), Vector3.ZERO, Vector3.ONE, false))
	var beam := MeshInstance3D.new()
	beam.mesh = Toon.cylinder(0.9, 2.6, pos.y, 24)
	beam.material_override = _additive(Color(0.35, 1.0, 0.55, 0.08))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = -pos.y * 0.5 - 0.3
	_ufo.add_child(beam)
	var spot := SpotLight3D.new()
	spot.light_color = UFO_GREEN
	spot.light_energy = 8.0
	spot.spot_range = pos.y + 4.0
	spot.spot_angle = 16.0
	spot.rotation_degrees.x = -90.0
	_ufo.add_child(spot)
	# Glowing patch where the beam hits the ground.
	var glow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(6, 6)
	quad.orientation = PlaneMesh.FACE_Y
	glow.mesh = quad
	glow.material_override = Toon.glow_dot(Color(0.35, 1.0, 0.55, 0.5), false)
	glow.position = Vector3(pos.x, 0.05, pos.z)
	add_child(glow)


# --- Small props ---------------------------------------------------------------------------

func _crate_stack(pos: Vector3, rot_y: float, layout: int) -> void:
	var s := _prop(self, pos, rot_y, "Crates")
	var body := WOOD
	var frame := WOOD_DARK
	match layout:
		0:
			_crate(s, Vector3.ZERO, 0.0, 0.9, body, frame)
		1:
			_crate(s, Vector3(-0.5, 0, 0), 5.0, 0.9, body, frame)
			_crate(s, Vector3(0.5, 0, 0.1), -8.0, 0.85, WOOD_OLD, frame)
		2:
			_crate(s, Vector3(-0.5, 0, 0), 0.0, 0.95, body, frame)
			_crate(s, Vector3(0.5, 0, 0), 4.0, 0.95, WOOD_OLD, frame)
			_crate(s, Vector3(0.0, 0.95, 0.05), -10.0, 0.85, body, frame)


func _dead_tree(parent: Node3D, pos: Vector3, s: float, solid: bool) -> void:
	var t := _prop(parent, pos, _rng.randf() * 360.0, "DeadTree")
	var bark := Toon.mat(TREE_DEAD, 1.0, 0.0, 0.1)
	var height := 3.2 * s
	Toon.part(t, Toon.cylinder(0.12 * s, 0.3 * s, height, 8), bark, Vector3(0, height * 0.5, 0))
	for i in 5:
		var y := height * _rng.randf_range(0.45, 0.95)
		var branch := Toon.pivot(t, Vector3(0, y, 0))
		branch.rotation_degrees = Vector3(0, _rng.randf() * 360.0, _rng.randf_range(35, 65))
		var branch_len := _rng.randf_range(0.8, 1.6) * s
		Toon.part(branch, Toon.cylinder(0.02 * s, 0.08 * s, branch_len, 6), bark, Vector3(0, branch_len * 0.5, 0))
		var twig := Toon.pivot(branch, Vector3(0, branch_len * 0.8, 0))
		twig.rotation_degrees.z = -40.0
		Toon.part(twig, Toon.cylinder(0.01 * s, 0.03 * s, branch_len * 0.5, 5), bark, Vector3(0, branch_len * 0.25, 0))
	if solid:
		_collider(t, _cyl_shape(0.32 * s, height), Vector3(0, height * 0.5, 0))
		_breakable(t, 1)


func _toxic_puddle(pos: Vector3, size: float) -> void:
	var goo := Toon.emissive(TOXIC, 1.4)
	for i in 3:
		var offset := Vector3(_rng.randf_range(-0.5, 0.5) * size, 0.012 + i * 0.008, _rng.randf_range(-0.4, 0.4) * size)
		Toon.part(self, Toon.cylinder(size * 0.55, size * 0.55, 0.02, 20), goo, pos + offset, Vector3(0, _rng.randf() * 180, 0),
				Vector3(1.0, 1.0, _rng.randf_range(0.5, 0.9)), false)
	_point_light(self, pos + Vector3.UP * 0.5, TOXIC, 0.8, 3.0)


func _scatter_decor() -> void:
	var root := _prop(self, Vector3.ZERO, 0.0, "Decor")
	var pebbles: Array[Transform3D] = []
	var tufts: Array[Transform3D] = []
	for i in 260:
		var p := Vector3(_rng.randf_range(-16.5, 16.5), 0, _rng.randf_range(-16.5, 16.5))
		if absf(p.x) < 4.0 and p.z > 5.0 and p.z < 9.5:
			continue
		var s := _rng.randf_range(0.06, 0.2)
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, 0)).scaled(Vector3(s, s * 0.6, s * 1.2))
		if i % 3 == 0:
			tufts.append(Transform3D(Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)).scaled(Vector3.ONE * _rng.randf_range(0.6, 1.2)), p + Vector3.UP * 0.12))
		else:
			pebbles.append(Transform3D(basis, p + Vector3.UP * s * 0.2))
	_multi(root, Toon.box(Vector3.ONE), Toon.mat(STONE_DARK, 1.0, 0.0, 0.0), pebbles, false)
	_multi(root, Toon.cylinder(0.0, 0.06, 0.3, 5), Toon.mat(GRASS.lightened(0.1), 1.0, 0.0, 0.0), tufts, false)
	# Stone blocks (solid) scattered around, like the reference.
	var blocks := [[-9.0, -3.0], [-10.0, 4.0], [9.5, -10.5], [15.5, -5.0], [-15.5, -8.0], [12.0, 4.5], [-12.0, 15.5]]
	for i in blocks.size():
		var p := Vector3(blocks[i][0], 0, blocks[i][1])
		var s := _rng.randf_range(0.5, 0.8)
		_solid_box(_breakable(_prop(self, Vector3.ZERO, 0.0, "StoneBlock"), 2), Vector3(s, s * 0.8, s), p + Vector3.UP * s * 0.4, MapMaterials.spots(STONE if i % 2 == 0 else STONE_DARK, STONE_DARK.darkened(0.35), 4.0, 0.45, 1.0, 0.0, 0.1, 0.25), Vector3(0, _rng.randf() * 90.0, 0))

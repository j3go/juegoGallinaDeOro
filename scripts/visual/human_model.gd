@tool
class_name HumanModel
extends Node3D
## Chubby costumed kid (see personajes.png): round face peeking out of a hood, huge eyes,
## stubby mitten arms and big shoes. Four costumes, all built from primitives. Faces +Z.

enum Costume { CHICKEN, CONE, FISH, BUNNY }

const HIP_Y := 0.34
const HEAD_Y := 0.74
const RIG_SCALE := 1.0
const SKIN := Color(0.95, 0.72, 0.55)
const DIRT := Color(0.42, 0.31, 0.23)
const HOOD := Vector3(0.44, 0.42, 0.42)
const HOOD_CENTER := Vector3(0, 0.03, -0.03)

const FABRIC_SHADER := """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 dirt_color : source_color = vec4(0.42, 0.31, 0.23, 1.0);
uniform float dirt_amount = 0.0;
uniform float dirt_scale = 6.0;
uniform float seed = 0.0;
uniform float roughness_value = 0.9;
uniform float rim_value = 0.3;
varying vec3 local_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 p = local_pos * dirt_scale + seed;
	float n = noise(p) * 0.6 + noise(p * 2.3) * 0.28 + noise(p * 5.7) * 0.12;
	float stain = smoothstep(1.0 - dirt_amount, 1.03 - dirt_amount, n);
	float grain = noise(local_pos * 90.0);
	vec3 col = albedo.rgb * (0.95 + 0.07 * grain);
	ALBEDO = mix(col, dirt_color.rgb * (0.9 + 0.2 * grain), stain * 0.85);
	ROUGHNESS = roughness_value;
	RIM = rim_value;
	RIM_TINT = 0.6;
}
"""

static var _shader: Shader
static var _fabrics := {}
static var _tori := {}

@export var costume: Costume = Costume.CHICKEN:
	set(value):
		costume = value
		if is_inside_tree():
			_build()

var rig: Node3D
var body_root: Node3D
var head: Node3D
var hips: Array[Node3D] = []
var arms: Array[Node3D] = []
var sleeves: Array[Node3D] = []
var hands: Array[Node3D] = []
var eyes: Array[Node3D] = []
var pupils: Array[Node3D] = []
## Accessories that lag behind the body: {node, base: Vector3, amount: float, sway: float}.
var wobblers: Array[Dictionary] = []
var fish_tail: Node3D

var _torso := Vector3(0.36, 0.36, 0.32)
var _torso_y := 0.25
var _phase := 0.0
var _time := 0.0
var _air := 0.0
var _hug := 0.0
var _celebrating := false
var _sad := false
var _blink_timer := 3.0
var _look_timer := 1.5
var _look := Vector2.ZERO
var _look_target := Vector2.ZERO
var _prev_body_y := HIP_Y
var _spring := Vector2.ZERO
var _spring_vel := Vector2.ZERO
var _prev_yaw := 0.0
var _fx_tween: Tween
# Tug-of-war while in a grab (see set_grab): smoothed blends 0..1.
var _grab_targets: Array[Vector3] = []
var _grab_strain_target := 0.0
var _grab_dragged_target := 0.0
var _grab_lift_target := 0.0
var _grab := 0.0
var _strain := 0.0
var _dragged := 0.0
var _lift := 0.0
var _dazed := false
var _cheer_until := 0.0
var _squint := 0.0
var _stretch: Array[float] = [1.0, 1.0]
var _recoil := 0.0
var _surprise := 0.0


func _ready() -> void:
	_build()


func set_costume(value: Costume) -> void:
	costume = value


# --- Materials & helpers -------------------------------------------------------------------

static func fabric(color: Color, dirt: float = 0.0, scale: float = 6.0, roughness: float = 0.9, rim: float = 0.3) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%.2f|%.2f" % [color.to_html(), dirt, scale, roughness, rim]
	if _fabrics.has(key):
		return _fabrics[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = FABRIC_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("dirt_color", DIRT)
	m.set_shader_parameter("dirt_amount", dirt)
	m.set_shader_parameter("dirt_scale", scale)
	m.set_shader_parameter("seed", float(_fabrics.size()) * 3.7)
	m.set_shader_parameter("roughness_value", roughness)
	m.set_shader_parameter("rim_value", rim)
	_fabrics[key] = m
	return m


static func torus(inner: float, outer: float) -> TorusMesh:
	var key := "%.3f|%.3f" % [inner, outer]
	if not _tori.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 32
		m.ring_segments = 12
		_tori[key] = m
	return _tori[key]


## Ellipsoid with the given radii.
func _blob(parent: Node3D, radii: Vector3, material: Material, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var r := maxf(radii.x, maxf(radii.y, radii.z))
	return Toon.part(parent, Toon.sphere(r, 32, 16), material, pos, rot_deg, radii / r)


## Places a part on the surface of an ellipsoid, with its local +Z along the surface normal.
func _on_surface(parent: Node3D, center: Vector3, radii: Vector3, dir: Vector3, mesh: Mesh,
		material: Material, scl: Vector3 = Vector3.ONE, lift: float = 0.0, roll_deg: float = 0.0) -> MeshInstance3D:
	var d := dir.normalized()
	var p := d / sqrt(pow(d.x / radii.x, 2) + pow(d.y / radii.y, 2) + pow(d.z / radii.z, 2))
	var n := Vector3(p.x / (radii.x * radii.x), p.y / (radii.y * radii.y), p.z / (radii.z * radii.z)).normalized()
	var up := Vector3.UP if absf(n.y) < 0.98 else Vector3.FORWARD
	var mi := Toon.part(parent, mesh, material, center + p + n * lift)
	mi.basis = Basis.looking_at(n, up, true) * Basis(Vector3.BACK, deg_to_rad(roll_deg))
	mi.scale = scl
	return mi


func _wobbler(node: Node3D, amount: float, sway: float = 0.0) -> void:
	wobblers.append({"node": node, "base": node.rotation, "amount": amount, "sway": sway})


# --- Build ---------------------------------------------------------------------------------

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	hips.clear()
	arms.clear()
	sleeves.clear()
	hands.clear()
	eyes.clear()
	pupils.clear()
	wobblers.clear()
	fish_tail = null

	rig = Toon.pivot(self, Vector3.ZERO, "Rig")
	rig.scale = Vector3.ONE * RIG_SCALE
	body_root = Toon.pivot(rig, Vector3(0, HIP_Y, 0), "Body")

	match costume:
		Costume.CHICKEN:
			_build_chicken()
		Costume.CONE:
			_build_cone()
		Costume.FISH:
			_build_fish()
		Costume.BUNNY:
			_build_bunny()


## Shared body: legs, torso, mitten arms and the hooded head. Returns nothing; sets `head`.
func _build_base(torso: Vector3, torso_mat: Material, leg_mat: Material, shoe_mat: Material,
		sleeve_mat: Material, hand_mat: Material, hood_mat: Material) -> void:
	_torso = torso
	_torso_y = 0.24 + (torso.y - 0.36) * 0.4
	for side: float in [-1.0, 1.0]:
		var hip := Toon.pivot(rig, Vector3(0.13 * side, HIP_Y, 0))
		Toon.part(hip, Toon.capsule(0.1, 0.3), leg_mat, Vector3(0, -0.1, 0))
		_blob(hip, Vector3(0.14, 0.095, 0.17), shoe_mat, Vector3(0, -0.25, 0.045))
		hips.append(hip)

	_blob(body_root, torso, torso_mat, Vector3(0, _torso_y, 0))

	for side: float in [-1.0, 1.0]:
		var arm := Toon.pivot(body_root, Vector3((torso.x - 0.04) * side, _torso_y + torso.y * 0.48, 0.02))
		sleeves.append(Toon.part(arm, Toon.capsule(0.088, 0.3), sleeve_mat, Vector3(0, -0.11, 0)))
		hands.append(_blob(arm, Vector3(0.115, 0.12, 0.115), hand_mat, Vector3(0, -0.27, 0.01)))
		arms.append(arm)

	head = Toon.pivot(body_root, Vector3(0, HEAD_Y, 0.02), "Head")
	_blob(head, HOOD, hood_mat, HOOD_CENTER)
	_blob(head, Vector3(0.33, 0.3, 0.26), Toon.mat(SKIN, 0.75, 0.0, 0.25), Vector3(0, -0.03, 0.14))
	Toon.part(head, torus(0.26, 0.37), hood_mat, Vector3(0, -0.03, 0.3), Vector3(90, 0, 0), Vector3(1.0, 0.9, 0.97))
	_build_eyes()


func _build_eyes() -> void:
	var white := Toon.mat(Color(0.97, 0.97, 0.95), 0.3, 0.0, 0.0)
	var black := Toon.mat(Color(0.05, 0.05, 0.07), 0.2, 0.0, 0.0)
	var shine := Toon.unshaded(Color(1, 1, 1))
	for side: float in [-1.0, 1.0]:
		var eye := Toon.pivot(head, Vector3(0.135 * side, 0.02, 0.345))
		eye.rotation_degrees = Vector3(-4, 20 * side, 0)
		_blob(eye, Vector3(0.112, 0.13, 0.05), white)
		var pupil := Toon.pivot(eye, Vector3(-0.014 * side, -0.008, 0.03))
		_blob(pupil, Vector3(0.078, 0.09, 0.035), black)
		_blob(pupil, Vector3(0.02, 0.02, 0.01), shine, Vector3(0.024, 0.036, 0.03))
		eyes.append(eye)
		pupils.append(pupil)


func _torso_center() -> Vector3:
	return Vector3(0, _torso_y, 0)


## Two shoulder straps in front and a backpack behind.
func _backpack(color: Color, strap_x: float = 0.17) -> void:
	var dark := fabric(color, 0.1, 5.0, 0.8)
	_blob(body_root, Vector3(0.25, 0.25, 0.13), dark, Vector3(0, _torso_y + 0.06, -_torso.z - 0.04), Vector3(-6, 0, 0))
	_blob(body_root, Vector3(0.18, 0.1, 0.07), dark, Vector3(0, _torso_y - 0.06, -_torso.z - 0.13))
	for side: float in [-1.0, 1.0]:
		_on_surface(body_root, _torso_center(), _torso, Vector3(strap_x * side / _torso.x, 0.38, 0.75),
				Toon.box(Vector3(0.065, 0.32, 0.025)), dark, Vector3.ONE, 0.0, -10.0 * side)
		_on_surface(body_root, _torso_center(), _torso, Vector3(side * 0.75, 0.55, -0.1),
				Toon.box(Vector3(0.065, 0.26, 0.025)), dark, Vector3.ONE, 0.0, 0.0)


func _build_chicken() -> void:
	var suit := fabric(Color(0.93, 0.9, 0.84), 0.34, 5.5)
	var red := Toon.mat(Color(0.86, 0.17, 0.13), 0.7)
	var yellow := Toon.mat(Color(0.98, 0.76, 0.22), 0.55)
	var shoe := fabric(Color(0.42, 0.29, 0.21), 0.1, 8.0, 0.8)
	_build_base(Vector3(0.42, 0.4, 0.37), suit, suit, shoe, Toon.mat(SKIN, 0.75), Toon.mat(SKIN, 0.75), suit)

	# Comb, beak and the costume's own eyes on top of the hood.
	var comb := Toon.pivot(head, Vector3(0, 0.41, 0.02))
	_blob(comb, Vector3(0.075, 0.1, 0.07), red, Vector3(0, 0.05, 0.12), Vector3(30, 0, 0))
	_blob(comb, Vector3(0.085, 0.12, 0.075), red, Vector3(0, 0.09, 0.0))
	_blob(comb, Vector3(0.075, 0.1, 0.07), red, Vector3(0, 0.05, -0.12), Vector3(-30, 0, 0))
	_wobbler(comb, 0.6, 0.5)
	var beak := Toon.part(head, Toon.cylinder(0.0, 0.12, 0.26, 20), yellow, Vector3(0, 0.29, 0.4), Vector3(72, 0, 0), Vector3(1.3, 1.0, 0.6))
	beak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var white := Toon.mat(Color(0.97, 0.97, 0.95), 0.3, 0.0, 0.0)
	var black := Toon.mat(Color(0.05, 0.05, 0.07), 0.2, 0.0, 0.0)
	for side: float in [-1.0, 1.0]:
		var e := _on_surface(head, HOOD_CENTER, HOOD, Vector3(0.62 * side, 0.55, 0.6),
				Toon.sphere(0.1), white, Vector3(1.0, 1.15, 0.45))
		Toon.part(e, Toon.sphere(0.06), black, Vector3(0.012 * side, 0, 0.075), Vector3.ZERO, Vector3(1.0, 1.1, 0.5))
	# Red wattle peeking out under the beak on one side.
	_blob(head, Vector3(0.05, 0.08, 0.05), red, Vector3(-0.34, -0.1, 0.2))

	# Bandana: knot ring around the neck plus a triangle in front.
	var bandana := fabric(Color(0.86, 0.2, 0.15), 0.12, 6.0, 0.8)
	Toon.part(body_root, torus(0.27, 0.34), bandana, Vector3(0, 0.56, 0.03), Vector3(-12, 0, 0), Vector3(1.05, 0.9, 1.0))
	_on_surface(body_root, _torso_center(), _torso, Vector3(0, 0.55, 1.0),
			Toon.prism(Vector3(0.46, 0.3, 0.05)), bandana, Vector3.ONE, 0.01, 180.0)
	_blob(body_root, Vector3(0.09, 0.07, 0.06), bandana, Vector3(0.24, 0.52, 0.18))

	_backpack(Color(0.12, 0.12, 0.13), 0.24)

	# Tail feathers.
	var tail := Toon.pivot(body_root, Vector3(0, _torso_y - 0.2, -_torso.z + 0.08))
	for i in 3:
		var a := (i - 1) * 28.0
		_blob(tail, Vector3(0.08, 0.16, 0.06), suit, Vector3((i - 1) * 0.07, 0.0, -0.1), Vector3(-65, 0, a))
	_wobbler(tail, -0.8, 0.6)


func _build_cone() -> void:
	var jacket := fabric(Color(0.33, 0.43, 0.24), 0.18, 6.0)
	var pants := fabric(Color(0.1, 0.1, 0.11), 0.05, 7.0)
	var balaclava := fabric(Color(0.1, 0.1, 0.12), 0.0, 6.0, 0.95, 0.35)
	var shoe := fabric(Color(0.85, 0.77, 0.64), 0.2, 8.0, 0.8)
	_build_base(Vector3(0.36, 0.35, 0.32), jacket, pants, shoe, jacket, Toon.mat(SKIN, 0.75), balaclava)
	# Pants show under the jacket.
	_blob(body_root, Vector3(0.31, 0.16, 0.28), pants, Vector3(0, 0.02, 0))
	# Jacket hood bunched behind the neck and a collar.
	Toon.part(body_root, torus(0.22, 0.33), jacket, Vector3(0, 0.53, 0.0), Vector3(-10, 0, 0), Vector3(1.0, 1.3, 1.0))
	_blob(body_root, Vector3(0.3, 0.2, 0.15), jacket, Vector3(0, 0.62, -0.3), Vector3(20, 0, 0))

	var grey := Toon.mat(Color(0.62, 0.62, 0.6), 0.45, 0.4)
	_on_surface(body_root, _torso_center(), _torso, Vector3(0, 0.15, 1.0), Toon.box(Vector3(0.025, 0.36, 0.02)), grey, Vector3.ONE, 0.0, 0.0)
	_on_surface(body_root, _torso_center(), _torso, Vector3(0, 0.62, 1.0), Toon.box(Vector3(0.04, 0.08, 0.02)), grey, Vector3.ONE, 0.01, 0.0)
	var tape := fabric(Color(0.68, 0.67, 0.62), 0.15, 9.0, 0.6)
	_on_surface(body_root, _torso_center(), _torso, Vector3(-0.4, -0.1, 1.0), Toon.box(Vector3(0.17, 0.1, 0.02)), jacket, Vector3.ONE, 0.0, 0.0)
	_on_surface(body_root, _torso_center(), _torso, Vector3(-0.42, 0.0, 1.0), Toon.box(Vector3(0.15, 0.05, 0.02)), tape, Vector3.ONE, 0.012, 6.0)
	_on_surface(body_root, _torso_center(), _torso, Vector3(0.9, 0.5, 0.2), Toon.box(Vector3(0.12, 0.05, 0.02)), tape, Vector3.ONE, 0.0, -20.0)

	# Traffic cone hat, slightly tilted.
	var orange := fabric(Color(0.95, 0.42, 0.12), 0.2, 4.5, 0.55, 0.2)
	var stripe := fabric(Color(0.95, 0.92, 0.86), 0.25, 4.5, 0.55, 0.2)
	var hat := Toon.pivot(head, Vector3(0.03, 0.2, -0.03))
	hat.rotation_degrees = Vector3(-8, 0, -10)
	Toon.part(hat, Toon.box(Vector3(0.62, 0.09, 0.62)), orange, Vector3(0, 0.045, 0), Vector3(0, 35, 0))
	const H := 0.8
	const R := 0.33
	const TIP := 0.035
	Toon.part(hat, Toon.cylinder(TIP, R, H, 24), orange, Vector3(0, 0.09 + H * 0.5, 0))
	for band: Vector2 in [Vector2(0.2, 0.38), Vector2(0.56, 0.7)]:
		var h := (band.y - band.x) * H
		Toon.part(hat, Toon.cylinder(lerpf(R, TIP, band.y) + 0.006, lerpf(R, TIP, band.x) + 0.006, h, 24), stripe,
				Vector3(0, 0.09 + (band.x + band.y) * 0.5 * H, 0))
	Toon.part(hat, Toon.sphere(TIP), orange, Vector3(0, 0.09 + H, 0))
	_wobbler(hat, 0.35, 0.4)


func _build_fish() -> void:
	var hoodie := fabric(Color(0.24, 0.26, 0.56), 0.12, 6.0)
	var pants := fabric(Color(0.22, 0.24, 0.52), 0.1, 7.0)
	var shoe := fabric(Color(0.92, 0.9, 0.86), 0.2, 8.0, 0.8)
	_build_base(Vector3(0.35, 0.35, 0.31), hoodie, pants, shoe, hoodie, Toon.mat(SKIN, 0.75), hoodie)
	_blob(body_root, Vector3(0.3, 0.15, 0.27), pants, Vector3(0, 0.03, 0))

	# Drawstrings hanging from the hood.
	var cord := Toon.mat(Color(0.88, 0.86, 0.8), 0.7)
	for side: float in [-1.0, 1.0]:
		Toon.part(head, Toon.capsule(0.014, 0.16), cord, Vector3(0.07 * side, -0.4, 0.3), Vector3(-15, 0, 0))
		Toon.part(head, Toon.sphere(0.024), cord, Vector3(0.07 * side, -0.48, 0.32))

	# Patches on the hoodie and legs.
	var patch := fabric(Color(0.62, 0.64, 0.7), 0.2, 9.0, 0.7)
	var c := _torso_center()
	_on_surface(body_root, c, _torso, Vector3(-0.8, 0.1, 0.7), Toon.box(Vector3(0.12, 0.08, 0.02)), patch, Vector3.ONE, 0.0, 15.0)
	_on_surface(body_root, c, _torso, Vector3(0.6, -0.5, 0.7), Toon.box(Vector3(0.1, 0.07, 0.02)), patch, Vector3.ONE, 0.0, -25.0)
	_on_surface(body_root, c, _torso, Vector3(-0.5, 0.4, -0.8), Toon.box(Vector3(0.13, 0.08, 0.02)), patch, Vector3.ONE, 0.0, 30.0)
	Toon.part(hips[1], Toon.box(Vector3(0.09, 0.06, 0.02)), patch, Vector3(0.0, -0.12, 0.1), Vector3(0, 0, 20))

	# Crossbody bag.
	var strap := fabric(Color(0.3, 0.3, 0.26), 0.1, 6.0, 0.8)
	Toon.part(body_root, torus(_torso.x - 0.005, _torso.x + 0.03), strap, c + Vector3(0, 0.02, 0), Vector3(0, 0, 90 - 38), Vector3(1.0, 1.0, 0.92))
	var bag := _on_surface(body_root, c, _torso, Vector3(-0.55, -0.45, 0.75), Toon.sphere(0.13), fabric(Color(0.33, 0.33, 0.28), 0.15, 7.0, 0.8),
			Vector3(1.2, 0.85, 0.5), 0.02)
	bag.rotation_degrees.z += 8.0

	# Fish lying on the hood.
	var fish := Toon.pivot(head, Vector3(0.0, 0.4, -0.03))
	fish.scale = Vector3.ONE * 1.18
	var scales := fabric(Color(0.56, 0.66, 0.74), 0.18, 5.0, 0.6)
	var belly := fabric(Color(0.86, 0.84, 0.75), 0.1, 5.0, 0.7)
	_blob(fish, Vector3(0.38, 0.15, 0.17), scales, Vector3(0.02, 0.0, 0.0), Vector3(0, 0, 4))
	_blob(fish, Vector3(0.34, 0.09, 0.155), belly, Vector3(0.04, -0.06, 0.0), Vector3(0, 0, 4))
	_blob(fish, Vector3(0.13, 0.12, 0.15), scales, Vector3(0.3, 0.0, 0.0), Vector3(0, 0, -10))
	Toon.part(fish, Toon.prism(Vector3(0.22, 0.12, 0.03)), scales, Vector3(-0.02, 0.17, 0.0), Vector3(0, 0, -8))
	fish_tail = Toon.pivot(fish, Vector3(-0.34, 0.01, 0.0))
	for s: float in [-1.0, 1.0]:
		_blob(fish_tail, Vector3(0.1, 0.13, 0.025), scales, Vector3(-0.09, 0.08 * s, 0.0), Vector3(0, 0, -50.0 * s))
	var dark := Toon.mat(Color(0.12, 0.12, 0.15), 0.5)
	for z: float in [-1.0, 1.0]:
		for a: float in [45.0, -45.0]:
			Toon.part(fish, Toon.box(Vector3(0.07, 0.016, 0.012)), dark, Vector3(0.32, 0.03, 0.135 * z), Vector3(0, 0, a))
	Toon.part(fish, Toon.box(Vector3(0.012, 0.05, 0.06)), dark, Vector3(0.43, -0.03, 0.0), Vector3(0, 0, 20))
	_wobbler(fish, 0.3, 0.6)


func _build_bunny() -> void:
	var pink := fabric(Color(0.93, 0.53, 0.6), 0.24, 5.5)
	var inner := fabric(Color(0.97, 0.76, 0.78), 0.05, 5.5)
	_build_base(Vector3(0.36, 0.37, 0.33), pink, pink, pink, pink, pink, pink)

	for side: float in [-1.0, 1.0]:
		var ear := Toon.pivot(head, Vector3(0.16 * side, 0.33, -0.06))
		ear.rotation_degrees = Vector3(-8, 0, -14 * side)
		_blob(ear, Vector3(0.1, 0.34, 0.075), pink, Vector3(0, 0.3, 0))
		_blob(ear, Vector3(0.06, 0.27, 0.03), inner, Vector3(0, 0.31, 0.055))
		_wobbler(ear, 1.0, 0.8)

	# Bandage on the cheek.
	var tan := Toon.mat(Color(0.88, 0.68, 0.48), 0.8)
	Toon.part(head, Toon.box(Vector3(0.14, 0.055, 0.02)), tan, Vector3(-0.16, -0.1, 0.37), Vector3(0, -24, 30))
	Toon.part(head, Toon.box(Vector3(0.045, 0.058, 0.024)), Toon.mat(Color(0.78, 0.55, 0.38), 0.8), Vector3(-0.16, -0.1, 0.37), Vector3(0, -24, 30))

	# Drawstring bow at the neck.
	var cord := Toon.mat(Color(0.94, 0.9, 0.82), 0.7)
	for side: float in [-1.0, 1.0]:
		Toon.part(body_root, torus(0.02, 0.045), cord, Vector3(0.05 * side, 0.36, 0.37), Vector3(90, 0, 90), Vector3(1.0, 1.0, 1.4))
		Toon.part(body_root, Toon.capsule(0.012, 0.14), cord, Vector3(0.03 * side, 0.28, 0.36), Vector3(-15, 0, 12 * side))
	Toon.part(body_root, Toon.sphere(0.025), cord, Vector3(0, 0.36, 0.38))

	_backpack(Color(0.18, 0.17, 0.18), 0.22)


# --- Animation -----------------------------------------------------------------------------

## Called every physics frame. `speed` is horizontal speed in m/s.
func animate(delta: float, speed: float, on_floor: bool) -> void:
	if delta <= 0.0 or rig == null:
		return
	_time += delta
	var ratio := clampf(speed / 5.0, 0.0, 1.7)
	var running := clampf((speed - 5.5) / 3.0, 0.0, 1.0)
	if speed > 0.15 and on_floor:
		_phase += delta * (6.0 + speed * 1.4)
	var k := 1.0 - exp(-14.0 * delta)
	_air = move_toward(_air, 0.0 if on_floor else 1.0, delta * 6.0)
	_hug = maxf(_hug - delta, 0.0)
	_recoil = maxf(_recoil - delta * 2.5, 0.0)
	_surprise = maxf(_surprise - delta, 0.0)
	_grab = move_toward(_grab, 0.0 if _grab_targets.is_empty() else 1.0, delta * 7.0)
	_strain = lerpf(_strain, _grab_strain_target, k * 0.5)
	_dragged = lerpf(_dragged, _grab_dragged_target, k * 0.4)
	_lift = lerpf(_lift, 0.0 if _grab_targets.is_empty() else _grab_lift_target, k * 0.4)
	var tug := _grab * _strain * (1.0 - _dragged)
	var cheering := _celebrating or _time < _cheer_until

	# Legs: swing from the hip and lift the foot on the forward stroke.
	var stride := minf(ratio, 1.25)
	var swing := sin(_phase) * stride * (0.75 + running * 0.25)
	for i in hips.size():
		var side := -1.0 if i == 0 else 1.0
		var s := swing * (1.0 if i == 0 else -1.0)
		var air_pose := -0.8 if i == 0 else 0.45
		var leg := lerpf(s, air_pose, _air)
		if _grab > 0.0:
			# Tug: one foot planted ahead, the other pushing back; kicking when dragged.
			var brace := (-0.55 if i == 0 else 0.5) * (0.5 + _strain * 0.5) + s * 0.3
			var kick := 0.45 + sin(_time * 17.0 + i * PI) * 0.3
			leg = lerpf(leg, lerpf(brace, kick, maxf(_dragged, _lift)), _grab)
		if _dazed:
			leg = 0.25 + sin(_time * 5.0 + i * 2.0) * 0.08
		hips[i].rotation.x = lerpf(hips[i].rotation.x, leg, k)
		var lift := maxf(0.0, -sin(_phase + (0.0 if i == 0 else PI))) * 0.07 * stride
		hips[i].position.y = HIP_Y + lift * (1.0 - _air)
		hips[i].rotation.z = lerpf(hips[i].rotation.z, side * 0.06 * _air, k)

	# Arms: opposite to the legs; flail in the air, hug the egg on collect, cheer when winning.
	for i in arms.size():
		var side := -1.0 if i == 0 else 1.0
		var target_x := swing * 1.1 * side * (1.0 + running * 0.4)
		var target_z := side * (0.32 + ratio * 0.08)
		if _sad:
			target_x = 0.15
			target_z = side * 0.08
		if _air > 0.0:
			target_x = lerpf(target_x, -0.6 + sin(_time * 22.0 + i * PI) * 0.35, _air)
			target_z = lerpf(target_z, side * 1.3, _air)
		if _hug > 0.0:
			target_x = -1.25
			target_z = side * 0.35
		var stretch := 1.0
		if _grab > 0.0 and not _grab_targets.is_empty():
			var aim := _aim_arm(i, _grab_targets[mini(i, _grab_targets.size() - 1)], _grab_targets.size() == 1)
			target_x = lerpf(target_x, aim.x, _grab)
			target_z = lerpf(target_z, aim.y, _grab)
			stretch = lerpf(1.0, aim.z, _grab)
		if _recoil > 0.0:
			# Let go: arms fly up and out.
			target_x = lerpf(target_x, -2.2, _recoil)
			target_z = lerpf(target_z, side * 1.1, _recoil)
		if cheering:
			target_x = -0.3
			target_z = side * (2.6 + sin(_time * 12.0 + i * PI) * 0.35)
		if _dazed:
			# Flat on the back with the arms splayed out.
			target_x = -0.3
			target_z = side * (1.35 + sin(_time * 4.0 + i) * 0.1)
		arms[i].rotation.x = lerpf(arms[i].rotation.x, target_x, k)
		arms[i].rotation.z = lerpf(arms[i].rotation.z, target_z, k)
		_set_stretch(i, lerpf(_stretch[i], stretch, k))

	# Body: bouncy waddle, lean into the run, breathe when idle.
	var bounce := absf(sin(_phase)) * (0.06 + running * 0.04) * stride
	var breathe := sin(_time * 2.4) * 0.012 * (1.0 - minf(ratio, 1.0))
	body_root.position.y = HIP_Y + bounce + breathe
	body_root.scale = Vector3(1.0 - breathe * 0.6, 1.0 + breathe, 1.0 - breathe * 0.6)
	var lean := 0.1 * ratio + running * 0.22 + (0.28 if _sad else 0.0) - _air * 0.12
	# Clinch: press forward head to head, or lean back when pulling away; tremble with the
	# effort and sway side to side wrestling. Recoil when let go.
	lean = lerpf(lean, 0.22 - _strain * 0.55, _grab) - _recoil * 0.5
	lean = lerpf(lean, -0.2, _lift)
	body_root.rotation.x = lerpf(body_root.rotation.x, lean, k)
	body_root.position.x = sin(_time * 47.0) * 0.02 * tug
	var wrestle := sin(_time * 7.0) * 0.1 * _grab * (1.0 - _lift)
	body_root.rotation.z = sin(_phase) * 0.09 * minf(ratio, 1.0) + sin(_time * 31.0) * 0.05 * tug + wrestle
	# Being dragged: fall forward onto the belly, still holding on.
	rig.rotation.x = lerpf(rig.rotation.x, _grab * _dragged * 1.2, k * 0.6)
	# Being lifted by the winner: feet off the ground, swinging around.
	if _lift > 0.001:
		rig.position.y = 0.45 * _lift
		rig.rotation.z = sin(_time * 5.0) * 0.25 * _lift
	elif rig.rotation.z != 0.0:
		rig.rotation.z = 0.0
	body_root.rotation.y = sin(_phase) * 0.1 * minf(ratio, 1.0)
	head.rotation.z = -body_root.rotation.z * 0.7 + sin(_time * 1.3) * 0.03 * (1.0 - minf(ratio, 1.0))
	head.rotation.y = -body_root.rotation.y * 0.6
	var head_x := (0.4 if _sad else 0.0) - running * 0.15 + (-0.25 if cheering else 0.0) + tug * 0.15 - _dragged * _grab * 0.5
	head.rotation.x = lerpf(head.rotation.x, head_x, k)
	if _dazed:
		head.rotation.y = sin(_time * 3.0) * 0.35
	head.position.y = HEAD_Y + sin(_phase * 2.0 - 0.9) * 0.012 * stride

	_update_wobble(delta)
	# Eyes squeezed shut while wrestling (not when lifted: then they go wide).
	_update_eyes(delta, maxf(tug, _grab * 0.75 * (1.0 - _lift)))
	if fish_tail:
		fish_tail.rotation.y = sin(_time * (3.0 + ratio * 6.0)) * (0.2 + ratio * 0.25)


## Floppy bits (ears, comb, hat, fish) follow a damped spring driven by bounce and turning.
func _update_wobble(delta: float) -> void:
	var vy := (body_root.position.y - _prev_body_y) / delta
	_prev_body_y = body_root.position.y
	var yaw := global_rotation.y if is_inside_tree() else 0.0
	var turn := wrapf(yaw - _prev_yaw, -PI, PI) / delta
	_prev_yaw = yaw
	var target := Vector2(clampf(vy * 0.12, -0.5, 0.5) + _air * 0.35, clampf(turn * 0.05, -0.4, 0.4))
	_spring_vel += ((target - _spring) * 110.0 - _spring_vel * 7.0) * delta
	_spring += _spring_vel * delta
	for w in wobblers:
		var node: Node3D = w["node"]
		var base: Vector3 = w["base"]
		node.rotation = base + Vector3(_spring.x * w["amount"], 0.0, _spring.y * w["sway"])


## Aims arm `i` at a world point. Returns (rotation.x, rotation.z, stretch) for its pivot.
func _aim_arm(i: int, target: Vector3, share: bool) -> Vector3:
	var local := body_root.global_transform.affine_inverse() * target
	if share:
		# Both hands on the same rival: side by side, not on top of each other.
		local.x += (-1.0 if i == 0 else 1.0) * 0.09
	var d := local - arms[i].position
	var dist := d.length()
	if dist < 0.01:
		return Vector3(-1.4, 0.0, 1.0)
	var dir := d / dist
	# The arm hangs along -Y: with Euler YXZ and no yaw, -Y maps to (sin z, -cos z cos x, -cos z sin x).
	return Vector3(atan2(-dir.z, -dir.y), asin(clampf(dir.x, -1.0, 1.0)), clampf(dist / 0.33, 1.0, 2.7))


## Rubber arms: the sleeve stretches from the shoulder and the mitten slides to its end.
func _set_stretch(i: int, s: float) -> void:
	_stretch[i] = s
	sleeves[i].scale.y = s
	sleeves[i].position.y = 0.04 - 0.15 * s
	hands[i].position.y = -0.27 - (s - 1.0) * 0.3


func _update_eyes(delta: float, tug: float) -> void:
	# Squeezed "> <" eyes while pulling hard.
	var was_squinting := _squint > 0.0
	_squint = move_toward(_squint, 1.0 if _dazed else smoothstep(0.3, 0.8, tug), delta * 6.0)
	if _squint > 0.0 or was_squinting:
		for i in eyes.size():
			eyes[i].scale.y = lerpf(1.0, 0.22, _squint)
			# Dazed: the squeezed eyes wobble around.
			var dizzy := sin(_time * 8.0 + i * PI) * 0.5 if _dazed else 0.0
			eyes[i].rotation.z = (-1.0 if i == 0 else 1.0) * 0.5 * _squint + dizzy
	_blink_timer -= delta
	if _blink_timer <= 0.0 and _squint == 0.0:
		_blink_timer = randf_range(2.2, 5.0)
		for eye in eyes:
			var tw := eye.create_tween()
			tw.tween_property(eye, "scale:y", 0.1, 0.06)
			tw.tween_property(eye, "scale:y", 1.0, 0.08)
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = randf_range(0.8, 2.6)
		_look_target = Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.5)) if randf() < 0.6 else Vector2.ZERO
	_look = _look.lerp(_look_target, 1.0 - exp(-12.0 * delta))
	for i in pupils.size():
		var side := -1.0 if i == 0 else 1.0
		pupils[i].position = Vector3(-0.014 * side + _look.x * 0.02, -0.008 + _look.y * 0.02, 0.03)
		var wide := 1.12 if _celebrating or _time < _cheer_until else 1.0
		if _surprise > 0.0 or _dragged * _grab > 0.5 or _lift > 0.5:
			wide = 1.25
		pupils[i].scale = Vector3.ONE * wide


func play_jump() -> void:
	_squash(Vector3(0.85, 1.2, 0.85), 0.25)


func play_land() -> void:
	_squash(Vector3(1.22, 0.78, 1.22), 0.3)
	_spring_vel.x -= 6.0


func play_collect() -> void:
	_hug = 0.45
	_kill_fx()
	_fx_tween = create_tween()
	_fx_tween.tween_property(rig, "position:y", 0.35, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_fx_tween.parallel().tween_property(rig, "scale", Vector3(0.88, 1.1, 0.88) * RIG_SCALE, 0.14)
	_fx_tween.tween_property(rig, "position:y", 0.0, 0.14).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_fx_tween.tween_property(rig, "scale", Vector3(1.12, 0.84, 1.12) * RIG_SCALE, 0.06)
	_fx_tween.tween_property(rig, "scale", Vector3.ONE * RIG_SCALE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func play_celebrate() -> void:
	_celebrating = true
	_kill_fx()
	_fx_tween = create_tween().set_loops()
	_fx_tween.tween_property(rig, "position:y", 0.45, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_fx_tween.tween_property(rig, "position:y", 0.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_fx_tween.tween_property(rig, "scale", Vector3(1.12, 0.86, 1.12) * RIG_SCALE, 0.06)
	_fx_tween.tween_property(rig, "scale", Vector3.ONE * RIG_SCALE, 0.12)


## Wrestling pose for this frame: `targets` are world points the hands reach for (one per arm),
## `strain` how hard it pulls away (0..1), `dragged` how much it is being dragged on its belly
## (0..1) and `lifted` how much the rival is lifting it off the ground (0..1).
## An empty `targets` lets go.
func set_grab(targets: Array[Vector3], strain: float, dragged: float, lifted: float) -> void:
	_grab_targets = targets
	_grab_strain_target = strain
	_grab_dragged_target = dragged
	_grab_lift_target = lifted


## How high this character is currently lifted by a rival (0..1).
func lift_amount() -> float:
	return _lift


## Lying dazed after being thrown: eyes squeezed and wobbling, arms splayed.
func set_dazed(value: bool) -> void:
	_dazed = value
	if value:
		_lift = 0.0
		rig.position.y = 0.0
		rig.rotation.z = 0.0
		_spring_vel.x -= 8.0


## Short victory cheer: a hop with both arms up.
func play_cheer(duration: float) -> void:
	_cheer_until = _time + duration
	_kill_fx()
	_fx_tween = create_tween()
	_fx_tween.tween_property(rig, "position:y", 0.4, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_fx_tween.tween_property(rig, "position:y", 0.0, 0.18).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_fx_tween.tween_property(rig, "scale", Vector3(1.15, 0.85, 1.15) * RIG_SCALE, 0.06)
	_fx_tween.tween_property(rig, "scale", Vector3.ONE * RIG_SCALE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Start of a grab: the grabber lunges forward, the grabbed one jumps in surprise.
func play_grab_start(initiator: bool) -> void:
	_kill_fx()
	_fx_tween = create_tween()
	if initiator:
		_fx_tween.tween_property(rig, "scale", Vector3(0.9, 0.92, 1.22) * RIG_SCALE, 0.08).set_ease(Tween.EASE_OUT)
		_fx_tween.tween_property(rig, "scale", Vector3.ONE * RIG_SCALE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_spring_vel.x += 5.0
	else:
		_surprise = 0.6
		_fx_tween.tween_property(rig, "position:y", 0.22, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_fx_tween.parallel().tween_property(rig, "scale", Vector3(0.88, 1.15, 0.88) * RIG_SCALE, 0.1)
		_fx_tween.tween_property(rig, "position:y", 0.0, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_fx_tween.tween_property(rig, "scale", Vector3.ONE * RIG_SCALE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_spring_vel.x -= 7.0


## End of a grab: stumble back with the arms flung up.
func play_grab_release() -> void:
	_recoil = 1.0
	_surprise = 0.5
	play_land()


func play_sad() -> void:
	_sad = true


func _squash(target: Vector3, duration: float) -> void:
	_kill_fx()
	var base := Vector3.ONE * RIG_SCALE
	_fx_tween = create_tween()
	_fx_tween.tween_property(rig, "scale", target * RIG_SCALE, duration * 0.3).set_ease(Tween.EASE_OUT)
	_fx_tween.tween_property(rig, "scale", base, duration * 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _kill_fx() -> void:
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	rig.position.y = 0.0
	rig.scale = Vector3.ONE * RIG_SCALE

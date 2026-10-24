@tool
class_name KingChickenModel
extends ChickenModel
## Goofy crowned chicken (based on reference/gallina_rey.png): pear-shaped body, long neck,
## bulging googly eyes, open beak, floppy comb under a tilted gold crown, feathered wings and
## long scaly legs with clawed toes. Reuses all of ChickenModel's animation.

const KING_BEAK_COLOR := Color(1.0, 0.56, 0.14)
const CLAW_COLOR := Color(0.96, 0.93, 0.84)
const MOUTH_COLOR := Color(0.55, 0.12, 0.1)
const GEM_RED := Color(0.85, 0.08, 0.12)
const GEM_BLUE := Color(0.15, 0.35, 0.95)
const FEATHER_TIP_COLOR := Color(0.9, 0.86, 0.78)


func _init() -> void:
	rig_scale = 0.7
	body_center = Vector3(0, 0.6, 0)
	hip_up_offset = 0.45
	head_rest_z = 0.1
	vent = Vector3(0, 0.68, 0.34)


func _build() -> void:
	var white := Toon.mat(BODY_COLOR, 0.85, 0.0, 0.2)
	var wing_mat := Toon.mat(WING_COLOR, 0.85, 0.0, 0.2)
	var comb := Toon.mat(COMB_COLOR, 0.7)
	var beak := Toon.mat(KING_BEAK_COLOR, 0.55)
	var leg_mat := Toon.mat(LEG_COLOR, 0.7)
	var claw := Toon.mat(CLAW_COLOR, 0.5)

	rig = Toon.pivot(self, Vector3.ZERO, "Rig")
	rig.scale = Vector3.ONE * rig_scale

	for side: float in [-1.0, 1.0]:
		legs.append(_build_leg(side, leg_mat, claw))

	body_root = Toon.pivot(rig, Vector3(0, BODY_Y, 0), "Body")
	# Pear shape: wide bottom, puffed chest and a long neck tapering into the head.
	Toon.part(body_root, Toon.sphere(0.44, 32, 16), white, Vector3(0, 0.6, 0), Vector3.ZERO, Vector3(0.92, 1.0, 0.92))
	Toon.part(body_root, Toon.sphere(0.28), white, Vector3(0, 0.78, 0.15))
	Toon.part(body_root, Toon.ellipsoid(0.2, 0.75), white, Vector3(0, 1.04, 0.05), Vector3(8, 0, 0))
	_build_ruff(white)

	head = Toon.pivot(body_root, Vector3(0, 1.34, head_rest_z), "Head")
	Toon.part(head, Toon.sphere(0.19, 24, 12), white, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.05, 1.0))
	_build_face(beak, comb)
	_build_crown(head, comb)

	for side: float in [-1.0, 1.0]:
		wings.append(_build_wing(side, wing_mat))

	tail = Toon.pivot(body_root, Vector3(0, 0.74, -0.4), "Tail")
	for i in 3:
		var a := (i - 1) * 28.0
		Toon.part(tail, Toon.ellipsoid(0.07, 0.26), white, Vector3((i - 1) * 0.08, 0.08, -0.04), Vector3(-40, 0, -a))


func _build_leg(side: float, leg_mat: Material, claw: Material) -> Node3D:
	var hip := Toon.pivot(rig, Vector3(0.14 * side, 0.42, 0.0))
	Toon.part(hip, Toon.cylinder(0.05, 0.042, 0.38), leg_mat, Vector3(0, -0.2, 0))
	# Scaly rings along the shank.
	for k in 4:
		Toon.part(hip, Toon.cylinder(0.052, 0.052, 0.025), leg_mat, Vector3(0, -0.12 - k * 0.065, 0))
	Toon.part(hip, Toon.sphere(0.055), leg_mat, Vector3(0, -0.38, 0.01))
	# Feet point slightly outwards, like in the reference.
	var foot := Toon.pivot(hip, Vector3(0, -0.39, 0.01))
	foot.rotation_degrees.y = 14 * side
	for a: float in [-32.0, 0.0, 32.0]:
		var toe := Toon.pivot(foot)
		toe.rotation_degrees.y = a
		Toon.part(toe, Toon.capsule(0.032, 0.2), leg_mat, Vector3(0, 0, 0.09), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.8))
		Toon.part(toe, Toon.cylinder(0.0, 0.026, 0.07), claw, Vector3(0, -0.005, 0.21), Vector3(100, 0, 0))
	var back := Toon.pivot(foot)
	back.rotation_degrees.y = 180
	Toon.part(back, Toon.capsule(0.028, 0.12), leg_mat, Vector3(0, 0, 0.05), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.8))
	Toon.part(back, Toon.cylinder(0.0, 0.022, 0.05), claw, Vector3(0, -0.005, 0.12), Vector3(100, 0, 0))
	return hip


## Spiky feather collar where the neck meets the body.
func _build_ruff(white: Material) -> void:
	for i in 10:
		var ring := Toon.pivot(body_root, Vector3(0, 0.9, 0.04))
		ring.rotation_degrees.y = -135 + i * 30
		Toon.part(ring, Toon.ellipsoid(0.065, 0.3), white, Vector3(0, -0.06, 0.25), Vector3(72, 0, 0), Vector3(1.0, 1.0, 0.6))


func _build_face(beak: Material, comb: Material) -> void:
	var eye_white := Toon.mat(Color(1, 1, 1), 0.35, 0.0, 0.0)
	var eye_black := Toon.mat(EYE_COLOR, 0.25, 0.0, 0.0)
	var shine := Toon.unshaded(Color(1, 1, 1))
	# Big bulging googly eyes, each looking a slightly different way.
	var looks := [Vector2(-0.025, 0.02), Vector2(0.01, -0.015)]
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var eye := Toon.pivot(head, Vector3(0.095 * side, 0.08, 0.12))
		Toon.part(eye, Toon.sphere(0.115), eye_white)
		var look: Vector2 = looks[i]
		Toon.part(eye, Toon.sphere(0.042), eye_black, Vector3(look.x, look.y, 0.1), Vector3.ZERO, Vector3(1.0, 1.0, 0.5))
		Toon.part(eye, Toon.sphere(0.013, 8, 4), shine, Vector3(look.x + 0.012, look.y + 0.016, 0.124), Vector3.ZERO, Vector3.ONE, false)
		eyes.append(eye)

	# Open beak: upper half points slightly up, lower half hangs down.
	Toon.part(head, Toon.cylinder(0.0, 0.07, 0.2), beak, Vector3(0, -0.03, 0.25), Vector3(82, 0, 0), Vector3(1.35, 1.0, 0.8))
	Toon.part(head, Toon.cylinder(0.0, 0.055, 0.14), beak, Vector3(0, -0.11, 0.21), Vector3(112, 0, 0), Vector3(1.2, 1.0, 0.5))
	Toon.part(head, Toon.sphere(0.045), Toon.mat(MOUTH_COLOR, 0.6), Vector3(0, -0.07, 0.18), Vector3.ZERO, Vector3(1.2, 0.8, 0.8))

	# Wattle under the beak.
	for side: float in [-1.0, 1.0]:
		Toon.part(head, Toon.sphere(0.055), comb, Vector3(0.035 * side, -0.2, 0.15), Vector3(0, 0, 10 * side), Vector3(0.7, 1.4, 0.6))


## Floppy comb peeking out from under a tilted gold crown with gems.
func _build_crown(parent: Node3D, comb: Material) -> void:
	Toon.part(parent, Toon.sphere(0.07), comb, Vector3(-0.02, 0.17, 0.11), Vector3(0, 0, 30), Vector3(0.6, 1.3, 1.0))
	Toon.part(parent, Toon.sphere(0.08), comb, Vector3(0.05, 0.2, 0.03), Vector3(0, 0, -20), Vector3(0.6, 1.2, 1.1))
	Toon.part(parent, Toon.sphere(0.06), comb, Vector3(0.08, 0.15, 0.13), Vector3(30, 0, -50), Vector3(0.6, 1.2, 0.9))

	var gold := Toon.gold()
	var crown := Toon.pivot(parent, Vector3(-0.03, 0.22, -0.03), "Crown")
	crown.rotation_degrees = Vector3(-8, 0, 16)
	crown.scale = Vector3.ONE * 1.3
	Toon.part(crown, Toon.cylinder(0.11, 0.1, 0.08, 20), gold)
	for i in 6:
		var a := TAU * i / 6.0
		var dir := Vector3(sin(a), 0, cos(a))
		Toon.part(crown, Toon.cylinder(0.0, 0.035, 0.1, 8), gold, dir * 0.095 + Vector3(0, 0.08, 0))
		Toon.part(crown, Toon.sphere(0.018, 8, 4), gold, dir * 0.095 + Vector3(0, 0.135, 0))
		var gem := Toon.mat(GEM_RED if i % 2 == 0 else GEM_BLUE, 0.2, 0.0, 0.3)
		Toon.part(crown, Toon.sphere(0.022, 12, 6), gem, dir * 0.108, Vector3(0, rad_to_deg(a), 0), Vector3(1.0, 1.0, 0.6))


## Folded wing lying along the body: a rounded shoulder of coverts and a fan of long flight
## feathers sweeping backwards. The feather fan sits on its own pivot so it lags the flap.
func _build_wing(side: float, wing_mat: Material) -> Node3D:
	var tip_mat := Toon.mat(FEATHER_TIP_COLOR, 0.85, 0.0, 0.2)
	var wing := Toon.pivot(body_root, Vector3(0.36 * side, 0.86, 0.06))
	var plate := Toon.pivot(wing)
	plate.rotation_degrees = Vector3(-25, 0, 14 * side)
	Toon.part(plate, Toon.sphere(0.2), wing_mat, Vector3(0.03 * side, -0.12, -0.08), Vector3(-20, 0, 0), Vector3(0.32, 0.9, 1.25))
	var tip := Toon.pivot(plate, Vector3(0.02 * side, -0.2, -0.04))
	# Flight feathers overlap from the front (short) to the back (long), sweeping backwards.
	var lengths := [0.26, 0.32, 0.38, 0.42, 0.4]
	for k in lengths.size():
		var feather := Toon.pivot(tip, Vector3(0, k * 0.03, 0.05 - k * 0.06))
		feather.rotation_degrees.x = 30 + k * 12
		var length: float = lengths[k]
		Toon.part(feather, Toon.ellipsoid(0.06, length), wing_mat if k < 3 else tip_mat,
				Vector3(0.005 * k * side, -length * 0.45, 0), Vector3.ZERO, Vector3(0.3, 1.0, 1.0))
	wing_tips.append(tip)
	return wing

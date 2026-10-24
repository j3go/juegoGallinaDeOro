@tool
class_name ChickenModel
extends Node3D
## Round, toy-like chicken built from primitives (based on the reference image).
## Faces +Z. All animation is procedural or tween based.

signal lay_moment

const BODY_COLOR := Color(0.98, 0.96, 0.91)
const WING_COLOR := Color(0.96, 0.93, 0.87)
const COMB_COLOR := Color(0.93, 0.4, 0.34)
const BEAK_COLOR := Color(1.0, 0.82, 0.27)
const LEG_COLOR := Color(1.0, 0.6, 0.2)
const EYE_COLOR := Color(0.13, 0.13, 0.15)
const BODY_Y := 0.2

var rig: Node3D
var body_root: Node3D
var head: Node3D
var tail: Node3D
var wings: Array[Node3D] = []
var legs: Array[Node3D] = []
var eyes: Array[Node3D] = []

var _phase := 0.0
var _time := 0.0
var _busy := false
var _flap_boost := 0.0
var _blink_timer := 2.5
var _peck := 0.0
## 0 = normal, 1 = shooting pose (bent back, legs up, butt pointing forward). Set by the AI.
var fire_pose_target := 0.0
var _pose := 0.0

## Lean used by the shooting pose and the body centre it rotates around (rig space).
const POSE_LEAN := -2.2
const POSE_LIFT := 0.15
const BODY_CENTER := Vector3(0, 0.44, -0.02)


func _ready() -> void:
	_build()


func _build() -> void:
	var white := Toon.mat(BODY_COLOR, 0.85, 0.0, 0.2)
	var wing_mat := Toon.mat(WING_COLOR, 0.85, 0.0, 0.2)
	var comb := Toon.mat(COMB_COLOR, 0.7)
	var beak := Toon.mat(BEAK_COLOR, 0.6)
	var leg_mat := Toon.mat(LEG_COLOR, 0.7)
	var eye_white := Toon.mat(Color(1, 1, 1), 0.4, 0.0, 0.0)
	var eye_black := Toon.mat(EYE_COLOR, 0.25, 0.0, 0.0)
	var shine := Toon.unshaded(Color(1, 1, 1))

	rig = Toon.pivot(self, Vector3.ZERO, "Rig")
	rig.scale = Vector3.ONE * 0.78

	for side: float in [-1.0, 1.0]:
		var hip := Toon.pivot(rig, Vector3(0.15 * side, 0.24, 0.02))
		Toon.part(hip, Toon.cylinder(0.035, 0.042, 0.22), leg_mat, Vector3(0, -0.11, 0))
		Toon.part(hip, Toon.sphere(0.09), leg_mat, Vector3(0, -0.22, 0.06), Vector3.ZERO, Vector3(0.9, 0.35, 1.5))
		legs.append(hip)

	body_root = Toon.pivot(rig, Vector3(0, BODY_Y, 0), "Body")
	# Main egg-shaped body; the head sphere blends into it so it reads as one blob.
	Toon.part(body_root, Toon.sphere(0.5, 32, 16), white, Vector3(0, 0.44, -0.02), Vector3.ZERO, Vector3(0.88, 0.9, 1.0))

	head = Toon.pivot(body_root, Vector3(0, 0.82, 0.14), "Head")
	Toon.part(head, Toon.sphere(0.37, 32, 16), white, Vector3.ZERO, Vector3.ZERO, Vector3(0.92, 1.0, 1.0))

	for side: float in [-1.0, 1.0]:
		var eye_pivot := Toon.pivot(head)
		eye_pivot.rotation_degrees = Vector3(-10, 50 * side, 0)
		var eye := Toon.pivot(eye_pivot, Vector3(0, 0, 0.335))
		Toon.part(eye, Toon.sphere(0.125), eye_white, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.12, 0.35))
		Toon.part(eye, Toon.sphere(0.088), eye_black, Vector3(0, 0, 0.03), Vector3.ZERO, Vector3(0.95, 1.15, 0.35))
		Toon.part(eye, Toon.sphere(0.024, 8, 4), shine, Vector3(0.028 * side, 0.04, 0.065), Vector3.ZERO, Vector3.ONE, false)
		eyes.append(eye)

	Toon.part(head, Toon.cylinder(0.0, 0.075, 0.2), beak, Vector3(0, -0.06, 0.38), Vector3(90, 0, 0), Vector3(1.3, 1.0, 0.75))
	Toon.part(head, Toon.sphere(0.05), comb, Vector3(0, -0.17, 0.33), Vector3(15, 0, 0), Vector3(0.75, 1.6, 0.75))
	Toon.part(head, Toon.sphere(0.1), comb, Vector3(0, 0.35, 0.1), Vector3.ZERO, Vector3(0.5, 1.0, 1.0))
	Toon.part(head, Toon.sphere(0.11), comb, Vector3(0, 0.39, -0.03), Vector3.ZERO, Vector3(0.5, 1.0, 1.0))
	Toon.part(head, Toon.sphere(0.085), comb, Vector3(0, 0.34, -0.14), Vector3.ZERO, Vector3(0.5, 1.0, 1.0))

	for side: float in [-1.0, 1.0]:
		var wing := Toon.pivot(body_root, Vector3(0.38 * side, 0.58, 0.0))
		Toon.part(wing, Toon.sphere(0.27), wing_mat, Vector3(0.05 * side, -0.12, -0.08),
				Vector3(22, 0, -8 * side), Vector3(0.32, 0.72, 1.1))
		wings.append(wing)

	tail = Toon.pivot(body_root, Vector3(0, 0.62, -0.4), "Tail")
	Toon.part(tail, Toon.sphere(0.15), white, Vector3(0, 0.12, -0.06), Vector3(-35, 0, 0), Vector3(0.45, 1.0, 0.7))
	Toon.part(tail, Toon.sphere(0.13), white, Vector3(0.12, 0.05, -0.04), Vector3(-30, 0, 25), Vector3(0.45, 1.0, 0.7))
	Toon.part(tail, Toon.sphere(0.13), white, Vector3(-0.12, 0.05, -0.04), Vector3(-30, 0, -25), Vector3(0.45, 1.0, 0.7))


## Called every physics frame with the current horizontal speed (m/s).
func animate(delta: float, speed: float) -> void:
	_time += delta
	var moving := speed > 0.15
	var amount := clampf(speed / 2.0, 0.0, 1.3)
	_phase += delta * (5.0 + speed * 4.0) if moving else delta * 1.5
	var k := 1.0 - exp(-10.0 * delta)

	if not _busy and _pose <= 0.001:
		body_root.rotation.z = lerpf(body_root.rotation.z, sin(_phase) * 0.13 * amount, k)
		body_root.rotation.x = lerpf(body_root.rotation.x, 0.1 * amount + _peck * 0.5, k)
		body_root.position.y = BODY_Y + absf(sin(_phase)) * 0.05 * amount + sin(_time * 2.2) * 0.008
		head.position.z = 0.14 + sin(_phase * 2.0) * 0.03 * amount

	for i in legs.size():
		var side := -1.0 if i == 0 else 1.0
		if _pose <= 0.001:
			legs[i].rotation.x = lerpf(legs[i].rotation.x, sin(_phase) * 0.6 * side * amount, k)

	_flap_boost = maxf(_flap_boost - delta, 0.0)
	var flap := 0.08 + (sin(_time * 30.0) * 0.5 + 0.5) * 0.7 * _flap_boost + sin(_phase * 2.0) * 0.06 * amount
	for i in wings.size():
		var side := -1.0 if i == 0 else 1.0
		wings[i].rotation.z = side * flap

	tail.rotation.x = sin(_time * 3.0) * 0.05 - 0.1 * amount
	_peck = maxf(_peck - delta * 2.0, 0.0)
	_apply_fire_pose(delta)
	_update_blink(delta)


func _apply_fire_pose(delta: float) -> void:
	_pose = move_toward(_pose, fire_pose_target, delta * 3.0)
	if _pose <= 0.001:
		for i in legs.size():
			legs[i].position = Vector3(0.15 * (-1.0 if i == 0 else 1.0), 0.24, 0.02)
		return
	var t := smoothstep(0.0, 1.0, _pose)
	var angle := POSE_LEAN * t
	# Rotate around the body centre so the chicken doesn't sink into the ground.
	var rotated := Basis(Vector3.RIGHT, angle) * BODY_CENTER
	body_root.rotation.x = angle
	body_root.rotation.z = lerpf(body_root.rotation.z, 0.0, t)
	body_root.position = Vector3(0, BODY_Y, 0) + (BODY_CENTER - rotated) + Vector3.UP * POSE_LIFT * t
	# Legs go up in the air, sticking out of the belly (now facing up).
	for i in legs.size():
		var side := -1.0 if i == 0 else 1.0
		var hip_down := Vector3(0.15 * side, 0.24, 0.02)
		var hip_up := Vector3(0.15 * side, BODY_CENTER.y + POSE_LIFT + 0.28, 0.12)
		legs[i].position = hip_down.lerp(hip_up, t)
		legs[i].rotation.x = lerpf(legs[i].rotation.x, PI * 0.9 + sin(_time * 16.0 + i) * 0.25, t)
	head.rotation.x = 1.4 * t
	flap(0.2)


## Where the egg comes out while in the shooting pose (local to this model, facing +Z).
func vent_position() -> Vector3:
	return Vector3(0, 0.72, 0.38)


func play_shot() -> void:
	flap(0.8)
	var tw := create_tween()
	tw.tween_property(rig, "scale", Vector3(0.88, 1.12, 0.88) * 0.78, 0.06)
	tw.tween_property(rig, "scale", Vector3.ONE * 0.78, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func flap(duration: float = 0.6) -> void:
	_flap_boost = maxf(_flap_boost, duration)


func peck() -> void:
	_peck = 1.0


## Crouch, emit `lay_moment` at the bottom of the crouch, then spring back.
func play_lay() -> Tween:
	_busy = true
	flap(1.2)
	var tw := create_tween()
	tw.tween_property(body_root, "scale", Vector3(1.14, 0.78, 1.1), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(body_root, "position:y", BODY_Y - 0.1, 0.35)
	tw.parallel().tween_property(body_root, "rotation:x", -0.15, 0.35)
	tw.tween_interval(0.3)
	tw.tween_callback(lay_moment.emit)
	tw.tween_property(body_root, "scale", Vector3(0.9, 1.18, 0.9), 0.12)
	tw.parallel().tween_property(body_root, "position:y", BODY_Y + 0.08, 0.12)
	tw.tween_property(body_root, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(body_root, "position:y", BODY_Y, 0.25)
	tw.tween_callback(func() -> void: _busy = false)
	return tw


func play_hop() -> void:
	if _busy:
		return
	_busy = true
	flap(0.5)
	var tw := create_tween()
	tw.tween_property(body_root, "scale", Vector3(1.1, 0.85, 1.1), 0.1)
	tw.tween_property(body_root, "position:y", BODY_Y + 0.4, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(body_root, "scale", Vector3(0.92, 1.12, 0.92), 0.18)
	tw.tween_property(body_root, "position:y", BODY_Y, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(body_root, "scale", Vector3(1.12, 0.86, 1.12), 0.08)
	tw.tween_property(body_root, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _busy = false)


func _update_blink(delta: float) -> void:
	_blink_timer -= delta
	if _blink_timer > 0.0:
		return
	_blink_timer = randf_range(2.0, 4.5)
	for eye in eyes:
		var tw := eye.create_tween()
		tw.tween_property(eye, "scale:y", 0.1, 0.06)
		tw.tween_property(eye, "scale:y", 1.0, 0.08)

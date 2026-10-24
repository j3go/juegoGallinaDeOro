@tool
class_name EggModel
extends Node3D
## Shiny golden egg with a soft ground glow and a few floating sparkles.

const SHELL_Y := 0.3

var shell: Node3D
var sparkles: CPUParticles3D
var _time := 0.0


func _ready() -> void:
	_time = randf() * TAU
	shell = Toon.pivot(self, Vector3(0, SHELL_Y, 0), "Shell")
	var gold := Toon.gold()
	# Two overlapping ellipsoids give the classic egg silhouette (wider at the bottom).
	Toon.part(shell, Toon.ellipsoid(0.2, 0.44, 32, 16), gold, Vector3(0, -0.02, 0))
	Toon.part(shell, Toon.ellipsoid(0.165, 0.42, 32, 16), gold, Vector3(0, 0.05, 0))

	var glow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 1.3)
	quad.orientation = PlaneMesh.FACE_Y
	glow.mesh = quad
	glow.material_override = Toon.glow_dot(Color(1.0, 0.75, 0.25, 0.55), false)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position.y = 0.04
	add_child(glow)

	# Small warm light so eggs read from afar, especially on darker maps.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.3)
	light.light_energy = 0.9
	light.omni_range = 2.0
	light.position.y = SHELL_Y + 0.2
	add_child(light)

	sparkles = CPUParticles3D.new()
	sparkles.amount = 6
	sparkles.lifetime = 1.4
	sparkles.mesh = _quad(0.14)
	sparkles.material_override = Toon.glow_dot(Color(1.0, 0.92, 0.55))
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkles.emission_sphere_radius = 0.35
	sparkles.direction = Vector3.UP
	sparkles.spread = 20.0
	sparkles.initial_velocity_min = 0.1
	sparkles.initial_velocity_max = 0.35
	sparkles.gravity = Vector3.ZERO
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	sparkles.scale_amount_curve = curve
	sparkles.position.y = SHELL_Y
	add_child(sparkles)


## Gentle bob and spin to catch the eye.
func idle(delta: float) -> void:
	_time += delta
	shell.rotation.y += delta * 1.4
	shell.rotation.z = sin(_time * 1.7) * 0.12
	shell.position.y = SHELL_Y + 0.05 + sin(_time * 2.4) * 0.06


func play_land() -> void:
	var tw := create_tween()
	tw.tween_property(shell, "scale", Vector3(1.3, 0.7, 1.3), 0.07)
	tw.tween_property(shell, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func play_collect() -> Tween:
	sparkles.emitting = false
	var tw := create_tween().set_parallel()
	tw.tween_property(shell, "position:y", SHELL_Y + 1.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(shell, "rotation:y", shell.rotation.y + TAU * 1.5, 0.35)
	tw.tween_property(shell, "scale", Vector3.ONE * 1.35, 0.18)
	tw.chain().tween_property(shell, "scale", Vector3.ZERO, 0.15).set_ease(Tween.EASE_IN)
	return tw


func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q

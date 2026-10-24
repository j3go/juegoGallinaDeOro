class_name ItemPickup
extends Node3D
## Item lying on the ground (kunai or immortality). Taken with the pickup button by someone
## with a free item slot; a single owner.

var kind: CharacterBase.Item = CharacterBase.Item.KUNAI
var _taken := false
var _visual: Node3D
var _time := 0.0


func setup(item_kind: CharacterBase.Item) -> void:
	kind = item_kind
	_visual = Node3D.new()
	_visual.position.y = 0.7
	add_child(_visual)
	var color := Color(1.0, 0.35, 0.3) if kind == CharacterBase.Item.KUNAI else Color(1.0, 0.85, 0.3)
	if kind == CharacterBase.Item.KUNAI:
		var k := Node3D.new()
		k.rotation_degrees = Vector3(0, 0, 50)
		k.scale = Vector3.ONE * 1.6
		_visual.add_child(k)
		Kunai.build_model(k)
	else:
		# A glowing star.
		var star_mat := Toon.emissive(Color(1.0, 0.82, 0.3), 2.5)
		Toon.part(_visual, Toon.sphere(0.18, 16, 8), star_mat)
		for i in 5:
			var arm := Toon.pivot(_visual)
			arm.rotation.z = TAU * i / 5.0
			Toon.part(arm, Toon.cylinder(0.0, 0.1, 0.32, 6), star_mat, Vector3(0, 0.26, 0), Vector3.ZERO, Vector3(1, 1, 0.5))
	# Ring and soft column of light so items are easy to spot.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.65
	ring.mesh = torus
	ring.material_override = Toon.emissive(color, 2.0)
	ring.position.y = 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var beam := MeshInstance3D.new()
	beam.mesh = Toon.cylinder(0.5, 0.5, 4.0, 16)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.albedo_color = Color(color, 0.07)
	beam.material_override = beam_mat
	beam.position.y = 2.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 2.5
	light.position.y = 0.8
	add_child(light)
	scale = Vector3.ONE * 0.2
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	if _visual:
		_visual.rotation.y += delta * 2.0
		_visual.position.y = 0.7 + sin(_time * 2.5) * 0.08


func is_available() -> bool:
	return not _taken


func try_collect() -> bool:
	if _taken:
		return false
	_taken = true
	Effects.sparkle_burst(get_parent(), global_position + Vector3.UP * 0.7, Color(1.0, 0.9, 0.6), 14)
	queue_free()
	return true

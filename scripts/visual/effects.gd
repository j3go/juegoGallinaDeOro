class_name Effects
extends RefCounted
## One-shot visual effects (particle bursts, floating text). Each effect frees itself.

const GOLD := Color(1.0, 0.82, 0.3)


static func sparkle_burst(parent: Node, pos: Vector3, color: Color = GOLD, amount: int = 26) -> void:
	var p := _burst(parent, pos, amount, 0.75)
	p.material_override = Toon.glow_dot(color)
	p.mesh = _quad(0.22)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -5.0, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.emitting = true
	_ring(parent, pos, color)


static func dust_puff(parent: Node, pos: Vector3, amount: int = 10) -> void:
	var p := _burst(parent, pos + Vector3.UP * 0.1, amount, 0.55)
	p.mesh = Toon.sphere(0.12, 8, 4)
	p.material_override = Toon.mat(Color(1.0, 0.97, 0.9), 1.0, 0.0, 0.0)
	p.direction = Vector3.UP
	p.spread = 80.0
	p.flatness = 0.6
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, 1.0, 0)
	p.damping_min = 3.0
	p.damping_max = 4.0
	p.emitting = true


## Comic puff of gas when the chicken shoots (doesn't hide the laser or the egg: it goes backwards).
static func gas_puff(parent: Node, pos: Vector3, direction: Vector3) -> void:
	var p := _burst(parent, pos, 14, 0.9)
	p.mesh = Toon.sphere(0.16, 8, 4)
	p.material_override = Toon.mat(Color(0.72, 0.82, 0.5), 1.0, 0.0, 0.0)
	p.direction = direction.normalized() + Vector3.UP * 0.3
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 2.0
	p.damping_max = 3.5
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.emitting = true


## Column of light plus sparkles, used where the chicken teleports out and back in.
static func teleport_flash(parent: Node, pos: Vector3, color: Color = Color(0.75, 0.45, 1.0)) -> void:
	sparkle_burst(parent, pos + Vector3.UP * 0.6, color, 34)
	var beam := MeshInstance3D.new()
	beam.mesh = Toon.cylinder(0.5, 0.5, 1.0, 20)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color, 0.8)
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(beam)
	beam.global_position = Vector3(pos.x, 0.0, pos.z)
	beam.scale = Vector3(1.4, 0.01, 1.4)
	var tw := beam.create_tween()
	tw.tween_property(beam, "scale", Vector3(1.0, 5.0, 1.0), 0.15).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(beam, "position:y", 2.5, 0.15).set_ease(Tween.EASE_OUT)
	tw.tween_property(beam, "scale", Vector3(0.05, 6.0, 0.05), 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(beam.queue_free)


static func floating_text(parent: Node, pos: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UITheme.font()
	label.font_size = 110
	label.outline_size = 28
	label.outline_modulate = Color(0.25, 0.16, 0.08)
	label.modulate = color
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	label.global_position = pos
	label.scale = Vector3.ONE * 0.3
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "global_position", pos + Vector3.UP * 1.3, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.3)
	tw.tween_callback(label.queue_free)


static func _burst(parent: Node, pos: Vector3, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	parent.add_child(p)
	p.global_position = pos
	parent.get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)
	return p


static func _ring(parent: Node, pos: Vector3, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = Vector3(pos.x, 0.08, pos.z)
	ring.scale = Vector3.ONE * 0.3
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(2.4, 1.0, 2.4), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)


static func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q

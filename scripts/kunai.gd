class_name Kunai
extends Projectile
## Thrown kunai: straight line, first valid hit, single use. Makes the victim drop eggs
## (no knockdown) and is consumed on impact or at the end of its range.

var thrower: CharacterBase


func launch(by: CharacterBase, from: Vector3, dir: Vector3, context: MatchContext) -> void:
	thrower = by
	_start(from, dir, context.config.kunai_speed, context.config.kunai_range, 0.22, context, [by.get_rid()])
	var model := Node3D.new()
	add_child(model)
	model.rotation.y = atan2(direction.x, direction.z)
	Kunai.build_model(model)
	Sfx.play_3d(context.world_root, Sfx.THROW, from, -2.0)
	Sfx.loop_3d(self, Sfx.LOOP_KUNAI, -6.0)


static func build_model(parent: Node3D) -> void:
	var blade := Toon.mat(Color(0.75, 0.78, 0.82), 0.25, 0.8, 0.3)
	var dark := Toon.mat(Color(0.15, 0.15, 0.17), 0.6)
	var wrap := Toon.mat(Color(0.8, 0.15, 0.15), 0.7)
	# Points along +Z.
	Toon.part(parent, Toon.prism(Vector3(0.16, 0.36, 0.03)), blade, Vector3(0, 0, 0.22), Vector3(90, 0, 0))
	Toon.part(parent, Toon.cylinder(0.025, 0.025, 0.28, 8), wrap, Vector3(0, 0, -0.1), Vector3(90, 0, 0))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.035
	ring.outer_radius = 0.06
	Toon.part(parent, ring, dark, Vector3(0, 0, -0.27), Vector3(90, 0, 0))


func _on_flying(_delta: float) -> void:
	pass


func _on_hit_character(character: CharacterBase) -> void:
	character.hit_by_kunai(direction)
	Effects.sparkle_burst(ctx.world_root, global_position, Color(0.9, 0.9, 1.0), 10)
	Sfx.play_3d(ctx.world_root, Sfx.KUNAI_HIT, global_position, 0.0)
	queue_free()


func _on_hit_world() -> void:
	Effects.dust_puff(ctx.world_root, global_position, 5)
	Sfx.play_3d(ctx.world_root, Sfx.KUNAI_THUNK, global_position, -2.0)
	queue_free()

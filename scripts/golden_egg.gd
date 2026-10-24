class_name GoldenEgg
extends Area3D
## Golden egg lying on the ground. Picked up only by pressing the pickup button next to it,
## and it can go into exactly one inventory.

signal collected(egg: GoldenEgg, collector: CharacterBase)

enum EggState { FLYING, READY, TAKEN }

const ARC_HEIGHT := 1.2
const FLIGHT_TIME := 0.55

var egg_state: EggState = EggState.FLYING
var landing_position := Vector3.ZERO
var points := 1

@onready var model: EggModel = $Model


func _process(delta: float) -> void:
	if egg_state == EggState.READY:
		model.idle(delta)


func is_available() -> bool:
	return egg_state == EggState.READY


## True while the egg is still worth chasing (flying eggs can already be targeted).
func can_be_targeted() -> bool:
	return egg_state != EggState.TAKEN


func launch(from: Vector3, to: Vector3) -> void:
	landing_position = to
	global_position = from
	model.scale = Vector3.ONE * 0.3
	var tw := create_tween().set_parallel()
	tw.tween_method(_arc.bind(from, to), 0.0, 1.0, FLIGHT_TIME)
	tw.tween_property(model, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_on_landed)


func _arc(t: float, from: Vector3, to: Vector3) -> void:
	global_position = from.lerp(to, t) + Vector3.UP * ARC_HEIGHT * 4.0 * t * (1.0 - t)


func _on_landed() -> void:
	global_position = landing_position
	egg_state = EggState.READY
	model.play_land()
	Effects.dust_puff(get_parent(), landing_position)
	Sfx.play_3d(get_parent(), Sfx.EGG_PLOP, landing_position, -8.0, 0.2)


## Returns false if someone else already took it (the state flips synchronously, so two
## simultaneous presses can never duplicate an egg).
func try_collect(collector: CharacterBase) -> bool:
	if egg_state != EggState.READY:
		return false
	egg_state = EggState.TAKEN
	collected.emit(self, collector)
	Effects.sparkle_burst(get_parent(), global_position + Vector3.UP * 0.4)
	Effects.floating_text(get_parent(), global_position + Vector3.UP * 1.0, "+%d" % points, collector.team_color.lightened(0.3))
	var tw := model.play_collect()
	tw.chain().tween_callback(queue_free)
	return true

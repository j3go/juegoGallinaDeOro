class_name Sfx
extends RefCounted
## Plays a sound only if the resource exists, so missing audio never breaks the game.
## Sounds are synthesized by tools/gen_audio.py. A sound can be a path or an Array of paths
## (variants: one is picked at random each time). Everything plays on the "SFX" bus.

const BUS := "SFX"

const COLLECT := "res://assets/sounds/coin.wav"
const LAY := "res://assets/sounds/lay.wav"
const BEEP := "res://assets/sounds/beep.wav"
const GO := "res://assets/sounds/go.wav"
const END := "res://assets/sounds/end.wav"
const JUMP := "res://assets/sounds/boing.wav"
const LOCK := "res://assets/sounds/lock.wav"
const HIT := "res://assets/sounds/egg_bonk.wav"
const PUSH := "res://assets/sounds/slap.wav"
const GRAB := "res://assets/sounds/grab_zip.wav"
const THROW := "res://assets/sounds/kunai_throw.wav"
const ITEM := "res://assets/sounds/item.wav"
const WAVE := "res://assets/sounds/wave.wav"
const SHIELD := "res://assets/sounds/shield.wav"

## The chicken's shot: one of several farts.
const SHOOT := ["res://assets/sounds/fart_1.wav", "res://assets/sounds/fart_2.wav", "res://assets/sounds/fart_3.wav"]
const FART_BIG := "res://assets/sounds/fart_big.wav"
const EGG_CRACK := "res://assets/sounds/egg_crack.wav"
const EGG_SPLAT := "res://assets/sounds/egg_splat.wav"
const EGG_PLOP := "res://assets/sounds/egg_plop.wav"
const KNOCKDOWN := "res://assets/sounds/knockdown.wav"
const EXPLOSION := "res://assets/sounds/explosion.wav"
const KUNAI_THUNK := "res://assets/sounds/kunai_thunk.wav"
const KUNAI_HIT := "res://assets/sounds/kunai_hit.wav"
const CLUCK := ["res://assets/sounds/cluck_1.wav", "res://assets/sounds/cluck_2.wav", "res://assets/sounds/cluck_3.wav"]
const ROOSTER := "res://assets/sounds/rooster.wav"
const WING_FLAPS := "res://assets/sounds/wing_flaps.wav"
const TELEPORT_OUT := "res://assets/sounds/teleport_out.wav"
const TELEPORT_IN := "res://assets/sounds/teleport_in.wav"
const THROW_DOWN := "res://assets/sounds/throw_down.wav"
const DIZZY := "res://assets/sounds/dizzy_birds.wav"
const FANFARE := "res://assets/sounds/fanfare.wav"

## Loops that follow a moving object (see `loop_3d`).
const LOOP_EGG := "res://assets/sounds/egg_whistle_loop.wav"
const LOOP_ERRATIC := "res://assets/sounds/egg_erratic_loop.wav"
const LOOP_FUSE := "res://assets/sounds/fuse_loop.wav"
const LOOP_KUNAI := "res://assets/sounds/kunai_whir_loop.wav"
const LOOP_FLAP := "res://assets/sounds/flap_loop.wav"


static func play(parent: Node, sound: Variant, volume_db: float = 0.0) -> void:
	var stream := _stream(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = BUS
	parent.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


static func play_3d(parent: Node, sound: Variant, pos: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	var stream := _stream(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 8.0
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.bus = BUS
	parent.add_child(player)
	player.global_position = pos
	player.play()
	player.finished.connect(player.queue_free)


## Looping sound attached to `parent` (moves with it and stops when it is freed).
## Returns the player so the caller can stop it earlier with `queue_free()`.
static func loop_3d(parent: Node3D, path: String, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var stream := _stream(path) as AudioStreamWAV
	if stream == null:
		return null
	if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 8.0
	player.bus = BUS
	parent.add_child(player)
	player.play()
	return player


static func _stream(sound: Variant) -> AudioStream:
	var path: String = sound.pick_random() if sound is Array else sound
	if not ResourceLoader.exists(path):
		return null
	return load(path)

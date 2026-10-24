class_name Sfx
extends RefCounted
## Plays a sound only if the resource exists, so missing audio never breaks the game.

const COLLECT := "res://assets/sounds/collect.wav"
const LAY := "res://assets/sounds/lay.wav"
const BEEP := "res://assets/sounds/beep.wav"
const GO := "res://assets/sounds/go.wav"
const END := "res://assets/sounds/end.wav"
const JUMP := "res://assets/sounds/jump.wav"
const SHOOT := "res://assets/sounds/shoot.wav"
const LOCK := "res://assets/sounds/lock.wav"
const HIT := "res://assets/sounds/hit.wav"
const PUSH := "res://assets/sounds/push.wav"
const GRAB := "res://assets/sounds/grab.wav"
const THROW := "res://assets/sounds/throw.wav"
const ITEM := "res://assets/sounds/item.wav"
const WAVE := "res://assets/sounds/wave.wav"
const SHIELD := "res://assets/sounds/shield.wav"


static func play(parent: Node, path: String, volume_db: float = 0.0) -> void:
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = volume_db
	parent.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


static func play_3d(parent: Node, path: String, pos: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = load(path)
	player.volume_db = volume_db
	player.unit_size = 8.0
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	parent.add_child(player)
	player.global_position = pos
	player.play()
	player.finished.connect(player.queue_free)

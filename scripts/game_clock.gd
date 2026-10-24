class_name GameClock
extends Node
## Single match clock (scaled game time) shared by grabs, cooldowns and effects,
## so every timer uses the same time base.

static var now := 0.0


func _ready() -> void:
	now = 0.0
	process_physics_priority = -100


func _physics_process(delta: float) -> void:
	now += delta

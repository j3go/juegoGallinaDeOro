class_name PlayerController
extends CharacterBase
## Player: camera-relative movement and an elevated three-quarter camera that keeps the
## other players in view. E pick up, F / left click push, G / right click grab, Q use item.

const CAMERA_HEIGHT := 1.2
const PITCH_MIN := -1.2
const PITCH_MAX := -0.35
const MAX_MOUSE_STEP := 120.0

var _yaw := 0.0
var _pitch := -0.82
var _was_on_floor := true
var _ignore_mouse_until := 0
var _last_mouse_mode := Input.MOUSE_MODE_VISIBLE

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D


func _ready() -> void:
	super._ready()
	is_player = true
	# The pivot follows the player smoothly instead of being rigidly parented.
	camera_pivot.top_level = true
	camera_pivot.global_position = global_position + Vector3.UP * CAMERA_HEIGHT
	spring_arm.add_excluded_object(get_rid())
	_yaw = rotation.y
	model.rotation.y = _yaw + PI
	_update_camera(1.0)


## Moves the player (e.g. to a map's spawn point) and snaps the camera behind it.
func place_at(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	camera_pivot.global_position = pos + Vector3.UP * CAMERA_HEIGHT
	_update_camera(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Capturing the mouse warps the cursor to the centre, which arrives as one huge
		# motion event: skip events right after capturing and clamp outliers.
		if Time.get_ticks_msec() < _ignore_mouse_until:
			return
		var motion := (event as InputEventMouseMotion).relative.limit_length(MAX_MOUSE_STEP)
		_yaw -= motion.x * config.mouse_sensitivity
		_pitch = clampf(_pitch - motion.y * config.mouse_sensitivity, PITCH_MIN, PITCH_MAX)
	elif event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif is_active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and is_active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if Input.mouse_mode != _last_mouse_mode:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_ignore_mouse_until = Time.get_ticks_msec() + 150
		_last_mouse_mode = Input.mouse_mode


## When true (tests), input is not read and `move_input` is driven from outside.
var scripted := false


## Horizontal direction the camera looks at (used to aim the kunai).
func camera_forward() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3.FORWARD


func _physics_process(delta: float) -> void:
	if not scripted:
		var input_dir := Vector2.ZERO
		if is_active:
			input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		# World-space direction: in a chain everyone's "north" is the same.
		move_input = (Basis(Vector3.UP, _yaw) * Vector3(input_dir.x, 0.0, input_dir.y)).limit_length(1.0)
		if is_active:
			if Input.is_action_just_pressed("pickup"):
				try_pickup()
			if Input.is_action_just_pressed("push"):
				try_push()
			if Input.is_action_just_pressed("grab"):
				try_grab()
			if Input.is_action_just_pressed("use_item"):
				use_item(camera_forward())
	var running := is_active and Input.is_action_pressed("sprint")
	var max_speed := config.player_run_speed if running else config.player_walk_speed
	var rate := config.player_acceleration if move_input.length() > 0.01 else config.player_deceleration
	if not is_on_floor():
		rate *= 0.45

	if can_act() and is_on_floor() and Input.is_action_just_pressed("jump") and not scripted:
		velocity.y = config.jump_velocity
		model.play_jump()
		Sfx.play(self, Sfx.JUMP, -10.0)

	_move_body(delta, move_input * max_speed, rate)

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		model.play_land()
	_was_on_floor = on_floor

	_face_direction(move_input, delta, 14.0)
	model.animate(delta, horizontal_speed(), on_floor)
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var target := global_position + Vector3.UP * CAMERA_HEIGHT
	camera_pivot.global_position = camera_pivot.global_position.lerp(target, 1.0 - exp(-10.0 * delta))
	camera_pivot.rotation = Vector3(0.0, _yaw, 0.0)
	spring_arm.rotation.x = _pitch

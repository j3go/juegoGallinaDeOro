class_name CharacterBase
extends CharacterBody3D
## Shared logic for the six competitors (player and NPCs), following design doc v0.1:
## manual pickup, push, grab chains, items, knockdown with recovery and temporary immortality.
## Subclasses only decide `move_input` and when to call the try_* actions.

signal score_changed(character: CharacterBase, score: int)
## Item, grab, knockdown or immortality changed (for the HUD).
signal status_changed(character: CharacterBase)
## "push", "grab", "kunai", "immortality", "egg_hit", "kunai_hit", "pickup".
signal action_performed(character: CharacterBase, action: String)

enum Item { NONE, KUNAI, IMMORTALITY }

const ITEM_NAMES := {Item.NONE: "—", Item.KUNAI: "Kunai", Item.IMMORTALITY: "Inmortalidad"}
const EXTERNAL_FRICTION := 12.0

@export var display_name := "Jugador"
@export var team_color := Color.WHITE
@export var config: GameConfig

## Eggs carried (this is the score).
var score := 0
var is_active := false
var is_player := false
var gravity := 22.0
var item: Item = Item.NONE

## Desired horizontal direction (length <= 1). It is also this character's pull in a chain.
var move_input := Vector3.ZERO
## Set by GrabSystem every physics frame while this character is part of a chain.
var in_chain := false
var chain_velocity := Vector3.ZERO
var outgoing_link: GrabSystem.GrabLink = null
var incoming_links: Array[GrabSystem.GrabLink] = []
## Game time when this character may start another grab / push.
var grab_ready_at := 0.0
var push_ready_at := 0.0

var ctx: MatchContext

var _motion := Vector3.ZERO
var _external := Vector3.ZERO
var _down_until := -1.0
var _recover_until := -1.0
var _stun_until := -1.0
var _immortal_until := -1.0
var _was_down := false
var _bubble: MeshInstance3D
var _stars: Node3D
var _effort_arrow: Node3D

@onready var model: HumanModel = $Model


func _ready() -> void:
	gravity = config.gravity
	_build_status_visuals()


func setup_match(context: MatchContext) -> void:
	ctx = context


# --- State queries ----------------------------------------------------------------------

func now() -> float:
	return GameClock.now


func is_down() -> bool:
	return now() < _down_until


func is_recovering() -> bool:
	return not is_down() and now() < _recover_until


func is_immortal() -> bool:
	return now() < _immortal_until


func immortal_time_left() -> float:
	return maxf(0.0, _immortal_until - now())


## Knocked down, recovering or stunned characters can't pick up, push, grab or use items.
func can_act() -> bool:
	return is_active and now() >= _recover_until and now() >= _stun_until


func is_linked() -> bool:
	return outgoing_link != null or not incoming_links.is_empty()


## Eggs can't be picked up while grabbing or being grabbed (immortality doesn't change that).
func can_pick_eggs() -> bool:
	return can_act() and not is_linked()


func grab_cooldown_left() -> float:
	return maxf(0.0, grab_ready_at - now())


func get_forward() -> Vector3:
	var f := model.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


## This character's contribution to a chain: force 1 in the direction it is pulling.
func pull_force() -> Vector3:
	if not can_act():
		return Vector3.ZERO
	return Vector3(move_input.x, 0.0, move_input.z).limit_length(1.0)


# --- Actions --------------------------------------------------------------------------------

## One press picks up one nearby egg (if not in any grab) or an item (if the slot is free).
func try_pickup() -> bool:
	if not can_act() or ctx == null:
		return false
	if can_pick_eggs():
		var egg := ctx.egg_manager.nearest_available(global_position, config.pickup_radius)
		if egg and egg.try_collect(self):
			action_performed.emit(self, "pickup")
			return true
	if item == Item.NONE:
		var pickup := ctx.item_manager.nearest_item(global_position, config.pickup_radius)
		if pickup and pickup.try_collect():
			item = pickup.kind
			Sfx.play_3d(self, Sfx.ITEM, global_position, -4.0)
			status_changed.emit(self)
			return true
	return false


## Short frontal shove. Never makes anyone drop eggs.
func try_push() -> bool:
	if not can_act() or outgoing_link != null or now() < push_ready_at or ctx == null:
		return false
	push_ready_at = now() + config.push_cooldown
	var forward := get_forward()
	var min_dot := cos(deg_to_rad(config.push_angle_deg))
	for other in ctx.competitors:
		if other == self:
			continue
		var to := other.global_position - global_position
		to.y = 0.0
		var distance := to.length()
		if distance < config.push_range and distance > 0.01 and forward.dot(to / distance) >= min_dot:
			other.receive_push(to / distance * config.push_force)
	_external += forward * 2.5
	model.play_jump()
	Sfx.play_3d(self, Sfx.PUSH, global_position, -3.0)
	action_performed.emit(self, "push")
	return true


## Starts a 3 s grab on the closest rival in front.
func try_grab() -> bool:
	if not can_act() or outgoing_link != null or now() < grab_ready_at or ctx == null:
		return false
	var forward := get_forward()
	var best: CharacterBase = null
	var best_distance := INF
	for other in ctx.competitors:
		if other == self or other.is_down() or not other.is_active:
			continue
		var to := other.global_position - global_position
		to.y = 0.0
		var distance := to.length()
		if distance < config.grab_range and distance < best_distance and (distance < 0.6 or forward.dot(to / distance) > 0.2):
			best = other
			best_distance = distance
	if best and ctx.grab_system.create_link(self, best):
		action_performed.emit(self, "grab")
		return true
	return false


## Uses the stored item. The kunai flies along `aim`.
func use_item(aim: Vector3) -> bool:
	if not can_act() or item == Item.NONE or outgoing_link != null or ctx == null:
		return false
	match item:
		Item.KUNAI:
			aim.y = 0.0
			if aim.length() < 0.1:
				aim = get_forward()
			var kunai := Kunai.new()
			ctx.world_root.add_child(kunai)
			kunai.launch(self, global_position + Vector3.UP * 0.9 + aim.normalized() * 0.5, aim.normalized(), ctx)
			action_performed.emit(self, "kunai")
		Item.IMMORTALITY:
			if is_immortal():
				return false  # doesn't stack or renew while active
			_immortal_until = now() + config.immortality_time
			Sfx.play_3d(self, Sfx.SHIELD, global_position, -2.0)
			action_performed.emit(self, "immortality")
	item = Item.NONE
	status_changed.emit(self)
	return true


# --- Being hit -----------------------------------------------------------------------------

func receive_push(impulse: Vector3) -> void:
	_external += impulse + Vector3.UP * 3.0
	var tw := model.create_tween()
	tw.tween_property(model, "scale", Vector3(1.15, 0.85, 1.15), 0.06)
	tw.tween_property(model, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Returns true if the egg had an effect (immortal characters just stop it).
func hit_by_egg(direction: Vector3) -> bool:
	if is_down() or is_recovering():
		return false  # hits during the fall or the recovery don't cause new losses
	if is_immortal():
		Effects.sparkle_burst(ctx.world_root, global_position + Vector3.UP, Color(1.0, 0.9, 0.4), 14)
		return false
	_drop_eggs(config.egg_hit_drop_fraction, direction)
	_knock_down(direction)
	action_performed.emit(self, "egg_hit")
	return true


func hit_by_kunai(direction: Vector3) -> bool:
	if is_down() or is_recovering() or is_immortal():
		return false
	_drop_eggs(config.kunai_drop_fraction, direction)
	_stun_until = now() + config.kunai_stun_time
	_external += direction * 3.5 + Vector3.UP * 2.0
	model.play_land()
	action_performed.emit(self, "kunai_hit")
	status_changed.emit(self)
	return true


## Instant push (e.g. bouncing off lava): a short moment without control so it really expels.
func knockback(impulse: Vector3) -> void:
	_external = impulse
	_motion = Vector3.ZERO
	_stun_until = maxf(_stun_until, now() + 0.45)


func add_eggs(points: int) -> void:
	score += points
	score_changed.emit(self, score)
	model.play_collect()


func set_active(active: bool) -> void:
	is_active = active
	if not active:
		move_input = Vector3.ZERO


func celebrate(won: bool) -> void:
	if won:
		model.play_celebrate()
	else:
		model.play_sad()


func _drop_eggs(fraction: float, direction: Vector3) -> void:
	var count := mini(score, ceili(score * fraction))
	if count <= 0:
		return
	score -= count
	score_changed.emit(self, score)
	ctx.egg_manager.scatter_eggs(global_position + Vector3.UP * 0.9, count, direction)


func _knock_down(direction: Vector3) -> void:
	_down_until = now() + config.knockdown_time
	_recover_until = _down_until + config.recovery_time
	ctx.grab_system.release_links_of(self)
	_motion = Vector3.ZERO
	_external = direction * 6.0 + Vector3.UP * 5.0
	# Fall backwards along the hit direction.
	model.rotation.y = atan2(-direction.x, -direction.z)
	var tw := model.create_tween()
	tw.tween_property(model, "rotation:x", -1.45, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(model, "position:y", 0.3, 0.25)
	Sfx.play_3d(self, Sfx.HIT, global_position, 0.0)
	status_changed.emit(self)


func _get_up() -> void:
	var tw := model.create_tween()
	tw.tween_property(model, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(model, "position:y", 0.0, 0.3)
	model.play_land()
	status_changed.emit(self)


# --- Movement --------------------------------------------------------------------------------

## Moves the body. `own_velocity` is what the character wants; chains override it with the
## velocity from their summed forces, and pushes/hits add a decaying external impulse.
func _move_body(delta: float, own_velocity: Vector3, acceleration: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var target := own_velocity
	if is_down():
		target = Vector3.ZERO
	elif in_chain:
		target = chain_velocity  # stunned members still move with their chain
	elif not can_act():
		target = Vector3.ZERO
	_motion = _motion.move_toward(Vector3(target.x, 0.0, target.z), acceleration * delta)
	if _external.y > 0.0:
		velocity.y = maxf(velocity.y, _external.y)
		_external.y = 0.0
	var external_flat := Vector3(_external.x, 0.0, _external.z).move_toward(Vector3.ZERO, EXTERNAL_FRICTION * delta)
	_external = external_flat
	velocity.x = _motion.x + _external.x
	velocity.z = _motion.z + _external.z
	move_and_slide()
	_update_status_visuals(delta)


## Smoothly turns the visual model towards a horizontal direction.
func _face_direction(direction: Vector3, delta: float, turn_speed: float = 12.0) -> void:
	if is_down() or Vector2(direction.x, direction.z).length_squared() < 0.0004:
		return
	var target := atan2(direction.x, direction.z)
	model.rotation.y = lerp_angle(model.rotation.y, target, 1.0 - exp(-turn_speed * delta))


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# --- Status visuals ----------------------------------------------------------------------------

func _build_status_visuals() -> void:
	_bubble = MeshInstance3D.new()
	_bubble.mesh = Toon.sphere(1.0, 24, 12)
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bubble_mat.albedo_color = Color(1.0, 0.85, 0.3, 0.22)
	bubble_mat.rim_enabled = true
	_bubble.material_override = bubble_mat
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble.position.y = 0.85
	_bubble.visible = false
	add_child(_bubble)

	_stars = Node3D.new()
	_stars.position.y = 1.9
	_stars.visible = false
	add_child(_stars)
	for i in 3:
		var star := Toon.part(_stars, Toon.sphere(0.08, 8, 4), Toon.emissive(Color(1.0, 0.9, 0.3), 3.0),
				Vector3(cos(TAU * i / 3.0), 0, sin(TAU * i / 3.0)) * 0.35, Vector3.ZERO, Vector3.ONE, false)
		star.name = "Star%d" % i

	# Arrow on the ground showing which way this character is pulling in a chain.
	_effort_arrow = Node3D.new()
	_effort_arrow.position.y = 0.06
	_effort_arrow.visible = false
	add_child(_effort_arrow)
	var arrow_mat := Toon.unshaded(team_color)
	Toon.part(_effort_arrow, Toon.box(Vector3(0.12, 0.02, 0.6)), arrow_mat, Vector3(0, 0, 0.75), Vector3.ZERO, Vector3.ONE, false)
	Toon.part(_effort_arrow, Toon.cylinder(0.0, 0.2, 0.3, 3), arrow_mat, Vector3(0, 0, 1.15), Vector3(90, 0, 0), Vector3(1, 1, 0.15), false)


func _update_status_visuals(delta: float) -> void:
	var down := is_down()
	if _was_down and not down:
		_get_up()
	_was_down = down
	_stars.visible = down
	if down:
		_stars.rotation.y += delta * 6.0
	# Blink while recovering so the protection is visible.
	model.visible = not is_recovering() or int(now() * 10.0) % 2 == 0
	_bubble.visible = is_immortal()
	if _bubble.visible:
		var pulse := 1.0 + sin(now() * 8.0) * 0.04
		_bubble.scale = Vector3(0.75, 1.0, 0.75) * pulse
		# Flash when about to run out.
		_bubble.visible = immortal_time_left() > 1.0 or int(now() * 8.0) % 2 == 0
	var pull := pull_force()
	_effort_arrow.visible = in_chain and pull.length() > 0.1
	if _effort_arrow.visible:
		_effort_arrow.rotation.y = atan2(pull.x, pull.z)

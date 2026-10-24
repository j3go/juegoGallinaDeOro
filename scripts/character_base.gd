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
var _tug_dust_at := 0.0
var _effort_at := 0.0
var _dazed_until := -1.0
var _was_dazed := false

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


## Thrown to the ground at the end of a grab: lying there with stars until it gets up.
func is_dazed() -> bool:
	return now() < _dazed_until


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


## Rivals linked to this character: first the one it grabbed, then those grabbing it.
func grab_partners() -> Array[CharacterBase]:
	var partners: Array[CharacterBase] = []
	if outgoing_link != null:
		partners.append(outgoing_link.to)
	for l in incoming_links:
		partners.append(l.from)
	return partners


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


## Called by GrabSystem when a link involving this character starts.
func grab_started(initiator: bool) -> void:
	model.play_grab_start(initiator)
	if ctx:
		Effects.floating_text(ctx.world_root, global_position + Vector3.UP * 1.6, "!", Color(1.0, 0.85, 0.3))


## Called by GrabSystem when a link involving this character ends.
func grab_ended() -> void:
	if is_linked() or is_down() or is_dazed():
		return
	model.play_grab_release()
	if ctx:
		Effects.dust_puff(ctx.world_root, global_position, 6)


## The grab ran out and `thrower` slams this character to the ground: it flies back a little,
## lands on its back and stays dazed (no moving or acting, eggs kept). Returns false if it
## can't be thrown (immortal, already down or the stun is disabled).
func throw_down(thrower: CharacterBase) -> bool:
	if config.grab_throw_stun <= 0.0 or is_immortal() or is_down():
		return false
	var away := global_position - thrower.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -thrower.facing_direction()
	_dazed_until = now() + config.grab_throw_stun
	_stun_until = maxf(_stun_until, _dazed_until)
	_motion = Vector3.ZERO
	_external = away * 3.5 + Vector3.UP * 3.5
	model.set_dazed(true)
	# Fall backwards, away from the thrower, and bounce on landing.
	model.rotation.y = atan2(-away.x, -away.z)
	var tw := model.create_tween()
	tw.tween_property(model, "rotation:x", -1.5, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(model, "position:y", 0.3, 0.3)
	tw.tween_callback(func() -> void:
		if ctx:
			Effects.dust_puff(ctx.world_root, global_position, 8))
	Sfx.play_3d(self, Sfx.HIT, global_position, -4.0)
	status_changed.emit(self)
	return true


## Won a grab: short cheer with the arms up.
func cheer() -> void:
	model.play_cheer(0.9)


func facing_direction() -> Vector3:
	return Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))


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
	# In a grab, look at the rival you are struggling with.
	var partners := grab_partners()
	if not partners.is_empty():
		direction = partners[0].global_position - global_position
	if is_down() or is_dazed() or Vector2(direction.x, direction.z).length_squared() < 0.0004:
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
	if _was_down and not down and not is_dazed():
		_get_up()
	_was_down = down
	var dazed := is_dazed()
	if _was_dazed and not dazed:
		model.set_dazed(false)
		if not down:
			_get_up()
	_was_dazed = dazed
	_stars.visible = down or dazed
	if _stars.visible:
		_stars.rotation.y += delta * 6.0
		# Lying on its back: the stars circle over the head, not over the feet.
		var back := -facing_direction()
		_stars.position = back * 0.95 + Vector3.UP * 0.75
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
	_update_grab_pose()


## Wrestling clinch: arms wrapped around the rival, heads pressed together and swaying. When the
## grabber is winning it lifts the grabbed one off the ground (legs kicking); a grabber losing the
## tug gets dragged onto its belly. Effort bursts fly off while both strain.
func _update_grab_pose() -> void:
	var partners := grab_partners()
	if partners.is_empty() or is_down():
		model.set_grab([], 0.0, 0.0, 0.0)
		return
	var to_partner := partners[0].global_position - global_position
	to_partner.y = 0.0
	to_partner = to_partner.normalized()
	var targets: Array[Vector3] = []
	if partners.size() == 1:
		# Both arms around the rival's sides (a little behind them), lifted if the rival is up.
		var p := partners[0]
		var side := Vector3.UP.cross(to_partner)
		var height := global_position.y + 0.68 + p.model.lift_amount() * 0.45
		for s: float in [-1.0, 1.0]:
			var hand := p.global_position + side * s * 0.24 + to_partner * 0.06
			targets.append(Vector3(hand.x, height, hand.z))
	else:
		for p: CharacterBase in partners.slice(0, 2):
			var mid := (global_position + p.global_position) * 0.5
			targets.append(Vector3(mid.x, global_position.y + 0.68, mid.z))
	var pull := pull_force().dot(to_partner)
	var strain := clampf(0.45 - pull, 0.0, 1.0)
	var dragged := 0.0
	if pull < 0.3:
		dragged = clampf((chain_velocity.dot(to_partner) - 0.6) / 1.6, 0.0, 1.0)
	# Only being grabbed: the winner lifts you up instead of dragging you on the floor.
	var lifted := dragged if outgoing_link == null else 0.0
	model.set_grab(targets, strain, dragged - lifted, lifted)
	if not ctx:
		return
	# Dust kicked up by heels digging in or a body sliding on the ground.
	if now() >= _tug_dust_at and (dragged - lifted > 0.5 or (strain > 0.8 and horizontal_speed() > 0.5)):
		_tug_dust_at = now() + 0.2
		Effects.dust_puff(ctx.world_root, global_position, 3)
	if outgoing_link != null and now() >= _effort_at:
		_effort_at = now() + randf_range(0.35, 0.6)
		Effects.effort_burst(ctx.world_root, (global_position + partners[0].global_position) * 0.5 + Vector3.UP * 1.25)

class_name NPCAI
extends CharacterBase
## Rival for the design doc v0.1 rules. Every "think" (with a reaction delay) it picks a goal:
## dodge the laser, use its item, grab or push a rival, fetch an item or the best egg, or circle
## the chicken. Pickups need an explicit press, so it presses when close enough (and is free of
## grabs). While in a chain it keeps pulling towards its own goal, so chains really fight.

enum Goal { WANDER, EGG, ITEM, DODGE }

const ACCELERATION := 22.0
const EYE_HEIGHT := 1.3

@export var profile: NPCProfile

var goal: Goal = Goal.WANDER
var goal_point := Vector3.ZERO
## Set by tests: AI doesn't think or steer, `move_input` is driven from outside.
var scripted := false

var _goal_egg: GoldenEgg = null
var _goal_item: ItemPickup = null
var _think_at := 0.0
var _goal_until := 0.0
var _stuck_timer := 0.0
var _stuck_pos := Vector3.ZERO
var _speed_seed := 0.0

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var name_tag: Label3D = $NameTag
@onready var alert: Label3D = $Alert


func _ready() -> void:
	if profile:
		display_name = profile.display_name
		team_color = profile.team_color
		model.set_costume(profile.costume)
	super._ready()
	name_tag.text = display_name
	name_tag.font = UITheme.font()
	name_tag.modulate = team_color.lightened(0.15)
	alert.font = UITheme.font()
	alert.visible = false
	_speed_seed = randf() * TAU
	model.rotation.y = PI


func set_active(active: bool) -> void:
	super.set_active(active)
	if active:
		_set_goal(Goal.WANDER, _wander_point())


func get_state_name() -> String:
	return Goal.keys()[goal]


func _physics_process(delta: float) -> void:
	if is_active and not scripted and ctx:
		if now() >= _think_at:
			_think_at = now() + _reaction_delay() * 0.6
			if can_act():
				_think()
		_continuous_actions()
		move_input = _steer()
		_check_stuck(delta)
	var speed := profile.move_speed * (1.0 + sin(now() * 0.7 + _speed_seed) * 0.05)
	if goal == Goal.WANDER:
		speed *= profile.wander_speed_factor
	_move_body(delta, move_input * speed, ACCELERATION)
	_face_direction(move_input, delta, 10.0)
	model.animate(delta, horizontal_speed(), is_on_floor())


# --- Decisions -------------------------------------------------------------------------------

func _think() -> void:
	var chicken := ctx.chicken
	# 1. The laser: step out of the line (or turn on immortality if we're the one targeted).
	if chicken.is_warning():
		var line_distance := chicken.distance_to_line(global_position)
		var danger := line_distance < ctx.config.egg_radius + 0.9
		if danger and item == Item.IMMORTALITY and chicken.state == Chicken.State.LOCK:
			use_item(get_forward())
			return
		if danger and randf() < profile.dodge_skill:
			_set_goal(Goal.DODGE, _dodge_point(), 1.2)
			_show_alert("!")
			return
	if goal == Goal.DODGE and now() < _goal_until:
		return
	# 2. Throw the kunai at the richest rival in sight.
	if item == Item.KUNAI and outgoing_link == null:
		var victim := _richest_rival_in_sight(11.0)
		if victim:
			var aim := _flat(victim.global_position - global_position).normalized()
			var error := deg_to_rad(randf_range(-1.0, 1.0) * (1.0 - profile.aim_skill) * 14.0)
			_face_now(aim)
			use_item(aim.rotated(Vector3.UP, error))
			return
	if item == Item.IMMORTALITY and score >= 3 and chicken.is_warning() and chicken.target == self:
		use_item(get_forward())
		return
	# 3. Rough play: shove a rival into the laser, or grab one who is about to pick up an egg.
	if outgoing_link == null and randf() < profile.aggression:
		if _try_shove_into_laser() or _try_grab_egg_thief() or _try_push_competitor():
			return
	# 4. Pick a goal: item, egg or wander around the chicken.
	var egg := _best_egg()
	var pickup := _nearest_item() if item == Item.NONE else null
	var egg_distance := _flat_distance(egg.global_position) if egg else INF
	if pickup and _flat_distance(pickup.global_position) < egg_distance * 0.8:
		_goal_item = pickup
		_set_goal(Goal.ITEM, pickup.global_position)
	elif egg:
		_goal_egg = egg
		_set_goal(Goal.EGG, egg.global_position)
	elif goal != Goal.WANDER or agent.is_navigation_finished():
		_set_goal(Goal.WANDER, _wander_point())


## Pickup presses and other things checked every frame (not only on "think").
func _continuous_actions() -> void:
	if not can_act():
		return
	match goal:
		Goal.EGG:
			if not (is_instance_valid(_goal_egg) and _goal_egg.is_available()):
				_think_at = minf(_think_at, now() + 0.15)
			elif _flat_distance(_goal_egg.global_position) < ctx.config.pickup_radius * 0.85 and can_pick_eggs():
				try_pickup()
		Goal.ITEM:
			if not (is_instance_valid(_goal_item) and _goal_item.is_available()) or item != Item.NONE:
				_think_at = minf(_think_at, now() + 0.15)
			elif _flat_distance(_goal_item.global_position) < ctx.config.pickup_radius * 0.85:
				try_pickup()


func _try_shove_into_laser() -> bool:
	var chicken := ctx.chicken
	if not chicken.is_warning() or now() < push_ready_at:
		return false
	for other in ctx.competitors:
		if other == self or not other.can_act():
			continue
		var to := _flat(other.global_position - global_position)
		if to.length() > ctx.config.push_range * 0.9:
			continue
		# Push only if it moves them towards the line and we're not in it ourselves.
		var before := chicken.distance_to_line(other.global_position)
		var after := chicken.distance_to_line(other.global_position + to.normalized() * 1.5)
		if after < before and after < 1.2 and chicken.distance_to_line(global_position) > 1.0:
			_face_now(to.normalized())
			return try_push()
	return false


func _try_grab_egg_thief() -> bool:
	if now() < grab_ready_at:
		return false
	for other in ctx.competitors:
		if other == self or not other.can_act() or other.is_linked():
			continue
		var to := _flat(other.global_position - global_position)
		if to.length() > ctx.config.grab_range * 0.95:
			continue
		# Being grabbed stops them from picking up eggs (and makes them target material).
		var near_egg := ctx.egg_manager.nearest_available(other.global_position, 2.0) != null
		var is_leader := ctx.chicken.target == other and ctx.chicken.is_warning()
		if near_egg or is_leader:
			_face_now(to.normalized())
			if try_grab():
				_show_alert("¡Te agarré!")
				return true
	return false


func _try_push_competitor() -> bool:
	if now() < push_ready_at or goal != Goal.EGG or not is_instance_valid(_goal_egg):
		return false
	for other in ctx.competitors:
		if other == self or not other.can_act():
			continue
		var to := _flat(other.global_position - global_position)
		# Shove whoever stands between us and our egg.
		if to.length() < ctx.config.push_range * 0.9 \
				and other.global_position.distance_to(_goal_egg.global_position) < global_position.distance_to(_goal_egg.global_position):
			_face_now(to.normalized())
			return try_push()
	return false


func _best_egg() -> GoldenEgg:
	var best: GoldenEgg = null
	var best_cost := INF
	var candidates: Array[GoldenEgg] = []
	for egg in ctx.egg_manager.get_available_eggs():
		var d := _flat_distance(egg.global_position)
		if d > profile.detection_radius:
			continue
		var cost := d
		for other in ctx.competitors:
			if other != self and _flat(other.global_position - egg.global_position).length() + 2.0 < d:
				cost += profile.rival_awareness * 4.0
		candidates.append(egg)
		if cost < best_cost:
			best_cost = cost
			best = egg
	if candidates.size() > 1 and randf() < profile.mistake_chance:
		return candidates.pick_random()
	return best


func _nearest_item() -> ItemPickup:
	var best: ItemPickup = null
	var best_d := profile.detection_radius * 1.3
	for pickup in ctx.item_manager.get_items():
		var d := _flat_distance(pickup.global_position)
		if d < best_d:
			best = pickup
			best_d = d
	return best


func _richest_rival_in_sight(max_distance: float) -> CharacterBase:
	var best: CharacterBase = null
	for other in ctx.competitors:
		if other == self or other.score <= 0 or other.is_down() or other.is_immortal():
			continue
		if _flat_distance(other.global_position) > max_distance:
			continue
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * EYE_HEIGHT, other.global_position + Vector3.UP, 1)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		if best == null or other.score > best.score:
			best = other
	return best


func _dodge_point() -> Vector3:
	var chicken := ctx.chicken
	var side := chicken.aim_direction.cross(Vector3.UP).normalized()
	var rel := _flat(global_position - chicken.global_position)
	if rel.dot(side) < 0.0:
		side = -side
	return ctx.level.snap_to_ground(global_position + side * 2.6, global_position)


func _wander_point() -> Vector3:
	# Circle the chicken at a safe-ish distance (the leader stays further away).
	var radius := randf_range(5.0, 9.0) + (3.0 if _is_leader() else 0.0)
	return ctx.level.random_point_near(ctx.chicken.global_position, radius - 1.5, radius + 1.5)


func _is_leader() -> bool:
	for other in ctx.competitors:
		if other != self and other.score >= score:
			return false
	return score > 0


func _set_goal(new_goal: Goal, point: Vector3, hold: float = 0.0) -> void:
	goal = new_goal
	_goal_until = now() + hold
	if point.distance_to(goal_point) > 0.4 or agent.is_navigation_finished():
		goal_point = point
		agent.target_position = point


# --- Steering ----------------------------------------------------------------------------------

func _steer() -> Vector3:
	if not can_act():
		return Vector3.ZERO
	var target := goal_point
	if goal == Goal.EGG and is_instance_valid(_goal_egg):
		target = _goal_egg.global_position
	if _flat_distance(target) < 0.7:
		return Vector3.ZERO
	var next := target if _flat_distance(target) < 1.5 else agent.get_next_path_position()
	if agent.is_navigation_finished() and _flat_distance(target) > 1.5:
		next = target
	var to := _flat(next - global_position)
	return to.normalized() if to.length() > 0.05 else Vector3.ZERO


func _check_stuck(delta: float) -> void:
	if move_input.length() < 0.1 or in_chain:
		_stuck_timer = 0.0
		_stuck_pos = global_position
		return
	_stuck_timer += delta
	if _stuck_timer < 1.2:
		return
	if global_position.distance_to(_stuck_pos) < 0.35:
		_set_goal(Goal.WANDER, _wander_point())
	_stuck_timer = 0.0
	_stuck_pos = global_position


func _face_now(direction: Vector3) -> void:
	model.rotation.y = atan2(direction.x, direction.z)


func _reaction_delay() -> float:
	return maxf(0.05, profile.reaction_time + randf_range(-profile.reaction_jitter, profile.reaction_jitter))


func _flat_distance(point: Vector3) -> float:
	return Vector2(global_position.x - point.x, global_position.z - point.z).length()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _show_alert(text: String) -> void:
	alert.text = text
	alert.visible = true
	alert.scale = Vector3.ONE * 0.2
	var tw := alert.create_tween()
	tw.tween_property(alert, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_callback(alert.hide)

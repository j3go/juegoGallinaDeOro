class_name GrabSystem
extends Node3D
## Grab links and chains (design doc v0.1, confirmed rules):
## - Each link lasts `grab_duration` (3 s) from its own start; links end independently.
## - The initiator can start another grab `grab_duration + grab_cooldown` (13 s) after starting.
## - Characters joined by links form a chain. Every member adds its pull ONCE in its input
##   direction (world space): force 1 if it is grabbing someone, `grabbed_pull_weight` if it is
##   only being grabbed, so a grabber drags its victim without much resistance. The chain moves
##   with the sum: equal opposite pulls cancel, pulls in the same direction add up (with a top
##   speed), uneven ones favour the larger side.

class GrabLink:
	var from: CharacterBase
	var to: CharacterBase
	var started := 0.0
	var ends := 0.0
	var length := 1.0

signal link_started(link: GrabLink)
signal link_ended(link: GrabLink)

var links: Array[GrabLink] = []
var _config: GameConfig
var _competitors: Array[CharacterBase] = []


func _ready() -> void:
	# Runs before the characters so they move with this frame's chain velocity.
	process_physics_priority = -10


func setup(config: GameConfig, competitors: Array[CharacterBase]) -> void:
	_config = config
	_competitors = competitors


func create_link(from: CharacterBase, to: CharacterBase) -> bool:
	if from == to or from.outgoing_link != null:
		return false
	for l in links:
		if (l.from == from and l.to == to) or (l.from == to and l.to == from):
			return false
	var link := GrabLink.new()
	link.from = from
	link.to = to
	link.started = GameClock.now
	link.ends = link.started + _config.grab_duration
	# Keep the current distance as rope length so joining never makes anyone jump.
	link.length = maxf(0.8, _flat(to.global_position - from.global_position).length())
	links.append(link)
	from.outgoing_link = link
	to.incoming_links.append(link)
	# The cooldown starts when the grab ends: next grab 13 s after this one started.
	from.grab_ready_at = link.started + _config.grab_duration + _config.grab_cooldown
	Sfx.play_3d(self, Sfx.GRAB, to.global_position, -3.0)
	from.grab_started(true)
	to.grab_started(false)
	from.status_changed.emit(from)
	to.status_changed.emit(to)
	link_started.emit(link)
	return true


## Releases every link involving `character` (e.g. knocked down). Other links keep their timers,
## and the initiators keep their original next-use time.
func release_links_of(character: CharacterBase) -> void:
	for l in links.duplicate():
		if l.from == character or l.to == character:
			_end_link(l)


func release_all() -> void:
	for l in links.duplicate():
		_end_link(l)


func time_left(link: GrabLink) -> float:
	return maxf(0.0, link.ends - GameClock.now)


## Connected groups of linked characters (only groups of 2 or more).
func get_chains() -> Array:
	var neighbours := {}
	for l in links:
		neighbours.get_or_add(l.from, []).append(l.to)
		neighbours.get_or_add(l.to, []).append(l.from)
	var seen := {}
	var chains := []
	for start: CharacterBase in neighbours:
		if seen.has(start):
			continue
		var chain: Array[CharacterBase] = []
		var stack: Array = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: CharacterBase = stack.pop_back()
			chain.append(c)
			for n: CharacterBase in neighbours[c]:
				if not seen.has(n):
					seen[n] = true
					stack.append(n)
		chains.append(chain)
	return chains


## Sum of the members' pulls; each member counts once even if it grabs and is grabbed.
func chain_force(chain: Array[CharacterBase]) -> Vector3:
	var net := Vector3.ZERO
	for c in chain:
		net += c.pull_force() * pull_weight(c)
	return net


## Grabbers pull with force 1; characters that are only being grabbed resist weakly.
func pull_weight(c: CharacterBase) -> float:
	return 1.0 if c.outgoing_link != null else _config.grabbed_pull_weight


func _physics_process(_delta: float) -> void:
	for l in links.duplicate():
		if GameClock.now >= l.ends:
			_end_link(l)
	for c in _competitors:
		c.in_chain = false
		c.chain_velocity = Vector3.ZERO
	for chain: Array[CharacterBase] in get_chains():
		var velocity := (chain_force(chain) * _config.pull_speed).limit_length(_config.chain_max_speed)
		for c in chain:
			c.in_chain = true
			c.chain_velocity = velocity
	# Soft rope: if collisions stretch a link, gently pull both ends back together.
	for l in links:
		var d := _flat(l.to.global_position - l.from.global_position)
		var stretch := d.length() - l.length
		if stretch > 0.15:
			var fix := d.normalized() * minf(stretch * 4.0, 3.0)
			l.from.chain_velocity += fix * 0.5
			l.to.chain_velocity -= fix * 0.5


func _end_link(link: GrabLink) -> void:
	links.erase(link)
	if link.from.outgoing_link == link:
		link.from.outgoing_link = null
	link.to.incoming_links.erase(link)
	link.from.grab_ended()
	link.to.grab_ended()
	link.from.status_changed.emit(link.from)
	link.to.status_changed.emit(link.to)
	link_ended.emit(link)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

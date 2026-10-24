class_name MatchContext
extends RefCounted
## Everything a character needs to interact with the match, passed once at setup.

var config: GameConfig
var level: Level
var egg_manager: EggManager
var item_manager: ItemManager
var grab_system: GrabSystem
var chicken: Chicken
var competitors: Array[CharacterBase] = []
## Node where projectiles and effects are spawned.
var world_root: Node3D

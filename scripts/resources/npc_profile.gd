class_name NPCProfile
extends Resource
## Look and personality of a rival. Small differences make each NPC play differently.

@export_group("Apariencia")
@export var display_name := "Rival"
## Costume from personajes.png.
@export var costume: HumanModel.Costume = HumanModel.Costume.CONE
## Color used for the name tag, HUD and score rows.
@export var team_color := Color(0.9, 0.4, 0.4)

@export_group("Movimiento")
@export var move_speed := 6.5
## Fraction of move_speed used while wandering without a target.
@export_range(0.3, 1.0) var wander_speed_factor := 0.7

@export_group("Percepción")
## Max distance at which eggs can be spotted (needs line of sight beyond close range).
@export var detection_radius := 10.0
## Chance of noticing a visible egg on each scan.
@export_range(0.0, 1.0) var notice_chance := 0.85
@export var scan_interval := 0.4
## Distance at which the NPC hears the chicken lay an egg.
@export var hearing_radius := 12.0
@export_range(0.0, 1.0) var hearing_chance := 0.7

@export_group("Decisiones")
@export var reaction_time := 0.45
@export var reaction_jitter := 0.2
## Chance of picking a random known egg instead of the best one.
@export_range(0.0, 1.0) var mistake_chance := 0.12
## How much the NPC avoids eggs a rival is clearly closer to.
@export_range(0.0, 1.0) var rival_awareness := 0.6
## Chance of wandering towards the chicken instead of a random spot.
@export_range(0.0, 1.0) var chicken_follow_chance := 0.35

@export_group("Combate (diseño v0.1)")
## How often it pushes or grabs rivals when there is a chance.
@export_range(0.0, 1.0) var aggression := 0.5
## Chance of noticing the laser and stepping out of the line.
@export_range(0.0, 1.0) var dodge_skill := 0.7
## Kunai accuracy (1 = perfect aim).
@export_range(0.0, 1.0) var aim_skill := 0.7

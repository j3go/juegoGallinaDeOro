class_name GameConfig
extends Resource
## Tunable values for a match (design doc v0.1). Edit assets/config/default_config.tres to tweak.
## Values marked "confirmado" in the design doc: 3 s grab, 10 s cooldown after it ends.

@export_group("Partida")
@export var match_duration := 180.0
@export var countdown_seconds := 3
@export var egg_points := 1

@export_group("Gallina")
## Pause between attacks.
@export var attack_interval_min := 2.5
@export var attack_interval_max := 4.0
## The laser follows the target for this long...
@export var aim_time := 1.8
## ...then stays fixed this long before the shot.
@export var lock_time := 0.6
@export var recover_time := 0.7
@export var egg_speed := 14.0
@export var egg_range := 26.0
## Radius of the flying egg (also the width shown by the laser).
@export var egg_radius := 0.32

@export_group("Impactos")
## Share of carried eggs dropped when hit (1 = all). The doc suggests testing partial losses.
@export_range(0.0, 1.0) var egg_hit_drop_fraction := 1.0
@export_range(0.0, 1.0) var kunai_drop_fraction := 1.0
@export var knockdown_time := 1.4
## Protection after getting up: no actions, and hits don't cause new losses.
@export var recovery_time := 1.6
@export var kunai_stun_time := 0.4
@export var drop_scatter_radius := 3.0

@export_group("Recogida")
@export var pickup_radius := 1.5

@export_group("Empujón")
@export var push_range := 1.9
@export var push_angle_deg := 70.0
@export var push_force := 9.0
@export var push_cooldown := 1.0

@export_group("Agarre")
@export var grab_range := 1.7
@export var grab_duration := 3.0
## Starts when the grab ends (so the next grab is possible 13 s after starting one).
@export var grab_cooldown := 10.0
## Chain speed per unit of net pulling force (every participant pulls with force 1).
@export var pull_speed := 2.6
## Joint force doesn't multiply speed without limit.
@export var chain_max_speed := 4.0

@export_group("Objetos")
@export var first_wave_delay := 15.0
@export var wave_interval := 30.0
@export var items_per_wave := 3
@export var max_ground_items := 6
@export var kunai_speed := 20.0
@export var kunai_range := 18.0
@export var immortality_time := 5.0

@export_group("Jugador")
@export var player_walk_speed := 5.0
@export var player_run_speed := 7.5
@export var player_acceleration := 30.0
@export var player_deceleration := 40.0
@export var jump_velocity := 7.5
@export var mouse_sensitivity := 0.0025

@export_group("Física")
@export var gravity := 22.0

class_name AudioSettings
extends RefCounted
## Player's sound preferences: general, music and effects volumes plus mute. Music and effects
## get their own buses (created here) under Master. Saved to user://settings.cfg.

const PATH := "user://settings.cfg"
const SECTION := "sonido"
const MAX_VOLUME := 1.5
## Bus name -> saved key. "Master" is the general volume.
const BUSES := {"Master": "volumen", "Music": "musica", "SFX": "efectos"}
const DEFAULTS := {"Master": 1.0, "Music": 0.7, "SFX": 1.0}

static var volumes := DEFAULTS.duplicate()
static var muted := false


## Creates the buses, reads the saved settings (if any) and applies them. Call once at startup.
static func load_and_apply() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for bus: String in BUSES:
			volumes[bus] = clampf(float(cfg.get_value(SECTION, BUSES[bus], DEFAULTS[bus])), 0.0, MAX_VOLUME)
		muted = bool(cfg.get_value(SECTION, "silencio", false))
	apply()


static func get_volume(bus: String) -> float:
	return volumes[bus]


static func set_volume(bus: String, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, MAX_VOLUME)
	apply()


static func set_muted(value: bool) -> void:
	muted = value
	apply()


static func apply() -> void:
	for bus: String in BUSES:
		var index := AudioServer.get_bus_index(bus)
		if index == -1:
			continue
		var value: float = volumes[bus]
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
		AudioServer.set_bus_mute(index, value <= 0.001 or (muted and bus == "Master"))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # keep any other sections
	for bus: String in BUSES:
		cfg.set_value(SECTION, BUSES[bus], volumes[bus])
	cfg.set_value(SECTION, "silencio", muted)
	cfg.save(PATH)

class_name LBAAudioBuses
extends Node

const SETTINGS_PATH := "user://lba1-godot.cfg"
const DEFAULT_LEVELS := {
	&"master_volume": 255,
	&"music_volume": 255,
	&"sound_volume": 255,
	&"speech_volume": 255,
	&"cinematic_volume": 179,
}
const BUS_NAMES := {
	&"master_volume": &"Master",
	&"music_volume": &"LBA Music",
	&"sound_volume": &"LBA Sound",
	&"speech_volume": &"LBA Speech",
	&"cinematic_volume": &"LBA Cinematics",
}

var levels: Dictionary = DEFAULT_LEVELS.duplicate()
var wall_collision_damage: bool = false
var grid_lighting_enabled: bool = true


func _ready() -> void:
	_ensure_bus(&"LBA Music", &"Master")
	_ensure_bus(&"LBA Sound", &"Master")
	_ensure_bus(&"LBA Speech", &"Master")
	# The native port applies cinematic * music * master to premixed FMV audio.
	_ensure_bus(&"LBA Cinematics", &"LBA Music")
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		for key in DEFAULT_LEVELS:
			levels[key] = clampi(int(settings.get_value("audio", str(key), DEFAULT_LEVELS[key])), 0, 255)
		wall_collision_damage = bool(settings.get_value("gameplay", "wall_collision_damage", false))
		grid_lighting_enabled = bool(settings.get_value("graphics", "grid_lighting_enabled", true))
	for key in levels:
		_apply_level(key)


func set_setting(key: StringName, value: Variant) -> void:
	if key == &"wall_collision_damage":
		wall_collision_damage = bool(value)
	elif key == &"grid_lighting_enabled":
		grid_lighting_enabled = bool(value)
	elif levels.has(key):
		levels[key] = clampi(int(roundf(float(value))), 0, 255)
		_apply_level(key)
	else:
		return
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	for level in levels:
		settings.set_value("audio", str(level), levels[level])
	settings.set_value("gameplay", "wall_collision_damage", wall_collision_damage)
	settings.set_value("graphics", "grid_lighting_enabled", grid_lighting_enabled)
	if settings.save(SETTINGS_PATH) != OK:
		push_error("Could not save LBA1 audio settings")


func _ensure_bus(name: StringName, send: StringName) -> void:
	var index := AudioServer.get_bus_index(name)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, str(name))
	AudioServer.set_bus_send(index, send)


func _apply_level(key: StringName) -> void:
	var index := AudioServer.get_bus_index(BUS_NAMES[key])
	if index != -1:
		AudioServer.set_bus_volume_linear(index, float(levels[key]) / 255.0)

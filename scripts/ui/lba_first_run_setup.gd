class_name LBAFirstRunSetup
extends Control

signal import_settings_requested

func _ready() -> void:
	($Center/Panel/Content/OpenSettings as Button).pressed.connect(
		func() -> void: import_settings_requested.emit())

@tool
extends EditorPlugin

var _companion_export: EditorExportPlugin


func _enter_tree() -> void:
	_companion_export = preload("res://addons/lba_build_companions/export_companions.gd").new()
	add_export_plugin(_companion_export)


func _exit_tree() -> void:
	if _companion_export != null:
		remove_export_plugin(_companion_export)
		_companion_export = null

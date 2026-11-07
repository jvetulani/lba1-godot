extends Node3D

# An isolated rendering check. This scene does not start native gameplay.
@onready var _world: LBAWorld3D = $World3D


func _ready() -> void:
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	if data_dir.is_empty():
		data_dir = ProjectSettings.globalize_path("user://lba1-native/data")
	if not FileAccess.file_exists(data_dir.path_join("lba_gri.hqr")):
		push_error("Import original LBA1 data or set LBA_TEST_DATA_PATH to preview the world")
		return
	if not _world.load_grid_scene(0, data_dir):
		return
	if _world.set_actor_body(0, 0, data_dir):
		_world.set_actor_native_state(0, 32 * 512, 2 * 256, 32 * 512, 0)

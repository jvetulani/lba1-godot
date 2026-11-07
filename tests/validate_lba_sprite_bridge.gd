extends SceneTree

const SPRITES := preload("res://scripts/render/lba_sprite_renderer.gd")


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("user://lba_sprite_fixture")
	DirAccess.make_dir_recursive_absolute(dir)
	var palette := PackedByteArray()
	palette.resize(768)
	for color in range(256):
		palette[color * 3] = color
		palette[color * 3 + 1] = color
		palette[color * 3 + 2] = color
	var sprite := PackedByteArray([4, 0, 0, 0, 2, 1, 0, 0, 1, 0x41, 15, 0])
	_write_hqr(dir.path_join("ress.hqr"), palette)
	_write_hqr(dir.path_join("sprites.hqr"), sprite)
	var renderer := SPRITES.new()
	var first: MeshInstance3D = renderer.create_instance(dir, 0, 3, -4)
	assert(first != null, "Sprite HQR did not decode")
	assert(first.material_override != null, "Sprite material missing")
	assert(first.mesh is QuadMesh, "Sprite should be a reusable quad")
	var second: MeshInstance3D = renderer.create_instance(dir, 0)
	assert(second != null and second.mesh == first.mesh, "Sprite topology was rebuilt")
	assert(second.material_override == first.material_override, "Sprite material was rebuilt")
	var special: MeshInstance3D = renderer.create_special_effect(0)
	assert(special.mesh != null, "Hit star visual missing")
	print("PASS LBA sprite HQR, cache and hit effect")
	first.free()
	second.free()
	special.free()
	quit(0)


func _write_hqr(path: String, payload: PackedByteArray) -> void:
	var bytes := PackedByteArray()
	bytes.resize(14)
	bytes.encode_u32(0, 4)
	bytes.encode_u32(4, payload.size())
	bytes.encode_u32(8, payload.size())
	bytes.encode_u16(12, 0)
	bytes.append_array(payload)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(bytes)
	file.close()

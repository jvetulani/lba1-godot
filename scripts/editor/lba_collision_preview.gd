@tool
extends Node3D

# The .tscn serializer preserves MultiMesh instance counts, but not the
# individual per-instance transforms. Restore them from compact grid indices
# whenever an authored LBA location is opened in the Godot editor.
const GRID := preload("res://scripts/import/lba1_grid_decoder.gd")
const COORD := preload("res://scripts/render/lba_coordinates.gd")

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	for child in get_children():
		if not (child is MultiMeshInstance3D):
			continue
		if not child.has_meta("lba_cell_indices"):
			continue
		var indices: PackedInt32Array = child.get_meta("lba_cell_indices")
		var mm: MultiMesh = child.multimesh
		if mm == null:
			continue
		if mm.instance_count != indices.size():
			mm.instance_count = indices.size()
		for j in range(indices.size()):
			var index: int = indices[j]
			var z: int = index / (GRID.WIDTH * GRID.HEIGHT)
			var x: int = (index / GRID.HEIGHT) % GRID.WIDTH
			var y: int = index % GRID.HEIGHT
			mm.set_instance_transform(j, Transform3D(Basis.IDENTITY, COORD.grid_cell(x, y, z)))
		# Explicit scene-wide bounds also avoid editor frustum culling problems.
		mm.custom_aabb = AABB(Vector3(-0.1, -0.1, -0.1),
			Vector3(GRID.WIDTH * COORD.CELL_XZ + 0.2,
			GRID.HEIGHT * COORD.CELL_Y + 0.2,
			GRID.DEPTH * COORD.CELL_XZ + 0.2))

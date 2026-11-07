class_name LBA1GridDecoder
extends RefCounted

# GRI columns and BLL block cells follow lba1-native/engine/game/GRILLE.C
# and GRILLE_A.C. This decodes authored scene data; gameplay state remains native.
const HQR := preload("res://scripts/import/hqr_reader.gd")
const WIDTH := 64
const HEIGHT := 25
const DEPTH := 64
const COLUMN_COUNT := WIDTH * DEPTH
const CELL_COUNT := COLUMN_COUNT * HEIGHT


static func read_scene(data_dir: String, scene_index: int) -> Dictionary:
	var grid_entry: Dictionary = HQR.read_entry(data_dir.path_join("lba_gri.hqr"), scene_index)
	if not grid_entry.get("ok", false):
		return _error("GRI scene %d: %s" % [scene_index, grid_entry.get("error", "unavailable")])
	var blocks_entry: Dictionary = HQR.read_entry(data_dir.path_join("lba_bll.hqr"), scene_index)
	if not blocks_entry.get("ok", false):
		return _error("BLL scene %d: %s" % [scene_index, blocks_entry.get("error", "unavailable")])
	return decode(grid_entry["data"], blocks_entry["data"])


static func decode(grid: PackedByteArray, blocks: PackedByteArray) -> Dictionary:
	if grid.size() < COLUMN_COUNT * 2:
		return _error("GRI column table is truncated")
	if blocks.size() < 8:
		return _error("BLL block table is truncated")
	var block_table_bytes := int(blocks.decode_u32(0))
	if block_table_bytes < 8 or block_table_bytes % 4 != 0 or block_table_bytes > blocks.size():
		return _error("BLL block table size is invalid")
	var block_count := block_table_bytes / 4
	var block_offsets := PackedInt32Array()
	block_offsets.resize(block_count)
	var block_cells := PackedInt32Array()
	block_cells.resize(block_count)
	for block_index in range(block_count):
		var offset := int(blocks.decode_u32(block_index * 4))
		if offset < block_table_bytes or offset > blocks.size() - 3:
			return _error("BLL block %d has an invalid offset" % block_index)
		var cell_total := int(blocks[offset]) * int(blocks[offset + 1]) * int(blocks[offset + 2])
		if cell_total == 0 or cell_total > 256 or offset + 3 + cell_total * 4 > blocks.size():
			return _error("BLL block %d has invalid dimensions" % block_index)
		block_offsets[block_index] = offset
		block_cells[block_index] = cell_total

	# Indexed as y + x * HEIGHT + z * WIDTH * HEIGHT, matching BufCube.
	var cells := PackedInt32Array()
	cells.resize(CELL_COUNT)
	var brick_ids := PackedInt32Array()
	brick_ids.resize(CELL_COUNT)
	brick_ids.fill(-1)
	var occupied_count := 0
	var visible_count := 0
	for z in range(DEPTH):
		for x in range(WIDTH):
			var column_index := x + z * WIDTH
			var read_at := int(grid.decode_u16(column_index * 2))
			if read_at >= grid.size():
				return _error("GRI column %d points outside the archive" % column_index)
			var command_count := int(grid[read_at])
			read_at += 1
			var y := 0
			for command in range(command_count):
				if read_at >= grid.size():
					return _error("GRI column %d is truncated" % column_index)
				var header := int(grid[read_at])
				read_at += 1
				var run_length := (header & 0x3f) + 1
				if y + run_length > HEIGHT:
					return _error("GRI column %d exceeds scene height" % column_index)
				var mode := header & 0xc0
				if mode == 0x40 or mode == 0xc0:
					var word_count := run_length if mode == 0x40 else 1
					if read_at + word_count * 2 > grid.size():
						return _error("GRI column %d cell data is truncated" % column_index)
				for step in range(run_length):
					var cell := 0
					if mode != 0:
						cell = int(grid.decode_u16(read_at + step * 2 if mode == 0x40 else read_at))
					var output_index := y + step + x * HEIGHT + z * WIDTH * HEIGHT
					cells[output_index] = cell
					# The low byte is a 1-based block ID; the high byte alone
					# does not make a visible or collidable block.
					if (cell & 0xff) != 0:
						var block_index := (cell & 0xff) - 1
						var cell_index := cell >> 8
						if block_index < 0 or block_index >= block_count or cell_index >= block_cells[block_index]:
							return _error("GRI column %d references BLL block %d cell %d (block count %d, cell count %d)" % [column_index, block_index, cell_index, block_count, block_cells[block_index] if block_index >= 0 and block_index < block_count else -1])
						occupied_count += 1
						var block_offset := block_offsets[block_index]
						var brick_id := int(blocks.decode_u16(block_offset + 3 + cell_index * 4 + 2))
						if brick_id != 0:
							brick_ids[output_index] = brick_id - 1
							visible_count += 1
				read_at += run_length * 2 if mode == 0x40 else (2 if mode == 0x80 else 0)
				y += run_length
			if y != HEIGHT:
				return _error("GRI column %d has %d cells, expected %d" % [column_index, y, HEIGHT])
	return {
		"ok": true,
		"cells": cells,
		"brick_ids": brick_ids,
		"block_count": block_count,
		"occupied_count": occupied_count,
		"visible_count": visible_count,
	}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

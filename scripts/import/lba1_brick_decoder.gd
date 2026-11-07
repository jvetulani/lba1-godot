class_name LBA1BrickDecoder
extends RefCounted

# The BRK graph RLE matches lba1-native/translate/graph_a.c.
const HQR := preload("res://scripts/import/hqr_reader.gd")


static func read_brick(data_dir: String, brick_index: int, palette: PackedByteArray) -> Dictionary:
	var entry: Dictionary = HQR.read_entry(data_dir.path_join("lba_brk.hqr"), brick_index)
	if not entry.get("ok", false):
		return _error("BRK %d: %s" % [brick_index, entry.get("error", "unavailable")])
	return decode(entry["data"], palette)


static func decode(data: PackedByteArray, palette: PackedByteArray) -> Dictionary:
	if palette.size() < 768:
		return _error("LBA1 palette is truncated")
	if data.size() < 4:
		return _error("BRK header is truncated")
	var width := int(data[0])
	var height := int(data[1])
	if width == 0 or height == 0:
		return _error("BRK dimensions are empty")
	var pixels := PackedByteArray()
	pixels.resize(width * height * 4)
	var read_at := 4
	for y in range(height):
		if read_at >= data.size():
			return _error("BRK line %d is truncated" % y)
		var command_count := int(data[read_at])
		read_at += 1
		var x := 0
		for command in range(command_count):
			if read_at >= data.size():
				return _error("BRK line %d command is truncated" % y)
			var header := int(data[read_at])
			read_at += 1
			var run_length := (header & 0x3f) + 1
			if x + run_length > width:
				return _error("BRK line %d exceeds image width" % y)
			var mode := header & 0xc0
			if mode == 0x40 or mode == 0xc0:
				var color_count := run_length if mode == 0x40 else 1
				if read_at + color_count > data.size():
					return _error("BRK line %d colors are truncated" % y)
			for step in range(run_length):
				if mode != 0:
					var palette_index := int(data[read_at + step if mode == 0x40 else read_at])
					var color_offset := palette_index * 3
					var output_offset := (y * width + x + step) * 4
					for channel in range(3):
						var dac := int(palette[color_offset + channel]) >> 2
						pixels[output_offset + channel] = (dac << 2) | (dac >> 4)
					pixels[output_offset + 3] = 255
			read_at += run_length if mode == 0x40 else (1 if mode == 0x80 else 0)
			x += run_length
		if x != width:
			return _error("BRK line %d has %d pixels, expected %d" % [y, x, width])
	if read_at != data.size():
		return _error("BRK has trailing bytes")
	return {
		"ok": true,
		"image": Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels),
		"width": width,
		"height": height,
		"hot_x": int(data[2]),
		"hot_y": int(data[3]),
	}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

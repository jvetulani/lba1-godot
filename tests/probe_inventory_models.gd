extends SceneTree

const HQR := preload("res://scripts/import/hqr_reader.gd")
const BODY := preload("res://scripts/import/lba1_body_decoder.gd")

func _initialize() -> void:
	var path := OS.get_environment("LBA_TEST_DATA_PATH").path_join("invobj.hqr")
	for index in [0, 1, 2, 3, 27]:
		var entry := HQR.read_entry(path, index)
		if not entry.get("ok", false):
			print(index, ": ", entry.get("error"))
			continue
		var bytes: PackedByteArray = entry["data"]
		var body: Dictionary = BODY.decode(bytes)
		var static_body: Dictionary = BODY.decode_static(bytes)
		print(index, ": flags=", bytes.decode_u16(0), " len=", bytes.size(), " animated=", body.get("ok", false), " static=", static_body.get("ok", false), " error=", body.get("error", ""))
	quit()

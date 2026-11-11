class_name LBATextHQR
extends RefCounted

const HQR := preload("res://scripts/import/hqr_reader.gd")
const FILES_PER_LANGUAGE := 14
const ENTRIES_PER_FILE := 2
const GAM_BANK := 2


static func load_bank(path: String, file_index: int, language: int = 0) -> Dictionary:
	if language < 0 or language >= 5 or file_index < 0 or file_index >= FILES_PER_LANGUAGE:
		return {}
	var base_entry := (language * FILES_PER_LANGUAGE * ENTRIES_PER_FILE) + (file_index * ENTRIES_PER_FILE)
	var order_entry: Dictionary = HQR.read_entry(path, base_entry)
	var text_entry: Dictionary = HQR.read_entry(path, base_entry + 1)
	if not order_entry.get("ok", false):
		return {}
	if not text_entry.get("ok", false):
		return {}
	var order_bytes: PackedByteArray = order_entry["data"]
	var text_bytes: PackedByteArray = text_entry["data"]
	if order_bytes.size() % 2 != 0 or text_bytes.size() < 2:
		return {}
	var max_text: int = order_bytes.size() / 2
	var offsets: Array[int] = []
	for slot in range(max_text + 1):
		var byte_offset := slot * 2
		if byte_offset + 1 >= text_bytes.size():
			return {}
		offsets.append(int(text_bytes.decode_u16(byte_offset)))
	var bank := {}
	for slot in range(max_text):
		var id := int(order_bytes.decode_u16(slot * 2))
		var start := offsets[slot]
		var stop := offsets[slot + 1]
		if start < 0 or stop <= start or stop > text_bytes.size():
			continue
		var first := int(text_bytes[start])
		# Printable CP850 bytes are characters, NOT formatting flags. This
		# preserves the initial T/E/A of the original intro narration.
		var is_style_byte := first < 32
		var attr := first if is_style_byte else 0
		var payload := PackedByteArray()
		if stop - start > 0:
			payload = text_bytes.slice(start + (1 if is_style_byte else 0), stop)
		if not payload.is_empty() and payload[payload.size() - 1] == 0:
			payload = payload.slice(0, payload.size() - 1)
		bank[id] = {
			"attr": attr,
			"text": _decode_cp850(payload),
		}
	return bank


static func voice_ordinal(path: String, file_index: int, language: int, text_id: int) -> int:
	# VOX entries are indexed by the position in the selected language's
	# order bank. Using an English ordinal for French would play wrong speech.
	var entry_index := language * FILES_PER_LANGUAGE * 2 + file_index * 2
	var entry: Dictionary = HQR.read_entry(path, entry_index)
	if not entry.get("ok", false):
		return -1
	var bytes: PackedByteArray = entry["data"]
	for index in range(bytes.size() / 2):
		if int(bytes.decode_u16(index * 2)) == text_id:
			return index
	return -1


static func get_text(path: String, file_index: int, language: int, text_id: int) -> String:
	var bank := load_bank(path, file_index, language)
	var entry: Dictionary = bank.get(text_id, {})
	return str(entry.get("text", ""))


static func load_intro_texts(path: String, language: int = 0) -> Array:
	var bank := load_bank(path, GAM_BANK, language)
	var result: Array = []
	for text_id in [150, 151, 152]:
		result.append(str((bank.get(text_id, {}) as Dictionary).get("text", "")))
	return result


static func _decode_cp850(bytes: PackedByteArray) -> String:
	var output := ""
	for value in bytes:
		var byte := int(value)
		if byte == 0:
			break
		if byte >= 32 and byte < 127:
			output += String.chr(byte)
		else:
			match byte:
				9:
					output += "\t"
				10:
					output += "\n"
				13:
					output += ""
				129:
					output += "ü"
				130:
					output += "é"
				131:
					output += "â"
				132:
					output += "ä"
				133:
					output += "à"
				134:
					output += "å"
				135:
					output += "ç"
				136:
					output += "ê"
				137:
					output += "ë"
				138:
					output += "è"
				139:
					output += "ï"
				140:
					output += "î"
				141:
					output += "ì"
				142:
					output += "Ä"
				143:
					output += "Å"
				144:
					output += "É"
				145:
					output += "æ"
				146:
					output += "Æ"
				147:
					output += "ô"
				148:
					output += "ö"
				149:
					output += "ò"
				150:
					output += "û"
				151:
					output += "ù"
				152:
					output += "ÿ"
				153:
					output += "Ö"
				154:
					output += "Ü"
				160:
					output += "á"
				161:
					output += "í"
				162:
					output += "ó"
				163:
					output += "ú"
				164:
					output += "ñ"
				165:
					output += "Ñ"
				168:
					output += "¿"
				173:
					output += "¡"
				225:
					output += "ß"
				_:
					output += String.chr(byte)
	return output

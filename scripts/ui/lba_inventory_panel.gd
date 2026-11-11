class_name LBAInventoryPanel
extends GameActionPanel

var _slot_nodes: Array[Button] = []
var _selected_slot := 0
var _items: Array[Dictionary] = []
signal selected_item_changed(slot: int)

func _ready() -> void:
    super._ready()
    for node in $Center/Panel/Upper/Contents/Entries.get_children():
        var button := node as Button
        _slot_nodes.append(button)
        button.mouse_filter = Control.MOUSE_FILTER_IGNORE
        button.focus_mode = Control.FOCUS_NONE
        button.pressed.connect(_choose.bind(_slot_nodes.size() - 1))
    _refresh()

func set_entries(entries: Array[Dictionary]) -> void:
    _items = entries.duplicate(true)
    if not is_node_ready():
        return
    for i in range(_slot_nodes.size()):
        var button := _slot_nodes[i]
        var entry: Dictionary = _items[i] if i < _items.size() else {}
        (button.get_node("Preview") as TextureRect).texture = entry.get("icon") as Texture2D
        var count := int(entry.get("count", 0))
        (button.get_node("Count") as Label).text = str(count) if count > 1 else ""
    _refresh()

func current_slot() -> int:
    return _selected_slot

func focus_first() -> void:
    _refresh()

func _input(event: InputEvent) -> void:
    if not is_visible_in_tree():
        return
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo:
        return
    var code := key.keycode
    var target := _selected_slot
    match code:
        KEY_LEFT: target = int(_selected_slot / 7) * 7 + posmod(_selected_slot % 7 - 1, 7)
        KEY_RIGHT: target = int(_selected_slot / 7) * 7 + posmod(_selected_slot % 7 + 1, 7)
        KEY_UP: target = posmod(_selected_slot - 7, 28)
        KEY_DOWN: target = posmod(_selected_slot + 7, 28)
        KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
            if _selected_slot < _items.size() and bool(_items[_selected_slot].get("enabled", false)):
                if _selected_slot == 0:
                    action_requested.emit(&"open_holomap", null)
                # Item use is not bridged to the native game yet. Do not
                # emit use_item: it currently triggers an unrelated warning,
                # sometimes after the inventory has closed. Selection remains
                # navigable and its original description stays visible.
            get_viewport().set_input_as_handled()
            return
        _: return
    _choose(target)
    get_viewport().set_input_as_handled()

func _choose(index: int) -> void:
    _selected_slot = clampi(index, 0, 27)
    _refresh()
    selected_item_changed.emit(_selected_slot)

func _refresh() -> void:
    if not is_node_ready():
        return
    var description := get_node_or_null("Center/Panel/Description/Contents/Text") as RichTextLabel
    if description != null:
        var entry: Dictionary = _items[_selected_slot] if _selected_slot < _items.size() else {}
        var text_value := str(entry.get("description", entry.get("label", "")))
        # Never leave the whole text box empty when a native inventory update
        # has not arrived yet. Missing GAM descriptions are diagnosed upstream.
        description.text = text_value if not text_value.strip_edges().is_empty() else "Item description unavailable"
    for i in range(_slot_nodes.size()):
        _slot_nodes[i].set_pressed_no_signal(i == _selected_slot)

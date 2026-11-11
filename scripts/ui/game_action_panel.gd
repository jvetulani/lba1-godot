class_name GameActionPanel
extends Control

signal action_requested(action: StringName, value: Variant)

var _entries: Array[Dictionary] = []
var _pending_action: StringName = &""
var _pending_value: Variant = null


func _ready() -> void:
	for node in find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if not button.has_meta("action"):
			continue
		var action := StringName(str(button.get_meta("action", button.name.to_snake_case())))
		if button.toggle_mode:
			button.toggled.connect(func(enabled: bool) -> void: action_requested.emit(action, enabled))
		else:
			button.pressed.connect(_on_button_pressed.bind(action, button))
	for node in find_children("*", "Range", true, false):
		var slider := node as Range
		if not slider.has_meta("action"):
			continue
		var action := StringName(str(slider.get_meta("action", slider.name.to_snake_case())))
		slider.value_changed.connect(func(value: float) -> void: action_requested.emit(action, value))
	var confirmation := find_child("Confirmation", true, false) as ConfirmationDialog
	if confirmation != null:
		confirmation.confirmed.connect(_on_confirmation_confirmed)


# Wrap navigation on every menu built from GameActionPanel, including
# conventional buttons, sliders, OptionButtons, save/load lists and inventory.
# The Ctrl behavior selector is managed separately by GameUI's posmod logic.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or name in ["ModeMenu", "LoadScreen"]:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code := key.keycode
	if code != KEY_UP and code != KEY_DOWN:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or (focused != self and not is_ancestor_of(focused)):
		return
	var direction := -1 if code == KEY_UP else 1
	if focused is ItemList:
		if _lba_wrap_item_list(focused as ItemList, direction):
			get_viewport().set_input_as_handled()
		return
	if _lba_wrap_navigation(focused, direction):
		get_viewport().set_input_as_handled()


func _lba_focusables() -> Array[Control]:
	var controls: Array[Control] = []
	for node in find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
			continue
		if control is BaseButton and (control as BaseButton).disabled:
			continue
		if control is ItemList or control is BaseButton or control is Range \
				or control is LineEdit or control is TextEdit:
			controls.append(control)
	return controls


func _lba_wrap_navigation(focused: Control, direction: int) -> bool:
	var controls := _lba_focusables()
	var here := controls.find(focused)
	if here < 0 or controls.is_empty():
		return false
	controls[posmod(here + direction, controls.size())].grab_focus()
	return true


func _lba_wrap_item_list(items: ItemList, direction: int) -> bool:
	if items.item_count == 0:
		return false
	var selected := items.get_selected_items()
	var current := selected[0] if not selected.is_empty() else (0 if direction > 0 else items.item_count - 1)
	var stride := maxi(1, items.max_columns)
	# A list arranged into multiple columns moves vertically by an entire row.
	# On crossing either end, wrap to the opposite edge.
	for step in range(items.item_count):
		current = posmod(current + direction * stride, items.item_count)
		if not items.is_item_disabled(current) and items.is_item_selectable(current):
			items.select(current)
			items.ensure_current_is_visible()
			items.item_selected.emit(current)
			return true
	return false


func focus_first() -> void:
	for node in find_children("*", "Control", true, false):
		var control := node as Control
		if control.focus_mode != Control.FOCUS_NONE and control.is_visible_in_tree() and (not control is BaseButton or not (control as BaseButton).disabled):
			control.grab_focus()
			return


func set_entries(entries: Array[Dictionary]) -> void:
	_entries = entries.duplicate(true)
	var list := find_child("Entries", true, false) as ItemList
	if list == null:
		return
	list.clear()
	for entry in _entries:
		var index := list.item_count
		list.add_item(str(entry.get("label", entry.get("id", ""))))
		if entry.get("icon") is Texture2D:
			list.set_item_icon(index, entry["icon"])
		if not bool(entry.get("enabled", true)):
			list.set_item_selectable(index, false)
	list.deselect_all()


func _on_button_pressed(action: StringName, button: BaseButton) -> void:
	var value: Variant = int(button.get_meta("behavior")) if button.has_meta("behavior") else null
	var list := find_child("Entries", true, false) as ItemList
	if list != null and action in [&"save", &"load", &"use_item"]:
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		value = _entries[selected[0]].get("id", selected[0])
	if button.has_meta("confirm") and bool(button.get_meta("confirm")):
		var confirmation := find_child("Confirmation", true, false) as ConfirmationDialog
		if confirmation != null:
			confirmation.dialog_text = str(button.get_meta("confirmation_text", "Continue?"))
			_pending_action = action
			_pending_value = value
			confirmation.popup_centered()
			return
	action_requested.emit(action, value)


func _on_confirmation_confirmed() -> void:
	if _pending_action == &"":
		return
	var action := _pending_action
	var value: Variant = _pending_value
	_pending_action = &""
	_pending_value = null
	action_requested.emit(action, value)

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
		list.add_item(str(entry.get("label", entry.get("id", ""))))
	list.deselect_all()


func _on_button_pressed(action: StringName, button: BaseButton) -> void:
	var value: Variant = null
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

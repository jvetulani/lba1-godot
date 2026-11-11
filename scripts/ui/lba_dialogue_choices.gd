@tool
class_name LBADialogueChoices
extends Control

signal option_chosen(index: int)

const MENU_BUTTON := preload("res://scenes/ui/MenuButton.tscn")
@export_multiline var editor_prompt := "Choose your response":
	set(value):
		editor_prompt = value
		if Engine.is_editor_hint() and is_inside_tree():
			_refresh_preview()
@export var editor_choices: PackedStringArray = PackedStringArray(["Yes", "No", "Tell me more"]):
	set(value):
		editor_choices = value
		if Engine.is_editor_hint() and is_inside_tree():
			_refresh_preview()


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_preview()


func set_choices(prompt: String, options: PackedStringArray) -> void:
	_render_choices(prompt, options)


func _refresh_preview() -> void:
	_render_choices(editor_prompt, editor_choices)


func _render_choices(prompt: String, choices: PackedStringArray) -> void:
	var label := get_node_or_null("Panel/Contents/Prompt") as Label
	var entries := get_node_or_null("Panel/Contents/Choices") as VBoxContainer
	if label == null or entries == null:
		return
	label.text = prompt
	for node in entries.get_children():
		entries.remove_child(node)
		node.queue_free()
	for index in range(choices.size()):
		var button := MENU_BUTTON.instantiate() as Button
		if button == null:
			continue
		button.set("caption", choices[index])
		entries.add_child(button)
		button.pressed.connect(func() -> void: option_chosen.emit(index))

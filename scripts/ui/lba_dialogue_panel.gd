class_name LBADialoguePanel
extends "res://scripts/ui/game_action_panel.gd"

@export_group("Dialogue Controls")
@export var body: RichTextLabel
@export var chevron: TextureRect
@export var item_preview: TextureRect

@export_group("Presentation")
# The same authored scene is used for all three text-window presentations.
@export_enum("Dialogue", "Poster", "Item pickup") var presentation_mode: int = 0
@export var window_frame: Control


@export_group("Text Reveal")
@export_range(1.0, 240.0, 1.0) var reveal_characters_per_second: float = 43.0


func _ready() -> void:
	super._ready()
	validate_refs()


func validate_refs() -> bool:
	var valid := true
	if not is_instance_valid(body):
		push_warning("LBADialoguePanel: assign Body (RichTextLabel) in the Inspector.")
		valid = false
	if not is_instance_valid(chevron):
		push_warning("LBADialoguePanel: assign Chevron (TextureRect) in the Inspector.")
	if not is_instance_valid(item_preview):
		push_warning("LBADialoguePanel: assign Item Preview (TextureRect) in the Inspector.")
	return valid

func set_presentation(mode: int, preview_texture: Texture2D = null) -> void:
	presentation_mode = clampi(mode, 0, 2)
	if not is_instance_valid(window_frame):
		push_warning("LBADialoguePanel: Window Frame is not assigned in the Inspector.")
	if not is_instance_valid(item_preview):
		push_warning("LBADialoguePanel: Item Preview is not assigned in the Inspector.")
		return
	# Frame, padding, colors and font are inherited from the shared Theme.
	item_preview.visible = presentation_mode == 2 and preview_texture != null
	item_preview.texture = preview_texture if presentation_mode == 2 else null

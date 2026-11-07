class_name LBAPlasmaButton
extends Button

@export var caption := ""
@export_range(32.0, 256.0, 1.0) var plasma_pixel_scale := 96.0

@onready var _plasma: ColorRect = $Plasma
@onready var _caption: Label = $Caption


func _ready() -> void:
	_plasma.material = _plasma.material.duplicate()
	_plasma.resized.connect(_update_plasma_scale)
	_update_plasma_scale()
	_caption.text = caption
	focus_entered.connect(_update_style)
	focus_exited.connect(_update_style)
	mouse_entered.connect(_update_style)
	mouse_exited.connect(_update_style)
	_update_style()


func _update_style() -> void:
	var active := has_focus() or is_hovered()
	(_plasma.material as ShaderMaterial).set_shader_parameter("selected", 1.0 if active else 0.0)
	_caption.modulate = Color.WHITE if active else Color(0.87, 0.93, 0.96)


func set_original_palette(texture: Texture2D) -> void:
	if _plasma == null:
		return
	var material := _plasma.material as ShaderMaterial
	material.set_shader_parameter("original_palette", texture)
	material.set_shader_parameter("use_original_palette", texture != null)


func _update_plasma_scale() -> void:
	if _plasma != null and _plasma.material is ShaderMaterial:
		(_plasma.material as ShaderMaterial).set_shader_parameter("plasma_dimensions", _plasma.size / plasma_pixel_scale)

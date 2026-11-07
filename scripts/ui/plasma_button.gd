class_name LBAPlasmaButton
extends Button

@export var caption := ""

@onready var _plasma: ColorRect = $Plasma
@onready var _caption: Label = $Caption


func _ready() -> void:
	_plasma.material = _plasma.material.duplicate()
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

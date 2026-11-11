@tool
class_name LBAFrame
extends Control

func _ready() -> void:
    _sync_padding()

func _notification(what: int) -> void:
    if what == NOTIFICATION_THEME_CHANGED:
        _sync_padding()

func _sync_padding() -> void:
    var body := get_node_or_null("Contents") as Control
    if body == null:
        return
    body.offset_left = float(get_theme_constant("padding_left", "LBAFrame"))
    body.offset_top = float(get_theme_constant("padding_top", "LBAFrame"))
    body.offset_right = -float(get_theme_constant("padding_right", "LBAFrame"))
    body.offset_bottom = -float(get_theme_constant("padding_bottom", "LBAFrame"))
    var frame := get_node_or_null("Edge") as NinePatchRect
    if frame != null:
        var slice := get_theme_constant("slice_size", "LBAFrame")
        frame.patch_margin_left = slice
        frame.patch_margin_top = slice
        frame.patch_margin_right = slice
        frame.patch_margin_bottom = slice
    var fill := get_node_or_null("Fill") as Control
    if fill != null:
        var inset := float(get_theme_constant("fill_inset", "LBAFrame"))
        fill.offset_left = inset
        fill.offset_top = inset
        fill.offset_right = -inset
        fill.offset_bottom = -inset

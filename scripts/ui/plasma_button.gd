@tool
class_name LBAPlasmaButton
extends Button

# Button dimensions, typography, border widths and corner radii belong to
# the Button and its shared Theme. Plasma inherits the border shape.
@export var caption: String = "Menu button":
	set(value):
		caption = value
		if is_node_ready():
			_apply_caption()

# Only timing differs between menu-button instances.
@export_range(-20.0, 20.0, 0.05) var time_offset: float = 0.0:
	set(value):
		time_offset = value
		if is_node_ready():
			_update_phase()

@export var auto_stagger: bool = true:
	set(value):
		auto_stagger = value
		if is_node_ready():
			_update_phase()

@export var editor_animate: bool = true:
	set(value):
		editor_animate = value
		if is_node_ready() and Engine.is_editor_hint():
			set_process(value)

@onready var _plasma: ColorRect = get_node_or_null("Plasma") as ColorRect
@onready var _caption: Label = get_node_or_null("Caption") as Label
var _preview_clock: float = 0.0
var _tracked_style: StyleBoxFlat


func _ready() -> void:
	_apply_caption()
	if _plasma == null:
		push_warning("MenuButton requires a direct child ColorRect named Plasma.")
		return
	# Keyboard/controller focus only: no mouse hover highlight or clicking.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plasma.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_phase()
	_plasma.set_instance_shader_parameter("editor_preview", Engine.is_editor_hint())
	focus_entered.connect(_refresh_focus)
	focus_exited.connect(_refresh_focus)
	_sync_theme_shape()
	_refresh_focus()
	set_process(Engine.is_editor_hint() and editor_animate)


func _exit_tree() -> void:
	if _tracked_style != null and _tracked_style.changed.is_connected(_sync_theme_shape):
		_tracked_style.changed.disconnect(_sync_theme_shape)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_sync_theme_shape()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint() or not editor_animate or _plasma == null:
		return
	_preview_clock += delta
	_plasma.set_instance_shader_parameter("editor_phase", _preview_clock)
	_plasma.queue_redraw()


func _apply_caption() -> void:
	if _caption != null:
		_caption.text = caption


func _update_phase() -> void:
	if _plasma == null:
		return
	var phase := time_offset
	if auto_stagger:
		phase += float(get_index()) * 1.37
	_plasma.set_instance_shader_parameter("phase_offset", phase)


func _refresh_focus() -> void:
	if _plasma == null:
		return
	var selected := has_focus() and not disabled
	# Keep plasma visible while editing the reusable MenuButton scene.
	_plasma.visible = Engine.is_editor_hint() or selected
	_sync_theme_shape()


func _sync_theme_shape() -> void:
	if _plasma == null:
		return
	# Focus is an overlay, so use its outline when it is a StyleBoxFlat.
	# A StyleBoxEmpty focus falls back to the normal style's geometry.
	var focus_style := get_theme_stylebox("focus")
	var normal_style := get_theme_stylebox("normal")
	var style: StyleBoxFlat
	if focus_style is StyleBoxFlat:
		style = focus_style as StyleBoxFlat
	elif normal_style is StyleBoxFlat:
		style = normal_style as StyleBoxFlat

	if style != _tracked_style:
		if _tracked_style != null and _tracked_style.changed.is_connected(_sync_theme_shape):
			_tracked_style.changed.disconnect(_sync_theme_shape)
		_tracked_style = style
		if _tracked_style != null and not _tracked_style.changed.is_connected(_sync_theme_shape):
			_tracked_style.changed.connect(_sync_theme_shape)

	if style == null:
		# Fall back to a rectangular fill if the theme has no flat style.
		_plasma.set_instance_shader_parameter("corner_radii", Vector4.ZERO)
		_plasma.set_instance_shader_parameter("border_insets", Vector4.ZERO)
		return

	_plasma.set_instance_shader_parameter("corner_radii", Vector4(
		float(style.corner_radius_top_left),
		float(style.corner_radius_top_right),
		float(style.corner_radius_bottom_right),
		float(style.corner_radius_bottom_left)
	))
	# The inset is the visible outline thickness, not the text content
	# margin. Content margins remain entirely theme-controlled.
	_plasma.set_instance_shader_parameter("border_insets", Vector4(
		float(style.border_width_left),
		float(style.border_width_top),
		float(style.border_width_right),
		float(style.border_width_bottom)
	))


# Keep compatibility with the existing GameUI palette hook. The palette is
# now authored in the shared GradientTexture1D, not replaced at runtime.
func set_original_palette(_texture: Texture2D) -> void:
	pass

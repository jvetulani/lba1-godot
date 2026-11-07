class_name LBAGameplayInput
extends RefCounted

# These bits match lba1-native/include/lba_host.h. UI actions stay in GameUI.
const FORWARD := 1 << 0
const BACKWARD := 1 << 1
const TURN_LEFT := 1 << 2
const TURN_RIGHT := 1 << 3
const PRIMARY := 1 << 4
const WEAPON := 1 << 5
const RECENTER_CAMERA := 1 << 6


static func sample_actions() -> int:
	var actions := 0
	if Input.is_action_pressed(&"lba_forward"):
		actions |= FORWARD
	if Input.is_action_pressed(&"lba_backward"):
		actions |= BACKWARD
	if Input.is_action_pressed(&"lba_turn_left"):
		actions |= TURN_LEFT
	if Input.is_action_pressed(&"lba_turn_right"):
		actions |= TURN_RIGHT
	if Input.is_action_pressed(&"lba_primary"):
		actions |= PRIMARY
	if Input.is_action_pressed(&"lba_weapon"):
		actions |= WEAPON
	if Input.is_action_pressed(&"lba_recenter_camera"):
		actions |= RECENTER_CAMERA
	return actions

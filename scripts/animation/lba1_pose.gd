class_name LBA1Pose
extends RefCounted

const POSE = preload("res://scripts/animation/character_pose.gd")

const ANGLE_SCALE := TAU / 1024.0


static func sample(body: Dictionary, animation: Dictionary, source_frame: int, target_frame: int, weight: float) -> Dictionary:
	return POSE.sample(body, animation, source_frame, target_frame, weight, 1024.0)


static func from_native_groups(body: Dictionary, packed: PackedInt32Array) -> Dictionary:
	return POSE.from_native_groups(body, packed, 1024.0)

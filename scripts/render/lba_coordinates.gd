class_name LBACoordinates
extends RefCounted

const PIXEL_SIZE := 0.02
const CELL_XZ := 24.0 * sqrt(2.0) * PIXEL_SIZE
const CELL_Y := 15.0 / cos(deg_to_rad(30.0)) * PIXEL_SIZE
# GRILLE_A.C Map2Screen(0,0,0) starts a brick at (288,215), while
# Proj_ISO(0,0,0) starts an actor at (311,240). This offset belongs to
# every grid graph, independently of scene and camera position.
const GRID_GRAPH_ORIGIN_PIXELS := Vector2(-23.0, -25.0)


static func native_position(x: int, y: int, z: int) -> Vector3:
	return Vector3(float(x) / 512.0 * CELL_XZ,
		float(y) / 256.0 * CELL_Y,
		float(z) / 512.0 * CELL_XZ)


static func grid_cell(x: int, y: int, z: int) -> Vector3:
	return Vector3(float(x) * CELL_XZ, float(y) * CELL_Y, float(z) * CELL_XZ)


static func body_basis(angle: int) -> Basis:
	var rotation := Basis(Vector3.UP, TAU * float(angle & 1023) / 1024.0)
	return rotation.scaled(Vector3(CELL_XZ, 2.0 * CELL_Y, CELL_XZ))


static func camera_facing_basis() -> Basis:
	var from_center := Vector3(cos(deg_to_rad(30.0)) / sqrt(2.0), 0.5,
		cos(deg_to_rad(30.0)) / sqrt(2.0))
	var right := Vector3.UP.cross(from_center).normalized()
	var up := from_center.cross(right).normalized()
	return Basis(right, up, from_center)


static func screen_pixel_offset(x: float, y: float) -> Vector3:
	var facing := camera_facing_basis()
	return facing.x * x * PIXEL_SIZE - facing.y * y * PIXEL_SIZE


static func grid_graph_center(hot_x: int, hot_y: int, width: int, height: int) -> Vector3:
	return screen_pixel_offset(GRID_GRAPH_ORIGIN_PIXELS.x + float(hot_x) + float(width) * 0.5,
		GRID_GRAPH_ORIGIN_PIXELS.y + float(hot_y) + float(height) * 0.5)

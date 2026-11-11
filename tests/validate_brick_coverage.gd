extends SceneTree
const RENDERER := preload("res://scripts/render/lba_grid_renderer.gd")

func _initialize() -> void:
	var source := Image.create(48, 40, false, Image.FORMAT_RGBA8)
	source.fill(Color.TRANSPARENT)
	var brick := {"width":48,"height":40,"hot_x":0,"hot_y":0,"image":source}
	assert(RENDERER.projected_alpha_coverage(brick) == 0.0)
	# A fully opaque valid BRK must cover a measurable area of a projected box.
	source.fill(Color.WHITE)
	var coverage := RENDERER.projected_alpha_coverage(brick)
	assert(coverage > 0.015)
	print("PASS: projected BRK image coverage test; opaque coverage=",coverage)
	quit()

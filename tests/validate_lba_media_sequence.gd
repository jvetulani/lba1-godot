extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_path := OS.get_environment("LBA_TEST_DATA_PATH")
	if data_path.is_empty():
		push_error("Set LBA_TEST_DATA_PATH to an imported LBA1 data directory")
		quit(1)
		return
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var ui: GameUI = main.get_node("GameUI")
	var media: LBAMediaSequence = ui.get_node("Frame/MediaSequence")
	if not ui.configure_media(data_path.path_join("media-cache"), data_path):
		_fail(main, "Media manifest was not loaded")
		return
	var backdrop := ui.get_node("Frame/MenuBackdrop") as TextureRect
	if backdrop.texture == null or backdrop.texture.get_width() != 640:
		_fail(main, "Original menu artwork was not decoded")
		return
	if not ui.play_intro():
		_fail(main, "Intro did not start")
		return
	var texture := media.get_node("Illustration").texture as Texture2D
	if texture == null or texture.get_width() != 640 or texture.get_height() != 480:
		_fail(main, "Intro illustration was not decoded")
		return
	if not (media.get_node("Narrator") as AudioStreamPlayer).playing:
		_fail(main, "Narrator did not start")
		return
	for segment in range(3):
		media._on_narrator_finished()
	if not (media.get_node("Movie") as VideoStreamPlayer).is_playing():
		_fail(main, "INTROD OGV did not start")
		return
	if media._cues.is_empty():
		_fail(main, "INTROD music cues were not loaded")
		return
	media.skip()
	print("LBA media sequence: menu artwork, narration, OGV and music cues started")
	await process_frame
	media._stop_music()
	main.free()
	await create_timer(0.2).timeout
	quit(0)


func _fail(main: Node, message: String) -> void:
	push_error(message)
	main.free()
	quit(1)

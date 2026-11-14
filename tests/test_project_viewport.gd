extends SceneTree
## Run with real project scaling: godot --path . --resolution 390x844 -s tests/test_project_viewport.gd
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.autosave_path = "user://viewport-check-no-save.json"
	if DisplayServer.get_name() == "headless": root.size = Vector2i(390, 844)
	root.add_child(scene)
	for frame in range(5): await process_frame
	var viewport_size: Vector2 = root.get_visible_rect().size
	var failed: bool = false
	print("Project viewport: physical=", root.size, " logical=", viewport_size, " content_scale=", root.content_scale_size, " mode=", root.content_scale_mode)
	if root.content_scale_size != Vector2i(390, 844):
		push_error("Project design viewport must use portrait dimensions")
		failed = true
	if root.size != Vector2i(390, 844):
		push_error("Launch this portrait check with --resolution 390x844")
		failed = true
	if root.size.x == 390 and root.size.y == 844:
		if absf(viewport_size.x - 390.0) > 1 or not scene.mobile or scene.navigation.visible:
			push_error("Actual portrait window must show mobile layout at usable text scale")
			failed = true
		if scene.main_scroll.size.x > 390 or scene.command_input.get_global_rect().end.y > viewport_size.y + 1:
			push_error("Actual project portrait controls must fit logical viewport")
			failed = true
	if not failed: print("Project content scaling checks passed")
	quit(1 if failed else 0)

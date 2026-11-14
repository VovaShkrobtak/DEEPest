extends SceneTree
## Optional visual smoke test; requires an X11 display and real renderer.
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for dimensions in [Vector2i(1280,800), Vector2i(390,844)]:
		root.size = dimensions
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		var screenshot: Image = root.get_texture().get_image()
		screenshot.save_png("/tmp/deepest-%dx%d.png" % [dimensions.x, dimensions.y])
	scene._set_scale(2.0)
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/deepest-390x844-large-text.png")
	scene._set_scale(1.0)
	quit()

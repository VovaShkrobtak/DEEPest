extends SceneTree
## Run: godot --headless --path . -s tests/test_ui.gd
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.autosave_path = "user://test-ui-autosave.json"
	_remove_save(scene.autosave_path)
	root.add_child(scene)
	await process_frame
	for dimensions in [Vector2i(390, 844), Vector2i(1280, 800)]:
		root.size = dimensions
		await process_frame
		await process_frame
		_check(scene.main_scroll.size.x > 200, "Reading column has usable width")
		_check(scene.main_scroll.size.y > 150, "Reading column has usable height")
		_check(scene.command_input.get_global_rect().end.y <= root.get_visible_rect().size.y + 1, "Command stays inside viewport")
		_check(scene.page.size.x <= scene.main_scroll.size.x + 1, "Content has no horizontal overflow")
		_check(scene.navigation.visible == (dimensions.x >= 980), "Navigation adapts to viewport")
	for tab in scene.TABS:
		scene._select_tab(tab)
		await process_frame
		_check(scene.page.get_child_count() > 0, "Tab contains content: " + tab)
	scene._select_tab("Мир")
	var before: Dictionary = scene.kernel.export_state()
	var buttons: Array[Button] = []
	_find_actions(scene.page, buttons)
	_check(not buttons.is_empty(), "World exposes actual action buttons")
	_check(scene.snapshot.get("time_label", "") == "16:20", "Observer exposes scenario clock")
	_check(scene.snapshot.get("date_label", "") == "14 октября 1998", "Observer exposes scenario date")
	if not buttons.is_empty():
		buttons[0].pressed.emit()
		await process_frame
		_check(scene.kernel.export_state() != before, "Actual action button mutates authoritative kernel")
	scene.action_timer.stop()
	# A single global progress/cancel affordance follows the player between tabs.
	scene._cancel()
	scene._perform("rest")
	scene.action_timer.stop()
	for tab in ["Мир", "Вещи", "Тело", "Люди", "Настройки"]:
		scene._select_tab(tab)
		var cancel_button: Button = _find_button(scene.page, "Прервать действие")
		_check(cancel_button != null, "Active action can be cancelled in " + tab)
	var cancel_button: Button = _find_button(scene.page, "Прервать действие")
	if cancel_button != null: cancel_button.pressed.emit()
	_check(scene.kernel.snapshot().action.is_empty(), "Global cancel reaches kernel")
	_check(FileAccess.file_exists(scene.autosave_path), "Cancel writes separate autosave")
	var cancelled_state: Dictionary = scene.kernel.export_state()
	var resumed = load("res://scenes/main.tscn").instantiate()
	resumed.autosave_path = scene.autosave_path
	root.add_child(resumed)
	await process_frame
	_check(JSON.parse_string(JSON.stringify(resumed.kernel.export_state())) == JSON.parse_string(JSON.stringify(cancelled_state)), "Launch resumes valid autosave")
	resumed.queue_free()
	await process_frame
	var corrupt_primary := FileAccess.open(scene.autosave_path, FileAccess.WRITE)
	corrupt_primary.store_string("{broken-primary")
	corrupt_primary.close()
	var recovered = load("res://scenes/main.tscn").instantiate()
	recovered.autosave_path = scene.autosave_path
	root.add_child(recovered)
	await process_frame
	_check(recovered.message.contains("резервной") and recovered.autosave_protected, "Backup recovery is visible and protects invalid primary")
	recovered._notification(NOTIFICATION_APPLICATION_PAUSED)
	_check(FileAccess.get_file_as_string(scene.autosave_path) == "{broken-primary", "Recovered backup does not overwrite invalid primary on pause")
	recovered.queue_free()
	await process_frame
	# Controlled fixture: a visible person must expose actual social action buttons.
	var fixture: Dictionary = scene.kernel.export_state()
	fixture.world.npcs.nina.location = fixture.location
	fixture.world.npcs.nina.destination = ""
	fixture.world.npcs.nina.travel_s = 0.0
	_check(scene.kernel.restore_state(fixture).ok, "Social UI fixture is valid")
	scene._refresh()
	scene._select_tab("Люди")
	var social: Array[Button] = []
	_find_actions(scene.page, social)
	_check(not social.is_empty(), "People tab exposes social action buttons")
	if not social.is_empty():
		social[0].pressed.emit()
		scene.action_timer.stop()
		_check(not scene.kernel.snapshot().action.is_empty(), "Social action button starts kernel action")
		scene._cancel()
	# Corrupt autosaves survive pause until a deliberate successful player action.
	var bad_path: String = "user://test-ui-corrupt-autosave.json"
	_remove_save(bad_path)
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string("{broken")
	bad_file.close()
	var corrupted = load("res://scenes/main.tscn").instantiate()
	corrupted.autosave_path = bad_path
	root.add_child(corrupted)
	await process_frame
	_check(corrupted.autosave_protected, "Corruption is reported and protected")
	corrupted._notification(NOTIFICATION_APPLICATION_PAUSED)
	_check(FileAccess.get_file_as_string(bad_path) == "{broken", "Pause does not overwrite corrupt autosave")
	corrupted._perform("inspect")
	corrupted.action_timer.stop()
	corrupted._notification(NOTIFICATION_APPLICATION_PAUSED)
	_check(FileAccess.get_file_as_string(bad_path) != "{broken", "Player action allows subsequent autosave")
	corrupted.queue_free()
	await process_frame
	_remove_save(bad_path)
	scene._select_tab("Мир")
	scene._perform("inspect")
	scene.action_timer.stop()
	scene._advance()
	scene._advance()
	_check(scene.kernel.snapshot().action.is_empty(), "Timed action completes through UI")
	_check(not scene.kernel.snapshot().won and scene.kernel.snapshot().goals.is_empty(), "No first-night goals or completion state")
	_check(FileAccess.file_exists(scene.autosave_path), "Completion writes autosave")
	_check(scene.message == scene.snapshot.journal.back().text, "Completion reports latest public result")
	scene.snapshot["won"] = true
	scene._rebuild_content()
	_check(not _has_label(scene.page, "ВЫ ВСТРЕТИЛИ УТРО"), "No scripted victory banner")
	scene.snapshot["won"] = false
	scene.snapshot["alive"] = false
	scene._rebuild_content()
	var dead_actions: Array[Button] = []
	_find_actions(scene.page, dead_actions)
	_check(dead_actions.is_empty() and not scene.command_input.editable, "Death removes gameplay actions")
	_check(_find_button(scene.page, "Новое прохождение…") != null, "Death offers restart")
	scene._refresh()
	_remove_save(scene.autosave_path)

	_check(not scene.portrait_mode, "Android landscape setting is the default")
	scene._set_portrait_mode(true)
	_check(scene.portrait_mode, "Portrait can be enabled")
	var settings := ConfigFile.new()
	_check(settings.load(scene.settings_path) == OK and bool(settings.get_value("interface", "portrait_mode", false)), "Orientation persists")
	scene._set_portrait_mode(false)
	scene._set_scale(2.0)
	root.size = Vector2i(390, 844)
	await process_frame
	await process_frame
	_check(scene.page.size.x <= scene.main_scroll.size.x + 1, "200% text has no horizontal overflow")
	_check(scene.command_input.get_global_rect().end.y <= root.get_visible_rect().size.y + 1, "200% command stays visible")
	scene._set_scale(1.0)
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("UI checks passed: responsive layouts, 200% text, social actions, global cancel, autosave/resume/corruption, completion/death")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _find_actions(node: Node, output: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button and child.has_meta("action_id") and not child.disabled:
			output.append(child)
		_find_actions(child, output)

func _check(condition: bool, description: String) -> void:
	if not condition: failures.append(description)

func _find_button(node: Node, caption: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == caption: return child
		var found := _find_button(child, caption)
		if found != null: return found
	return null

func _remove_save(path: String) -> void:
	for suffix: String in ["", ".bak1", ".bak2", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _has_label(node: Node, caption: String) -> bool:
	for child in node.get_children():
		if child is Label and child.text == caption: return true
		if _has_label(child, caption): return true
	return false

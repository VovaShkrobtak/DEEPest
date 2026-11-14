extends SceneTree
## Long-running actions must surface new OBSERVED danger without forcing a layout rebuild.
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.autosave_path = "user://ui-attention-no-save.json"
	root.add_child(scene)
	await process_frame
	var fixture: Dictionary = scene.kernel.export_state()
	for id: String in fixture.zombies.agents:
		fixture.zombies.agents[id].location = fixture.location
		fixture.zombies.agents[id].distance_m = 20.0
		fixture.zombies.agents[id].close_reported = false
		break
	check(scene.kernel.restore_state(fixture).ok, "Observed-threat fixture restores")
	scene._refresh()
	check(scene.snapshot.get("threat_warnings", []).size() > 0, "Source observation reports nearby infected")
	scene._perform("rest")
	scene.action_timer.stop()
	check(not scene.kernel.snapshot().action.is_empty(), "Long-running action starts with visible danger")
	scene._advance()
	scene.action_timer.stop()
	check(scene.notice.text.contains("ВНИМАНИЕ"), "Danger is visible while action is still in progress")
	check(not scene.kernel.snapshot().action.is_empty(), "No artificial cancellation or timer rollback")
	scene._cancel()
	scene.queue_free()
	await process_frame
	if FileAccess.file_exists("user://ui-attention-no-save.json"): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ui-attention-no-save.json"))
	if failures.is_empty(): print("Live sensory warnings: PASS")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func check(value: bool, label: String) -> void:
	if not value: failures.append(label)

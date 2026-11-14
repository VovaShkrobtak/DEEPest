extends SceneTree
const Kernel = preload("res://src/core/kernel.gd")
const SaveStore = preload("res://src/adapters/save_store.gd")
var failures: int = 0
func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)
func _initialize() -> void:
	var game = Kernel.new()
	game.command("clean_chimney")
	game.step(300)
	game.cancel()
	game.command("clean_chimney")
	check(game.export_state().action.elapsed_s == 300,"Resume repair preserves physical progress")
	game.cancel()
	game.command("move:yard")
	game.step(999)
	game.command("move:clinic")
	game.step(999)
	game.command("clean_chimney")
	check(game.export_state().action.elapsed_s == 0,"Repair work cannot teleport to another chimney")
	var local = Kernel.new()
	var fixture: Dictionary = local.export_state()
	fixture.environment.rooms.clinic.fuel_kg = 0.00001
	fixture.environment.rooms.clinic.burning = true
	check(local.restore_state(fixture).ok,"Remote fire fixture")
	local.command("wait")
	local.step(10)
	var leak: bool = false
	for entry: Dictionary in local.snapshot().journal:
		if entry.type == "fire_out": leak = true
	check(not leak,"Remote stove outcome cannot leak to player's journal")
	var saving = Kernel.new(24)
	saving.command("clean_chimney")
	saving.step(240)
	var store = SaveStore.new("user://test-real-kernel.json")
	check(store.save(saving).ok,"Save real kernel mid-action")
	var loaded = Kernel.new(1)
	check(store.load_into(loaded).ok,"Load real kernel mid-action")
	# JSON normalizes integer-shaped numbers; compare normalized authoritative values.
	check(JSON.parse_string(JSON.stringify(saving.export_state())) == JSON.parse_string(JSON.stringify(loaded.export_state())),"Real kernel save roundtrip")
	saving.step(360)
	loaded.step(360)
	check(equivalent(saving.export_state(),loaded.export_state()),"Restored work completes exactly once within numeric tolerance")
	check(loaded.export_state().environment.rooms.shelter.chimney_clean,"Restored physical work applied: " + JSON.stringify({"duration":saving.export_state().get("action",{}),"loaded_action":loaded.export_state().action,"progress":loaded.export_state().work_progress,"journal_tail":loaded.export_state().journal.slice(-5),"fatigue":loaded.export_state().body.fatigue,"pain":loaded.export_state().body.anatomy.pain_raw}))
	print("Transaction checks failures=",failures)
	quit(1 if failures else 0)

func equivalent(left: Variant, right: Variant) -> bool:
	if (left is float or left is int) and (right is float or right is int):
		return absf(float(left)-float(right)) <= maxf(1.0,absf(float(left))) * 0.0000000001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for key: Variant in left:
			if not right.has(key) or not equivalent(left[key],right[key]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index: int in range(left.size()):
			if not equivalent(left[index],right[index]): return false
		return true
	return left == right

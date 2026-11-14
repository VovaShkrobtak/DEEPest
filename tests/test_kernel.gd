extends SceneTree

var failures: int = 0
func check(value: bool, title: String) -> void:
	if not value:
		push_error(title)
		failures += 1

func _initialize() -> void:
	var script: Script = load("res://src/core/kernel.gd")
	if script == null:
		check(false, "Kernel must exist to execute survival commands")
		quit(1)
		return
	var k = script.new(1998)
	var before: Dictionary = k.export_state()
	check(not k.command("nonsense").ok, "unknown command rejected")
	check(k.export_state() == before, "rejection does not mutate")
	check(not k.command("move", {"target":"forest"}).ok, "graph prevents teleport")
	check(k.command("inspect").ok, "inspect starts action")
	k.step(120)
	check(k.export_state().action.is_empty(), "action completes")
	check(k.export_state().time_s > 0, "action advances world")
	var other = script.new(1998)
	other.command("inspect")
	other.step(120)
	check(k.export_state() == other.export_state(), "same seed commands replay identically")
	check(k.command("rest").ok, "long action starts")
	k.step(120)
	var mid: Dictionary = k.export_state()
	check(not mid.action.is_empty(), "mid-action state serializable")
	var restored = script.new(1)
	check(restored.restore_state(mid).ok, "restore accepts valid mid-action")
	k.step(3600)
	restored.step(3600)
	check(k.export_state() == restored.export_state(), "resume does not duplicate effects")
	var time_before: int = k.export_state().time_s
	k.command("rest")
	k.step(60)
	k.cancel()
	check(k.export_state().time_s == time_before + 60, "cancel retains elapsed consequences")
	var snapshot: Dictionary = k.snapshot()
	snapshot["location_id"] = "hacked"
	check(k.export_state().location != "hacked", "observer detached")
	check(not k.restore_state({"bad":true}).ok, "malformed save rejected")
	print("Kernel tests: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(1 if failures else 0)

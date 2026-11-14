extends SceneTree
const Kernel = preload("res://src/core/kernel.gd")
const Parser = preload("res://src/application/parser.gd")
var failures: int = 0
func check(ok: bool, label: String) -> void:
	if not ok:
		push_error(label)
		failures += 1
func _initialize() -> void:
	var kernel = Kernel.new(1998)
	var parser = Parser.new()
	var initial: Dictionary = kernel.export_state()
	var well: Dictionary = parser.parse("идти к колодцу", kernel.available_actions())
	check(well.ok, "Known well target parsed")
	check(not kernel.command(well.id, well.parameters).ok, "Cannot bypass graph from shelter")
	check(kernel.export_state() == initial, "Rejected route does not mutate")
	var yard: Dictionary = parser.parse("идти во двор", kernel.available_actions())
	check(yard.ok and kernel.command(yard.id, yard.parameters).ok, "Parser starts reachable move")
	kernel.step(600)
	check(kernel.export_state().location == "yard", "Move actually completes")
	well = parser.parse("идти к колодцу", kernel.available_actions())
	check(well.ok and kernel.command(well.id, well.parameters).ok, "Well reachable from yard")
	kernel.step(600)
	check(kernel.export_state().location == "well", "Second move completes")
	var before: Dictionary = kernel.export_state()
	for text in ["пить -1л", "пить NaNл", "пить 9л", "перелить 500 мл"]:
		check(not parser.parse(text, kernel.available_actions()).ok, "Invalid input rejected: " + text)
		check(kernel.export_state() == before, "Parsing is pure")
	var actions: Array = kernel.available_actions()
	for action: Dictionary in actions:
		var parsed: Dictionary = parser.parse(action.title, actions)
		check(parsed.ok and parsed.id == action.id, "Exact metadata title resolves: " + action.title)
		check(kernel.export_state() == before, "Title parsing does not mutate or execute")
	# Enabled status belongs to kernel validation, never bypassed by free text.
	var disabled: Array = [{"id": "drink", "title": "Выпить воды", "enabled": false, "reason": "Нет воды"}]
	var choice: Dictionary = parser.parse("Выпить воды", disabled)
	check(choice.ok and choice.id == "drink", "Disabled choice still names intended command")
	check(not choice.has("enabled") and not choice.parameters.has("enabled"), "Parser cannot override authorization")
	print("parser integration: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

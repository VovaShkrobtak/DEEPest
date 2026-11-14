extends SceneTree
const Nav = preload("res://src/domain/infected_navigation.gd")
const World = preload("res://src/domain/world.gd")
var errors: Array[String] = []
func _initialize() -> void:
	var model = Nav.new()
	var graph: Dictionary = World.new().locations()
	var doors: Dictionary = model.initial_state()
	check(model.validate_state(doors,graph) == "", "Portal defaults validated")
	check(model.shortest_path(graph,doors,"forest","shelter") == ["forest","yard","shelter"], "Grounded route uses existing edges")
	check(model.act(doors,graph,"shelter","yard","close").ok, "Door closes physically")
	check(not model.is_open(doors,"shelter","yard"), "Closed door blocks movement")
	check(model.act(doors,graph,"shelter","yard","brace",2.0).ok, "Physical bracing accumulates mass")
	check(not model.act(doors,graph,"yard","shelter","open").ok, "Braced door cannot be opened through wall")
	var failure: float = model.failure_energy(doors[model.key_for("shelter","yard")],model.key_for("shelter","yard"))
	var result: Dictionary = model.strike(doors,"shelter","yard",failure - 2.0)
	check(result.ok and not result.breached, "Door persists until energy threshold")
	result = model.strike(doors,"yard","shelter",3.0)
	check(result.breached and model.is_open(doors,"yard","shelter"), "Accumulated impact breaches real door")
	check(is_equal_approx(float(result.released_kg),2.0), "Bracing material released only by breach")
	check(model.validate_state(doors,graph).is_empty(), "Breached door remains valid for save/load")
	var broken: Dictionary = doors.duplicate(true)
	broken["shelter|yard"]["brace_kg"] = -1.0
	check(not model.validate_state(broken,graph).is_empty(), "Negative wood cannot enter saves")
	check(not model.act(doors,graph,"forest","garden","open").ok, "No invented direct route")
	print("Navigation and doors: ", "PASS" if errors.is_empty() else JSON.stringify(errors))
	quit(0 if errors.is_empty() else 1)
func check(ok: bool, msg: String) -> void:
	if not ok: errors.append(msg)

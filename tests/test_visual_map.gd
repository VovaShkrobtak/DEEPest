extends SceneTree
## Schematic map must be a pure observer-based UI and activate only actual exits.
const MapProjectionScript = preload("res://src/application/map_projection.gd")
const Map = preload("res://src/adapters/visual_map.gd")
const Kernel = preload("res://src/core/kernel.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var kernel = Kernel.new(1998)
	var observer_snapshot: Dictionary = kernel.snapshot()
	var before: String = JSON.stringify(kernel.export_state())
	var projection = MapProjectionScript.new()
	var house: Dictionary = projection.build(observer_snapshot)
	_check(house.get("mode", "") == "house", "Initial home uses house schematic")
	_check(house.get("routes", []).size() == 1, "Home has only actual yard exit")
	_check(str(house.routes[0].id) == "yard", "Home exit targets yard")
	_check(not house.has("actors") and not house.has("sounds"), "No fabricated actor/sound positions")
	_check(projection.build(observer_snapshot) == house, "Projection is deterministic")
	_check(JSON.stringify(kernel.export_state()) == before, "Projection never mutates the world")
	var view = Map.new()
	root.add_child(view)
	view.size = Vector2(350.0, 280.0)
	view.set_diagram(house)
	await process_frame
	var picked: Array[String] = []
	view.route_selected.connect(func(id: String) -> void: picked.append(id))
	var exit_point: Vector2 = view.route_position("yard")
	_check(exit_point.x > 0.0, "Home exit has a valid touch target")
	_check(view.route_at(exit_point) == "yard", "Home exit can be selected")
	_check(view.route_at(Vector2(5.0, 5.0)).is_empty(), "Empty map area is not a route")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = exit_point
	view._gui_input(click)
	_check(picked == ["yard"], "Click emits a real route identifier")
	_check(JSON.stringify(kernel.export_state()) == before, "Click alone does not move character")
	var yard_snapshot := observer_snapshot.duplicate(true)
	yard_snapshot.location_id = "yard"
	yard_snapshot.routes = kernel.modules.world.locations().yard.connections.duplicate(true)
	var yard: Dictionary = projection.build(yard_snapshot)
	_check(yard.get("mode", "") == "yard", "Yard uses route graph")
	_check(yard.routes.size() == 6, "All six yard connections represented")
	view.set_diagram(yard)
	for route: Dictionary in yard.routes:
		_check(view.route_at(view.route_position(str(route.id))) == str(route.id),
			"Route touch target: " + str(route.id))
	var secret_fixture := yard_snapshot.duplicate(true)
	secret_fixture["hidden_infected_coordinates"] = Vector2(0.8, 0.4)
	secret_fixture["hidden_npc_coordinates"] = Vector2(0.4, 0.3)
	_check(projection.build(secret_fixture) == yard, "Private state cannot alter the map")
	secret_fixture.location_id = "forest"
	_check(projection.build(secret_fixture).is_empty(), "Unknown map locations use text UI")
	view.queue_free()
	await process_frame
	if failures.is_empty():
		print("Visual map 1.0: PASS")
	else:
		for failure: String in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)

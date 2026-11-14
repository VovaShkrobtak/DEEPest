extends SceneTree
const Sound = preload("res://src/domain/acoustics.gd")
const Kernel = preload("res://src/core/kernel.gd")
const World = preload("res://src/domain/world.gd")
const Env = preload("res://src/domain/environment.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var model = Sound.new()
	var graph: Dictionary = World.new().locations()
	var environment: Dictionary = Env.new().initial_state(1998)
	environment.weather.wind_m_s = 0.0
	environment.weather.rain = 0.0
	var state: Dictionary = model.initial_state()
	check(model.emit(state, graph, "yard", "metal", 92.0, "world"), "Valid physical source")
	var event: Dictionary = state.events[0]
	check(model.received_db(event, "yard", 2.0, graph, environment) > model.received_db(event, "yard", 90.0, graph, environment), "Inverse-square field attenuates with distance")
	check(model.received_db(event, "yard", 90.0, graph, environment) > model.received_db(event, "forest", 0.0, graph, environment), "Network path attenuates distant listener")
	var closed: float = model.received_db(event, "shelter", 0.0, graph, environment)
	environment.rooms.shelter.window_open = true
	check(model.received_db(event, "shelter", 0.0, graph, environment) > closed + 8.0, "Open window transmits more than closed window")
	environment.rooms.shelter.window_open = false
	environment.rooms.shelter.sealed = true
	check(model.received_db(event, "shelter", 0.0, graph, environment) < closed, "Sealing further attenuates sound")
	var dry: float = model.background_db("yard", environment)
	environment.weather.wind_m_s = 10.0
	environment.weather.rain = 1.0
	check(model.background_db("yard", environment) > dry + 20.0, "Rain and wind mask ambient sound")
	environment.weather.wind_m_s = 0.0
	environment.weather.rain = 0.0
	var quiet_event: Dictionary = event.duplicate(true)
	quiet_event.level_db = 48.0
	check(not model.can_hear(quiet_event, "forest", 0.0, 25.0, graph, environment), "Quiet distant noise is not detected")
	check(model.can_hear(event, "yard", 20.0, 25.0, graph, environment), "Loud nearby noise can be heard")
	check(not model.emit(state, graph, "nowhere", "metal", 70.0, "world"), "Invalid world source rejected")
	check(not model.emit(state, graph, "yard", "metal", NAN, "world"), "Nonfinite acoustic level rejected")
	check(model.hear(state, "yard", graph, environment).size() == 1, "Sound is observable")
	var report: String = JSON.stringify(model.hear(state, "yard", graph, environment))
	check(not report.contains("world") and not report.contains("yard") and not report.contains("92.0"), "Public sound avoids origin, owner, exact strength")
	check(model.validate_state(state, graph).is_empty(), "Valid acoustic state passes validation")
	var invalid: Dictionary = state.duplicate(true)
	invalid.events[0].level_db = 400.0
	check(not model.validate_state(invalid, graph).is_empty(), "Forged acoustic amplitude rejected")
	model.advance(state, 45.0)
	check(state.events.is_empty(), "Old acoustic events expire deterministically")

	var old_kernel = Kernel.new(1998)
	var legacy_save: Dictionary = old_kernel.export_state()
	legacy_save.erase("acoustics")
	check(old_kernel.restore_state(legacy_save).ok, "Old save gains an acoustic clock without breaking the world")
	check(old_kernel.export_state().acoustics.time_s == float(old_kernel.export_state().time_s), "Legacy sound clock starts aligned to simulation")
	var forged_kernel = Kernel.new(1998)
	var corrupted: Dictionary = forged_kernel.export_state()
	corrupted.acoustics.events.append({"sequence":1,"time_s":0.0,"location":"yard",
		"kind":"metal","level_db":100.0,"offset_m":0.0,"owner":"unknown"})
	corrupted.acoustics.sequence = 1
	check(forged_kernel.restore_state(corrupted).ok, "Physically valid explicit external sound fixture accepted")
	var hostile: Dictionary = corrupted.duplicate(true)
	hostile.acoustics.events[0].location = "missing_region"
	check(not forged_kernel.restore_state(hostile).ok, "Unknown sound source locations cannot enter saves")
	check(forged_kernel.export_state() == corrupted, "Rejected sound forgery does not mutate live world")
	print("Acoustic model: ", "PASS" if failures.is_empty() else JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
func check(result: bool, description: String) -> void:
	if not result: failures.append(description)

extends SceneTree
const World = preload("res://src/domain/world.gd")
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void:
	var model = World.new()
	var a: Dictionary = model.initial_state(1998)
	check(a == model.initial_state(1998), "seed replay")
	check(model.observe(a, "shelter").npcs.is_empty(), "offscreen NPC hidden")
	var journey: Dictionary = model.initial_state(1998)
	model.advance(journey, 60.0, {})
	check(journey.resources.well_water_kg == 1000.0 and journey.npcs.nina.destination == "yard", "no water teleport before journey")
	var scarce: Dictionary = model.initial_state(1998)
	scarce.resources.well_water_kg = 0.1
	model.advance(scarce, 3600.0, {})
	check(scarce.resources.well_water_kg == 0.0, "competing NPCs cannot duplicate water")
	var before: float = a.resources.well_water_kg
	model.advance(a, 3600.0, {})
	check(a.resources.well_water_kg < before, "NPC depletes finite well")
	check(a.npcs.nina.water_kg >= 0.0, "nonnegative NPC water")
	var b: Dictionary = model.initial_state(1998)
	for i in range(60):
		model.advance(b, 60.0, {})
	check(a == b, "fast forward matches minutes")
	var c: Dictionary = model.initial_state(1)
	c.resources.well_water_kg = 0.2
	model.apply(c, {"kind":"take_water", "mass_kg":0.2})
	check(c.resources.well_water_kg == 0.0, "finite water withdrawal")
	check(not model.availability(c, {"kind":"take_water", "mass_kg":0.1}).is_empty(), "empty well rejected")
	check(not model.availability(c, {"kind":"trade", "npc_id":"pavel", "location":"clinic"}).is_empty(), "remote trade rejected")
	var wound: float = c.npcs.nina.body.wound_m2
	model.apply(c, {"kind":"help_nina", "npc_id":"nina", "location":"clinic"})
	check(c.npcs.nina.body.bandaged and c.npcs.nina.body.wound_m2 == wound, "bandage helps without healing wound")
	var cloth: float = c.npcs.pavel.cloth
	model.apply(c, {"kind":"trade", "npc_id":"pavel", "location":"workshop"})
	check(c.npcs.pavel.cloth == cloth - 2.0, "finite barter stock")
	var warm: Dictionary = model.initial_state(9)
	var cold: Dictionary = warm.duplicate(true)
	warm.npcs.pavel.water_kg = 2.0
	cold.npcs.pavel.water_kg = 2.0
	model.advance(warm,60.0,{"weather":{"temp_k":250.0},"rooms":{"workshop":{"temp_k":300.0,"smoke":0.5,"oxygen":0.209}}})
	model.advance(cold,60.0,{"weather":{"temp_k":250.0},"rooms":{"workshop":{"temp_k":270.0,"smoke":0.0,"oxygen":0.209}}})
	check(warm.npcs.pavel.body.skin_k > cold.npcs.pavel.body.skin_k, "NPC uses indoor room temperature")
	check(warm.npcs.pavel.body.toxin > cold.npcs.pavel.body.toxin, "NPC breathes local smoke")
	warm.npcs.pavel.body.conscious = false
	check(not model.availability(warm,{"kind":"talk","npc_id":"pavel","location":"workshop"}).is_empty(), "unconscious NPC cannot talk")
	var plot: Dictionary = model.initial_state(2)
	model.apply(plot,{"kind":"plant"})
	model.advance(plot,60.0,{"weather":{"temp_k":270.0,"rain":1.0},"hour":12.0})
	check(plot.resources.growth == 0.0 and plot.resources.rain_input_kg > 0.0, "Kelvin cold blocks growth and dimensionless rain wets soil")
	model.advance(plot,60.0,{"weather":{"temp_k":290.0},"hour":22.0})
	check(plot.resources.growth == 0.0, "night blocks growth")
	var soil: float = plot.resources.soil_water_kg
	model.advance(plot,60.0,{"weather":{"temp_k":290.0},"hour":12.0})
	check(plot.resources.growth > 0.0 and plot.resources.soil_water_kg < soil and plot.resources.photosynthesis_input_kg > 0.0, "daylight growth has accounted inputs")
	plot.resources.growth = 1.0
	plot.resources.garden_biomass_kg = 2.0
	model.apply(plot,{"kind":"harvest"})
	check(plot.resources.garden_biomass_kg == 0.0 and not model.availability(plot,{"kind":"harvest"}).is_empty(), "harvest cannot duplicate")
	model.apply(plot,{"kind":"plant"})
	check(plot.resources.garden_biomass_kg == 0.0 and plot.resources.growth == 0.0, "reseed starts empty crop")
	print("world: %s failures" % failures)
	quit(1 if failures else 0)

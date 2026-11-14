extends SceneTree
const EnvModel = preload("res://src/domain/environment.gd")
const WorldModel = preload("res://src/domain/world.gd")
var failures: int = 0
func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)
func finite(value: Variant) -> bool:
	if value is float: return is_finite(value)
	if value is Dictionary:
		for item: Variant in value.values():
			if not finite(item): return false
	if value is Array:
		for item: Variant in value:
			if not finite(item): return false
	return true
func _initialize() -> void:
	var env = EnvModel.new()
	var world = WorldModel.new()
	var air: Dictionary = env.initial_state(1998)
	var society: Dictionary = world.initial_state(1998)
	var start: int = Time.get_ticks_usec()
	for day: int in range(100):
		env.advance(air,86400,{})
		world.advance(society,86400,{"weather":air.weather,"rooms":air.rooms})
	check(finite(air) and finite(society),"100-day world contains no NaN/Inf")
	check(air.time_s == 8640000 and society.time_s == 8640000,"100 days preserve monotonic clock")
	check(society.resources.well_water_kg >= 0.0 and society.resources.well_water_kg <= 1000.0,"Water cannot become negative or regenerate on revisit")
	for npc: Dictionary in society.npcs.values():
		check(npc.memory.size() <= 32,"NPC memory remains bounded")
	print("100-day passive domain soak: wall_ms=",(Time.get_ticks_usec()-start)/1000.0," failures=",failures)
	quit(1 if failures else 0)

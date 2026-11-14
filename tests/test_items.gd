extends SceneTree
const Items = preload("res://src/domain/items.gd")
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var m = Items.new()
	var s: Dictionary = m.initial_state()
	check(m.observe(s).process_label == "Питьевой запас", "Initial known reserve has truthful label")
	var perception: Dictionary = s.duplicate(true)
	perception.water.history = "Вода набрана; качество по виду неизвестно"
	perception.water.temp_k = 350.0
	check(m.observe(perception).process_label == "Вода ещё не закипела", "Hot water is not boiled")
	perception.water.temp_k = 373.15
	check("вода кипит" in m.observe(perception).water_text, "Visible boiling is observable")
	perception.water.boil_exposure_s = 60.0
	check(m.observe(perception).process_label == "Воду кипятили", "Actual exposure labels treatment")
	var before: Dictionary = s.duplicate(true)
	m.apply(s, {"type":"add_item", "item":"wood", "amount":NAN})
	check(s == before, "NaN command must not mutate")
	m.apply(s, {"type":"craft_bandage"})
	check(s.inventory.cloth == before.inventory.cloth - 1 and s.inventory.bandage == 1, "cloth conserved into bandage")
	var mass_before_repair: float = m.mass_kg(s)
	m.apply(s, {"type":"repair_radio"})
	check(is_equal_approx(m.mass_kg(s),mass_before_repair), "parts remain installed mass")
	var repaired: Dictionary = s.duplicate(true)
	m.apply(s, {"type":"repair_radio"})
	check(s == repaired, "repeated repair cannot duplicate or spend parts")
	m.apply(s, {"type":"switch_radio"})
	var charge: float = s.electricity.battery_j
	m.advance(s, 100.0, {})
	check(is_equal_approx(s.electricity.battery_j, charge - 100.0), "radio drains one watt")
	m.advance(s, 1e7, {})
	check(s.electricity.battery_j == 0.0 and not s.electricity.radio_on, "finite battery turns circuit off")
	s.water.volume_kg = 0.0
	m.apply(s, {"type":"take_water", "mass_kg":1.0,"temp_k":293.15,"microbes":100.0,"chemical":2.0})
	m.apply(s, {"type":"take_water", "mass_kg":1.0,"temp_k":313.15,"microbes":0.0,"chemical":0.0})
	check(is_equal_approx(s.water.temp_k, 303.15) and s.water.chemical == 1.0, "mix energy and solute")
	m.advance(s, 1200.0, {"heating_water":true,"fire_w":1000.0,"temp_k":293.15})
	check(s.water.microbes < 1.0 and s.water.chemical == 1.0, "heating removes microbes only")
	check(s.water.volume_kg == 2.0, "closed kettle conserves water")
	m.apply(s, {"type":"repair_cart"})
	check(m.capacity_kg(s) > 18.0, "repair cart expands carrying")
	var cold: Dictionary = m.initial_state()
	var warm: Dictionary = cold.duplicate(true)
	m.advance(cold, 3600.0, {"temp_k":273.15})
	m.advance(warm, 3600.0, {"temp_k":303.15})
	check(warm.food_age_warm_s > cold.food_age_warm_s, "food deteriorates faster warm")
	print("items tests: %d failures" % failures)
	quit(failures)

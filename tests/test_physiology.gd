extends SceneTree

const Physiology = preload("res://src/domain/physiology.gd")
var failures: int = 0

func check(ok: bool, label: String) -> void:
	if not ok:
		push_error(label)
		failures += 1

func _initialize() -> void:
	var model = Physiology.new()
	var state: Dictionary = model.initial_state()
	var original: Dictionary = state.duplicate(true)
	model.advance(state, 0.0, {})
	check(state == original, "Zero time must not mutate")
	model.apply(state, {"kind": "drink", "water_kg": 0.3})
	check(state.water_kg == original.water_kg and state.gut_water_kg == 0.3, "Drinking absorbs with delay")
	var before_total: float = state.water_kg + state.gut_water_kg
	model.advance(state, 60.0, {"temp_k": 293.15})
	check(state.water_kg > original.water_kg, "Gut water absorbed")
	check(absf(before_total - state.water_kg - state.gut_water_kg - state.water_lost_kg) < 0.000001, "Water ledger balances")
	var untreated: Dictionary = model.initial_state()
	var treated: Dictionary = untreated.duplicate(true)
	model.apply(treated, {"kind": "bandage"})
	model.advance(untreated, 600.0, {"temp_k": 293.15})
	model.advance(treated, 600.0, {"temp_k": 293.15})
	check(treated.blood_kg > untreated.blood_kg, "Bandage slows bleeding")
	check(treated.wound_m2 > 0.0 and treated.blood_kg <= 5.0, "Bandage does not heal tissue or refill blood")
	var dry: Dictionary = model.initial_state()
	dry.clothing_water_kg = 0.0
	var wet: Dictionary = dry.duplicate(true)
	wet.clothing_water_kg = 0.6
	model.advance(dry, 1800.0, {"temp_k": 278.15, "wind_m_s": 3.0})
	model.advance(wet, 1800.0, {"temp_k": 278.15, "wind_m_s": 3.0})
	check(wet.core_k < dry.core_k, "Wet clothing increases cooling")
	var fast: Dictionary = model.initial_state()
	var slow: Dictionary = fast.duplicate(true)
	model.advance(fast, 7200.0, {"temp_k": 291.15})
	for index in range(120):
		model.advance(slow, 60.0, {"temp_k": 291.15})
	check(fast == slow, "Acceleration uses identical substeps")
	var smoke: Dictionary = model.initial_state()
	model.advance(smoke, 1800.0, {"smoke": 1.0, "oxygen": 0.08})
	check(not smoke.conscious, "Accumulated smoke/hypoxia impairs consciousness")
	var observed: Dictionary = model.observe(model.initial_state())
	check(not observed.has("core_k") and not observed.has("water_kg"), "Observations hide true numbers")
	var sleeper: Dictionary = model.initial_state()
	var tired: float = sleeper.fatigue
	model.advance(sleeper, 3600.0, {"temp_k": 295.15, "sleeping": true, "shelter": true})
	check(sleeper.fatigue < tired, "Safe sleep reduces fatigue")
	for ambient in [291.15, 295.15]:
		var comfortable: Dictionary = model.initial_state()
		model.advance(comfortable, 86400.0, {"temp_k":ambient,"shelter":true})
		check(comfortable.alive and comfortable.core_k > 308.15 and comfortable.core_k < 311.15, "Basal day thermoregulates at comfortable ambient")
	var worker: Dictionary = model.initial_state()
	model.advance(worker, 3600.0, {"temp_k":293.15,"exertion":0.5,"shelter":true})
	check(worker.alive and worker.core_k < 312.15, "Moderate work dissipates metabolic heat")
	check(worker.sweat_evaporated_kg > 0.0, "Warm work evaporates body water")
	check(absf(worker.water_kg + worker.water_lost_kg - 41.5) < 0.000001, "Sweating remains in water balance")
	check(absf(worker.sweat_heat_j - worker.sweat_evaporated_kg * 2400000.0) < 0.001, "Sweat latent heat ledger balances")
	print("physiology: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

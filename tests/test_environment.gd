extends SceneTree

func _initialize() -> void:
	var script: Script = load('res://src/domain/environment.gd')
	if script == null:
		push_error('Environment implementation is missing')
		quit(1)
		return
	var model: RefCounted = script.new()
	var state: Dictionary = model.initial_state(1998)
	assert(not state.rooms.shelter.burning)
	model.apply(state, {'kind': 'add_fuel', 'mass_kg': 2.0})
	model.apply(state, {'kind': 'light_fire'})
	var initial_fuel: float = state.rooms.shelter.fuel_kg
	var fine: Dictionary = state.duplicate(true)
	for i in range(120):
		model.advance(state, 60.0, {})
	for i in range(720):
		model.advance(fine, 10.0, {})
	assert(state.rooms.shelter.fuel_kg < initial_fuel)
	assert(state.rooms.shelter.energy_j > 0.0)
	assert(absf(state.rooms.shelter.temp_k - fine.rooms.shelter.temp_k) < 0.02)
	assert(absf(state.rooms.shelter.fuel_kg - fine.rooms.shelter.fuel_kg) < 0.00001)
	assert(state.rooms.shelter.smoke > 0.1)
	assert(state.rooms.shelter.oxygen < 0.2095)
	var smoke_before: float = state.rooms.shelter.smoke
	model.apply(state, {'kind': 'extinguish'})
	model.apply(state, {'kind': 'ventilate'})
	model.advance(state, 1800.0, {})
	assert(state.rooms.shelter.smoke < smoke_before * 0.1)
	assert(state.rooms.shelter.oxygen > fine.rooms.shelter.oxygen)
	assert(absf(state.rooms.shelter.fuel_kg + state.rooms.shelter.burned_kg - initial_fuel) < 0.00001)
	var room: Dictionary = state.rooms.shelter
	assert(absf(room.energy_j - room.flue_energy_j - room.heat_loss_j - (room.temp_k - 279.15) * 900000.0) < 0.001)
	assert(absf(room.ash_kg + room.exhaust_wood_kg - room.burned_kg) < 0.00001)
	var sealed: Dictionary = model.initial_state()
	var ventilated: Dictionary = sealed.duplicate(true)
	model.apply(sealed, {'kind': 'seal_window'})
	model.apply(ventilated, {'kind': 'ventilate'})
	model.advance(sealed, 3600.0, {})
	model.advance(ventilated, 3600.0, {})
	assert(sealed.rooms.shelter.temp_k > ventilated.rooms.shelter.temp_k)
	var unchanged: Dictionary = sealed.duplicate(true)
	model.apply(sealed, {'kind': 'add_fuel', 'mass_kg': -1.0})
	model.advance(sealed, -1.0, {})
	assert(sealed == unchanged)
	var kettle: Dictionary = model.initial_state()
	var bare: Dictionary = model.initial_state()
	for trial: Dictionary in [kettle, bare]:
		model.apply(trial, {'kind': 'add_fuel', 'mass_kg': 1.0})
		model.apply(trial, {'kind': 'light_fire'})
	model.advance(kettle, 60.0, {'heating_water': true, 'location': 'shelter'})
	model.advance(bare, 60.0, {})
	assert(kettle.rooms.shelter.temp_k < bare.rooms.shelter.temp_k)
	assert(kettle.rooms.shelter.last_water_w > 0.0)
	assert(kettle.rooms.clinic.last_water_w == 0.0)
	var kettle_room: Dictionary = kettle.rooms.shelter
	assert(absf(kettle_room.energy_j - kettle_room.flue_energy_j - kettle_room.heat_loss_j - kettle_room.water_transfer_j - (kettle_room.temp_k - 279.15) * 900000.0) < 0.001)
	model.apply(kettle, {'kind': 'extinguish'})
	model.advance(kettle, 10.0, {'heating_water': true, 'location': 'shelter'})
	assert(kettle.rooms.shelter.last_water_w == 0.0)
	var outdoors: Dictionary = model.conditions(state, 'yard')
	assert(not outdoors.shelter and outdoors.smoke == 0.0)
	var observation: Dictionary = model.observe(state, 'shelter')
	assert(observation.has('objects') and observation.has('warnings'))
	for day in range(100):
		state.time_s = float(day) * 86400.0
		model.advance(state, 10.0, {})
		assert(is_finite(state.weather.temp_k))
		assert(state.weather.temp_k > 230.0 and state.weather.temp_k < 320.0)
	print('PASS environment: fuel/energy, 10/60s equivalence, smoke, vent recovery, 100 day weather')
	quit(0)

extends RefCounted

const HEAT_CAPACITY_J_K: float = 900000.0
const WOOD_ENERGY_J_KG: float = 15000000.0
const AMBIENT_OXYGEN: float = 0.2095

func initial_state(seed_value: int = 1998) -> Dictionary:
	var rooms: Dictionary = {}
	for id: String in ['shelter', 'clinic', 'workshop']:
		rooms[id] = {'temp_k': 279.15, 'smoke': 0.0, 'oxygen': AMBIENT_OXYGEN,
			'window_open': false, 'sealed': false, 'chimney_clean': false,
			'fuel_kg': 0.0, 'burning': false, 'ash_kg': 0.0, 'burned_kg': 0.0,
			'energy_j': 0.0, 'heat_loss_j': 0.0, 'flue_energy_j': 0.0,
			'last_water_w': 0.0, 'water_transfer_j': 0.0,
			'exhaust_wood_kg': 0.0}
	return {'seed': seed_value, 'time_s': 0.0, 'weather': _weather(0.0, seed_value), 'rooms': rooms}

func _weather(time_s: float, seed_value: int) -> Dictionary:
	var day: float = time_s / 86400.0
	var phase: float = float(seed_value % 997) / 997.0 * TAU
	var seasonal: float = 9.0 * cos(TAU * (day + 70.0) / 365.0)
	var front: float = sin(day * 0.73 + phase)
	return {'temp_k': 274.15 + seasonal + 2.0 * sin(TAU * day - PI / 2.0) + 2.0 * front,
		'wind_m_s': 2.0 + 1.5 * sin(day * 1.13 + phase),
		'rain': maxf(0.0, front - 0.55) / 0.45}

func advance(state: Dictionary, dt: float, context: Dictionary) -> Array:
	var events: Array = []
	if not is_finite(dt) or dt <= 0.0:
		return events
	var remaining: float = dt
	while remaining > 0.000001:
		var step: float = minf(10.0, remaining)
		var weather: Dictionary = _weather(float(state.time_s) + step * 0.5, int(state.seed))
		for id: String in _room_ids(state):
			var room: Dictionary = state.rooms[id]
			var was_burning: bool = room.burning
			_tick_room(room, step, weather, bool(context.get('heating_water', false)) and str(context.get('location', '')) == id)
			if was_burning and not room.burning:
				events.append({'type': 'fire_out', 'location': id, 'text': 'Печь погасла: топливо или воздух иссякли.'})
		state.time_s += step
		remaining -= step
	state.weather = _weather(float(state.time_s), int(state.seed))
	return events

func _tick_room(room: Dictionary, dt: float, weather: Dictionary, draw_heat: bool = false) -> void:
	var exchange_s: float = 0.00008 if room.sealed else 0.0002
	if room.window_open:
		exchange_s = 0.003 + float(weather.wind_m_s) * 0.0003
	var burned: float = 0.0
	if room.burning:
		var oxygen_factor: float = clampf((float(room.oxygen) - 0.13) / 0.0795, 0.0, 1.0)
		burned = minf(float(room.fuel_kg), 0.00012 * oxygen_factor * dt)
		room.fuel_kg -= burned
		room.burned_kg += burned
		room.ash_kg += burned * 0.01
		room.exhaust_wood_kg += burned * 0.99
		if room.fuel_kg <= 0.0000001 or oxygen_factor <= 0.001:
			room.burning = false
	var decay: float = exp(-exchange_s * dt)
	var smoke_source: float = burned * (0.04 if room.chimney_clean else 2.5) / dt
	room.smoke = float(room.smoke) * decay + smoke_source / exchange_s * (1.0 - decay)
	# O2 volume fraction: reduced room model, 36 kg of effective air inventory.
	var oxygen_sink: float = burned * 1.4 / 36.0 / dt
	room.oxygen = AMBIENT_OXYGEN + (float(room.oxygen) - AMBIENT_OXYGEN) * decay - oxygen_sink / exchange_s * (1.0 - decay)
	var chemical_j: float = burned * WOOD_ENERGY_J_KG
	var useful_j: float = chemical_j * 0.55
	var water_draw_j: float = minf(useful_j, 900.0 * dt) if draw_heat else 0.0
	room.last_water_w = water_draw_j / dt
	room.water_transfer_j = float(room.get('water_transfer_j', 0.0)) + water_draw_j
	room.energy_j += chemical_j
	room.flue_energy_j += chemical_j - useful_j
	useful_j -= water_draw_j
	var conductance: float = (30.0 if room.sealed else 48.0) + exchange_s * 36000.0
	var equilibrium: float = float(weather.temp_k) + useful_j / dt / conductance
	var old_temp: float = room.temp_k
	room.temp_k = equilibrium + (old_temp - equilibrium) * exp(-conductance * dt / HEAT_CAPACITY_J_K)
	room.heat_loss_j += useful_j - (float(room.temp_k) - old_temp) * HEAT_CAPACITY_J_K

func apply(state: Dictionary, effect: Dictionary) -> void:
	var location: String = str(effect.get('location', 'shelter'))
	if not state.rooms.has(location):
		return
	var room: Dictionary = state.rooms[location]
	match str(effect.get('kind', '')):
		'clean_chimney': room.chimney_clean = true
		'light_fire': room.burning = float(room.fuel_kg) > 0.0 and float(room.oxygen) > 0.14
		'add_fuel':
			var mass: float = float(effect.get('mass_kg', 0.0))
			if is_finite(mass) and mass > 0.0:
				room.fuel_kg += mass
		'extinguish': room.burning = false
		'ventilate': room.window_open = not bool(room.window_open)
		'seal_window': room.sealed = true

func conditions(state: Dictionary, location: String) -> Dictionary:
	if state.rooms.has(location):
		var room: Dictionary = state.rooms[location]
		return {'temp_k': room.temp_k, 'wind_m_s': 0.2 if room.window_open else 0.0,
			'rain': 0.0, 'smoke': room.smoke, 'oxygen': room.oxygen, 'shelter': true}
	return {'temp_k': state.weather.temp_k, 'wind_m_s': state.weather.wind_m_s,
		'rain': state.weather.rain, 'smoke': 0.0, 'oxygen': AMBIENT_OXYGEN, 'shelter': false}

func observe(state: Dictionary, location: String) -> Dictionary:
	var air: Dictionary = conditions(state, location)
	var temp_label: String = 'прохладно'
	if air.temp_k < 273.15:
		temp_label = 'морозно'
	elif air.temp_k < 283.15:
		temp_label = 'холодно'
	elif air.temp_k >= 291.15:
		temp_label = 'тепло'
	var weather_label: String = 'Ветер шевелит голые ветви.'
	if state.weather.rain > 0.1:
		weather_label = 'Сырой дождь стучит по крыше и земле.'
	var descriptions: Array = ['В воздухе ' + temp_label + '.']
	var objects: Array = []
	var warnings: Array = []
	if air.shelter:
		var room: Dictionary = state.rooms[location]
		objects.append({'id': 'stove', 'title': 'Печь', 'text': 'В топке горят дрова.' if room.burning else 'Печь не горит.'})
		objects.append({'id': 'window', 'title': 'Окно', 'text': 'Окно открыто, тянет сквозняком.' if room.window_open else 'Окно закрыто.'})
		if not room.chimney_clean:
			descriptions.append('В дымоходе виден налёт сажи: тягу стоит проверить.')
		if location == 'shelter':
			descriptions.append('Настенный термометр показывает около %d °C.' % roundi(float(room.temp_k) - 273.15))
		if air.smoke > 0.1:
			warnings.append('В комнате пахнет дымом, щиплет глаза. Нужен свежий воздух.')
	else:
		descriptions.append(weather_label)
	return {'temp_label': temp_label, 'weather_label': weather_label, 'description': descriptions, 'objects': objects, 'warnings': warnings}

func _room_ids(state: Dictionary) -> Array:
	var ids: Array = state.rooms.keys()
	ids.sort()
	return ids

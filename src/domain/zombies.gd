extends RefCounted
## Early deterministic, bounded infected model. All positions are distances (metres)
## along local approaches to named places, not invented screen-space coordinates.
## The pathogen/behavior rules are fictional gameplay assumptions, not medicine.
const START_COUNT: int = 3
const HEARING_REFERENCE_M: float = 1.0
const MIN_CONTACT_DISTANCE_M: float = 1.5

func initial_state(seed_value: int = 1998) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 91741
	var agents: Dictionary = {}
	for i in range(START_COUNT):
		var id: String = "infected_%02d" % (i + 1)
		agents[id] = {
			"location": "forest", "distance_m": [260.0, 420.0, 730.0][i] + rng.randf_range(-8.0, 8.0),
			"target_location": "", "alert_s": 0.0, "contact_cooldown_s": 0.0,
			"leg_integrity": rng.randf_range(0.62, 0.95), "tissue_integrity": rng.randf_range(0.70, 0.98),
			"hearing_threshold_db": rng.randf_range(35.0, 43.0), "close_reported": false
		}
	return {"schema_version":1, "seed":seed_value, "time_s":0.0, "agents":agents, "contacts":0}

func availability(state: Dictionary, effect: Dictionary) -> String:
	if String(effect.get("kind","")) != "retreat":
		return "Неизвестное взаимодействие с заражёнными."
	var location: String = str(effect.get("location",""))
	for id: String in state.agents:
		var agent: Dictionary = state.agents[id]
		if agent.location == location and float(agent.distance_m) <= 12.0:
			return ""
	return "Поблизости не видно заражённого, от которого нужно отступать."

func apply(state: Dictionary, effect: Dictionary) -> void:
	if not availability(state,effect).is_empty():
		return
	var location: String = str(effect.get("location",""))
	# Retreat spends time and exertion in the kernel; it only changes relative separation.
	for id: String in state.agents:
		var agent: Dictionary = state.agents[id]
		if agent.location == location and float(agent.distance_m) <= 12.0:
			agent.distance_m += 7.0
			agent.alert_s = maxf(float(agent.alert_s), 240.0)
			agent.close_reported = false

func advance(state: Dictionary, dt: float, context: Dictionary) -> Array:
	var events: Array = []
	if not is_finite(dt) or dt <= 0.0:
		return events
	var player_location: String = str(context.get("player_location", ""))
	var graph: Dictionary = context.get("graph", {})
	var noise_db: float = maxf(0.0, float(context.get("noise_db", 0.0)))
	var barrier_db: float = maxf(0.0, float(context.get("barrier_db", 0.0)))
	var weather_k: float = float(context.get("temperature_k", 280.15))
	var ids: Array = state.agents.keys()
	ids.sort()
	for id: String in ids:
		var agent: Dictionary = state.agents[id]
		agent.contact_cooldown_s = maxf(0.0, float(agent.contact_cooldown_s) - dt)
		# A deteriorating body loses locomotor capacity; frost can immobilise tissue.
		var degradation: float = dt / (240.0 * 86400.0) * (1.0 if weather_k < 293.15 else 2.0)
		agent.tissue_integrity = maxf(0.0, float(agent.tissue_integrity) - degradation)
		var path_m: float = _shortest_distance(graph, str(agent.location), player_location)
		var acoustic_distance_m: float = float(agent.distance_m) + path_m
		var sound_range_m: float = HEARING_REFERENCE_M * pow(10.0, (noise_db - float(agent.hearing_threshold_db) - barrier_db) / 20.0)
		if noise_db > 0.0 and acoustic_distance_m <= sound_range_m:
			agent.alert_s = maxf(float(agent.alert_s), 600.0)
			agent.target_location = player_location
		var alerted: bool = float(agent.alert_s) > 0.0
		agent.alert_s = maxf(0.0, float(agent.alert_s) - dt)
		var speed_m_s: float = 0.32 * float(agent.leg_integrity) * float(agent.tissue_integrity)
		if weather_k < 268.15:
			speed_m_s *= 0.6
		var progress: float = dt * (speed_m_s if alerted else 0.006)
		var remaining_m: float = maxf(0.0, float(agent.distance_m) - progress)
		if alerted and remaining_m <= 0.0 and str(agent.location) != str(agent.target_location):
			var next: String = _next_hop(graph, str(agent.location), str(agent.target_location))
			if next != "":
				var edge_m: float = float(graph[agent.location].connections[next])
				remaining_m = maxf(0.0, edge_m - maxf(0.0, progress - float(agent.distance_m)))
				agent.location = next
		elif not alerted and remaining_m <= 0.0 and str(agent.location) == "forest":
			# Existing infected drift toward settlements, never materialise from thin air.
			agent.location = "yard"
			remaining_m = float(graph.forest.connections.yard)
		agent.distance_m = remaining_m
		if float(agent.alert_s) <= 0.0:
			agent.target_location = ""
		if str(agent.location) == player_location and float(agent.distance_m) <= 30.0 and not agent.close_reported:
			agent.close_reported = true
			events.append({"type":"infected_approach","location":player_location,"text":"Где-то совсем близко слышатся шаркающие шаги и прерывистое дыхание."})
		elif float(agent.distance_m) > 45.0:
			agent.close_reported = false
		if str(agent.location) == player_location and float(agent.distance_m) <= MIN_CONTACT_DISTANCE_M and float(agent.contact_cooldown_s) <= 0.0:
			agent.contact_cooldown_s = 180.0
			state.contacts += 1
			events.append({"type":"infected_contact","location":player_location,
				"text":"Чужие пальцы цепляются за одежду. Вырываясь, вы чувствуете резкую боль в руке.",
				"wound_m2":0.00004,"bleeding_kg_s":0.0000007,"contamination":0.015})
	state.time_s += dt
	return events

func observe(state: Dictionary, location: String) -> Dictionary:
	var result: Dictionary = {"descriptions":[],"warnings":[],"threats":[]}
	for id: String in state.agents:
		var agent: Dictionary = state.agents[id]
		if str(agent.location) != location:
			continue
		var distance_m: float = float(agent.distance_m)
		if distance_m <= 30.0:
			result.warnings.append("Слышны близкие шаркающие шаги. Кто-то движется неестественно.")
			result.threats.append({"id":id,"title":"Заражённый поблизости","text":"Фигура находится рядом. Вы видите неровную походку, но не знаете точного состояния её тела."})
		elif distance_m <= 90.0:
			result.descriptions.append("Между постройками или деревьями время от времени мелькает медленно движущийся силуэт.")
		elif distance_m <= 160.0 and float(agent.alert_s) > 0.0:
			result.descriptions.append("Издали раздаётся хрип и сухое шуршание.")
	return result

func validate_state(state: Dictionary, graph: Dictionary) -> String:
	if not state is Dictionary or not state.has("agents") or not state.agents is Dictionary:
		return "Повреждено состояние заражённых."
	if state.get("schema_version") != 1 or not state.get("contacts") is int and not state.get("contacts") is float:
		return "Некорректная версия или счётчик контактов."
	if int(state.contacts) < 0 or state.agents.size() != START_COUNT:
		return "Некорректное число заражённых."
	for id: String in state.agents:
		if not initial_state(int(state.seed)).agents.has(id): return "Неизвестная сущность заражённого."
		var z: Dictionary = state.agents[id]
		if not z is Dictionary: return "Повреждён заражённый."
		for key: String in ["distance_m","alert_s","contact_cooldown_s","leg_integrity","tissue_integrity","hearing_threshold_db"]:
			if not (z.get(key) is float or z.get(key) is int): return "Некорректное поле заражённого."
			if not is_finite(float(z[key])) or float(z[key]) < 0.0: return "Недопустимое значение заражённого."
		if not graph.has(str(z.get("location",""))): return "Неизвестная локация заражённого."
		if str(z.get("target_location","")) != "" and not graph.has(str(z.target_location)): return "Неизвестная цель заражённого."
		if float(z.leg_integrity) > 1.0 or float(z.tissue_integrity) > 1.0: return "Невозможная сохранность тканей."
		if not z.get("close_reported") is bool: return "Некорректная сенсорная память."
	return ""

func _shortest_distance(graph: Dictionary, origin: String, target: String) -> float:
	if origin == target: return 0.0
	if not graph.has(origin) or not graph.has(target): return 1.0e10
	var frontier: Array = [{"location":origin,"distance":0.0}]
	var best: Dictionary = {}
	best[origin] = 0.0
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.distance) < float(b.distance))
		var current: Dictionary = frontier.pop_front()
		if current.location == target: return float(current.distance)
		for neighbor: String in graph[current.location].connections:
			var candidate: float = float(current.distance) + float(graph[current.location].connections[neighbor])
			if candidate < float(best.get(neighbor,1.0e10)):
				best[neighbor] = candidate
				frontier.append({"location":neighbor,"distance":candidate})
	return 1.0e10

func _next_hop(graph: Dictionary, origin: String, target: String) -> String:
	if not graph.has(origin) or not graph.has(target): return ""
	var shortest: float = 1.0e10
	var chosen: String = ""
	for neighbor: String in graph[origin].connections:
		var candidate: float = float(graph[origin].connections[neighbor]) + _shortest_distance(graph,neighbor,target)
		if candidate < shortest:
			shortest = candidate
			chosen = neighbor
	return chosen

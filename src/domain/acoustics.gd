extends RefCounted
## Deterministic reduced-order acoustics: dB at 1 m, spherical spreading,
## segment absorption, indoor/outdoor transmission and ambient masking.
## Graph path is a surrogate for geometry, not ray-traced room acoustics.
const MAX_EVENTS: int = 96
const MAX_AGE_S: float = 40.0
const AIR_ABSORPTION_DB_M: float = 0.004
const SPEED_OF_SOUND_M_S: float = 343.0
const SOUND_TYPES: Array[String] = ["footsteps", "work", "impact", "metal", "voice", "radio", "fire", "water", "shuffling", "breathing", "environment"]

func initial_state() -> Dictionary:
	return {"schema_version":1, "time_s":0.0, "sequence":0, "events":[]}

func advance(state: Dictionary, dt: float) -> void:
	if not is_finite(dt) or dt < 0.0: return
	state["time_s"] = float(state.get("time_s", 0.0)) + dt
	var retained: Array = []
	for event: Dictionary in state.get("events", []):
		if float(state.time_s) - float(event.get("time_s", 0.0)) <= MAX_AGE_S:
			retained.append(event)
	state["events"] = retained.slice(-MAX_EVENTS)

func emit(state: Dictionary, graph: Dictionary, location: String, kind: String, level_db: float, owner: String, offset_m: float = 0.0) -> bool:
	if not graph.has(location) or kind not in SOUND_TYPES or owner.is_empty() or owner.length() > 64:
		return false
	if not is_finite(level_db) or level_db < 0.0 or level_db > 140.0 or not is_finite(offset_m) or offset_m < 0.0 or offset_m > 20000.0:
		return false
	state["sequence"] = int(state.get("sequence", 0)) + 1
	var event: Dictionary = {"sequence":int(state.sequence), "time_s":float(state.time_s),
		"location":location, "kind":kind, "level_db":level_db, "owner":owner, "offset_m":offset_m}
	state["events"].append(event)
	if state["events"].size() > MAX_EVENTS: state["events"].pop_front()
	return true

func path_distance_m(graph: Dictionary, source: String, destination: String) -> float:
	if source == destination and graph.has(source): return 0.0
	if not graph.has(source) or not graph.has(destination): return INF
	var distances: Dictionary = {source:0.0}
	var visited: Dictionary = {}
	for iteration in range(graph.size()):
		var nearest: String = ""
		var minimum: float = INF
		for candidate: String in distances:
			if not visited.has(candidate) and float(distances[candidate]) < minimum:
				nearest = candidate
				minimum = float(distances[candidate])
		if nearest.is_empty(): break
		if nearest == destination: return minimum
		visited[nearest] = true
		for adjacent: String in graph[nearest].get("connections", {}):
			var proposed: float = minimum + float(graph[nearest].connections[adjacent])
			if proposed < float(distances.get(adjacent, INF)):
				distances[adjacent] = proposed
	return INF

func transmission_loss_db(source: String, listener: String, environment: Dictionary) -> float:
	if source == listener: return 0.0
	var rooms: Dictionary = environment.get("rooms", {})
	var loss: float = 0.0
	for endpoint: String in [source, listener]:
		if rooms.has(endpoint):
			var room: Dictionary = rooms[endpoint]
			loss += 4.0 if bool(room.get("window_open", false)) else (25.0 if bool(room.get("sealed", false)) else 17.0)
	return loss

func background_db(location: String, environment: Dictionary) -> float:
	var weather: Dictionary = environment.get("weather", {})
	var wind: float = maxf(0.0, float(weather.get("wind_m_s", 0.0)))
	var rain: float = clampf(float(weather.get("rain", 0.0)), 0.0, 1.0)
	var indoors: bool = environment.get("rooms", {}).has(location)
	var factor: float = 0.42 if indoors else 1.0
	var db: float = 24.0 + factor * (wind * 2.6 + rain * 22.0)
	var room: Dictionary = environment.get("rooms", {}).get(location, {})
	if bool(room.get("burning", false)): db += 6.0
	return db

func received_db(event: Dictionary, listener_location: String, listener_offset_m: float, graph: Dictionary, environment: Dictionary) -> float:
	var source: String = str(event.get("location", ""))
	var path: float = path_distance_m(graph, source, listener_location)
	if is_inf(path) or not is_finite(listener_offset_m): return -1000.0
	var separation: float = maxf(1.0, path + maxf(0.0, float(event.get("offset_m", 0.0))) + maxf(0.0, listener_offset_m))
	var spread_db: float = 20.0 * log(separation) / log(10.0)
	return float(event.get("level_db", 0.0)) - spread_db - separation * AIR_ABSORPTION_DB_M - transmission_loss_db(source, listener_location, environment)

func can_hear(event: Dictionary, listener_location: String, listener_offset_m: float, threshold_db: float, graph: Dictionary, environment: Dictionary, attention_bonus_db: float = 0.0) -> bool:
	var floor_db: float = maxf(threshold_db - attention_bonus_db, background_db(listener_location, environment) + 3.0 - attention_bonus_db)
	return received_db(event, listener_location, listener_offset_m, graph, environment) >= floor_db

func hear(state: Dictionary, listener_location: String, graph: Dictionary, environment: Dictionary, threshold_db: float = 23.0, attention_bonus_db: float = 0.0, ignore_owner: String = "player") -> Array:
	var records: Array = []
	var ordered: Array = state.get("events", []).duplicate(true)
	ordered.reverse()
	for event: Dictionary in ordered:
		if str(event.get("owner", "")) == ignore_owner: continue
		if float(state.time_s) - float(event.get("time_s", 0.0)) > MAX_AGE_S: continue
		if not can_hear(event, listener_location, 0.0, threshold_db, graph, environment, attention_bonus_db): continue
		var audible_db: float = received_db(event, listener_location, 0.0, graph, environment)
		var noise_floor: float = maxf(threshold_db, background_db(listener_location, environment) + 3.0)
		var strong: bool = audible_db >= noise_floor + 7.0
		var kind: String = str(event.get("kind", "environment"))
		var text_value: String = _uncertain_description(kind, strong)
		records.append({"text":text_value, "kind":kind if strong else "unidentified",
			"severity":"warning" if strong and kind in ["shuffling", "impact", "metal"] else "ordinary",
			"confidence":"recognizable" if strong else "uncertain"})
		if records.size() >= 4: break
	return records

func _uncertain_description(kind: String, recognizable: bool) -> String:
	if not recognizable: return "Слышен слабый, неразборчивый звук. Источник определить не удаётся."
	match kind:
		"shuffling": return "Слышны неровные шаркающие шаги. Кто или что движется — непонятно."
		"breathing": return "Доносится тяжёлое прерывистое дыхание."
		"footsteps": return "Слышны шаги по твёрдой поверхности."
		"impact": return "Раздаётся глухой удар."
		"metal": return "Слышен металлический скрежет."
		"voice": return "Доносятся голоса, но слова трудно разобрать."
		"radio": return "Слышны помехи и треск радиоприёмника."
		"fire": return "Слышно потрескивание огня."
		"water": return "Слышно плескание воды."
		"work": return "Слышна работа инструментом."
	return "Слышен звук из окружающей обстановки."

func validate_state(state: Dictionary, graph: Dictionary) -> String:
	if state.get("schema_version") != 1 or not state.get("events") is Array or not (state.get("sequence") is int or state.get("sequence") is float) or not _whole(state.get("sequence")):
		return "Неверная схема акустических событий."
	if not (state.get("time_s") is int or state.get("time_s") is float) or not is_finite(float(state.time_s)) or float(state.time_s) < 0.0:
		return "Некорректное акустическое время."
	if int(state.sequence) < 0 or state.events.size() > MAX_EVENTS: return "Повреждена очередь звуков."
	var seen: Dictionary = {}
	for event in state.events:
		if not event is Dictionary: return "Повреждено акустическое событие."
		for numeric: String in ["time_s", "level_db", "offset_m"]:
			if not (event.get(numeric) is int or event.get(numeric) is float) or not is_finite(float(event[numeric])) or float(event[numeric]) < 0.0: return "Недопустимая физическая величина звука."
		var number: Variant = event.get("sequence")
		if not (number is int or number is float) or not _whole(number) or int(number) < 1 or int(number) > int(state.sequence) or seen.has(number): return "Повреждён номер звукового события."
		seen[number] = true
		if not graph.has(str(event.get("location", ""))) or not str(event.get("kind", "")) in SOUND_TYPES or not event.get("owner") is String or str(event.owner).length() > 64:
			return "Неизвестный источник звука."
		if float(event.time_s) > float(state.time_s) or float(state.time_s) - float(event.time_s) > MAX_AGE_S + 0.01:
			return "Невозможное время звукового события."
		if float(event.level_db) > 140.0 or float(event.offset_m) > 20000.0: return "Невозможная сила или удалённость звука."
	return ""

func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

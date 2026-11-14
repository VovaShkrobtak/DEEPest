extends RefCounted
## Observer-side sensory gating. No interface primitives or mutations.
## Darkness, bodily condition and sound all limit what can be reported.
func observe(state: Dictionary, modules: Dictionary, location: String) -> Dictionary:
	var body: Dictionary = state.get("body", {})
	var surroundings: Dictionary = state.get("environment", {})
	var alive: bool = bool(body.get("alive", true))
	var conscious: bool = bool(body.get("conscious", true))
	var light: float = illumination(state, location)
	var vision_quality: float = 1.0
	if float(body.get("blood_kg", 5.0)) < 4.0: vision_quality *= 0.55
	if float(body.get("toxin", 0.0)) > 0.3: vision_quality *= 0.7
	if float(body.get("fatigue", 0.0)) > 0.8: vision_quality *= 0.75
	var visibility_m: float = 75.0 * light * vision_quality if alive and conscious else 0.0
	var hearing_penalty_db: float = 0.0
	if float(body.get("blood_kg", 5.0)) < 4.0: hearing_penalty_db += 8.0
	if float(body.get("hypoxia_s", 0.0)) > 40.0: hearing_penalty_db += 9.0
	if float(body.get("fatigue", 0.0)) > 0.7: hearing_penalty_db += 4.0
	var listening: bool = str(state.get("action", {}).get("id", "")) == "listen"
	var sounds: Array = []
	if conscious and alive:
		sounds = modules.acoustics.hear(state.acoustics, location, modules.world.locations(), surroundings, 23.0 + hearing_penalty_db, 8.0 if listening else 0.0)
	var warnings: Array = []
	var descriptions: Array = []
	var visible: Array = []
	if not conscious:
		descriptions.append("Зрение и слух не дают осмысленной картины происходящего.")
	elif light <= 0.04:
		descriptions.append("В темноте почти невозможно различить окружение. О звуках можно судить только на слух.")
	elif light < 0.16:
		descriptions.append("Слабый свет не позволяет разглядеть дальние детали.")
	for record: Dictionary in sounds:
		descriptions.append(str(record.get("text", "")))
		if str(record.get("severity", "")) == "warning":
			warnings.append(str(record.get("text", "")))
	# Named infected agents are not inherently observable: only visible forms.
	# More detailed occlusion needs sub-room geometry (not represented by the 7-node graph).
	if visibility_m >= 1.0:
		for id: String in state.zombies.agents:
			var agent: Dictionary = state.zombies.agents[id]
			if str(agent.get("location", "")) != location: continue
			if float(agent.get("distance_m", INF)) > visibility_m: continue
			var title: String = "Движущаяся фигура"
			var detail: String = "В поле зрения появляется неровно движущийся силуэт. На таком расстоянии невозможно определить состояние человека."
			visible.append({"title":title, "text":detail})
			warnings.append("Вы замечаете движущуюся фигуру неподалёку.")
			break # Do not reveal exact count or identity from coarse location model.
	return {"visible":visible, "warnings":warnings, "description":descriptions, "sounds":sounds,
		"light":light, "visual_range_m":visibility_m, "can_see":visibility_m >= 1.0,
		"can_hear":conscious and alive}

func illumination(state: Dictionary, location: String) -> float:
	var elapsed: float = float(state.get("time_s", 0.0))
	var hour: float = fmod(16.0 + 20.0 / 60.0 + elapsed / 3600.0, 24.0)
	var daylight: float = maxf(0.0, sin(PI * (hour - 6.0) / 12.0))
	var environment: Dictionary = state.get("environment", {})
	var rainy: float = clampf(float(environment.get("weather", {}).get("rain", 0.0)), 0.0, 1.0)
	daylight *= 1.0 - rainy * 0.3
	var room: Dictionary = environment.get("rooms", {}).get(location, {})
	if not room.is_empty():
		daylight *= 0.35 if bool(room.get("window_open", false)) else 0.25
		if bool(room.get("burning", false)): daylight += 0.37
	if bool(state.get("items", {}).get("electricity", {}).get("lamp_on", false)):
		daylight += 0.63
	return clampf(daylight, 0.0, 1.0)

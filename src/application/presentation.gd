extends RefCounted
## Pure presentation contract. Consumes ONLY publicly observable snapshot data.
## Never infer danger, a diagnosis, or positions from hidden kernel state.

const MAX_STATUS_LINES: int = 5

func build(snapshot: Dictionary, catalog: Array) -> Dictionary:
	var body: Dictionary = snapshot.get("body", {})
	var conditions: Dictionary = snapshot.get("conditions", {})
	var visible_threats: Array = snapshot.get("threat_warnings", [])
	var symptoms: Array = []
	for warning in body.get("warnings", []):
		_push_signal(symptoms, str(warning), "body", "warning")
	for sensation in body.get("sensations", []):
		_push_signal(symptoms, str(sensation), "body", "ordinary")
	for warning in conditions.get("warnings", []):
		_push_signal(symptoms, str(warning), "environment", "warning")
	var environment: Array = []
	if not str(conditions.get("temp_label", "")).is_empty():
		_push_signal(environment, "В воздухе " + str(conditions.temp_label) + ".", "environment", "ordinary")
	for warning in visible_threats:
		_push_signal(environment, str(warning), "perception", "danger")
	var alert: bool = not visible_threats.is_empty()
	var active: bool = not snapshot.get("action", {}).is_empty()
	var actions: Array = []
	var urgent: Array = []
	var people_visible: bool = not snapshot.get("people", []).is_empty()
	for descriptor: Dictionary in catalog:
		if not bool(snapshot.get("alive", true)):
			continue
		if not bool(snapshot.get("conscious", true)) and str(descriptor.get("id", "")) != "wait":
			continue
		var id: String = str(descriptor.get("id", ""))
		if not bool(descriptor.get("enabled", false)):
			continue
		var category: String = str(descriptor.get("category", ""))
		# Disabled retreat buttons disclose proximity even when the player cannot perceive a threat.
		if id == "retreat" and not alert:
			continue
		if category == "Люди" and not people_visible:
			continue
		# The kernel remains authoritative for whether a chosen action can start.
		var safe: Dictionary = descriptor.duplicate(true)
		safe["time_hint"] = _time_hint(id, float(descriptor.get("duration_s", 0.0)))
		actions.append(safe)
		if alert and (id == "retreat" or id == "listen" or id.begins_with("move:")) and bool(descriptor.get("enabled", false)):
			urgent.append(safe)
	return {
		"status": symptoms.slice(0, MAX_STATUS_LINES),
		"status_more": maxi(0, symptoms.size() - MAX_STATUS_LINES),
		"environment": environment,
		"threat_observed": alert,
		"attention": "work" if active else ("alert" if alert else "exploration"),
		"actions": actions,
		"urgent_actions": urgent,
		"people_empty": "В поле зрения никого нет. Это не доказывает, что поблизости никого не осталось.",
		"no_symptoms": "Дыхание ровное. Явного дискомфорта сейчас нет."
	}

func _push_signal(records: Array, value: String, source: String, severity: String) -> void:
	if value.is_empty():
		return
	for entry: Dictionary in records:
		if entry.text == value:
			return
	records.append({"text":value, "source":source, "severity":severity})

func _time_hint(id: String, seconds: float) -> String:
	if id.begins_with("move:"):
		return "Время пути зависит от темпа и нагрузки"
	if seconds < 90.0:
		return "Обычно несколько десятков секунд"
	if seconds < 600.0:
		return "Потребуется несколько минут"
	if seconds < 3600.0:
		return "Может занять значительную часть часа"
	return "Длительная работа; возможны перерывы"

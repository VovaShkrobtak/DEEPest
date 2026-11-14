extends RefCounted
## Perception boundary. Only public subsystem observations reach the interface.
func build(state: Dictionary, modules: Dictionary) -> Dictionary:
	var location: String = str(state.get("location", "shelter"))
	var body: Dictionary = modules.physiology.observe(state.body)
	var environment: Dictionary = modules.environment.observe(state.environment, location)
	var world: Dictionary = modules.world.observe(state.world, location)
	var infected: Dictionary = modules.zombies.observe(state.zombies, location)
	var inventory: Dictionary = modules.items.observe(state.items)
	var locations: Dictionary = modules.world.locations()
	var metadata: Dictionary = locations.get(location, {})
	var seconds: int = int(state.get("time_s", 0))
	var local_seconds: int = seconds + 16 * 3600 + 20 * 60
	var day: int = local_seconds / 86400 + 1
	var clock: int = local_seconds % 86400
	var calendar: Dictionary = Time.get_datetime_dict_from_unix_time(908382000 + seconds)
	var months: Array[String] = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
	var descriptions: Array = []
	var base = metadata.get("description", "")
	if base is Array:
		descriptions.append_array(base)
	elif not str(base).is_empty():
		descriptions.append(str(base))
	if not world.get("description", []).is_empty():
		descriptions = world.get("description", []).duplicate()
	descriptions.append_array(environment.get("description", []))
	descriptions.append_array(infected.get("descriptions", []))
	var journal: Array = state.get("journal", []).slice(-120).duplicate(true)
	for entry: Dictionary in journal:
		var entry_clock: int = (int(entry.get("time_s", 0)) + 16 * 3600 + 20 * 60) % 86400
		entry["time_label"] = "%02d:%02d" % [entry_clock / 3600, (entry_clock / 60) % 60]
	return {"location_id": location, "location_title": metadata.get("title", location),
		"description": descriptions, "conditions": environment, "body": body,
		"inventory": inventory, "people": world.get("npcs", []),
		"objects": environment.get("objects", []) + world.get("resources", []) + infected.get("threats", []),
		"threat_warnings": infected.get("warnings", []),
		"routes": metadata.get("connections", []), "journal": journal,
		"action": state.get("action", {}).duplicate(true), "goals": state.get("goals", []).duplicate(true),
		"time_label": "%02d:%02d" % [clock / 3600, (clock / 60) % 60],
		"date_label": "%d %s %d" % [calendar.day, months[calendar.month - 1], calendar.year], "day": day,
		"won": state.get("won", false), "seed": state.get("seed", 1998), "alive": body.get("alive", true),
		"conscious": body.get("conscious", true)}.duplicate(true)

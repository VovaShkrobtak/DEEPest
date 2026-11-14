extends RefCounted
## Persistent coarse navigation: graph portals and physical barriers.
## Assumed failure energies in joules. This is NOT 3D collision geometry.
const DOOR_LINKS: Dictionary = {
	"shelter|yard": {"failure_j":260.0, "material":"wood"},
	"clinic|yard": {"failure_j":340.0, "material":"wood"},
	"workshop|yard": {"failure_j":410.0, "material":"metal"}
}
const OBSTACLES: Dictionary = {
	"yard":{"detour_m":7.0, "fall_risk":0.045, "type":"debris"},
	"forest":{"detour_m":12.0, "fall_risk":0.065, "type":"roots"},
	"workshop":{"detour_m":4.0, "fall_risk":0.04, "type":"scrap"}
}
const MAX_BRACE_KG: float = 12.0

func initial_state() -> Dictionary:
	var doors: Dictionary = {}
	for key: String in DOOR_LINKS:
		doors[key] = {"open":true, "damage_j":0.0, "brace_kg":0.0}
	return doors

func key_for(a: String, b: String) -> String:
	var first: String = a if a < b else b
	var second: String = b if a < b else a
	return first + "|" + second

func door_for(doors: Dictionary, a: String, b: String) -> Dictionary:
	return doors.get(key_for(a,b), {})

func adjacent_doors(doors: Dictionary, graph: Dictionary, location: String) -> Array:
	var adjacent: Array = []
	if not graph.has(location): return adjacent
	for neighbor: String in graph[location].connections:
		var key: String = key_for(location, neighbor)
		if doors.has(key):
			adjacent.append({"other":neighbor, "key":key, "door":doors[key].duplicate(true)})
	return adjacent

func failure_energy(door: Dictionary, key: String) -> float:
	return float(DOOR_LINKS[key].failure_j) + float(door.brace_kg) * 190.0

func is_open(doors: Dictionary, a: String, b: String) -> bool:
	var door: Dictionary = door_for(doors,a,b)
	return door.is_empty() or bool(door.open)

func act(doors: Dictionary, graph: Dictionary, from: String, to: String, kind: String, brace_mass_kg: float = 0.0) -> Dictionary:
	if not graph.has(from) or not graph[from].connections.has(to):
		return {"ok":false,"reason":"Между местами нет прямого прохода."}
	var key: String = key_for(from,to)
	if not doors.has(key): return {"ok":false,"reason":"Здесь нет двери."}
	var door: Dictionary = doors[key]
	match kind:
		"open":
			if bool(door.open): return {"ok":false,"reason":"Дверь уже открыта."}
			if float(door.brace_kg) > 0.0: return {"ok":false,"reason":"Проход подпёрт. Сначала освободите его."}
			door.open = true
		"close":
			if not bool(door.open): return {"ok":false,"reason":"Дверь уже закрыта."}
			door.open = false
		"brace":
			if bool(door.open): return {"ok":false,"reason":"Нельзя подпереть открытую дверь."}
			if brace_mass_kg <= 0.0 or not is_finite(brace_mass_kg) or float(door.brace_kg) + brace_mass_kg > MAX_BRACE_KG:
				return {"ok":false,"reason":"Нужна подходящая подпорка."}
			door.brace_kg += brace_mass_kg
		"unbrace":
			if float(door.brace_kg) <= 0.0: return {"ok":false,"reason":"Подпорки нет."}
			var removed: float = float(door.brace_kg)
			door.brace_kg = 0.0
			return {"ok":true,"recovered_kg":removed}
		_:
			return {"ok":false,"reason":"Неизвестное воздействие на дверь."}
	return {"ok":true}

func strike(doors: Dictionary, a: String, b: String, impact_j: float) -> Dictionary:
	var key: String = key_for(a,b)
	if not doors.has(key) or not is_finite(impact_j) or impact_j <= 0.0:
		return {"ok":false,"breached":false,"released_kg":0.0}
	var door: Dictionary = doors[key]
	if bool(door.open): return {"ok":false,"breached":false,"released_kg":0.0}
	door.damage_j = minf(float(door.damage_j) + impact_j, failure_energy(door,key))
	if float(door.damage_j) >= failure_energy(door,key):
		door.open = true
		var released: float = float(door.brace_kg)
		door.brace_kg = 0.0
		return {"ok":true,"breached":true,"released_kg":released}
	return {"ok":true,"breached":false,"released_kg":0.0}

func shortest_path(graph: Dictionary, doors: Dictionary, start: String, finish: String) -> Array:
	# Dijkstra across *existing* graph edges. Closed doors have an explicit
	# breach cost, but are never crossed by teleportation.
	if not graph.has(start) or not graph.has(finish): return []
	if start == finish: return [start]
	var distance: Dictionary = {start:0.0}
	var previous: Dictionary = {}
	var settled: Dictionary = {}
	for unused in range(graph.size()):
		var current: String = ""
		var best: float = INF
		for node: String in distance:
			if not settled.has(node) and float(distance[node]) < best:
				current = node
				best = float(distance[node])
		if current.is_empty(): break
		if current == finish: break
		settled[current] = true
		for neighbor: String in graph[current].connections:
			var door: Dictionary = door_for(doors,current,neighbor)
			var extra: float = 0.0
			if not door.is_empty() and not bool(door.open):
				extra = 20.0 + maxf(0.0, failure_energy(door,key_for(current,neighbor)) - float(door.damage_j)) / 6.0
			extra += float(OBSTACLES.get(neighbor,{}).get("detour_m",0.0))
			var cost: float = best + float(graph[current].connections[neighbor]) + extra
			if cost < float(distance.get(neighbor,INF)):
				distance[neighbor] = cost
				previous[neighbor] = current
	if not distance.has(finish): return []
	var path: Array = [finish]
	var cursor: String = finish
	while cursor != start:
		if not previous.has(cursor): return []
		cursor = str(previous[cursor])
		path.push_front(cursor)
	return path

func validate_state(doors: Dictionary, graph: Dictionary) -> String:
	if not doors is Dictionary or doors.size() != DOOR_LINKS.size(): return "Изменён состав дверей."
	for key: String in DOOR_LINKS:
		if not doors.has(key): return "Дверь пропала из сохранения."
		var ends: PackedStringArray = key.split("|")
		if ends.size() != 2 or not graph.has(ends[0]) or not graph[ends[0]].connections.has(ends[1]):
			return "Дверь соединяет неизвестные места."
		var door: Variant = doors[key]
		if not door is Dictionary or door.size() != 3 or not door.get("open") is bool:
			return "Повреждено состояние двери."
		for property: String in ["damage_j","brace_kg"]:
			var value: Variant = door.get(property)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0:
				return "Недопустимая механическая величина двери."
		if float(door.brace_kg) > MAX_BRACE_KG: return "Недопустимая масса подпорки."
		if bool(door.open) and float(door.brace_kg) > 0.0: return "Открытая дверь не может быть подпёрта."
		if float(door.damage_j) > failure_energy(door,key): return "Повреждение превышает предел разрушения."
	for key: String in doors:
		if not DOOR_LINKS.has(key): return "Поддельная дверь."
	return ""

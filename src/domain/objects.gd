extends RefCounted
## Property-driven environmental objects. Coarse doorway geometry, SI units.
const DATA: Dictionary = {
	"shelter_wardrobe":{"title":"Платяной шкаф","alias":"шкаф","location":"shelter","material":"дерево","mass_kg":24.0,"width_m":0.82,"height_m":1.9,"depth_m":0.54,"friction":0.42,"salvage":{"wood":5,"parts":1}},
	"shelter_stool":{"title":"Табуретка","alias":"табурет","location":"shelter","material":"дерево","mass_kg":4.5,"width_m":0.40,"height_m":0.48,"depth_m":0.40,"friction":0.48,"salvage":{"wood":2}},
	"yard_crate":{"title":"Деревянный ящик","alias":"ящик","location":"yard","material":"дерево","mass_kg":9.0,"width_m":0.65,"height_m":0.55,"depth_m":0.55,"friction":0.52,"salvage":{"wood":3}},
	"clinic_cabinet":{"title":"Медицинская тумба","alias":"тумб","location":"clinic","material":"металл","mass_kg":14.0,"width_m":0.62,"height_m":0.84,"depth_m":0.48,"friction":0.38,"salvage":{"parts":3}},
	"workshop_shelf":{"title":"Стеллаж","alias":"стеллаж","location":"workshop","material":"металл","mass_kg":32.0,"width_m":1.25,"height_m":2.0,"depth_m":0.55,"friction":0.50,"salvage":{"parts":5}}
}
const MAX_BRACE_KG: float = 12.0

func initial_state() -> Dictionary:
	var entities: Dictionary = {}
	for id: String in DATA:
		entities[id] = {"location":str(DATA[id].location),"placement":"floor","intact":true,"damaged":false,"debris_kg":0.0}
	return {"version":1,"entities":entities}

func door_key(a: String,b: String) -> String:
	return (a if a < b else b)+"|"+(b if a < b else a)

func brace_weight(id: String, entity: Dictionary) -> float:
	return minf(7.0,float(DATA[id].mass_kg)*0.3)*(0.6 if bool(entity.damaged) else 1.0)

func brace_at(state: Dictionary, key: String) -> float:
	var total: float = 0.0
	for id: String in state.entities:
		var entry: Dictionary = state.entities[id]
		if bool(entry.intact) and str(entry.placement) == "door:"+key:
			total += brace_weight(id,entry)
	return total

func release_door(state: Dictionary, key: String, broken: bool = false) -> void:
	for id: String in state.entities:
		var entry: Dictionary = state.entities[id]
		if str(entry.placement) == "door:"+key:
			entry.placement = "floor"
			if broken: entry.damaged = true

func reconcile_breaches(state: Dictionary, doors: Dictionary) -> void:
	for id: String in state.entities:
		var entry: Dictionary = state.entities[id]
		var placement: String = str(entry.placement)
		if placement.begins_with("door:"):
			var key: String = placement.substr(5)
			if not doors.has(key) or bool(doors[key].open):
				entry.placement = "floor"
				entry.damaged = true

func observe(state: Dictionary, location: String) -> Array:
	var result: Array = []
	for id: String in DATA:
		var entry: Dictionary = state.entities[id]
		if str(entry.location) != location: continue
		var def: Dictionary = DATA[id]
		var detail: String
		if not bool(entry.intact):
			detail = "Остались обломки и отходы массой около %.1f кг." % float(entry.debris_kg)
		elif str(entry.placement).begins_with("door:"):
			detail = "Установлен перед дверью, сопротивляется взлому; масса %.1f кг." % float(def.mass_kg)
		else:
			detail = "%s; около %.1f кг; %.2f × %.2f × %.2f м." % [str(def.material),float(def.mass_kg),float(def.width_m),float(def.height_m),float(def.depth_m)]
			if bool(entry.damaged): detail += " Крепления повреждены."
		result.append({"title":str(def.title),"text":detail})
	return result

func can_act(state: Dictionary,id: String,verb: String,location: String,other: String,graph: Dictionary,doors: Dictionary,grip: float,mobility: float,has_tool: bool) -> String:
	if not DATA.has(id) or not state.entities.has(id): return "Такого предмета здесь нет."
	var entry: Dictionary = state.entities[id]
	var def: Dictionary = DATA[id]
	if str(entry.location) != location: return "Предмет находится в другом месте."
	if verb == "prop_inspect": return ""
	if not bool(entry.intact): return "Предмет уже разобран."
	if verb == "prop_unbrace":
		return "" if str(entry.placement).begins_with("door:") else "Предмет не подпирает дверь."
	if str(entry.placement) != "floor": return "Сначала отодвиньте предмет от двери."
	if verb == "prop_dismantle":
		return "" if has_tool else "Нужен исправный инструмент."
	var available_force_n: float = 180.0*grip+120.0*mobility
	var resistance_n: float = float(def.mass_kg)*9.81*float(def.friction)
	if available_force_n < resistance_n: return "Не хватает силы или устойчивости, чтобы сдвинуть предмет."
	if not graph.has(location) or not graph[location].connections.has(other): return "Нет доступного прохода."
	var door: Dictionary = doors.get(door_key(location,other),{})
	if verb == "prop_move":
		if float(def.width_m)>0.9: return "Предмет не проходит по ширине дверного проёма."
		if not door.is_empty() and not bool(door.open): return "Дверь закрыта."
		return ""
	if verb == "prop_brace":
		if door.is_empty(): return "В проходе нет двери."
		if bool(door.open): return "Сначала закройте дверь."
		if float(door.brace_kg)+brace_weight(id,entry)>MAX_BRACE_KG+0.000001: return "Слишком много подпорок."
		return ""
	return "Неизвестное действие с предметом."

func apply(state: Dictionary,id: String,verb: String,other: String = "") -> Dictionary:
	var entry: Dictionary = state.entities[id]
	match verb:
		"prop_move":
			entry.location = other
			return {"moved":true}
		"prop_brace":
			entry.placement = "door:"+door_key(str(entry.location),other)
			return {"brace_kg":brace_weight(id,entry)}
		"prop_unbrace":
			entry.placement = "floor"
			return {"released":true}
		"prop_dismantle":
			entry.intact = false
			var salvage: Dictionary = DATA[id].salvage.duplicate(true)
			# Salvage in inventory mass units; remaining mass stays in the scene.
			entry.debris_kg = maxf(0.0,float(DATA[id].mass_kg)-float(salvage.get("wood",0))-float(salvage.get("parts",0))*0.3)
			return {"salvage":salvage,"debris_kg":entry.debris_kg}
	return {}

func validate_state(state: Dictionary,graph: Dictionary,doors: Dictionary) -> String:
	if not state is Dictionary or state.get("version")!=1 or not state.get("entities") is Dictionary: return "Повреждена схема предметов."
	if state.size()!=2 or state.entities.size()!=DATA.size(): return "Изменён набор предметов."
	for id: String in DATA:
		if not state.entities.has(id) or not state.entities[id] is Dictionary: return "Предмет пропал."
		var entry: Dictionary = state.entities[id]
		if entry.size()!=5 or not entry.get("location") is String or not entry.get("placement") is String or not entry.get("intact") is bool or not entry.get("damaged") is bool:
			return "Повреждено состояние предмета."
		if not graph.has(entry.location) or not (entry.debris_kg is float or entry.debris_kg is int) or not is_finite(float(entry.debris_kg)): return "Недопустимая масса или место."
		if float(entry.debris_kg)<0.0 or float(entry.debris_kg)>float(DATA[id].mass_kg): return "Недопустимые обломки."
		if bool(entry.intact) and float(entry.debris_kg)!=0.0: return "Некорректные обломки целого предмета."
		if not bool(entry.intact) and str(entry.placement)!="floor": return "Разобранный предмет блокирует проход."
		if entry.placement!="floor":
			if not str(entry.placement).begins_with("door:"): return "Неизвестное положение."
			var key: String = str(entry.placement).substr(5)
			if not doors.has(key) or bool(doors[key].open) or not key.split("|").has(str(entry.location)): return "Предмет подпирает несуществующую дверь."
	for key: String in doors:
		if brace_at(state,key)>float(doors[key].brace_kg)+0.00001: return "Недостаточная механическая масса подпорки."
	return ""

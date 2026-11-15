extends RefCounted
## Composition-based constructions: materials and fasteners, never recipe IDs.
## Quantities are discrete units, mass in kg. Door bracing remains graph-based.
const MATERIALS: Dictionary = {
	"wood":{"mass_kg":1.0,"rigidity":115.0},
	"cloth":{"mass_kg":0.15,"rigidity":12.0},
	"wire":{"mass_kg":0.1,"rigidity":40.0},
	"parts":{"mass_kg":0.3,"rigidity":75.0}
}
const CONNECTORS: Array[String] = ["wire","cloth","parts"]
const MAX_ASSEMBLIES: int = 64

func initial_state() -> Dictionary:
	return {"version":1,"next_id":1,"entities":{}}

func _parts(a: String,b: String,link: String) -> Dictionary:
	var parts: Dictionary = {}
	for key: String in [a,b,link]:
		parts[key] = int(parts.get(key,0))+1
	return parts

func materials_valid(a: String,b: String,link: String) -> bool:
	return MATERIALS.has(a) and MATERIALS.has(b) and link in CONNECTORS

func components_mass(parts: Dictionary) -> float:
	var total: float = 0.0
	for key: String in parts:
		total += float(MATERIALS[key].mass_kg)*int(parts[key])
	return total

func rigidity(parts: Dictionary,damaged: bool = false) -> float:
	var power: float = 0.0
	for key: String in parts:
		power += float(MATERIALS[key].rigidity)*int(parts[key])
	return power*(0.5 if damaged else 1.0)

func brace_weight(entry: Dictionary) -> float:
	return minf(8.0,float(entry.mass_kg)*0.55)*(0.5 if bool(entry.damaged) else 1.0)

func brace_at(state: Dictionary,key: String) -> float:
	var amount: float = 0.0
	for id: String in state.entities:
		var entity: Dictionary = state.entities[id]
		if str(entity.placement) == "door:"+key:
			amount += brace_weight(entity)
	return amount

func release_door(state: Dictionary,key: String,broken: bool = false) -> void:
	for id: String in state.entities:
		var entity: Dictionary = state.entities[id]
		if str(entity.placement)=="door:"+key:
			entity.placement = "floor"
			if broken: entity.damaged = true

func reconcile_breaches(state: Dictionary,doors: Dictionary) -> void:
	for id: String in state.entities:
		var entity: Dictionary = state.entities[id]
		var placement: String = str(entity.placement)
		if placement.begins_with("door:"):
			var key: String = placement.substr(5)
			if not doors.has(key) or bool(doors[key].open):
				entity.placement = "floor"
				entity.damaged = true

func add(state: Dictionary,location: String,a: String,b: String,link: String) -> String:
	var id: String = "assembly_%04d" % int(state.next_id)
	state.next_id += 1
	var parts: Dictionary = _parts(a,b,link)
	state.entities[id] = {"location":location,"components":parts,"connector":link,
		"placement":"floor","mass_kg":components_mass(parts),"damaged":false}
	return id

func dismantle(state: Dictionary,id: String) -> Dictionary:
	var parts: Dictionary = state.entities[id].components.duplicate(true)
	state.entities.erase(id)
	return parts

func observe(state: Dictionary,location: String) -> Array:
	var result: Array = []
	var ids: Array = state.entities.keys()
	ids.sort()
	for id: String in ids:
		var entry: Dictionary = state.entities[id]
		if str(entry.location)!=location: continue
		var names: Array[String] = []
		for part: String in entry.components:
			names.append("%s × %d" % [part,int(entry.components[part])])
		var placement: String = "У двери." if str(entry.placement).begins_with("door:") else "На земле."
		result.append({"id":id,"title":"Самодельная конструкция "+id.substr(9),
			"text":"Материалы: "+", ".join(names)+". Масса %.2f кг. %s" % [float(entry.mass_kg),placement]+
				(" Повреждена." if bool(entry.damaged) else ""),
			"components":entry.components.duplicate(true),"mass_kg":float(entry.mass_kg),"placement":str(entry.placement)})
	return result

func validate_state(state: Dictionary,graph: Dictionary,doors: Dictionary) -> String:
	if not state is Dictionary or state.size()!=3 or state.get("version")!=1:
		return "Некорректная схема конструкций."
	if not state.get("next_id") is int and not state.get("next_id") is float: return "Неизвестный идентификатор конструкции."
	if float(state.next_id)!=floor(float(state.next_id)) or float(state.next_id)<1.0 or float(state.next_id)>1000000.0: return "Недопустимый счётчик конструкций."
	if not state.get("entities") is Dictionary or state.entities.size()>MAX_ASSEMBLIES: return "Слишком много конструкций."
	for id: String in state.entities:
		var entry: Variant = state.entities[id]
		if not entry is Dictionary or entry.size()!=6: return "Повреждена конструкция."
		if not str(id).begins_with("assembly_") or not entry.get("location") is String or not graph.has(entry.location): return "Конструкция в неизвестном месте."
		if not entry.get("components") is Dictionary or not entry.get("connector") is String or not entry.get("placement") is String or not entry.get("damaged") is bool: return "Повреждены детали конструкции."
		var parts: Dictionary = entry.components
		if parts.is_empty() or parts.size()>3 or not str(entry.connector) in CONNECTORS: return "Невозможное соединение."
		var count: int = 0
		for part: String in parts:
			var qty: Variant = parts[part]
			if not MATERIALS.has(part) or not (qty is int or qty is float) or not is_finite(float(qty)) or float(qty)!=floor(float(qty)) or int(qty)<1 or int(qty)>3:
				return "Недопустимый состав конструкции."
			count += int(qty)
		if count!=3 or int(parts.get(str(entry.connector),0))<1: return "Неполный состав конструкции."
		var weight: Variant = entry.get("mass_kg")
		if not (weight is int or weight is float) or not is_finite(float(weight)) or absf(float(weight)-components_mass(parts))>0.000001: return "Масса конструкции не совпадает с деталями."
		if str(entry.placement)!="floor":
			if not str(entry.placement).begins_with("door:"): return "Неизвестное положение конструкции."
			var key: String = str(entry.placement).substr(5)
			if not doors.has(key) or bool(doors[key].open) or not key.split("|").has(str(entry.location)): return "Конструкция опирается на несуществующую дверь."
	for key: String in doors:
		if brace_at(state,key)>float(doors[key].brace_kg)+0.00001: return "Недостаточная масса подпорок."
	return ""

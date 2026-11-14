extends RefCounted
## Deterministic, finite local world. Quantities are kg, m, seconds.
const STEP_S: float = 60.0
const Physiology = preload("res://src/domain/physiology.gd")
var physiology = Physiology.new()

func locations() -> Dictionary:
	return {
		"shelter": {"title":"Дом", "description":"Старый сельский дом с печью.", "connections":{"yard":12.0}},
		"yard": {"title":"Двор", "description":"От двора расходятся сельские дороги.", "connections":{"shelter":12.0,"well":180.0,"forest":500.0,"clinic":350.0,"workshop":240.0,"garden":120.0}},
		"well": {"title":"Колодец", "description":"Сруб колодца и тяжёлое ведро. Прозрачность не доказывает безопасность воды.", "connections":{"yard":180.0}},
		"forest": {"title":"Лес", "description":"Редкий лес; валежник и следы мелких животных.", "connections":{"yard":500.0}},
		"clinic": {"title":"Медпункт", "description":"Сельский медпункт; лекарств осталось мало.", "connections":{"yard":350.0}},
		"workshop": {"title":"Мастерская", "description":"Верстак, обрезки ткани и ручной инструмент.", "connections":{"yard":240.0}},
		"garden": {"title":"Огород", "description":"Небольшие грядки возле забора.", "connections":{"yard":120.0}}
	}

func initial_state(seed_value: int = 1998) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {"version":1,"seed":seed_value,"time_s":0.0,"pending_s":0.0,"locations":locations(),
		"resources":{"well_water_kg":1000.0,"forest_wood_kg":rng.randf_range(35.0,55.0),"fauna_kg":rng.randf_range(6.0,10.0),"garden_biomass_kg":0.0,"seeds":8,"soil_water_kg":1.0,"soil_wetness":0.1,"growth":0.0,"planted":false,"rain_input_kg":0.0,"evaporated_water_kg":0.0,"plant_water_kg":0.0,"photosynthesis_input_kg":0.0},
		"npcs":{"nina":_npc("Нина", "clinic", 0.35, 3.0, 2.0),"pavel":_npc("Павел", "workshop", 0.2, 4.0, 8.0)}}

func _npc(title: String, home: String, trust: float, food: float, cloth: float) -> Dictionary:
	var body: Dictionary = physiology.initial_state()
	body.anatomy = physiology.anatomy.initial_state(false)
	body.wound_m2 = 0.0
	body.bleeding_kg_s = 0.0
	body.bandaged = false
	body.infection = 0.0
	if home == "clinic":
		physiology.apply(body, {"kind":"trauma","part":"left_arm",
			"wound_m2":0.00015,"bleeding_kg_s":0.0000005,
			"tissue_damage":{"skin":0.012}})
		body.anatomy.adrenaline = 0.0
		body.stress = 0.22
	body.clothing_water_kg = 0.0
	return {"body":body,"title":title,"home":home,"location":home,"destination":"","travel_s":0.0,"trust":trust,"food":food,"cloth":cloth,"water_kg":0.35,"water_consumed_kg":0.0,"food_consumed":0.0,"needs":{"thirst":0.0,"hunger":0.0,"cold":0.0},"plan":"rest","memory":[],"helped":false}

func advance(state: Dictionary, dt: float, context: Dictionary) -> Array:
	var events: Array = []
	if dt <= 0.0 or not is_finite(dt):
		return events
	state.pending_s += dt
	while state.pending_s >= STEP_S:
		state.pending_s -= STEP_S
		state.time_s += STEP_S
		_tick(state, context, events)
	return events

func _tick(state: Dictionary, context: Dictionary, events: Array) -> void:
	for id in state.npcs:
		var npc: Dictionary = state.npcs[id]
		if not npc.body.alive:
			continue
		var water: float = minf(npc.water_kg, 2.0 / 1440.0)
		npc.water_kg -= water
		npc.water_consumed_kg += water
		npc.needs.thirst += (2.0 / 1440.0 - water)
		var food: float = minf(npc.food, 3.0 / 1440.0)
		npc.food -= food
		npc.food_consumed += food
		physiology.apply(npc.body, {"kind":"eat","water_kg":water,"energy_j":food * 2800000.0})
		npc.needs.hunger += 3.0 / 1440.0 - food
		var weather: Dictionary = context.get("weather", {})
		var local: Dictionary = context.get("rooms", {}).get(npc.location, {}) if npc.destination == "" else {}
		physiology.advance(npc.body, STEP_S, {"temp_k":local.get("temp_k",weather.get("temp_k", 285.15)),"wind_m_s":weather.get("wind_m_s",0.0),"rain":0.0 if not local.is_empty() else weather.get("rain",0.0),"smoke":local.get("smoke",0.0),"oxygen":local.get("oxygen",0.209),"shelter":not local.is_empty(),"exertion":0.35 if npc.destination != "" else 0.0,"sleeping":fmod(state.time_s,86400.0) > 57600.0 and npc.location == npc.home})
		if not npc.body.conscious:
			continue
		npc.needs.cold = maxf(0.0, 12.0 - float(weather.get("temperature_c", 12.0))) if npc.location in ["yard","well"] else 0.0
		if npc.destination != "":
			npc.travel_s = maxf(0.0, npc.travel_s - STEP_S)
			if npc.travel_s <= 0.0:
				npc.location = npc.destination
				npc.destination = ""
				events.append({"type":"npc_arrival","text":"%s приходит." % npc.title,"location":npc.location})
			else:
				continue
		if npc.location == "well" and npc.plan == "water":
			var taken: float = minf(2.0 - npc.water_kg, state.resources.well_water_kg)
			state.resources.well_water_kg -= taken
			npc.water_kg += taken
			npc.plan = "return"
			events.append({"type":"npc_water","text":"%s набирает воду из колодца." % npc.title if taken > 0.0 else "%s опускает пустое ведро: воды нет." % npc.title,"location":"well"})
		if npc.plan == "return":
			if npc.location == npc.home:
				npc.plan = "rest"
			else:
				_depart(state, npc, npc.home if npc.location == "yard" else "yard")
		elif npc.water_kg < 0.5:
			npc.plan = "water"
			_depart(state, npc, "well" if npc.location == "yard" else "yard")
	var r: Dictionary = state.resources
	var weather: Dictionary = context.get("weather", {})
	var rain: float = clampf(float(weather.get("rain", 0.0)),0.0,1.0) * 0.2
	r.rain_input_kg += rain
	r.soil_water_kg += rain
	var evaporation: float = minf(r.soil_water_kg, 0.002)
	r.soil_water_kg -= evaporation
	r.evaporated_water_kg += evaporation
	r.soil_wetness = clampf(r.soil_water_kg / 10.0, 0.0, 1.0)
	var hour: float = fmod(float(context.get("hour", 16.0 + 20.0 / 60.0 + state.time_s / 3600.0)),24.0)
	if r.planted and r.soil_water_kg > 0.1 and float(weather.get("temp_k", 285.15)) > 278.15 and hour >= 6.0 and hour < 18.0:
		var added: float = minf(2.0 - r.garden_biomass_kg, minf(2.0 / (30.0 * 720.0), r.soil_water_kg * 2.0))
		r.soil_water_kg -= added * 0.5
		r.plant_water_kg += added * 0.5
		r.photosynthesis_input_kg += added * 0.5
		r.garden_biomass_kg += added
		r.growth = minf(1.0,r.garden_biomass_kg / 2.0)

func _depart(state: Dictionary, npc: Dictionary, target: String) -> void:
	npc.destination = target
	npc.travel_s = float(state.locations[npc.location].connections[target]) / 1.0

func availability(state: Dictionary, effect: Dictionary) -> String:
	var kind: String = effect.get("kind", "")
	if kind in ["talk","share_food","trade","help_nina"]:
		var id: String = effect.get("npc_id", "nina")
		if not state.npcs.has(id): return "Здесь нет такого человека."
		var n: Dictionary = state.npcs[id]
		if not n.body.alive or not n.body.conscious: return "Человек не может сейчас общаться."
		if n.destination != "" or n.location != effect.get("location", n.location): return "Этот человек сейчас не рядом."
		if kind == "trade" and n.cloth < 2.0: return "Ткань для обмена закончилась."
		if kind == "help_nina" and (id != "nina" or n.helped): return "Повязка уже наложена."
	if kind in ["take_water","gather_wood","hunt","water_garden"]:
		var mass: float = float(effect.get("mass_kg", 1.0))
		if mass <= 0.0 or not is_finite(mass): return "Нужно указать положительную массу."
		var key: String = {"take_water":"well_water_kg","gather_wood":"forest_wood_kg","hunt":"fauna_kg"}.get(kind, "")
		if key != "" and state.resources[key] < mass: return "Здесь недостаточно ресурса."
	if kind == "plant" and (state.resources.seeds <= 0 or state.resources.planted): return "Нет семян или грядка уже засеяна."
	if kind == "harvest" and state.resources.growth < 1.0: return "Урожай ещё не созрел."
	return ""

func apply(state: Dictionary, effect: Dictionary) -> void:
	if not availability(state, effect).is_empty(): return
	var kind: String = effect.get("kind", "")
	var r: Dictionary = state.resources
	match kind:
		"take_water": r.well_water_kg -= float(effect.get("mass_kg",1.0))
		"gather_wood": r.forest_wood_kg -= float(effect.get("mass_kg",1.0))
		"hunt": r.fauna_kg -= float(effect.get("mass_kg",1.0))
		"plant":
			r.seeds -= 1
			r.planted = true
		"water_garden": r.soil_water_kg += float(effect.get("mass_kg",1.0))
		"harvest":
			r.garden_biomass_kg = 0.0
			r.growth = 0.0
			r.planted = false
		"talk", "share_food", "trade", "help_nina":
			var npc: Dictionary = state.npcs[effect.get("npc_id","nina")]
			npc.trust = minf(1.0,npc.trust + {"talk":0.01,"share_food":0.08,"trade":0.02,"help_nina":0.15}[kind])
			if kind == "share_food" or kind == "trade": npc.food += 1.0
			if kind == "trade": npc.cloth -= 2.0
			if kind == "help_nina":
				npc.helped = true
				physiology.apply(npc.body, {"kind":"bandage"})
			npc.memory.append({"time_s":state.time_s,"kind":kind,"source":"player"})
			if npc.memory.size() > 32: npc.memory.pop_front()

func observe(state: Dictionary, location: String) -> Dictionary:
	var result: Dictionary = {"npcs":[],"resources":[],"description":[]}
	if not state.locations.has(location): return result
	result.description.append(state.locations[location].description)
	for id in state.npcs:
		var npc: Dictionary = state.npcs[id]
		if npc.location == location and npc.destination == "":
			result.npcs.append({"id":id,"title":npc.title,"text":"%s здесь. %s" % [npc.title, "Разговаривает охотнее." if npc.trust > 0.5 else "Держится сдержанно."]})
	var r: Dictionary = state.resources
	match location:
		"well": result.resources.append({"id":"water","title":"Колодец","text":"Внизу видна вода." if r.well_water_kg > 0.0 else "Ведро возвращается пустым."})
		"forest":
			result.resources.append({"id":"wood","title":"Валежник","text":"Можно собрать сухие ветки." if r.forest_wood_kg > 1.0 else "Доступный валежник почти выбран."})
			result.resources.append({"id":"fauna","title":"Следы","text":"Встречаются свежие следы." if r.fauna_kg > 1.0 else "Свежих следов почти нет."})
		"garden": result.resources.append({"id":"garden","title":"Грядки","text":"Ростки тянутся над почвой." if r.planted else "Грядки не засеяны."})
	return result

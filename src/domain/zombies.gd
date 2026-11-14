extends RefCounted
## Infected 2.0. Fixed persistent population, stimulus-bound cognition,
## graph-grounded locomotion, energy-based barriers and physical contact.
## Fictional/approximate mechanics, NOT full 3D contact dynamics.
const Navigation = preload("res://src/domain/infected_navigation.gd")
const Anatomy = preload("res://src/domain/anatomy.gd")
const START_COUNT: int = 3
const MIN_CONTACT_DISTANCE_M: float = 1.5
const MAX_MEMORY_S: float = 360.0
const SEARCH_S: float = 150.0
const RNG_MOD: int = 2147483647
const POSTURES: Array[String] = ["upright","fallen","crawling"]
const MODES: Array[String] = ["wander","investigate","pursue","search","obstructed","fallen","grapple"]
var nav = Navigation.new()
var anatomy = Anatomy.new()

func initial_state(seed_value: int = 1998) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 91741
	var agents: Dictionary = {}
	for i: int in range(START_COUNT):
		var id: String = "infected_%02d" % (i+1)
		agents[id] = _new_agent(seed_value, i)
		agents[id]["distance_m"] = [260.0,420.0,730.0][i] + rng.randf_range(-8.0,8.0)
		agents[id]["leg_integrity"] = rng.randf_range(0.62,0.95)
		agents[id]["tissue_integrity"] = rng.randf_range(0.70,0.98)
		agents[id]["hearing_threshold_db"] = rng.randf_range(35.0,43.0)
	return {"schema_version":3, "seed":seed_value, "time_s":0.0,
		"agents":agents, "contacts":0, "doors":nav.initial_state()}

func _new_agent(seed_value: int, index: int) -> Dictionary:
	return {"location":"forest", "distance_m":260.0, "target_location":"",
		"alert_s":0.0, "contact_cooldown_s":0.0,
		"leg_integrity":0.8, "tissue_integrity":0.8,
		"hearing_threshold_db":39.0, "close_reported":false,
		"mode":"wander", "posture":"upright",
		"memory_s":0.0, "search_s":0.0, "search_index":0,
		"last_stimulus_sequence":0, "rng_state":int((abs(seed_value) + 1 + (index+1)*57991) % (RNG_MOD-1)) + 1,
		"stability":0.85, "fallen_s":0.0, "grapple_s":0.0,
		"grapple_strength":0.0, "impact_cooldown_s":0.0,
		"obstacle_delay_m":0.0, "obstacle_site":"", "search_origin":"",
		"anatomy":anatomy.initial_state(false),"blood_kg":5.0,
		"blood_loss_kg":0.0,"mass_kg":74.0,"alive":true}

func migrate_state(saved: Dictionary) -> Dictionary:
	# Legacy saves retain their original infected IDs, position, contact
	# wounds and timing. This operation adds fields but never resurrects actors.
	var upgraded: Dictionary = saved.duplicate(true)
	if int(upgraded.get("schema_version",0)) not in [1,2]: return upgraded
	if not upgraded.get("agents") is Dictionary: return upgraded
	var ids: Array = upgraded.agents.keys()
	ids.sort()
	for i: int in range(ids.size()):
		var id: String = str(ids[i])
		if not upgraded.agents[id] is Dictionary: continue
		var defaults: Dictionary = _new_agent(int(upgraded.get("seed",1998)),i)
		for field: String in defaults:
			if not upgraded.agents[id].has(field):
				upgraded.agents[id][field] = defaults[field]
	if not upgraded.has("doors"): upgraded["doors"] = nav.initial_state()
	upgraded["schema_version"] = 3
	return upgraded

func availability(state: Dictionary, effect: Dictionary) -> String:
	var kind: String = str(effect.get("kind",""))
	var location: String = str(effect.get("location",""))
	if kind in ["retreat","shove","break_grapple"]:
		var found: bool = false
		for id: String in state.agents:
			var agent: Dictionary = state.agents[id]
			if str(agent.location) != location or not bool(agent.get("alive",true)): continue
			if kind == "break_grapple" and float(agent.grapple_s) > 0.0:
				found = true
			elif kind != "break_grapple" and float(agent.distance_m) <= (3.0 if kind == "shove" else 12.0):
				found = true
		return "" if found else "Рядом нет доступного контакта для этого действия."
	return "Неизвестное взаимодействие с заражёнными."

func apply(state: Dictionary, effect: Dictionary) -> Dictionary:
	var reason: String = availability(state,effect)
	if reason != "": return {"ok":false,"reason":reason}
	var kind: String = str(effect.get("kind",""))
	var location: String = str(effect.get("location",""))
	var effort: float = clampf(float(effect.get("effort",1.0)),0.0,1.0)
	var candidates: Array = state.agents.keys()
	candidates.sort()
	for id: String in candidates:
		var a: Dictionary = state.agents[id]
		if str(a.location) != location or not bool(a.get("alive",true)): continue
		if kind == "break_grapple" and float(a.grapple_s) <= 0.0: continue
		if kind == "shove" and float(a.distance_m) > 3.0: continue
		if kind == "retreat" and float(a.distance_m) > 12.0: continue
		# A grapple is actual mechanical resistance: not a free movement flag.
		if float(a.grapple_s) > 0.0 and effort < float(a.grapple_strength) * 0.65:
			return {"ok":false,"reason":"Хватка не разжалась. Уйти не получилось.","held":true}
		if kind == "break_grapple":
			a.grapple_s = 0.0
			a.mode = "investigate"
			a.distance_m += 1.8 * maxf(0.25, effort)
			return {"ok":true,"released":true}
		if kind == "shove":
			var impulse: float = 22.0 * effort
			a.distance_m += impulse / 13.0
			a.stability = maxf(0.0, float(a.stability) - impulse / 65.0)
			a.grapple_s = 0.0
			a.mode = "investigate"
			var toppled: bool = float(a.stability) < 0.44
			if toppled: _fall(a, 0.5)
			return {"ok":true,"pushed_m":impulse/13.0,"fell":toppled}
		a.grapple_s = 0.0
		a.distance_m += 7.0 * maxf(0.30, effort)
		a.memory_s = maxf(float(a.memory_s),120.0)
		a.alert_s = maxf(float(a.alert_s),120.0)
		a.mode = "investigate"
		a.close_reported = false
		return {"ok":true,"released":true}
	return {"ok":false,"reason":"Контакт уже потерян."}

func door_action(state: Dictionary, graph: Dictionary, location: String, other: String, kind: String, brace_kg: float = 0.0) -> Dictionary:
	return nav.act(state.doors,graph,location,other,kind,brace_kg)

func nearby_doors(state: Dictionary, graph: Dictionary, location: String) -> Array:
	return nav.adjacent_doors(state.doors,graph,location)

func advance(state: Dictionary, dt: float, context: Dictionary) -> Array:
	var events: Array = []
	if not is_finite(dt) or dt <= 0.0: return events
	var remaining: float = dt
	while remaining > 0.000001:
		var step_s: float = minf(10.0,remaining)
		_tick(state,step_s,context,events)
		state.time_s += step_s
		remaining -= step_s
	return events

func _tick(state: Dictionary, dt: float, context: Dictionary, events: Array) -> void:
	var graph: Dictionary = context.get("graph",{})
	var environment: Dictionary = context.get("environment",{})
	var sound_state: Dictionary = context.get("acoustics",{})
	var sound_model: Variant = context.get("acoustic_model",null)
	var current_player_location: String = str(context.get("player_location",""))
	var warmth_k: float = float(context.get("temperature_k",280.15))
	var ids: Array = state.agents.keys()
	ids.sort()
	for id: String in ids:
		var a: Dictionary = state.agents[id]
		a.contact_cooldown_s = maxf(0.0,float(a.contact_cooldown_s)-dt)
		a.impact_cooldown_s = maxf(0.0,float(a.impact_cooldown_s)-dt)
		a.tissue_integrity = maxf(0.0,float(a.tissue_integrity) -
			dt / (240.0*86400.0) * (1.0 if warmth_k < 293.15 else 2.0))
		if bool(a.alive):
			var tissue_progress: Dictionary = anatomy.advance(a.anatomy,dt,
				0.35 if float(a.memory_s)>0.0 else 0.10,0.3,float(a.blood_kg))
			var lost: float = minf(float(a.blood_kg),float(tissue_progress.bleeding_kg))
			a.blood_kg = maxf(0.0,float(a.blood_kg)-lost)
			a.blood_loss_kg = float(a.blood_loss_kg)+lost
			if float(a.blood_kg) < 2.0 or float(a.tissue_integrity) <= 0.005:
				a.alive = false
				a.grapple_s = 0.0
				a.memory_s = 0.0
				a.mode = "wander"
				events.append({"type":"infected_collapse","location":str(a.location),
					"actor_id":id,"offset_m":float(a.distance_m)})
		if not bool(a.alive): continue
		a.grapple_s = maxf(0.0,float(a.grapple_s)-dt)
		a.memory_s = maxf(0.0,float(a.memory_s)-dt)
		# Independent source acquisition; no knowledge of player ID from UI.
		var discovered: Dictionary = _sense(id,a,context,graph,environment,sound_state,sound_model)
		if not discovered.is_empty():
			a.target_location = str(discovered.location)
			a.memory_s = MAX_MEMORY_S
			a.alert_s = MAX_MEMORY_S
			a.search_s = 0.0
			a.search_origin = str(discovered.location)
			a.mode = "pursue" if discovered.get("kind","") == "seen" else "investigate"
			if discovered.get("kind","") == "heard":
				a.last_stimulus_sequence = int(discovered.get("sequence",0))
		elif float(a.memory_s) <= 0.0 and a.mode in ["investigate","pursue","obstructed"]:
			a.mode = "search"
			a.search_s = SEARCH_S
			a.search_origin = str(a.target_location)
		if a.mode == "search":
			a.search_s = maxf(0.0,float(a.search_s)-dt)
			if float(a.search_s) <= 0.0:
				a.mode = "wander"
				a.target_location = ""
				a.search_origin = ""
				a.alert_s = 0.0
			elif a.target_location == "" or (str(a.target_location) == str(a.location) and float(a.distance_m) <= 0.01):
				_choose_search_location(a,graph)
		a.alert_s = float(a.memory_s)
		if float(a.fallen_s) > 0.0:
			a.fallen_s = maxf(0.0,float(a.fallen_s)-dt)
			a.mode = "fallen"
			if float(a.fallen_s) <= 0.0:
				a.posture = "upright" if float(a.leg_integrity) > 0.22 else "crawling"
				a.mode = "search" if float(a.search_s) > 0.0 else ("investigate" if float(a.memory_s) > 0.0 else "wander")
				events.append({"type":"infected_rise","location":str(a.location),"offset_m":float(a.distance_m)})
			_emit_motion_sound(id,a,graph,sound_state,sound_model)
			continue
		var physical: Dictionary = anatomy.capabilities(a.anatomy,float(a.blood_kg),0.0)
		var locomotion: float = 0.32 * float(a.leg_integrity) * float(a.tissue_integrity) * float(physical.mobility)
		if float(physical.mobility) < 0.15: a.posture = "crawling"
		if warmth_k < 268.15: locomotion *= 0.6
		if a.posture == "crawling": locomotion = minf(0.055,locomotion*0.45)
		var intentional: bool = a.mode in ["investigate","pursue","search","obstructed"]
		var speed: float = locomotion if intentional else 0.006
		if float(a.grapple_s) > 0.0:
			a.mode = "grapple"
			speed = 0.0
		elif a.mode == "grapple":
			a.mode = "investigate" if float(a.memory_s) > 0.0 else "wander"
		var progress: float = speed * dt
		if progress > 0.0:
			_progress_route(state,a,progress,graph,environment,events,id)
		_emit_motion_sound(id,a,graph,sound_state,sound_model)
		# Physical grab requires shared local position and functional arms.
		if str(a.location) == current_player_location and float(a.distance_m) <= MIN_CONTACT_DISTANCE_M:
			if float(a.contact_cooldown_s) <= 0.0 and a.posture != "fallen":
				_contact(state,a,events,current_player_location)
		elif float(a.distance_m) > 45.0:
			a.close_reported = false

func _sense(id: String, a: Dictionary, context: Dictionary, graph: Dictionary, environment: Dictionary, sounds: Dictionary, model: Variant) -> Dictionary:
	var player_location: String = str(context.get("player_location",""))
	# Simplified line-of-sight within one named place; distant rooms need a
	# real vision/portal graph. No blind omniscient target updates.
	if str(a.location) == player_location:
		var light: float = clampf(float(context.get("player_light",0.0)),0.0,1.0)
		var visibility: float = 55.0 * light * float(a.tissue_integrity)
		if float(a.distance_m) <= visibility and a.posture != "fallen":
			return {"kind":"seen","location":player_location}
	if model == null or sounds.is_empty(): return {}
	var strongest: float = -INF
	var found: Dictionary = {}
	var entries: Array = sounds.get("events",[])
	for i: int in range(maxi(0,entries.size()-32),entries.size()):
		var stimulus: Dictionary = entries[i]
		var owner: String = str(stimulus.get("owner",""))
		if owner.begins_with("infected_") or int(stimulus.get("sequence",0)) <= int(a.last_stimulus_sequence):
			continue
		if not model.can_hear(stimulus,str(a.location),float(a.distance_m),
				float(a.hearing_threshold_db),graph,environment): continue
		var age: float = maxf(0.0,float(sounds.get("time_s",0.0))-float(stimulus.time_s))
		var score: float = model.received_db(stimulus,str(a.location),float(a.distance_m),graph,environment)-age*0.08
		if score > strongest:
			strongest = score
			found = {"kind":"heard","location":str(stimulus.location),"sequence":int(stimulus.sequence)}
	return found

func _progress_route(state: Dictionary, a: Dictionary, step_distance_m: float, graph: Dictionary,
		environment: Dictionary, events: Array, id: String) -> void:
	if not graph.has(str(a.location)): return
	var target: String = str(a.target_location)
	var destination: String = ""
	if a.mode == "wander":
		if str(a.location) == "forest": destination = "yard"
	elif graph.has(target) and target != str(a.location):
		var route: Array = nav.shortest_path(graph,state.doors,str(a.location),target)
		if route.size() >= 2: destination = str(route[1])
	if float(a.obstacle_delay_m) > 0.0:
		a.obstacle_delay_m = maxf(0.0,float(a.obstacle_delay_m)-step_distance_m)
		return
	var weather: Dictionary = environment.get("weather",{})
	var obstacle: Dictionary = Navigation.OBSTACLES.get(str(a.location),{})
	if not obstacle.is_empty() and a.posture == "upright" and float(a.distance_m) < 22.0 and str(a.obstacle_site) != str(a.location):
		a.obstacle_site = str(a.location)
		var roll: float = _roll(a)
		var risk: float = float(obstacle.fall_risk) * (1.0 + float(weather.get("rain",0.0)) * 1.5) * (1.35 - float(a.stability))
		a.obstacle_delay_m = float(obstacle.detour_m)
		if roll < risk:
			_fall(a,float(weather.get("rain",0.0)))
			events.append({"type":"infected_fall","actor_id":id,"location":str(a.location),
				"offset_m":float(a.distance_m),"text":"Раздаётся тяжёлый удар о землю."})
			return
		events.append({"type":"infected_detour","location":str(a.location),
			"offset_m":float(a.distance_m)})
	var remaining: float = float(a.distance_m) - step_distance_m
	if remaining > 0.0:
		a.distance_m = remaining
		return
	a.distance_m = 0.0
	if destination.is_empty():
		if a.mode in ["investigate","pursue"] and float(a.memory_s) > 0.0 and a.target_location == a.location:
			a.mode = "search"
			a.search_s = SEARCH_S
		return
	if not nav.is_open(state.doors,str(a.location),destination):
		a.mode = "obstructed"
		# Door may be breached only from physically adjacent side, with a
		# measured accumulated impact energy, not a scripted countdown.
		if float(a.impact_cooldown_s) <= 0.0 and a.posture == "upright":
			var force: Dictionary = anatomy.capabilities(a.anatomy,float(a.blood_kg),0.0)
			var impact: float = 45.0 * float(a.tissue_integrity) * float(a.leg_integrity) * float(force.grip)
			var strike: Dictionary = nav.strike(state.doors,str(a.location),destination,impact)
			a.impact_cooldown_s = 20.0
			events.append({"type":"infected_door_breach" if strike.get("breached",false) else "infected_door_hit",
				"actor_id":id,"location":str(a.location),"offset_m":0.0, "other":destination, "impact_j":impact})
		return
	# A genuine door or graph edge is traversed only after reaching its side.
	var old_location: String = str(a.location)
	a.location = destination
	a.obstacle_site = ""
	a.distance_m = maxf(0.1,float(graph[old_location].connections[destination]) - maxf(0.0,-remaining))
	if a.mode == "obstructed": a.mode = "investigate"
	events.append({"type":"infected_traverse","location":destination,"offset_m":float(a.distance_m)})

func _choose_search_location(a: Dictionary, graph: Dictionary) -> void:
	if not graph.has(str(a.location)):
		a.target_location = ""
		return
	var choices: Array = graph[str(a.location)].connections.keys()
	choices.sort()
	if choices.is_empty():
		a.target_location = ""
		return
	var index: int = int(a.search_index) % choices.size()
	a.target_location = str(choices[index])
	a.search_index = int(a.search_index)+1

func _fall(a: Dictionary, wetness: float) -> void:

	a.posture = "fallen"
	a.mode = "fallen"
	a.fallen_s = 24.0 + 50.0 * (1.0 - float(a.leg_integrity))
	a.stability = maxf(0.0,float(a.stability)-0.26)
	# The fall transfers mechanical energy into a selected leg's tissues.
	var impact_j: float = float(a.mass_kg)*9.81*(0.43+wetness*0.12)
	var landing_leg: String = "left_leg" if _roll(a)<0.5 else "right_leg"
	anatomy.injure(a.anatomy,{"part":landing_leg,"wound_m2":0.00004,
		"bleeding_kg_s":impact_j*0.000000001,
		"contamination":clampf(0.13+wetness*0.15,0.0,1.0),
		"tissue_damage":{"skin":clampf(impact_j/7000.0,0.0,0.2),
			"muscle":clampf(impact_j/4000.0,0.0,0.25),
			"bone":clampf(impact_j/14000.0,0.0,0.14),
			"nerve":clampf(impact_j/30000.0,0.0,0.05)}})

func _roll(a: Dictionary) -> float:
	a.rng_state = int((int(a.rng_state) * 48271) % RNG_MOD)
	return float(a.rng_state) / float(RNG_MOD)

func _emit_motion_sound(id: String, a: Dictionary, graph: Dictionary, sounds: Dictionary, model: Variant) -> void:
	if model == null or sounds.is_empty(): return
	model.emit(sounds,graph,str(a.location),"shuffling",70.0 if a.mode == "pursue" else 64.0,
		id,float(a.distance_m))

func _contact(state: Dictionary, a: Dictionary, events: Array, location: String) -> void:
	a.contact_cooldown_s = 180.0
	state.contacts = int(state.contacts)+1
	var site: String = "left_arm" if int(state.contacts) % 2 == 1 else "right_arm"
	if a.posture == "crawling": site = "left_leg" if int(state.contacts) % 2 == 1 else "right_leg"
	var pressure: float = maxf(0.12,float(a.tissue_integrity)) * float(anatomy.capabilities(a.anatomy,float(a.blood_kg),0.0).grip)
	a.grapple_s = 32.0 * pressure
	a.grapple_strength = pressure * 0.8
	a.mode = "grapple"
	events.append({"type":"infected_contact","location":location,
		"text":"Кто-то цепляется за одежду. Резкая боль заставляет отдёрнуть конечность.",
		"part":site, "wound_m2":0.00004 * pressure,
		"bleeding_kg_s":0.0000007 * pressure,
		"contamination":0.015 * pressure,
		"tissue_damage":{"skin":0.018 * pressure,"muscle":0.009 * pressure,"nerve":0.003 * pressure}})

func observe(state: Dictionary, location: String, context: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"descriptions":[],"warnings":[],"threats":[]}
	var visibility: float = maxf(0.0,float(context.get("visual_range_m",0.0)))
	for id: String in state.agents:
		var a: Dictionary = state.agents[id]
		if str(a.location) == location and float(a.distance_m) <= visibility:
			var text_value: String = "На земле шевелится фигура." if a.posture != "upright" else "Видна неровно движущаяся фигура."
			result.warnings.append(text_value)
			result.threats.append({"title":"Фигура","text":text_value})
			break
	return result

func validate_state(state: Dictionary, graph: Dictionary) -> String:
	if not state is Dictionary or state.get("schema_version") != 3 or not state.get("agents") is Dictionary:
		return "Повреждена схема заражённых."
	if not (state.get("seed") is int or state.get("seed") is float) or not _whole(state.get("seed")): return "Неверный seed заражённых."
	if not (state.get("contacts") is int or state.get("contacts") is float) or not _whole(state.get("contacts")) or int(state.contacts) < 0: return "Некорректный счётчик контактов."
	if not (state.get("time_s") is float or state.get("time_s") is int) or not is_finite(float(state.time_s)) or float(state.time_s) < 0.0: return "Некорректное время заражённых."
	var required: Dictionary = initial_state(int(state.seed)).agents
	if state.agents.size() != START_COUNT: return "Численность заражённых не сохраняется."
	for id: String in required:
		if not state.agents.has(id) or not state.agents[id] is Dictionary: return "Пропал постоянный заражённый."
		var a: Dictionary = state.agents[id]
		if a.size() != required[id].size(): return "Повреждена структура заражённого."
		if not a.get("alive") is bool: return "Повреждён признак жизнеспособности заражённого."
		var injury_reason: String = anatomy.validate_state(a.get("anatomy",{}))
		if injury_reason != "": return injury_reason
		for field: String in ["location","target_location","mode","posture","search_origin","obstacle_site"]:
			if not a.get(field) is String: return "Неверный тип памяти заражённого."
		if not graph.has(str(a.location)) or (str(a.target_location) != "" and not graph.has(str(a.target_location))):
			return "Невозможная локация заражённого."
		if str(a.search_origin) != "" and not graph.has(str(a.search_origin)): return "Неизвестное место поиска."
		if str(a.obstacle_site) != "" and not graph.has(str(a.obstacle_site)): return "Неизвестное место препятствия."
		if str(a.mode) not in MODES or str(a.posture) not in POSTURES: return "Недопустимая поза или решение заражённого."
		for field: String in ["distance_m","alert_s","contact_cooldown_s","leg_integrity",
				"tissue_integrity","hearing_threshold_db","memory_s","search_s",
				"stability","fallen_s","grapple_s","grapple_strength","impact_cooldown_s",
				"obstacle_delay_m","blood_kg","blood_loss_kg","mass_kg"]:
			var value: Variant = a.get(field)
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
				return "Некорректная физическая величина заражённого: " + field
		for field: String in ["leg_integrity","tissue_integrity","stability","grapple_strength"]:
			if float(a[field]) > 1.0: return "Невозможная сохранность тканей и равновесия."
		if float(a.blood_kg) > 8.0 or float(a.mass_kg) < 20.0 or float(a.mass_kg) > 250.0: return "Невозможная масса или объём крови заражённого."
		if float(a.hearing_threshold_db) > 140.0 or float(a.grapple_s) > 240.0 or float(a.memory_s) > MAX_MEMORY_S or float(a.search_s) > SEARCH_S:
			return "Невозможное сенсорное состояние заражённого."
		for field: String in ["search_index","last_stimulus_sequence","rng_state"]:
			if not _whole(a.get(field)) or float(a[field]) < 0.0: return "Неверная последовательность решений заражённого."
		if int(a.rng_state) < 1 or int(a.rng_state) >= RNG_MOD: return "Недопустимый генератор заражённого."
		if not a.get("close_reported") is bool: return "Некорректная сенсорная отметка."
	for id: String in state.agents:
		if not required.has(id): return "Поддельный заражённый."
	return nav.validate_state(state.get("doors",{}),graph)

func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

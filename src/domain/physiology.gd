extends RefCounted
const Anatomy = preload("res://src/domain/anatomy.gd")
var anatomy = Anatomy.new()
## Reduced adult physiology; coefficients are gameplay assumptions, not clinical calibration.

func initial_state() -> Dictionary:
	return {"schema_version": 1, "core_k": 309.75, "skin_k": 302.15,
		"water_kg": 41.5, "blood_kg": 5.0, "energy_j": 18000000.0,
		"gut_water_kg": 0.0, "gut_energy_j": 0.0, "fatigue": 0.32,
		"stress": 0.22, "clothing_water_kg": 0.25, "wound_m2": 0.0003,
		"bleeding_kg_s": 0.000002, "infection": 0.03, "toxin": 0.0,
		"hypoxia_s": 0.0, "alive": true, "conscious": true,
		"anatomy":anatomy.initial_state(),
		"bandaged": false, "skills": {}, "water_lost_kg": 0.0,
		"blood_lost_kg": 0.0, "energy_used_j": 0.0,
		"heat_to_environment_j": 0.0, "clothing_evaporated_kg": 0.0,
		"rain_received_kg": 0.0, "sweat_evaporated_kg": 0.0, "sweat_heat_j": 0.0}

func advance(state: Dictionary, dt: float, context: Dictionary) -> Array:
	var events: Array = []
	if not is_finite(dt) or dt <= 0.0 or not state.get("alive", true):
		return events
	var was_conscious: bool = state.get("conscious", true)
	var remaining: float = dt
	while remaining > 0.0 and state.alive:
		var step: float = minf(60.0, remaining)
		_integrate(state, step, context)
		remaining -= step
	if not state.alive:
		events.append({"type": "death", "text": "Жизненные функции угасли."})
	elif was_conscious and not state.conscious:
		events.append({"type": "unconscious", "text": "Темнеет в глазах. Сознание ускользает."})
	elif not was_conscious and state.conscious:
		events.append({"type": "conscious", "text": "Вы приходите в себя."})
	return events

func _integrate(s: Dictionary, dt: float, c: Dictionary) -> void:
	var air: float = float(c.get("temp_k", 288.15))
	var effort: float = clampf(float(c.get("exertion", 0.0)), 0.0, 1.0)
	var wind: float = maxf(0.0, float(c.get("wind_m_s", 0.0)))
	var rain: float = maxf(0.0, float(c.get("rain", 0.0)))
	var sheltered: bool = c.get("shelter", false)
	var sleeping: bool = c.get("sleeping", false)
	var absorbed_water: float = minf(s.gut_water_kg, 0.00035 * dt)
	s.gut_water_kg -= absorbed_water
	s.water_kg += absorbed_water
	var absorbed_energy: float = minf(s.gut_energy_j, 250.0 * dt)
	s.gut_energy_j -= absorbed_energy
	s.energy_j += absorbed_energy
	var rain_in: float = rain * (0.000003 if sheltered else 0.00005) * dt
	s.clothing_water_kg += rain_in
	s.rain_received_kg += rain_in
	var drying: float = minf(s.clothing_water_kg, maxf(0.0, air - 273.15) * 0.0000003 * (1.0 + wind * 0.1) * dt)
	s.clothing_water_kg -= drying
	s.clothing_evaporated_kg += drying
	var shivering_w: float = clampf((309.65 - s.core_k) * 65.0, 0.0, 160.0)
	var metabolism_w: float = 85.0 + effort * 260.0 + shivering_w + float(s.anatomy.adrenaline) * 30.0
	var used: float = minf(s.energy_j, metabolism_w * dt)
	s.energy_j -= used
	s.energy_used_j += used
	var heat_w: float = used / dt * (1.0 - effort * 0.2)
	var conductance: float = 3.0 + minf(s.clothing_water_kg, 2.0) * 4.0 + wind * (0.05 if sheltered else 0.3)
	# Vasodilation increases internal heat transport as core warms. Sweat
	# removes heat and body water together; both flows remain in ledgers.
	var perfusion_w_k: float = 12.0 + clampf((s.core_k - 309.15) * 45.0, 0.0, 65.0)
	var core_to_skin_w: float = (s.core_k - s.skin_k) * perfusion_w_k
	var sweat_w: float = clampf((s.core_k - 309.8) * 240.0, 0.0, 600.0)
	var sweat_kg: float = minf(s.water_kg, sweat_w * dt / 2400000.0)
	s.water_kg -= sweat_kg
	s.water_lost_kg += sweat_kg
	s.sweat_evaporated_kg += sweat_kg
	s.sweat_heat_j += sweat_kg * 2400000.0
	var loss_j: float = conductance * (s.skin_k - air) * dt + drying * 2400000.0
	s.core_k += (heat_w * dt - core_to_skin_w * dt - sweat_kg * 2400000.0) / 210000.0
	s.skin_k += (core_to_skin_w * dt - loss_j) / 30000.0
	s.heat_to_environment_j += loss_j + sweat_kg * 2400000.0
	var injury: Dictionary = anatomy.advance(s.anatomy, dt, float(s.stress), effort, float(s.blood_kg))
	var bleed: float = minf(float(s.blood_kg), float(injury.get("bleeding_kg",0.0)))
	s.blood_kg -= bleed
	_sync_local_injuries(s)
	s.infection = clampf(maxf(float(s.infection), float(injury.get("local_inflammation",0.0)) * 0.35), 0.0, 1.0)
	s.blood_lost_kg += bleed
	# Body water includes the water fraction of circulating blood: record it once.
	var water_out: float = minf(s.water_kg, (0.000018 + effort * 0.00012 + maxf(0.0, s.core_k - 310.15) * 0.00006 + s.infection * 0.000025) * dt + bleed * 0.8)
	s.water_kg -= water_out
	s.water_lost_kg += water_out
	if s.wound_m2 > 0.0:
		s.infection = clampf(s.infection - dt * 0.0000005, 0.0, 1.0)
	var smoke: float = maxf(0.0, float(c.get("smoke", 0.0)))
	s.toxin = maxf(0.0, s.toxin + smoke * dt * 0.0008 - dt * 0.00005)
	var oxygen: float = float(c.get("oxygen", 0.209))
	s.hypoxia_s = maxf(0.0, s.hypoxia_s + dt * (maxf(0.0, 0.17 - oxygen) * 10.0 if oxygen < 0.17 else -0.5))
	var comfortable: bool = s.core_k > 308.0 and s.core_k < 311.0 and smoke < 0.1
	s.fatigue = clampf(s.fatigue + dt * (-0.000035 if sleeping and comfortable else 0.000006 + effort * 0.000025 + float(s.anatomy.adrenaline) * 0.000004), 0.0, 1.0)
	s.stress = clampf(s.stress + dt * (0.00003 if not comfortable else -0.000008), 0.0, 1.0)
	s.alive = s.core_k > 297.15 and s.core_k < 316.15 and s.blood_kg > 2.0 and s.water_kg > 29.0 and s.hypoxia_s < 1500.0 and s.toxin < 5.0
	s.conscious = s.alive and s.core_k > 303.15 and s.blood_kg > 3.0 and s.hypoxia_s < 180.0 and s.toxin < 1.0

func apply(state: Dictionary, effect: Dictionary) -> void:
	match String(effect.get("kind", "")):
		"drink", "eat":
			state.gut_water_kg += maxf(0.0, float(effect.get("water_kg", 0.0)))
			state.gut_energy_j += maxf(0.0, float(effect.get("energy_j", 0.0)))
			state.infection = clampf(state.infection + maxf(0.0, float(effect.get("microbes", 0.0))) * 0.05, 0.0, 1.0)
			state.toxin += maxf(0.0, float(effect.get("chemical", 0.0))) * 0.1

		"infected_contact", "trauma":
			var injury_effect: Dictionary = effect.duplicate(true)
			if not injury_effect.has("part"): injury_effect["part"] = "left_arm"
			if not injury_effect.has("tissue_damage"):
				injury_effect["tissue_damage"] = {"skin":0.025, "muscle":0.008}
			if anatomy.injure(state.anatomy, injury_effect):
				_sync_local_injuries(state)
				state.stress = clampf(float(state.stress) + 0.16, 0.0, 1.0)
		"sensory_injury":
			if anatomy.injure_sense(state.anatomy, str(effect.get("organ","")), float(effect.get("damage",0.0))):
				state.stress = clampf(float(state.stress) + 0.08, 0.0, 1.0)
		"bandage":
			if anatomy.treat(state.anatomy, "bandage", str(effect.get("part", ""))):
				_sync_local_injuries(state)
		"wash_wound":
			anatomy.treat(state.anatomy, "wash", str(effect.get("part", "")))

		"practice":
			var skill: String = String(effect.get("skill", "survival"))
			state.skills[skill] = int(state.skills.get(skill, 0)) + 1


func _sync_local_injuries(state: Dictionary) -> void:
	state.wound_m2 = anatomy.aggregate_wound_area(state.anatomy)
	state.bleeding_kg_s = anatomy.raw_bleeding_rate(state.anatomy)
	state.bandaged = anatomy.has_bandage(state.anatomy)

func capabilities(state: Dictionary) -> Dictionary:
	return anatomy.capabilities(state.anatomy, float(state.blood_kg), float(state.fatigue))

func action_efficiency(state: Dictionary, verb: String) -> float:
	var caps: Dictionary = capabilities(state)
	if verb in ["move", "retreat"]:
		return float(caps.mobility)
	if verb in ["repair_radio", "clean_chimney", "repair_cart", "craft_bandage", "seal_window", "plant", "harvest", "hunt", "wash_wound", "bandage", "help_nina"]:
		var coordination: float = float(caps.precision)
		if verb in ["hunt", "repair_radio"]:
			coordination *= float(caps.vision)
		return 1.0 if coordination >= 0.90 else clampf(coordination, 0.0, 0.90)
	if verb in ["gather_wood", "add_fuel", "fill_water", "ventilate", "light_fire", "cook", "boil_water", "trade", "share_food"]:
		var grip: float = float(caps.grip)
		return 1.0 if grip >= 0.90 else clampf(grip, 0.0, 0.90)
	return 1.0

func action_limit(state: Dictionary, verb: String) -> String:
	var caps: Dictionary = capabilities(state)
	if verb in ["move", "retreat", "hunt", "gather_wood", "plant", "harvest"] and float(caps.mobility) < 0.14:
		return "Ноги не выдерживают необходимого движения. Нужна помощь или иной способ перемещения."
	if verb in ["repair_radio", "clean_chimney", "repair_cart", "craft_bandage", "seal_window", "plant", "harvest", "hunt", "wash_wound", "bandage", "help_nina"] and float(caps.precision) < 0.20:
		return "Повреждённые руки не позволяют выполнить точную работу."
	if verb in ["gather_wood", "add_fuel", "fill_water", "ventilate", "light_fire", "cook", "boil_water"] and float(caps.grip) < 0.20:
		return "Не получается надёжно удерживать предметы."
	if verb in ["repair_radio", "hunt"] and float(caps.vision) < 0.12:
		return "Зрение не позволяет различить необходимые детали."
	return ""

func observe(state: Dictionary) -> Dictionary:
	var sensations: Array[String] = []
	var warnings: Array[String] = []
	var details: Array = []
	if state.core_k < 309.2: sensations.append("Вас знобит; пальцы слушаются хуже.")
	if state.core_k > 311.0: sensations.append("Жарко, голова тяжёлая.")
	if state.clothing_water_kg > 0.1: sensations.append("Одежда влажная и холодит кожу.")
	if state.water_kg < 41.0: sensations.append("Во рту сухо, хочется пить.")
	if state.energy_j < 12000000.0: sensations.append("Сосёт под ложечкой, ощущается слабость.")
	if state.fatigue > 0.45: sensations.append("Тяжелеют веки, трудно сосредоточиться.")
	if state.stress > 0.5: sensations.append("Тревога мешает собраться с мыслями.")
	if state.toxin > 0.2 or state.hypoxia_s > 30.0: warnings.append("Кружится голова, дышать тяжело.")
	if state.blood_kg < 4.0: warnings.append("Слабость, при движении темнеет в глазах.")
	var caps: Dictionary = capabilities(state)
	if float(state.anatomy.pain_raw) > 0.25 and float(state.anatomy.pain_felt) < float(state.anatomy.pain_raw) * 0.65:
		sensations.append("После испуга боль как будто отступила, но движения всё ещё неуверенные.")
	elif float(state.anatomy.pain_felt) > 0.45:
		warnings.append("Боль мешает сосредоточиться и двигаться.")
	elif float(state.anatomy.pain_felt) > 0.15:
		sensations.append("Боль отвлекает при попытке пошевелиться.")
	if float(caps.mobility) < 0.6: warnings.append("Трудно опереться на ногу, походка нарушена.")
	if float(caps.precision) < 0.6: warnings.append("Пальцы слушаются плохо; мелкие вещи трудно удерживать.")
	if float(caps.vision) < 0.55: sensations.append("Зрение расплывается, приходится напрягать глаза.")
	if float(caps.hearing_loss_db) > 20.0: sensations.append("Звуки приглушены, трудно разобрать их направление.")
	for part: String in Anatomy.PARTS:
		var region: Dictionary = state.anatomy.parts[part]
		var touched: bool = not region.wounds.is_empty()
		var structural: bool = float(region.tissues.bone) < 0.6 or float(region.tissues.nerve) < 0.6 or float(region.tissues.muscle) < 0.6
		if not touched and not structural: continue
		var pieces: Array[String] = []
		if structural: pieces.append("Движение ограничено, опора или хват ненадёжны.")
		for wound: Dictionary in region.wounds:
			if bool(wound.bandaged): pieces.append("Повязка прикрывает рану.")
			elif float(wound.bleeding_kg_s) > 0.0: pieces.append("Поверхность раны влажная, кровь продолжает выступать.")
			else: pieces.append("Кожа повреждена.")
			if float(wound.infection) > 0.2: pieces.append("Вокруг раны заметны воспаление и болезненность.")
		details.append({"title":str(Anatomy.PART_TITLES[part]), "text":" ".join(pieces)})
	if state.infection > 0.3: warnings.append("Ощущается недомогание; причина без осмотра неизвестна.")
	if sensations.is_empty(): sensations.append("Дыхание ровное; выраженного дискомфорта нет.")
	var condition: String = "В сознании"
	if not state.alive: condition = "Жизнь угасла"
	elif not state.conscious: condition = "Без сознания"
	elif not warnings.is_empty(): condition = "Самочувствие тревожное"
	return {"sensations": sensations, "condition": condition, "details": details,
		"warnings": warnings, "alive": state.alive, "conscious": state.conscious}

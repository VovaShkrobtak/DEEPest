extends RefCounted
## Reduced adult physiology; coefficients are gameplay assumptions, not clinical calibration.

func initial_state() -> Dictionary:
	return {"schema_version": 1, "core_k": 309.75, "skin_k": 302.15,
		"water_kg": 41.5, "blood_kg": 5.0, "energy_j": 18000000.0,
		"gut_water_kg": 0.0, "gut_energy_j": 0.0, "fatigue": 0.32,
		"stress": 0.22, "clothing_water_kg": 0.25, "wound_m2": 0.0003,
		"bleeding_kg_s": 0.000002, "infection": 0.03, "toxin": 0.0,
		"hypoxia_s": 0.0, "alive": true, "conscious": true,
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
	var metabolism_w: float = 85.0 + effort * 260.0 + shivering_w
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
	var bleed: float = minf(s.blood_kg, s.bleeding_kg_s * (0.12 if s.bandaged else 1.0) * dt)
	s.blood_kg -= bleed
	s.blood_lost_kg += bleed
	# Body water includes the water fraction of circulating blood: record it once.
	var water_out: float = minf(s.water_kg, (0.000018 + effort * 0.00012 + maxf(0.0, s.core_k - 310.15) * 0.00006 + s.infection * 0.000025) * dt + bleed * 0.8)
	s.water_kg -= water_out
	s.water_lost_kg += water_out
	if s.wound_m2 > 0.0:
		s.infection = clampf(s.infection + dt * s.wound_m2 * (0.00006 if s.bandaged else 0.0002) - dt * 0.0000005, 0.0, 1.0)
	var smoke: float = maxf(0.0, float(c.get("smoke", 0.0)))
	s.toxin = maxf(0.0, s.toxin + smoke * dt * 0.0008 - dt * 0.00005)
	var oxygen: float = float(c.get("oxygen", 0.209))
	s.hypoxia_s = maxf(0.0, s.hypoxia_s + dt * (maxf(0.0, 0.17 - oxygen) * 10.0 if oxygen < 0.17 else -0.5))
	var comfortable: bool = s.core_k > 308.0 and s.core_k < 311.0 and smoke < 0.1
	s.fatigue = clampf(s.fatigue + dt * (-0.000035 if sleeping and comfortable else 0.000006 + effort * 0.000025), 0.0, 1.0)
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
		"infected_contact":
			# Local tissue trauma + contamination, not arbitrary HP loss.
			state.wound_m2 += maxf(0.0, float(effect.get("wound_m2", 0.0)))
			state.bleeding_kg_s += maxf(0.0, float(effect.get("bleeding_kg_s", 0.0)))
			state.infection = clampf(state.infection + maxf(0.0, float(effect.get("contamination", 0.0))), 0.0, 1.0)
			state.stress = clampf(state.stress + 0.16, 0.0, 1.0)
		"bandage":
			state.bandaged = true
		"wash_wound":
			state.infection *= 0.7
		"practice":
			var skill: String = String(effect.get("skill", "survival"))
			state.skills[skill] = int(state.skills.get(skill, 0)) + 1

func observe(state: Dictionary) -> Dictionary:
	var sensations: Array[String] = []
	var warnings: Array[String] = []
	var details: Array = []
	if state.core_k < 309.2:
		sensations.append("Вас знобит; пальцы слушаются хуже.")
	if state.core_k > 311.0:
		sensations.append("Жарко, голова тяжёлая.")
	if state.clothing_water_kg > 0.1:
		sensations.append("Одежда влажная и холодит кожу.")
	if state.water_kg < 41.0:
		sensations.append("Во рту сухо, хочется пить.")
	if state.energy_j < 12000000.0:
		sensations.append("Сосёт под ложечкой, ощущается слабость.")
	if state.fatigue > 0.45:
		sensations.append("Тяжелеют веки, трудно сосредоточиться.")
	if state.stress > 0.5:
		sensations.append("Тревога мешает собраться с мыслями.")
	if state.toxin > 0.2 or state.hypoxia_s > 30.0:
		warnings.append("Кружится голова, дышать тяжело.")
	if state.blood_kg < 4.0:
		warnings.append("Слабость, при движении темнеет в глазах.")
	if state.wound_m2 > 0.0:
		details.append({"title": "Рука", "text": "Повязка прикрывает болезненный порез." if state.bandaged else "Небольшой порез саднит и понемногу кровит."})
	if state.infection > 0.3:
		warnings.append("Рана ноет; чувствуется недомогание.")
	if sensations.is_empty():
		sensations.append("Дыхание ровное; выраженного дискомфорта нет.")
	var condition: String = "В сознании"
	if not state.alive:
		condition = "Жизнь угасла"
	elif not state.conscious:
		condition = "Без сознания"
	elif not warnings.is_empty():
		condition = "Самочувствие тревожное"
	return {"sensations": sensations, "condition": condition, "details": details, "warnings": warnings, "alive": state.alive, "conscious": state.conscious}

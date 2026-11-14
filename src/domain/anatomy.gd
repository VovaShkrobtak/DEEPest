extends RefCounted
## Body topology and local injuries. All tissue coefficients are gameplay
## assumptions, not validated clinical or forensic predictions.
const PARTS: Array[String] = ["head", "chest", "abdomen", "left_arm", "right_arm", "left_leg", "right_leg"]
const TISSUES: Array[String] = ["skin", "muscle", "bone", "nerve", "vessel"]
const SENSES: Array[String] = ["left_eye", "right_eye", "left_ear", "right_ear"]
const PART_TITLES: Dictionary = {
	"head":"Голова", "chest":"Грудная клетка", "abdomen":"Живот",
	"left_arm":"Левая рука", "right_arm":"Правая рука",
	"left_leg":"Левая нога", "right_leg":"Правая нога"}
const MAX_WOUNDS_PER_PART: int = 8

func initial_state(with_start_wound: bool = true) -> Dictionary:
	var parts: Dictionary = {}
	for name: String in PARTS:
		var tissues: Dictionary = {}
		for tissue: String in TISSUES: tissues[tissue] = 1.0
		parts[name] = {"tissues":tissues, "wounds":[], "infection":0.0, "pain":0.0}
	var state: Dictionary = {"schema_version":2, "parts":parts,
		"senses":{"left_eye":1.0,"right_eye":1.0,"left_ear":1.0,"right_ear":1.0},
		"adrenaline":0.0, "pain_raw":0.0, "pain_felt":0.0,
		"blood_loss_kg":0.0}
	if with_start_wound:
		injure(state, {"part":"left_arm", "wound_m2":0.0003,
			"bleeding_kg_s":0.000002, "contamination":0.03,
			"tissue_damage":{"skin":0.025}})
		state.adrenaline = 0.0 # Old injury predates the starting moment.
		_refresh_pain(state)
	return state

func injure(state: Dictionary, effect: Dictionary) -> bool:
	var part: String = str(effect.get("part", ""))
	if not state.get("parts", {}).has(part): return false
	var area: float = float(effect.get("wound_m2", 0.0))
	var bleeding: float = float(effect.get("bleeding_kg_s", 0.0))
	var contamination: float = float(effect.get("contamination", 0.0))
	if not is_finite(area) or not is_finite(bleeding) or not is_finite(contamination):
		return false
	if area < 0.0 or area > 0.2 or bleeding < 0.0 or bleeding > 0.02 or contamination < 0.0 or contamination > 1.0: return false
	var damage: Dictionary = effect.get("tissue_damage", {})
	if not damage is Dictionary: return false
	for tissue: String in damage:
		if tissue not in TISSUES or not (damage[tissue] is int or damage[tissue] is float) or not is_finite(float(damage[tissue])) or float(damage[tissue]) < 0.0 or float(damage[tissue]) > 1.0:
			return false
	var region: Dictionary = state.parts[part]
	if area > 0.0 and region.wounds.size() >= MAX_WOUNDS_PER_PART: return false
	for tissue: String in damage:
		region.tissues[tissue] = clampf(float(region.tissues[tissue]) - float(damage[tissue]), 0.0, 1.0)
	if area > 0.0:
		region.wounds.append({"area_m2":area, "bleeding_kg_s":bleeding,
			"contamination":contamination, "infection":0.0,
			"bandaged":false, "age_s":0.0})
	# Shock response masks subjective pain briefly; tissue is not repaired.
	if area > 0.0 or not damage.is_empty():
		state.adrenaline = clampf(float(state.adrenaline) + 0.32, 0.0, 1.0)
	_refresh_pain(state)
	return true

func injure_sense(state: Dictionary, organ: String, damage: float) -> bool:
	if organ not in SENSES or not is_finite(damage) or damage <= 0.0 or damage > 1.0: return false
	state.senses[organ] = maxf(0.0, float(state.senses[organ]) - damage)
	state.adrenaline = minf(1.0, float(state.adrenaline) + 0.12)
	return true

func can_treat(state: Dictionary, kind: String, preferred: String = "") -> bool:
	if not preferred.is_empty() and not state.get("parts", {}).has(preferred): return false
	for part: String in PARTS:
		if not preferred.is_empty() and part != preferred: continue
		for wound: Dictionary in state.parts[part].wounds:
			if kind == "bandage" and not bool(wound.bandaged): return true
			if kind == "wash" and float(wound.contamination) > 0.0: return true
	return false

func treat(state: Dictionary, kind: String, preferred: String = "") -> bool:
	var chosen: String = preferred
	var candidate: Dictionary = {}
	if not state.parts.has(chosen):
		chosen = ""
	if not chosen.is_empty():
		for wound: Dictionary in state.parts[chosen].wounds:
			if kind == "bandage" and not bool(wound.bandaged):
				candidate = wound
				break
			if kind == "wash" and float(wound.contamination) > 0.0:
				candidate = wound
				break
	if candidate.is_empty():
		var best: float = -1.0
		for part: String in PARTS:
			for wound: Dictionary in state.parts[part].wounds:
				var priority: float = float(wound.bleeding_kg_s) if kind == "bandage" and not bool(wound.bandaged) else (float(wound.contamination) if kind == "wash" else -1.0)
				if priority > best and priority >= 0.0:
					best = priority
					candidate = wound
	if candidate.is_empty(): return false
	if kind == "bandage": candidate.bandaged = true
	elif kind == "wash":
		candidate.contamination *= 0.3 # Surface washing does not cure infection.
	else: return false
	return true

func advance(state: Dictionary, dt: float, stress: float, exertion: float, blood_kg: float) -> Dictionary:
	if not is_finite(dt) or dt <= 0.0: return {"bleeding_kg":0.0, "local_inflammation":0.0}
	var active_stress: float = clampf(stress, 0.0, 1.0)
	var desired_adrenaline: float = maxf(0.0, active_stress - 0.34) * 1.1
	# Approximate autonomic response: finite rise and decay, not instant healing.
	var rate: float = 0.0025 if desired_adrenaline > float(state.adrenaline) else 0.0006
	state.adrenaline = clampf(float(state.adrenaline) + (desired_adrenaline - float(state.adrenaline)) * (1.0 - exp(-dt * rate)), 0.0, 1.0)
	var blood_loss: float = 0.0
	var inflammation: float = 0.0
	for part: String in PARTS:
		var region: Dictionary = state.parts[part]
		var local_inflammation: float = float(region.infection)
		for wound: Dictionary in region.wounds:
			wound.age_s += dt
			var elapsed: float = float(wound.age_s)
			# Clotting is slow and does not regenerate blood; external pressure
			# reduces continuing loss on that wound alone.
			var clot: float = exp(-elapsed / 86400.0 * 0.25)
			var rate_kg_s: float = float(wound.bleeding_kg_s) * clot * (0.12 if bool(wound.bandaged) else 1.0)
			blood_loss += rate_kg_s * dt
			# Local wound inoculum and established infection are separate fields.
			var inoculum: float = float(wound.contamination)
			var microbial_gain: float = inoculum * (0.000001 if bool(wound.bandaged) else 0.000003) * dt
			wound.infection = clampf(float(wound.infection) + microbial_gain * (1.0 - float(wound.infection)) - dt * 0.0000004, 0.0, 1.0)
			local_inflammation = maxf(local_inflammation, float(wound.infection))
		region.infection = clampf(local_inflammation - 0.0000001 * dt, 0.0, 1.0)
		inflammation = maxf(inflammation, float(region.infection))
	var actual_loss: float = minf(maxf(0.0, blood_kg), blood_loss)
	state.blood_loss_kg += actual_loss
	_refresh_pain(state)
	return {"bleeding_kg":actual_loss,
		"local_inflammation":inflammation}

func _refresh_pain(state: Dictionary) -> void:
	var raw: float = 0.0
	for part: String in PARTS:
		var region: Dictionary = state.parts[part]
		var part_pain: float = 0.0
		for wound: Dictionary in region.wounds:
			part_pain += minf(0.28, float(wound.area_m2) * 220.0)
			part_pain += float(wound.infection) * 0.3
		var tissues: Dictionary = region.tissues
		part_pain += (1.0 - float(tissues.muscle)) * 0.25
		part_pain += (1.0 - float(tissues.bone)) * 0.42
		part_pain += (1.0 - float(tissues.nerve)) * 0.08
		region.pain = clampf(part_pain, 0.0, 1.0)
		raw += float(region.pain)
	state.pain_raw = clampf(raw, 0.0, 1.0)
	state.pain_felt = clampf(float(state.pain_raw) * (1.0 - float(state.adrenaline) * 0.68), 0.0, 1.0)

func _part_function(region: Dictionary) -> float:
	var t: Dictionary = region.tissues
	var mechanical: float = minf(float(t.bone), float(t.nerve))
	mechanical *= 0.4 + 0.6 * float(t.muscle)
	return clampf(mechanical * (1.0 - minf(0.35, float(region.pain) * 0.32)), 0.0, 1.0)

func capabilities(state: Dictionary, blood_kg: float, fatigue: float) -> Dictionary:
	var left_arm: float = _part_function(state.parts.left_arm)
	var right_arm: float = _part_function(state.parts.right_arm)
	var left_leg: float = _part_function(state.parts.left_leg)
	var right_leg: float = _part_function(state.parts.right_leg)
	var systemic: float = clampf((blood_kg - 2.5) / 2.5, 0.15, 1.0)
	var alertness: float = clampf(1.0 - fatigue * 0.25, 0.6, 1.0)
	var adrenaline: float = float(state.adrenaline)
	var mobility: float = minf(left_leg, right_leg) * 0.75 + (left_leg + right_leg) * 0.125
	var grip: float = maxf(left_arm, right_arm)
	var coordination: float = minf(left_arm, right_arm) * (1.0 - 0.22 * adrenaline)
	var eyes: float = (float(state.senses.left_eye) + float(state.senses.right_eye)) * 0.5
	var ears: float = maxf(float(state.senses.left_ear), float(state.senses.right_ear))
	return {"mobility":clampf(mobility * systemic * alertness * (1.0 + 0.08 * adrenaline), 0.0, 1.0),
		"grip":clampf(grip * systemic * (1.0 + 0.08 * adrenaline), 0.0, 1.0),
		"precision":clampf(coordination * systemic * alertness, 0.0, 1.0),
		"vision":clampf(eyes * alertness, 0.0, 1.0),
		"hearing_loss_db":(1.0 - ears) * 60.0,
		"pain":float(state.pain_felt),
		"adrenaline":adrenaline}

func raw_bleeding_rate(state: Dictionary) -> float:
	var rate: float = 0.0
	for part: String in PARTS:
		for wound: Dictionary in state.parts[part].wounds:
			rate += float(wound.bleeding_kg_s) * exp(-float(wound.age_s) / 86400.0 * 0.25)
	return rate

func aggregate_wound_area(state: Dictionary) -> float:
	var area: float = 0.0
	for part: String in PARTS:
		for wound: Dictionary in state.parts[part].wounds:
			area += float(wound.area_m2)
	return area

func has_bandage(state: Dictionary) -> bool:
	for part: String in PARTS:
		for wound: Dictionary in state.parts[part].wounds:
			if bool(wound.bandaged): return true
	return false

func validate_state(state: Dictionary) -> String:
	if not state is Dictionary or state.get("schema_version") != 2: return "Неверная схема анатомии."
	if not state.get("parts") is Dictionary or state.parts.size() != PARTS.size(): return "Неизвестные части тела."
	if not state.get("senses") is Dictionary or state.senses.size() != SENSES.size(): return "Неизвестные органы чувств."
	for field: String in ["adrenaline", "pain_raw", "pain_felt"]:
		if not _fraction(state.get(field)): return "Некорректное физиологическое поле: " + field
	if not _nonnegative_number(state.get("blood_loss_kg")): return "Повреждён баланс кровопотери."
	for sense: String in SENSES:
		if not _fraction(state.senses.get(sense)): return "Повреждён орган чувств."
	for part: String in state.parts:
		if part not in PARTS: return "Неизвестная часть тела."
		var region: Dictionary = state.parts[part]
		if not region.get("tissues") is Dictionary or region.tissues.size() != TISSUES.size() or not region.get("wounds") is Array:
			return "Неверная схема тканей."
		if not _fraction(region.get("infection")) or not _fraction(region.get("pain")): return "Недопустимое состояние тканей."
		if region.wounds.size() > MAX_WOUNDS_PER_PART: return "Слишком много ран."
		for tissue: String in region.tissues:
			if tissue not in TISSUES or not _fraction(region.tissues[tissue]): return "Недопустимое состояние ткани."
		for wound in region.wounds:
			if not wound is Dictionary or wound.size() != 6: return "Некорректная рана."
			for key: String in ["area_m2", "bleeding_kg_s", "contamination", "infection", "age_s"]:
				if not _nonnegative_number(wound.get(key)): return "Недопустимая величина раны."
			if float(wound.area_m2) > 0.2 or float(wound.bleeding_kg_s) > 0.02 or float(wound.contamination) > 1.0 or float(wound.infection) > 1.0:
				return "Недопустимый размер или загрязнение раны."
			if not wound.get("bandaged") is bool: return "Повреждена повязка."
	return ""

func _nonnegative_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0

func _fraction(value: Variant) -> bool:
	return _nonnegative_number(value) and float(value) <= 1.0

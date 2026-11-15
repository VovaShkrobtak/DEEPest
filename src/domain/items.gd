extends RefCounted
## Items schema 1; SI quantities. See docs/models_items.md for approximation limits.
const MASS: Dictionary = {"wood":1.0,"cloth":0.15,"bandage":0.15,"ration":0.4,"matches":0.002,"wire":0.1,"parts":0.3,"seed":0.02,"tool":0.8,"potato":0.2,"cooked_potato":0.2}
const TITLES: Dictionary = {"wood":"Дрова","cloth":"Ткань","bandage":"Повязка","ration":"Паёк","matches":"Спички","wire":"Провод","parts":"Детали","seed":"Семена","tool":"Инструмент","potato":"Картофель","cooked_potato":"Варёный картофель"}
func initial_state() -> Dictionary:
	return {"inventory":{"wood":3,"cloth":3,"bandage":0,"ration":3,"matches":8,"wire":2,"parts":3,"seed":2,"tool":1,"potato":2,"cooked_potato":0},"water":{"volume_kg":0.5,"capacity_kg":2.0,"temp_k":285.15,"microbes":0.0,"chemical":0.0,"boil_exposure_s":0.0,"history":"Начальный запас питьевой воды"},"electricity":{"battery_j":18000.0,"lamp_on":false,"radio_repaired":false,"radio_on":false},"cart_repaired":false,"tool_wear_j":0.0,"food_age_warm_s":0.0,"installed_mass_kg":0.0}
func capacity_kg(state: Dictionary) -> float:
	return 45.0 if state.cart_repaired else 18.0
func mass_kg(state: Dictionary) -> float:
	var total: float = 0.5 + float(state.water.volume_kg) + float(state.get("installed_mass_kg",0.0))
	for id: String in state.inventory:
		total += float(state.inventory[id]) * float(MASS.get(id, 0.0))
	return total
func _kind(effect: Dictionary) -> String:
	return str(effect.get("kind", effect.get("type", effect.get("action", ""))))
func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
func validate(state: Dictionary, effect: Dictionary) -> String:
	var kind: String = _kind(effect)
	var inv: Dictionary = state.inventory
	if kind in ["add_item","remove_item","eat","drop"]:
		var item: String = str(effect.get("item", "ration" if kind == "eat" else ""))
		var amount: Variant = effect.get("amount", 1)
		if not MASS.has(item) or not _number(amount) or float(amount) <= 0.0 or float(amount) != floor(float(amount)):
			return "Неверное количество или предмет."
		if kind == "eat" and item not in ["ration","potato","cooked_potato"]:
			return "Это несъедобно."
		if kind != "add_item" and float(inv.get(item,0)) < float(amount):
			return "Не хватает предметов."
		if kind == "add_item" and mass_kg(state) + float(MASS[item]) * float(amount) > capacity_kg(state):
			return "Груз слишком тяжёлый."
		return ""
	if kind in ["take_water","remove_water"]:
		var mass: Variant = effect.get("mass_kg", 0.0)
		if not _number(mass) or float(mass) <= 0.0:
			return "Неверный объём воды."
		if kind == "remove_water":
			return "Не хватает воды." if float(mass) > float(state.water.volume_kg) else ""
		for key: String in ["microbes","chemical","temp_k"]:
			var value: Variant = effect.get(key, 285.15 if key == "temp_k" else 0.0)
			if not _number(value) or float(value) < 0.0:
				return "Некорректные свойства воды."
		if float(effect.get("temp_k",285.15)) < 273.15 or float(effect.get("temp_k",285.15)) > 373.15:
			return "Поддерживается только жидкая вода."
		if float(state.water.volume_kg) + float(mass) > float(state.water.capacity_kg) or mass_kg(state) + float(mass) > capacity_kg(state):
			return "Недостаточно вместимости."
		return ""
	if kind == "craft_bandage":
		return "Нужна ткань." if int(inv.cloth) < 1 else ""
	if kind in ["repair_radio","repair_cart"]:
		if (kind == "repair_radio" and state.electricity.radio_repaired) or (kind == "repair_cart" and state.cart_repaired):
			return "Уже исправно."
		if int(inv.tool) < 1 or float(state.tool_wear_j) >= 1000000.0:
			return "Нужен исправный инструмент."
		if int(inv.parts) < 1 or int(inv["wire" if kind == "repair_radio" else "wood"]) < 1:
			return "Не хватает материалов."
		return ""
	if kind == "switch_radio":
		return "Радио не исправно." if not state.electricity.radio_repaired else ""
	if kind == "switch_lamp":
		return ""
	if kind == "boil":
		return "Нет воды." if float(state.water.volume_kg) <= 0.0 else ""
	if kind == "cook":
		return "Нет картофеля." if int(inv.potato) < 1 else ""
	return "Неизвестное действие с предметом."
func apply(state: Dictionary, effect: Dictionary) -> void:
	if not validate(state, effect).is_empty():
		return
	var kind: String = _kind(effect)
	var inv: Dictionary = state.inventory
	var water: Dictionary = state.water
	match kind:
		"add_item","remove_item","drop","eat":
			var item: String = str(effect.get("item", "ration"))
			inv[item] = int(inv.get(item,0)) + int(effect.get("amount",1)) * (1 if kind == "add_item" else -1)
		"take_water":
			var old: float = water.volume_kg
			var added: float = effect.mass_kg
			for key: String in ["temp_k","microbes","chemical"]:
				water[key] = (old * float(water[key]) + added * float(effect.get(key,285.15 if key == "temp_k" else 0.0))) / (old + added)
			water.volume_kg = old + added
			water.boil_exposure_s = 0.0
			water.history = "Вода набрана; качество по виду неизвестно"
		"remove_water":
			water.volume_kg -= float(effect.mass_kg)
			if water.volume_kg <= 0.0:
				water.microbes = 0.0
				water.chemical = 0.0
				water.boil_exposure_s = 0.0
		"craft_bandage":
			inv.cloth -= 1
			inv.bandage += 1
		"repair_radio","repair_cart":
			state.installed_mass_kg = float(state.get("installed_mass_kg",0.0)) + 0.3 + (0.1 if kind == "repair_radio" else 1.0)
			inv.parts -= 1
			inv["wire" if kind == "repair_radio" else "wood"] -= 1
			state.tool_wear_j += 12000.0
			if kind == "repair_radio":
				state.electricity.radio_repaired = true
			else:
				state.cart_repaired = true
		"switch_radio":
			state.electricity.radio_on = not state.electricity.radio_on and float(state.electricity.battery_j) > 0.0
		"switch_lamp":
			state.electricity.lamp_on = not state.electricity.lamp_on and float(state.electricity.battery_j) > 0.0
		"cook":
			inv.potato -= 1
			inv.cooked_potato += 1
func advance(state: Dictionary, dt: float, context: Dictionary) -> Array:
	var events: Array = []
	if not is_finite(dt) or dt <= 0.0:
		return events
	var power: float = (3.0 if state.electricity.lamp_on else 0.0) + (1.0 if state.electricity.radio_on else 0.0)
	state.electricity.battery_j = maxf(0.0, float(state.electricity.battery_j) - power * dt)
	if state.electricity.battery_j == 0.0 and power > 0.0:
		state.electricity.lamp_on = false
		state.electricity.radio_on = false
		events.append({"type":"battery_empty","text":"Батарея разрядилась; приборы погасли."})
	var ambient: float = float(context.get("temp_k",285.15))
	state.food_age_warm_s += dt * pow(2.0, clampf((ambient - 293.15) / 10.0,-4.0,4.0))
	var water: Dictionary = state.water
	if float(water.volume_kg) <= 0.0:
		return events
	var remaining: float = dt
	while remaining > 0.0:
		var step: float = minf(remaining, 10.0)
		remaining -= step
		var heating: float = minf(1000.0,maxf(0.0,float(context.get("fire_w",0.0)))) if context.get("heating_water",false) else 0.0
		var heat_capacity: float = float(water.volume_kg) * 4180.0 + 250.0
		var equilibrium: float = ambient + heating / 1.5
		water.temp_k = minf(373.15, equilibrium + (float(water.temp_k) - equilibrium) * exp(-1.5 * step / heat_capacity))
		if float(water.temp_k) >= 372.15:
			water.boil_exposure_s += step
			water.microbes *= exp(-step / 10.0)
			if float(water.boil_exposure_s) >= 60.0:
				water.history = "Воду кипятили; растворённые примеси кипячением не удаляются"
	return events
func observe(state: Dictionary) -> Dictionary:
	var items: Array = []
	for id: String in MASS:
		var quantity: int = int(state.inventory.get(id,0))
		if quantity > 0:
			items.append({"id":id,"title":TITLES[id],"quantity":quantity,"unit_mass_kg":float(MASS[id]),"total_mass_kg":float(MASS[id])*quantity,"text":"%s × %d" % [TITLES[id],quantity]})
	var equipment: Array = ["Тележка исправна" if state.cart_repaired else "Тележка требует ремонта","Радио исправно" if state.electricity.radio_repaired else "Радио не работает","Фонарь включён" if state.electricity.lamp_on else "Фонарь выключен"]
	if float(state.food_age_warm_s) > 172800.0:
		equipment.append("У продуктов изменился запах; безопасность неизвестна")
	var warmth: String = "кипит" if float(state.water.temp_k) >= 372.15 else ("горячая" if float(state.water.temp_k) > 323.15 else "прохладная")
	var process_label: String = "Питьевой запас" if str(state.water.history).begins_with("Начальный") else "Вода ещё не закипела"
	if float(state.water.boil_exposure_s) >= 60.0:
		process_label = "Воду кипятили"
	elif float(state.water.temp_k) >= 372.15:
		process_label = "Довели до кипения; продолжайте нагрев"
	if float(state.water.volume_kg) <= 0.0:
		process_label = "Чайник пуст"
	return {"items":items,"process_label":process_label,"water_text":"В чайнике около %.1f л, вода %s. %s." % [state.water.volume_kg,warmth,process_label + ". " + str(state.water.history)],"load_text":"Груз около %.1f / %.0f кг" % [mass_kg(state),capacity_kg(state)],"equipment":equipment}

func observe_ground(location_items: Dictionary) -> Array:
	var found: Array = []
	for id: String in MASS:
		var amount: int = int(location_items.get(id,0))
		if amount>0:
			found.append({"id":id,"title":TITLES[id],"quantity":amount,"unit_mass_kg":float(MASS[id]),
				"total_mass_kg":float(MASS[id])*amount})
	return found

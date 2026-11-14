extends RefCounted
## Deterministic finite command vocabulary; no model, IO or simulation mutation.
const VERBS: Dictionary = {
	"inspect": ["осмотр", "осмотреть", "осмотреться", "огляд", "inspect", "look"],
	"listen": ["прислушаться", "прислушиваться", "слушать", "listen"],
	"retreat": ["отступить", "отойти от зараженного", "отойти от заражённого", "retreat"],
	"move": ["идти", "пойти", "перейти", "пройти", "move", "go", "walk"],
	"clean_chimney": ["прочист", "очистить дымоход", "clean chimney"],
	"light_fire": ["разжечь", "растопить", "зажечь печь", "light fire"],
	"add_fuel": ["подбросить", "добавить дров", "add fuel"],
	"extinguish": ["потушить", "погасить печь", "extinguish"],
	"ventilate": ["проветрить", "открыть окно", "ventilate"],
	"seal_window": ["утеплить", "заделать", "заклеить окно", "seal window"],
	"fill_water": ["набрать", "наполнить", "fill water"],
	"boil_water": ["вскипятить", "кипятить", "boil"],
	"drink": ["пить", "выпить", "попить", "drink"],
	"eat": ["есть", "поесть", "съесть", "eat"],
	"bandage": ["перевязать", "наложить повязку", "bandage"],
	"wash_wound": ["промыть", "wash wound"],
	"craft_bandage": ["сделать повязку", "изготовить повязку", "craft bandage"],
	"rest": ["отдохнуть", "отдыхать", "ждать", "подождать", "rest", "wait"],
	"sleep": ["спать", "поспать", "уснуть", "sleep"],
	"dry_clothes": ["сушить", "высушить", "просушить", "dry"],
	"talk": ["говорить", "поговорить", "talk"],
	"share_food": ["поделиться", "угостить", "share food"],
	"trade": ["торговать", "обменять", "обменяться", "trade"],
	"help_nina": ["помочь", "help nina"],
	"gather_wood": ["собрать дров", "собирать дров", "gather wood"],
	"repair_radio": ["починить радио", "ремонт радио", "repair radio"],
	"switch_radio": ["включить радио", "выключить радио", "switch radio"],
	"switch_lamp": ["включить лампу", "выключить лампу", "switch lamp"],
	"repair_cart": ["починить тележку", "ремонт тележки", "repair cart"],
	"plant": ["посадить", "сеять", "посеять", "plant"],
	"water_garden": ["полить", "поливать", "water garden"],
	"harvest": ["собрать урожай", "убрать урожай", "harvest"],
	"hunt": ["охотиться", "охота", "hunt"],
	"cook": ["готовить", "приготовить", "сварить еду", "cook"],
	"drop": ["бросить", "выбросить", "положить", "drop"]}
const LOCATIONS: Dictionary = {
	"shelter": ["дом", "дому", "убежищ", "shelter", "home"],
	"yard": ["двор", "yard"], "well": ["колод", "well"],
	"forest": ["лес", "forest"], "clinic": ["медпункт", "clinic"],
	"workshop": ["мастерск", "workshop"], "garden": ["огород", "garden"]}

func _result(ok: bool, id: String = "", parameters: Dictionary = {}, message: String = "") -> Dictionary:
	return {"ok": ok, "id": id, "parameters": parameters, "message": message}

func _normal(text: String) -> String:
	return text.to_lower().replace("ё", "е").strip_edges()

func _has_alias(text: String, aliases: Array) -> bool:
	for alias: String in aliases:
		if text.contains(alias):
			return true
	return false

func parse(text: String, actions: Array) -> Dictionary:
	var input: String = _normal(text)
	if input.is_empty():
		return _result(false, "", {}, "Введите действие: осмотреться, идти к колодцу, пить, отдыхать.")
	if input.begins_with("перел") or input.begins_with("pour"):
		return _result(false, "", {}, "Переливание пока недоступно. Поддерживаются: набрать воду, кипятить, пить.")
	# Exact action IDs and titles remain usable even for disabled actions.
	for action: Dictionary in actions:
		if input == _normal(String(action.get("id", ""))) or input == _normal(String(action.get("title", ""))):
			return _resolved(String(action.id), input, actions)
	var matched: Array[String] = []
	for id: String in VERBS:
		for alias: String in VERBS[id]:
			if input == alias or input.begins_with(alias + " ") or (alias == "прочист" and input.begins_with(alias)) or (alias == "огляд" and input.begins_with(alias)):
				matched.append(id)
				break
	if matched.size() != 1:
		return _result(false, "", {}, "Действие не распознано. Попробуйте: осмотреться, идти во двор, выпить 250 мл, отдыхать.")
	return _resolved(matched[0], input, actions)

func _resolved(id: String, input: String, actions: Array) -> Dictionary:
	var base: String = id.get_slice(":", 0)
	var parameters: Dictionary = {}
	if base == "drink":
		var quantity: Dictionary = _drink_quantity(input)
		if not quantity.ok:
			return quantity
		parameters.mass_kg = quantity.parameters.mass_kg
	if base == "move" or base == "talk" or base == "drop":
		var targets: Array[String] = []
		if id.contains(":"):
			targets.append(id.get_slice(":", 1))
		elif base == "move":
			for location: String in LOCATIONS:
				if _has_alias(input, LOCATIONS[location]):
					targets.append(location)
		else:
			for action: Dictionary in actions:
				var candidate: String = String(action.get("id", ""))
				if not candidate.begins_with(base + ":"):
					continue
				var target: String = candidate.get_slice(":", 1)
				var aliases: Array = [target]
				if target == "nina":
					aliases.append("нин")
				elif target == "pavel":
					aliases.append_array(["павел", "павл"])
				var title: String = _normal(String(action.get("title", "")))
				if _has_alias(input, aliases) or (not title.is_empty() and input.contains(title)):
					targets.append(target)
		if targets.size() != 1:
			return _result(false, "", {}, "Уточните одну цель действия по доступным вариантам.")
		var target: String = targets[0]
		id = base + ":" + target
		parameters["npc_id" if base == "talk" else ("item" if base == "drop" else "target")] = target
	return _result(true, id, parameters)

func _drink_quantity(input: String) -> Dictionary:
	var amount: float = 0.25
	if input in ["пить пол-литра", "выпить пол-литра", "попить пол-литра", "пить поллитра", "выпить поллитра", "пить пол-литра воды", "выпить пол-литра воды"]:
		amount = 0.5
	else:
		var expression := RegEx.new()
		expression.compile("^(?:пить|выпить|попить|drink)(?: воду| water)?\\s+([+-]?[0-9]+(?:[.,][0-9]+)?)\\s*(мл|ml|литр[а-я]*|л|liters?|l)(?:\\s+(?:воды|water))?$")
		var found: RegExMatch = expression.search(input)
		if found != null:
			amount = found.get_string(1).replace(",", ".").to_float()
			if found.get_string(2) in ["мл", "ml"]:
				amount *= 0.001
			# Reject additional quantities or garbage around a requested amount.
			var tail: String = input.substr(found.get_end()).strip_edges()
			if not tail.is_empty() and tail not in ["воды", "water"]:
				return _result(false, "", {}, "Укажите один объём воды, например 250 мл.")
		elif input not in ["drink", "пить", "выпить", "попить", "пить воду", "выпить воду", "drink water", "выпить воды", "попить воды", "пить воды"]:
			return _result(false, "", {}, "Не удалось понять объём: пример — выпить 250 мл или 0,5 л.")
	if not is_finite(amount) or amount <= 0.0 or amount > 2.0:
		return _result(false, "", {}, "Объём должен быть больше нуля и не больше двух литров.")
	return _result(true, "drink", {"mass_kg": amount})

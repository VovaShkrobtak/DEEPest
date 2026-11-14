extends RefCounted
## Single authoritative command/transaction boundary. No UI or OS dependency.
const Command = preload("res://src/core/action_command.gd")
const Physiology = preload("res://src/domain/physiology.gd")
const EnvModel = preload("res://src/domain/environment.gd")
const World = preload("res://src/domain/world.gd")
const Items = preload("res://src/domain/items.gd")
const BUILD: String = "0.1.0"
const CONTENT_HASH: String = "deepest-first-night-v1"
const MAX_JOURNAL: int = 180
const MAX_TRACE: int = 240
const WORK_IDS: Array[String] = ["clean_chimney","seal_window","craft_bandage","repair_radio","repair_cart"]
var modules: Dictionary = {"physiology":Physiology.new(),"environment":EnvModel.new(),"world":World.new(),"items":Items.new()}
var _state: Dictionary

func _init(seed_value: int = 1998) -> void:
	_state = {"schema_version":1,"build":BUILD,"content_hash":CONTENT_HASH,"seed":seed_value,"time_s":0,"revision":0,
		"location":"shelter","body":modules.physiology.initial_state(),"environment":modules.environment.initial_state(seed_value),
		"world":modules.world.initial_state(seed_value),"items":modules.items.initial_state(),"action":{},"journal":[],"trace":[],"action_log":[],
		"work_progress":{},"knowledge":{},"goals":[],"won":false,"consumed":{},"ground":{}}
	_log("arrival", "14 октября 1998 года. Посёлок затих. По улицам бродят заражённые. Здесь нет сюжета, квестов или спасательного финала.")
	_log("hint", "На руке саднит порез. Из ткани можно сделать повязку. Выживание зависит от действий, звуков и состояния мира.")

func _result(ok: bool, message: String = "") -> Dictionary:
	return {"ok":ok,"message":message}

func _log(type: String, text: String, location: String = "") -> void:
	_state.journal.append({"time_s":_state.time_s,"type":type,"text":text,"location":location if location != "" else _state.location})
	if _state.journal.size() > MAX_JOURNAL:
		_state.journal.pop_front()

func _trace(type: String, payload: Dictionary) -> void:
	_state.trace.append({"sequence":_state.revision,"time_s":_state.time_s,"type":type,"payload":payload.duplicate(true)})
	if _state.trace.size() > MAX_TRACE:
		_state.trace.pop_front()

func _action(id: String, title: String, seconds: int, description: String, category: String = "Действия", params: Dictionary = {}) -> Dictionary:
	var reason: String = _validate(id, params)
	return {"id":id,"title":title,"description":description,"duration_s":seconds,"enabled":reason.is_empty(),"reason":reason,"category":category,"parameters":params.duplicate(true)}

func available_actions() -> Array:
	var out: Array = []
	out.append(_action("inspect","Осмотреться",60,"Замечать детали, а не гадать. Время идёт и при осмотре.","Мир"))
	var graph: Dictionary = modules.world.locations()
	for target: String in graph[_state.location].connections:
		var distance: float = graph[_state.location].connections[target]
		var load_kg: float = modules.items.mass_kg(_state.items)
		var speed: float = 1.2 / (1.0 + load_kg / 35.0 + float(_state.body.fatigue) * 0.6)
		out.append(_action("move:" + target, "Куда: " + str(graph[target].title), maxi(30,ceili(distance / speed)),"%d м по сельской дороге. По пути вы несёте весь груз." % int(distance),"Путь",{"target":target}))
	if _state.environment.rooms.has(_state.location):
		out.append(_action("clean_chimney","Проверить и очистить дымоход",600,"Улучшить тягу перед растопкой. Нужен инструмент.","Убежище"))
		out.append(_action("add_fuel","Подложить дрова",60,"Перенести 1 кг дров из рюкзака в печь.","Убежище"))
		out.append(_action("light_fire","Растопить печь",180,"Потребуется спичка и топливо в топке. Грязный дымоход дымит.","Убежище"))
		out.append(_action("extinguish","Погасить печь",60,"Закрыть подачу, остановить горение. Оставшееся топливо сохранится.","Убежище"))
		out.append(_action("ventilate","Закрыть окно" if _state.environment.rooms[_state.location].window_open else "Открыть окно",30,"Свежий воздух выводит дым, но уносит тепло.","Убежище"))
		out.append(_action("seal_window","Утеплить окно",900,"Заделать щели тканью. Снизится и утечка тепла, и приток воздуха.","Убежище"))
		out.append(_action("boil_water","Кипятить воду",1200,"Греть чайник у печи 20 минут. Кипячение не удаляет химические примеси.","Вода и еда"))
		out.append(_action("cook","Сварить картофель",900,"Потратить время у работающей печи. Готовая еда усвоится постепенно.","Вода и еда"))
		out.append(_action("dry_clothes","Сушиться у печи",1800,"Одежда сохнет от тепла, а не по таймеру. Печь должна гореть.","Тело"))
	if _state.location == "well":
		out.append(_action("fill_water","Набрать воду",180,"Наполнить чайник из колодца, не превышая его объём. Вид воды не доказывает безопасность.","Вода и еда"))
	if _state.location == "forest":
		out.append(_action("gather_wood","Собрать валежник",1200,"Собрать 2 кг древесины. Доступный валежник конечен.","Ремесло"))
		out.append(_action("hunt","Проверить силки",3600,"Заготовить добычу: ткань на силок, инструмент и час работы. Популяция конечна.","Ремесло"))
	if _state.location == "garden":
		out.append(_action("plant","Засеять грядку",1200,"Семена, влажная почва и недели подходящей погоды; быстрых урожаев не бывает.","Ремесло"))
		out.append(_action("water_garden","Полить грядку",180,"Передать 0,5 л из чайника почве.","Ремесло"))
		out.append(_action("harvest","Собрать урожай",1200,"Собрать созревшие клубни. Посев не восстанавливается сам.","Ремесло"))
	for npc_id: String in _state.world.npcs:
		var npc: Dictionary = _state.world.npcs[npc_id]
		if npc.location == _state.location and npc.destination == "":
			out.append(_action("talk:" + npc_id,"Поговорить: " + str(npc.title),300,"Узнать о жизни посёлка и полезных приёмах.","Люди",{"npc_id":npc_id}))
			out.append(_action("share_food:" + npc_id,"Поделиться едой: " + str(npc.title),120,"Передать один паёк. Поступки остаются в памяти.","Люди",{"npc_id":npc_id}))
			out.append(_action("trade:" + npc_id,"Обменять паёк на ткань",300,"Один ваш паёк на два отреза ткани из реального запаса собеседника.","Люди",{"npc_id":npc_id}))
			if npc_id == "nina":
				out.append(_action("help_nina","Помочь Нине с повязкой",600,"Нужна готовая повязка. Уход ограничит кровопотерю, но не вылечит рану мгновенно.","Люди",{"npc_id":"nina"}))
	out.append(_action("drink","Выпить воды",30,"Небольшими глотками: 250 мл. Горячую воду сначала остудите.","Вода и еда",{"mass_kg":0.25}))
	out.append(_action("eat","Поесть",300,"Съесть один паёк или приготовленный картофель.","Вода и еда"))
	out.append(_action("craft_bandage","Сделать повязку",300,"Один отрез ткани превратить в повязку. Ткань не появляется заново.","Ремесло"))
	out.append(_action("bandage","Перевязать руку",180,"Остановить часть кровотечения готовой повязкой.","Тело"))
	out.append(_action("wash_wound","Промыть порез",120,"Израсходовать 100 мл остывшей кипячёной воды.","Тело"))
	out.append(_action("rest","Отдохнуть полчаса",1800,"Сесть, снизить нагрузку. Мир продолжает жить.","Тело"))
	out.append(_action("sleep","Спать два часа",7200,"Сон помогает при приемлемой температуре и воздухе. Опасность прервёт сон.","Тело"))
	out.append(_action("wait","Подождать 10 минут",600,"Дать воде остыть или переждать. Потребности и запасы продолжают меняться.","Мир"))
	out.append(_action("repair_radio","Починить радиоприёмник",1500,"Мастерская, инструмент, провод и деталь. Нужна ещё энергия батареи.","Ремесло"))
	out.append(_action("switch_radio","Выключить радио" if _state.items.electricity.radio_on else "Включить радио",30,"Исправный приёмник расходует заряд; он не работает без питания.","Ремесло"))
	out.append(_action("switch_lamp","Выключить фонарь" if _state.items.electricity.lamp_on else "Включить фонарь",30,"Фонарь даёт свет и расходует батарею.","Вещи"))
	out.append(_action("repair_cart","Отремонтировать тележку",1800,"В мастерской: 1 кг дерева и деталь. Грузоподъёмность станет больше.","Ремесло"))
	return out

func _base(id: String) -> String:
	return id.split(":")[0]

func _params(id: String, args: Dictionary) -> Dictionary:
	var params: Dictionary = args.duplicate(true)
	if id.begins_with("move:"):
		params.target = id.substr(5)
	elif ":" in id:
		params.npc_id = id.split(":")[1]
	return params

func _validate(id: String, arguments: Dictionary) -> String:
	var args: Dictionary = _params(id, arguments)
	var verb: String = _base(id)
	var inv: Dictionary = _state.items.inventory
	var room: Dictionary = _state.environment.rooms.get(_state.location,{})
	if not _state.action.is_empty(): return "Сначала завершите или прервите текущее действие."
	if not _state.body.alive: return "Персонаж погиб. Можно начать новое выживание."
	if not _state.body.conscious and verb != "wait": return "Вы без сознания. Можно дать времени пройти."
	match verb:
		"move":
			return "Нет прямого пути. Сначала выйдите во двор." if not modules.world.locations()[_state.location].connections.has(str(args.get("target",""))) else ""
		"inspect","rest","wait": return ""
		"sleep":
			if room.is_empty(): return "Для сна найдите помещение."
			if float(room.smoke) > 0.1: return "Здесь дымно. Сначала проветрите."
			return ""
		"clean_chimney":
			if room.is_empty(): return "Здесь нет печи."
			if room.chimney_clean: return "Дымоход уже очищен."
			if room.burning: return "Сначала погасите печь."
			return "Нужен инструмент." if inv.tool < 1 else ""
		"add_fuel":
			if room.is_empty(): return "Здесь нет печи."
			return modules.items.validate(_state.items,{"kind":"remove_item","item":"wood","amount":1})
		"light_fire":
			if room.is_empty(): return "Здесь нет печи."
			if room.burning: return "Печь уже горит."
			if room.fuel_kg <= 0.0: return "В топке нет дров. Сначала подложите топливо."
			if room.oxygen <= 0.14: return "Нужен свежий воздух: проветрите помещение."
			return "Нет спичек." if inv.matches < 1 else ""
		"extinguish": return "Печь не горит." if room.is_empty() or not room.burning else ""
		"ventilate": return "Здесь нет окна." if room.is_empty() else ""
		"seal_window":
			if room.is_empty(): return "Здесь нет окна."
			if room.sealed: return "Щели уже заделаны."
			return "Нужна ткань." if inv.cloth < 1 else ""
		"boil_water","cook","dry_clothes":
			if room.is_empty() or not room.burning: return "Нужна работающая печь."
			if verb == "boil_water": return modules.items.validate(_state.items,{"kind":"boil"})
			if verb == "cook": return modules.items.validate(_state.items,{"kind":"cook"})
			return ""
		"fill_water":
			if _state.location != "well": return "Набрать воду можно у колодца."
			var mass: float = float(_state.items.water.capacity_kg) - float(_state.items.water.volume_kg)
			var reason: String = modules.items.validate(_state.items,{"kind":"take_water","mass_kg":mass})
			if reason != "": return "Чайник полон." if mass < 0.001 else reason
			return modules.world.availability(_state.world,{"kind":"take_water","mass_kg":mass})
		"drink":
			var mass: Variant = args.get("mass_kg",0.25)
			if not (mass is float or mass is int) or not is_finite(float(mass)) or float(mass) <= 0.0 or float(mass) > 2.0: return "Укажите объём от 1 до 2000 мл."
			if _state.items.water.temp_k > 323.15: return "Вода слишком горячая. Подождите, пока остынет."
			return modules.items.validate(_state.items,{"kind":"remove_water","mass_kg":float(mass)})
		"eat": return "Нет готовой еды." if inv.ration < 1 and inv.cooked_potato < 1 else ""
		"craft_bandage": return modules.items.validate(_state.items,{"kind":"craft_bandage"})
		"bandage","help_nina":
			if inv.bandage < 1: return "Нужна повязка. Сделайте её из ткани."
			if verb == "bandage": return "Повязка уже наложена." if _state.body.bandaged else ""
			return modules.world.availability(_state.world,{"kind":"help_nina","npc_id":"nina","location":_state.location})
		"wash_wound":
			if _state.items.water.temp_k > 313.15: return "Нужна остывшая вода."
			if _state.items.water.boil_exposure_s < 60.0: return "Сначала прокипятите воду."
			return modules.items.validate(_state.items,{"kind":"remove_water","mass_kg":0.1})
		"talk","share_food","trade":
			var reason: String = modules.world.availability(_state.world,{"kind":verb,"npc_id":args.get("npc_id",""),"location":_state.location})
			if reason != "": return reason
			if verb in ["share_food","trade"] and inv.ration < 1: return "Нужен паёк для передачи."
			if verb == "trade": return modules.items.validate(_state.items,{"kind":"add_item","item":"cloth","amount":2})
			return ""
		"gather_wood","hunt":
			if _state.location != "forest": return "Для этого нужно выйти в лес."
			if verb == "hunt" and (inv.cloth < 1 or inv.tool < 1): return "Нужны ткань и инструмент."
			var reason: String = modules.world.availability(_state.world,{"kind":verb,"mass_kg":2.0 if verb == "gather_wood" else 0.4})
			if reason != "": return reason
			return modules.items.validate(_state.items,{"kind":"add_item","item":"wood" if verb == "gather_wood" else "ration","amount":2 if verb == "gather_wood" else 1})
		"plant","water_garden","harvest":
			if _state.location != "garden": return "Для этого нужно быть у грядки."
			if verb == "plant" and inv.seed < 1: return "Нужны семена."
			var reason: String = modules.world.availability(_state.world,{"kind":verb,"mass_kg":0.5})
			if reason != "": return reason
			if verb == "water_garden": return modules.items.validate(_state.items,{"kind":"remove_water","mass_kg":0.5})
			if verb == "harvest": return modules.items.validate(_state.items,{"kind":"add_item","item":"potato","amount":10})
			return ""
		"repair_radio","repair_cart":
			if _state.location != "workshop": return "Работайте на верстаке в мастерской."
			return modules.items.validate(_state.items,{"kind":verb})
		"switch_radio","switch_lamp": return modules.items.validate(_state.items,{"kind":verb})
	return "Неизвестное действие. Откройте список доступных действий."

func command(id: String, parameters: Dictionary = {}) -> Dictionary:
	return submit(Command.new(id,parameters))

func submit(command_value: RefCounted) -> Dictionary:
	if command_value.expected_revision >= 0 and command_value.expected_revision != _state.revision:
		return _result(false,"Обстановка изменилась; обновите выбор.")
	var id: String = command_value.id
	var params: Dictionary = _params(id,command_value.parameters)
	var reason: String = _validate(id,params)
	if reason != "": return _result(false,reason)
	var descriptor: Dictionary = {}
	for candidate: Dictionary in available_actions():
		if candidate.id == id or (_base(candidate.id) == id and candidate.parameters == params):
			descriptor = candidate
			break
	if descriptor.is_empty():
		# Generic move/social grammar commands must resolve to a concrete affordance.
		if id == "move": return self.command("move:" + str(params.get("target","")),params)
		if id in ["talk","share_food","trade"]: return self.command(id + ":" + str(params.get("npc_id","")),params)
		return _result(false,"Такого действия сейчас нет рядом.")
	_state.action = {"id":descriptor.id,"title":descriptor.title,"elapsed_s":int(_state.work_progress.get(_work_key(descriptor.id,_state.location),0)),"duration_s":int(descriptor.duration_s),"parameters":params,"start_location":_state.location}
	_state.revision += 1
	_state.action_log.append({"time_s":_state.time_s,"id":descriptor.id,"parameters":params.duplicate(true)})
	# Bounded replay window. Full archival replay persistence remains documented.
	if _state.action_log.size() > 2048: _state.action_log.pop_front()
	_trace("action_start",_state.action)
	return _result(true,"Начато: " + str(descriptor.title))

func step(seconds: float) -> Dictionary:
	if not is_finite(seconds) or seconds <= 0.0 or seconds != floor(seconds): return _result(false,"Некорректный шаг времени.")
	if _state.action.is_empty(): return _result(false,"Сначала выберите действие.")
	var remaining: int = mini(int(seconds),86400)
	while remaining > 0 and not _state.action.is_empty():
		var action: Dictionary = _state.action
		var dt: int = mini(10,mini(remaining,int(action.duration_s) - int(action.elapsed_s)))
		var verb: String = _base(action.id)
		var air: Dictionary = modules.environment.conditions(_state.environment,_state.location)
		_append_events(modules.environment.advance(_state.environment,dt,{"heating_water":verb == "boil_water" and _state.items.water.volume_kg > 0.0,"location":_state.location}))
		air = modules.environment.conditions(_state.environment,_state.location)
		var burning: bool = _state.environment.rooms.get(_state.location,{}).get("burning",false)
		var item_context: Dictionary = air.duplicate(true)
		item_context.fire_w = float(_state.environment.rooms.get(_state.location,{}).get("last_water_w",0.0)) if burning else 0.0
		item_context.heating_water = verb == "boil_water"
		item_context.location = _state.location
		_append_events(modules.items.advance(_state.items,dt,item_context))
		var body_context: Dictionary = air.duplicate(true)
		body_context.exertion = 0.42 if verb in ["move","gather_wood","hunt","plant","repair_cart"] else (0.1 if verb in ["rest","sleep","wait","dry_clothes"] else 0.22)
		body_context.sleeping = verb in ["sleep","rest"]
		_append_events(modules.physiology.advance(_state.body,dt,body_context))
		_append_events(modules.world.advance(_state.world,dt,{"weather":_state.environment.weather,"rooms":_state.environment.rooms,"hour":fmod(16.0 + 20.0 / 60.0 + float(_state.time_s)/3600.0,24.0)}))
		_state.time_s += dt
		action.elapsed_s += dt
		remaining -= dt
		_state.revision += 1
		if not _state.body.alive or (not _state.body.conscious and verb != "wait"):
			_log("danger","Действие прервано: " + ("вы потеряли сознание." if _state.body.alive else "жизненные функции угасли."))
			_state.action = {}
		elif verb == "sleep" and (float(air.smoke) > 0.15 or float(_state.body.core_k) < 307.0):
			_log("danger","Вы просыпаетесь от холода или тяжёлого воздуха. Сон прерван; время уже прошло.")
			_state.action = {}
		elif action.elapsed_s >= action.duration_s:
			_state.action = {}
			var reason: String = _validate(action.id,action.parameters)
			if reason == "":
				_complete(action)
				_state.work_progress.erase(_work_key(action.id,action.start_location))
				_log("action",str(action.title) + " — завершено.")
				_trace("action_complete",action)
			else:
				_log("interrupted","Работа остановлена: " + reason + " Потраченное время сохраняется.")
		return _result(true)

func _append_events(events: Array) -> void:
	for event: Dictionary in events:
		_trace(str(event.get("type","event")),event)
		# Nonlocal NPC events belong only to developer trace.
		if event.get("location",_state.location) == _state.location:
			_log(str(event.get("type","event")),str(event.get("text","")))

func cancel() -> Dictionary:
	if _state.action.is_empty(): return _result(false,"Нет текущей работы.")
	if _base(_state.action.id) in WORK_IDS:
		_state.work_progress[_work_key(_state.action.id,_state.location)] = int(_state.action.elapsed_s)
	_trace("action_cancel",_state.action)
	_log("interrupted","Вы прерываете работу: " + str(_state.action.title) + ". Уже прошедшее время и изменения сохраняются.")
	_state.action = {}
	_state.revision += 1
	return _result(true,"Работа прервана.")

func _item(kind: String, args: Dictionary = {}) -> void:
	var effect: Dictionary = args.duplicate(true)
	effect.kind = kind
	modules.items.apply(_state.items,effect)

func _body(kind: String, args: Dictionary = {}) -> void:
	var effect: Dictionary = args.duplicate(true)
	effect.kind = kind
	modules.physiology.apply(_state.body,effect)

func _consume(item: String, amount: int = 1) -> void:
	_item("remove_item",{"item":item,"amount":amount})
	_state.consumed[item] = int(_state.consumed.get(item,0)) + amount

func _complete(action: Dictionary) -> void:
	var verb: String = _base(action.id)
	var params: Dictionary = action.parameters
	match verb:
		"inspect":
			_state.knowledge[_state.location] = {"seen_at":_state.time_s}
			_log("observation","Вы внимательно осматриваете место, прислушиваетесь и запоминаете детали.")
		"move":
			_state.location = params.target
			_state.knowledge[_state.location] = {"seen_at":_state.time_s}
		"add_fuel":
			_consume("wood")
			modules.environment.apply(_state.environment,{"kind":"add_fuel","mass_kg":1.0,"location":_state.location})
		"light_fire":
			_consume("matches")
			modules.environment.apply(_state.environment,{"kind":verb,"location":_state.location})
		"clean_chimney","extinguish","ventilate": modules.environment.apply(_state.environment,{"kind":verb,"location":_state.location})
		"seal_window":
			_consume("cloth")
			modules.environment.apply(_state.environment,{"kind":verb,"location":_state.location})
		"fill_water":
			var mass: float = float(_state.items.water.capacity_kg) - float(_state.items.water.volume_kg)
			modules.world.apply(_state.world,{"kind":"take_water","mass_kg":mass})
			_item("take_water",{"mass_kg":mass,"temp_k":maxf(274.15,float(_state.environment.weather.temp_k)),"microbes":0.6,"chemical":0.03})
		"boil_water":
			_log("observation", "Вода кипела; теперь дайте ей остыть. Растворённые примеси остаются." if _state.items.water.boil_exposure_s >= 60.0 else "Вода нагрелась, но ещё не прокипела достаточно. Проверьте топливо и повторите нагрев; время и тепло уже затрачены.")
		"drink":
			var mass: float = float(params.get("mass_kg",0.25))
			_body("drink",{"water_kg":mass,"microbes":float(_state.items.water.microbes)*mass,"chemical":float(_state.items.water.chemical)*mass})
			_item("remove_water",{"mass_kg":mass})
		"eat":
			var food: String = "cooked_potato" if _state.items.inventory.cooked_potato > 0 else "ration"
			_consume(food)
			_body("eat",{"energy_j":600000.0 if food == "cooked_potato" else 2800000.0,"water_kg":0.15 if food == "cooked_potato" else 0.08,"microbes":0.5 if _state.items.food_age_warm_s > 172800.0 else 0.0})
		"bandage":
			_consume("bandage")
			_body("bandage")
		"wash_wound":
			_item("remove_water",{"mass_kg":0.1})
			_body("wash_wound")
		"craft_bandage","repair_radio","repair_cart","switch_radio","switch_lamp","cook":
			_item(verb)
			if verb == "switch_radio" and _state.items.electricity.radio_on:
				_log("radio","Сквозь помехи доносится обрывок чужого разговора. Никто не обещает эвакуации.")
		"gather_wood","hunt":
			modules.world.apply(_state.world,{"kind":verb,"mass_kg":2.0 if verb == "gather_wood" else 0.4})
			_item("add_item",{"item":"wood" if verb == "gather_wood" else "ration","amount":2 if verb == "gather_wood" else 1})
			if verb == "hunt": _consume("cloth")
		"talk","trade","share_food","help_nina":
			var npc_id: String = params.get("npc_id","nina")
			if verb in ["trade","share_food"]: _consume("ration")
			if verb == "help_nina": _consume("bandage")
			if verb == "trade": _item("add_item",{"item":"cloth","amount":2})
			modules.world.apply(_state.world,{"kind":verb,"npc_id":npc_id,"location":_state.location})
			if verb == "talk":
				_state.knowledge["advice:" + npc_id] = {"seen_at":_state.time_s}
				_log("conversation","Нина: «Воду кипяти, но если пахнет химией — ищи другую. И мокрым не засыпай»." if npc_id == "nina" else "Павел: «Проверь тягу до растопки. Верстак бери, если приёмник починить решил»." )
		"plant":
			_consume("seed")
			modules.world.apply(_state.world,{"kind":verb})
		"water_garden":
			_item("remove_water",{"mass_kg":0.5})
			modules.world.apply(_state.world,{"kind":verb,"mass_kg":0.5})
		"harvest":
			modules.world.apply(_state.world,{"kind":verb})
			_item("add_item",{"item":"potato","amount":10})
	_body("practice",{"skill":verb})

func snapshot() -> Dictionary:
	var Observer: Script = load("res://src/application/observer.gd")
	return Observer.new().build(_state,modules)

func debug_snapshot() -> Dictionary:
	return _state.duplicate(true)

func export_state() -> Dictionary:
	return _state.duplicate(true)

func restore_state(data: Dictionary) -> Dictionary:
	var reason: String = validate_state(data)
	if reason != "": return _result(false,reason)
	_state = data.duplicate(true)
	# Old first-night quest fields remain for save compatibility, but do not govern play.
	_state.goals = []
	_state.won = false
	return _result(true,"Сохранение загружено.")

func validate_state(data: Dictionary) -> String:
	if data.get("schema_version",0) != 1 or data.get("build","") != BUILD or data.get("content_hash","") != CONTENT_HASH: return "Несовместимая версия сохранения или контента."
	for key: String in ["seed","time_s","revision","location","body","environment","world","items","action","journal","trace","action_log","work_progress","knowledge","goals","won","consumed","ground"]:
		if not data.has(key): return "Сохранение неполное: " + key
	if not _finite_tree(data): return "Сохранение содержит недопустимые численные значения."
	var graph: Dictionary = modules.world.locations()
	if not data.location is String or not graph.has(data.location): return "В сохранении неизвестное место."
	for field: String in ["seed","time_s","revision"]:
		if not _whole(data[field]) or float(data[field]) < 0.0 or float(data[field]) > 9007199254740991.0: return "Недопустимое целое поле: " + field
	for pair: Array in [["body",modules.physiology.initial_state()],["environment",modules.environment.initial_state()],["world",modules.world.initial_state()],["items",modules.items.initial_state()]]:
		if not data[pair[0]] is Dictionary or not _same_shape(pair[1],data[pair[0]]): return "Повреждена схема модуля: " + str(pair[0])
	for key: String in ["action","work_progress","knowledge","consumed","ground"]:
		if not data[key] is Dictionary: return "Повреждено поле " + key
	for key: String in ["journal","trace","action_log","goals"]:
		if not data[key] is Array: return "Повреждена очередь " + key
	if not data.won is bool: return "Повреждено состояние целей."
	if data.journal.size() > MAX_JOURNAL or data.trace.size() > MAX_TRACE or data.action_log.size() > 2048: return "Превышен размер журнала."
	if not _nonnegative(data.body) or not _nonnegative(data.items) or not _nonnegative(data.environment) or not _nonnegative(data.world): return "Отрицательная физическая величина."
	if data.items.water.capacity_kg != 2.0 or data.items.water.volume_kg > 2.0: return "Недопустимый объём воды."
	if data.items.electricity.battery_j > 18000.0: return "Недопустимый заряд."
	if data.items.inventory.size() != Items.MASS.size(): return "Неизвестные предметы в инвентаре."
	for item: String in data.items.inventory:
		if not Items.MASS.has(item) or not _whole(data.items.inventory[item]): return "Недопустимое количество предметов."
	if not _exact_keys(data.environment.rooms,modules.environment.initial_state().rooms) or not _exact_keys(data.world.npcs,modules.world.initial_state().npcs): return "Неизвестные сущности модулей."
	if JSON.stringify(data.world.locations) != JSON.stringify(graph):
		# JSON numeric encoding may change int→float; canonical graph itself uses float distances.
		if data.world.locations != graph: return "Изменена схема маршрутов."
	for room_id: String in data.environment.rooms:
		if not graph.has(room_id): return "Неизвестное помещение."
		var room: Dictionary = data.environment.rooms[room_id]
		if room.temp_k < 150.0 or room.temp_k > 1000.0 or room.oxygen > 0.3: return "Недопустимые условия помещения."
	for npc_id: String in data.world.npcs:
		var npc: Dictionary = data.world.npcs[npc_id]
		if not graph.has(npc.location) or (npc.destination != "" and not graph[npc.location].connections.has(npc.destination)): return "Неизвестный маршрут NPC."
		if npc.trust > 1.0 or npc.travel_s > 100000.0: return "Недопустимое состояние NPC."
	if not data.action.is_empty():
		var reason: String = _validate_saved_action(data.action,data.location,graph)
		if reason != "": return reason
	for id: String in data.work_progress:
		var job: PackedStringArray = id.split("@")
		if job.size() != 2 or not job[0] in WORK_IDS or (not graph.has(job[1]) and job[1] != "player") or not _whole(data.work_progress[id]) or data.work_progress[id] >= _duration(job[0]) or data.work_progress[id] < 0: return "Некорректный прогресс работы."
	for entry: Variant in data.journal:
		if not entry is Dictionary or not entry.get("text") is String or not entry.get("type") is String or not _whole(entry.get("time_s")) or not entry.get("location") is String: return "Повреждена запись журнала."
	return ""

func _work_key(id: String, location: String) -> String:
	return id + "@" + ("player" if id == "craft_bandage" else location)

func _duration(id: String) -> int:
	return int({"inspect":60,"clean_chimney":600,"add_fuel":60,"light_fire":180,"extinguish":60,"ventilate":30,"seal_window":900,"boil_water":1200,"cook":900,"dry_clothes":1800,"fill_water":180,"gather_wood":1200,"hunt":3600,"plant":1200,"water_garden":180,"harvest":1200,"talk":300,"share_food":120,"trade":300,"help_nina":600,"drink":30,"eat":300,"craft_bandage":300,"bandage":180,"wash_wound":120,"rest":1800,"sleep":7200,"wait":600,"repair_radio":1500,"switch_radio":30,"switch_lamp":30,"repair_cart":1800}.get(id,0))

func _validate_saved_action(action: Dictionary, location: String, graph: Dictionary) -> String:
	for key: String in ["id","title","elapsed_s","duration_s","parameters","start_location"]:
		if not action.has(key): return "Повреждено незавершённое действие."
	if not action.id is String or not action.title is String or not action.parameters is Dictionary or not action.start_location is String: return "Неверный тип действия."
	if not _whole(action.elapsed_s) or not _whole(action.duration_s) or action.elapsed_s < 0 or action.duration_s <= action.elapsed_s or action.duration_s > 86400: return "Недопустимый прогресс действия."
	if action.start_location != location: return "Работа относится к другому месту."
	var verb: String = _base(action.id)
	if verb == "move":
		var target: String = str(action.parameters.get("target",""))
		if action.id != "move:" + target or not graph[location].connections.has(target): return "Недопустимый путь действия."
	elif verb in ["talk","trade","share_food"]:
		var npc: String = str(action.parameters.get("npc_id",""))
		if npc not in ["nina","pavel"] or action.id != verb + ":" + npc or action.duration_s != _duration(verb): return "Недопустимая цель действия."
	elif action.id != verb or _duration(verb) <= 0 or action.duration_s != _duration(verb): return "Неизвестное действие в сохранении."
	if verb == "drink":
		var mass: Variant = action.parameters.get("mass_kg",0.25)
		if not (mass is int or mass is float) or mass <= 0.0 or mass > 2.0: return "Недопустимый объём действия."
	return ""

func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func _nonnegative(value: Variant, key: String = "") -> bool:
	# Signed environmental energy exchanges are valid; inventories/masses are not.
	if value is int or value is float:
		return float(value) >= 0.0 or key in ["heat_loss_j","heat_to_environment_j"]
	if value is Dictionary:
		for child: Variant in value:
			if not _nonnegative(value[child],str(child)): return false
	if value is Array:
		for child: Variant in value:
			if not _nonnegative(child,key): return false
	return true

func _exact_keys(value: Dictionary, reference: Dictionary) -> bool:
	if value.size() != reference.size(): return false
	for key: Variant in reference:
		if not value.has(key): return false
	return true

func _same_shape(reference: Dictionary, value: Dictionary) -> bool:
	for key: Variant in reference:
		if not value.has(key): return false
		if reference[key] is Dictionary:
			if not value[key] is Dictionary or not _same_shape(reference[key],value[key]): return false
		elif reference[key] is Array:
			if not value[key] is Array: return false
		elif reference[key] is bool:
			if not value[key] is bool: return false
		elif reference[key] is int or reference[key] is float:
			if not (value[key] is int or value[key] is float): return false
		elif typeof(reference[key]) != typeof(value[key]): return false
	return true

func _finite_tree(value: Variant, depth: int = 0) -> bool:
	if depth > 64: return false
	if value is float: return is_finite(value)
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _finite_tree(value[key],depth+1): return false
	if value is Array:
		for child: Variant in value:
			if not _finite_tree(child,depth+1): return false
	return value == null or value is Dictionary or value is Array or value is String or value is int or value is float or value is bool

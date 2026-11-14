extends RefCounted
## Single authoritative command/transaction boundary. No UI or OS dependency.
const Command = preload("res://src/core/action_command.gd")
const Physiology = preload("res://src/domain/physiology.gd")
const EnvModel = preload("res://src/domain/environment.gd")
const World = preload("res://src/domain/world.gd")
const Items = preload("res://src/domain/items.gd")
const Zombies = preload("res://src/domain/zombies.gd")
const Acoustics = preload("res://src/domain/acoustics.gd")
const Anatomy = preload("res://src/domain/anatomy.gd")
const Props = preload("res://src/domain/objects.gd")
const BUILD: String = "0.1.0"
const CONTENT_HASH: String = "deepest-first-night-v1"
const MAX_JOURNAL: int = 180
const MAX_TRACE: int = 240
const WORK_IDS: Array[String] = ["clean_chimney","seal_window","craft_bandage","repair_radio","repair_cart","prop_dismantle"]
var modules: Dictionary = {"physiology":Physiology.new(),"environment":EnvModel.new(),"world":World.new(),"items":Items.new(),"zombies":Zombies.new(),"acoustics":Acoustics.new(),"props":Props.new()}
var _state: Dictionary

func _init(seed_value: int = 1998) -> void:
	_state = {"schema_version":1,"build":BUILD,"content_hash":CONTENT_HASH,"seed":seed_value,"time_s":0,"revision":0,
		"location":"shelter","body":modules.physiology.initial_state(),"environment":modules.environment.initial_state(seed_value),
		"world":modules.world.initial_state(seed_value),"items":modules.items.initial_state(),"zombies":modules.zombies.initial_state(seed_value),"acoustics":modules.acoustics.initial_state(),"action":{},"journal":[],"trace":[],"action_log":[],
		"work_progress":{},"knowledge":{},"goals":[],"won":false,"consumed":{},"ground":{},"props":modules.props.initial_state()}
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
	var factor: float = 1.0 if _base(id) == "move" else clampf(modules.physiology.action_efficiency(_state.body, _base(id)), 0.30, 1.0)
	var actual_seconds: int = maxi(seconds, ceili(float(seconds) / factor))
	return {"id":id,"title":title,"description":description,"duration_s":actual_seconds,
		"base_duration_s":seconds,"ability_factor":factor,
		"enabled":reason.is_empty(),"reason":reason,"category":category,"parameters":params.duplicate(true)}


func available_actions() -> Array:
	var out: Array = []
	out.append(_action("inspect","Осмотреться",60,"Замечать детали, а не гадать. Время идёт и при осмотре.","Мир"))
	out.append(_action("listen","Прислушаться",20,"Выделить тихие звуки обстановки. Пока вы слушаете, мир не замирает.","Мир"))
	out.append(_action("retreat","Отступить от заражённого",30,"Разорвать близкий контакт ценой времени и физической нагрузки.","Опасность"))
	out.append(_action("shove","Оттолкнуть фигуру",18,"Приложить импульс руками, чтобы разорвать контакт или вывести противника из равновесия.","Опасность"))
	out.append(_action("break_grapple","Освободиться от захвата",12,"Вывернуть удерживаемую конечность; результат зависит от хватки и моторики.","Опасность"))
	var graph: Dictionary = modules.world.locations()
	for portal: Dictionary in modules.zombies.nearby_doors(_state.zombies,graph,_state.location):
		var other: String = str(portal.other)
		var door: Dictionary = portal.door
		if bool(door.open):
			out.append(_action("door_close:" + other,"Прикрыть дверь: " + str(graph[other].title),
				25,"Закрыть физический проход; движение и звук изменятся.","Убежище",{"other":other}))
		else:
			out.append(_action("door_open:" + other,"Открыть дверь: " + str(graph[other].title),
				25,"Открыть путь, если нет подпорки.","Убежище",{"other":other}))
			out.append(_action("door_brace:" + other,"Подпереть дверь: " + str(graph[other].title),
				90,"Израсходовать 1 кг древесины, увеличив усилие для разрушения.","Убежище",{"other":other}))
			out.append(_action("door_unbrace:" + other,"Убрать подпорку: " + str(graph[other].title),
				60,"Освободить проход, вернуть пригодную древесину.","Убежище",{"other":other}))

	for target: String in graph[_state.location].connections:
		var distance: float = graph[_state.location].connections[target]
		var load_kg: float = modules.items.mass_kg(_state.items)
		var mobility: float = maxf(0.12, float(modules.physiology.capabilities(_state.body).mobility))
		var speed: float = 1.2 * mobility / (1.0 + load_kg / 35.0 + float(_state.body.fatigue) * 0.6)
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
	out.append(_action("bandage","Перевязать наиболее кровоточащую рану",180,
		"Обработать подходящую рану; одна повязка не закрывает остальные.","Тело"))
	out.append(_action("wash_wound","Промыть загрязнённую рану",120,
		"Осторожно обработать поверхность 100 мл остывшей воды.","Тело"))
	for part: String in Anatomy.PARTS:
		if modules.physiology.anatomy.can_treat(_state.body.anatomy, "bandage", part):
			out.append(_action("bandage:" + part, "Перевязать: " + str(Anatomy.PART_TITLES[part]),
				180, "Зафиксировать повязку на конкретном повреждённом участке.","Тело",{"part":part}))
		if modules.physiology.anatomy.can_treat(_state.body.anatomy, "wash", part):
			out.append(_action("wash_wound:" + part, "Промыть: " + str(Anatomy.PART_TITLES[part]),
				120, "Вода очищает поверхность, но не излечивает глубокую инфекцию.","Тело",{"part":part}))
	out.append(_action("rest","Отдохнуть полчаса",1800,"Сесть, снизить нагрузку. Мир продолжает жить.","Тело"))
	out.append(_action("sleep","Спать два часа",7200,"Сон помогает при приемлемой температуре и воздухе. Опасность прервёт сон.","Тело"))
	out.append(_action("wait","Подождать 10 минут",600,"Дать воде остыть или переждать. Потребности и запасы продолжают меняться.","Мир"))
	out.append(_action("repair_radio","Починить радиоприёмник",1500,"Мастерская, инструмент, провод и деталь. Нужна ещё энергия батареи.","Ремесло"))
	out.append(_action("switch_radio","Выключить радио" if _state.items.electricity.radio_on else "Включить радио",30,"Исправный приёмник расходует заряд; он не работает без питания.","Ремесло"))
	out.append(_action("switch_lamp","Выключить фонарь" if _state.items.electricity.lamp_on else "Включить фонарь",30,"Фонарь даёт свет и расходует батарею.","Вещи"))
	out.append(_action("repair_cart","Отремонтировать тележку",1800,"В мастерской: 1 кг дерева и деталь. Грузоподъёмность станет больше.","Ремесло"))

	# Every object uses the same verbs, force model, geometry and material rules.
	# Unseen targets never enter the public action catalogue.
	if _player_light() >= 0.05:
		for object_id: String in Props.DATA:
			var entry: Dictionary = _state.props.entities[object_id]
			if str(entry.location) != _state.location: continue
			var definition: Dictionary = Props.DATA[object_id]
			var title: String = str(definition.title)
			out.append(_prop_action("prop_inspect:"+object_id,"Осмотреть: "+title,25,
				"Материал, размеры и состояние.","Предметы",{"object_id":object_id},str(definition.alias)))
			if not bool(entry.intact): continue
			if str(entry.placement).begins_with("door:"):
				out.append(_prop_action("prop_unbrace:"+object_id,"Отодвинуть от двери: "+title,150,
					"Освободить дверь, сохранив предмет.","Предметы",{"object_id":object_id},str(definition.alias)))
			else:
				out.append(_prop_action("prop_dismantle:"+object_id,"Разобрать: "+title,600,
					"Материалы и обломки останутся на земле.","Предметы",{"object_id":object_id},str(definition.alias)))
				for other: String in graph[_state.location].connections:
					var distance: float = float(graph[_state.location].connections[other])
					out.append(_prop_action("prop_move:"+object_id+":"+other,"Перетащить "+title+": "+str(graph[other].title),
						maxi(120,ceili(distance/0.35)),"Сопротивление пола, ширина прохода, усталость.","Предметы",
						{"object_id":object_id,"other":other},str(definition.alias)))
					if not modules.zombies.nav.door_for(_state.zombies.doors,_state.location,other).is_empty():
						out.append(_prop_action("prop_brace:"+object_id+":"+other,"Подпереть дверь: "+title,180,
							"Добавить физическое сопротивление закрытой двери.","Предметы",
							{"object_id":object_id,"other":other},str(definition.alias)))
	for item: String in _state.ground.get(_state.location,{}):
		if int(_state.ground[_state.location][item])>0:
			out.append(_action("ground_take:"+item,"Подобрать: "+str(Items.TITLES[item]),45,
				"Переложить одну единицу с земли в снаряжение.","Предметы",{"item":item}))
	for item: String in ["wood","parts","cloth","tool"]:
		if int(_state.items.inventory.get(item,0))>0:
			out.append(_action("ground_drop:"+item,"Оставить: "+str(Items.TITLES[item]),30,
				"Оставить одну единицу здесь, не уничтожая её.","Предметы",{"item":item}))
	return out

func _prop_action(id: String,title: String,seconds: int,description: String,category: String,params: Dictionary,alias: String) -> Dictionary:
	var descriptor: Dictionary = _action(id,title,seconds,description,category,params)
	descriptor["object_alias"] = alias
	return descriptor

func _base(id: String) -> String:
	return id.split(":")[0]

func _params(id: String, args: Dictionary) -> Dictionary:
	var params: Dictionary = args.duplicate(true)
	if id.begins_with("prop_"):
		params["object_id"] = id.get_slice(":",1)
		if id.get_slice_count(":")>2: params["other"] = id.get_slice(":",2)
	elif id.begins_with("ground_"):
		params["item"] = id.get_slice(":",1)
	elif id.begins_with("move:"):
		params["target"] = id.substr(5)
	elif id.begins_with("bandage:"):
		params["part"] = id.substr(8)
	elif id.begins_with("wash_wound:"):
		params["part"] = id.substr(11)
	elif id.begins_with("door_") and ":" in id:
		params["other"] = id.split(":")[1]
	elif ":" in id:
		params["npc_id"] = id.split(":")[1]
	return params

func _validate(id: String, arguments: Dictionary) -> String:
	var args: Dictionary = _params(id, arguments)
	var verb: String = _base(id)
	var inv: Dictionary = _state.items.inventory
	var room: Dictionary = _state.environment.rooms.get(_state.location,{})
	if not _state.action.is_empty(): return "Сначала завершите или прервите текущее действие."
	if not _state.body.alive: return "Персонаж погиб. Можно начать новое выживание."
	if not _state.body.conscious and verb != "wait": return "Вы без сознания. Можно дать времени пройти."
	var functional_block: String = modules.physiology.action_limit(_state.body, verb)
	if not functional_block.is_empty(): return functional_block
	match verb:
		"prop_inspect","prop_move","prop_brace","prop_unbrace","prop_dismantle":
			if _player_light()<0.05: return "Слишком темно, чтобы различить предмет."
			var caps: Dictionary = modules.physiology.capabilities(_state.body)
			return modules.props.can_act(_state.props,str(args.get("object_id","")),verb,_state.location,
				str(args.get("other","")),modules.world.locations(),_state.zombies.doors,
				float(caps.grip),float(caps.mobility),int(inv.tool)>0 and float(_state.items.tool_wear_j)<1000000.0)
		"ground_take","ground_drop":
			var item: String = str(args.get("item",""))
			if not Items.MASS.has(item): return "Неизвестный предмет."
			if verb == "ground_take":
				if int(_state.ground.get(_state.location,{}).get(item,0))<1: return "Такого предмета на земле больше нет."
				return modules.items.validate(_state.items,{"kind":"add_item","item":item,"amount":1})
			return modules.items.validate(_state.items,{"kind":"remove_item","item":item,"amount":1})
		"move":
			var target: String = str(args.get("target",""))
			if not modules.world.locations()[_state.location].connections.has(target):
				return "Нет прямого пути. Сначала выйдите во двор."
			if not modules.zombies.nav.is_open(_state.zombies.doors,_state.location,target):
				return "Путь перекрыт закрытой дверью."
			return ""
		"door_open","door_close","door_brace","door_unbrace":
			var other: String = str(args.get("other",""))
			var graph: Dictionary = modules.world.locations()
			if not graph[_state.location].connections.has(other):
				return "Нет доступного прохода к этой двери."
			var door: Dictionary = modules.zombies.nav.door_for(_state.zombies.doors,_state.location,other)
			if door.is_empty(): return "Здесь нет двери."
			if verb == "door_open":
				if bool(door.open): return "Дверь уже открыта."
				return "Сначала уберите подпорку." if float(door.brace_kg)>0.0 else ""
			if verb == "door_close": return "Дверь уже закрыта." if not bool(door.open) else ""
			if verb == "door_brace":
				if bool(door.open): return "Нужно сначала закрыть дверь."
				if float(door.brace_kg) >= 12.0: return "Дальше подпирать некуда."
				return modules.items.validate(_state.items,{"kind":"remove_item","item":"wood","amount":1})
			if float(door.brace_kg) <= 0.0: return "Подпорки нет."
			var key: String = modules.props.door_key(_state.location,other)
			var loose_wood: int = maxi(0,int(round(float(door.brace_kg)-modules.props.brace_at(_state.props,key))))
			return modules.items.validate(_state.items,{"kind":"add_item","item":"wood","amount":loose_wood}) if loose_wood>0 else ""
		"shove","break_grapple":
			var local: String = modules.zombies.availability(_state.zombies,{"kind":verb,"location":_state.location})
			if local != "": return local
			var body_caps: Dictionary = modules.physiology.capabilities(_state.body)
			return "Руки не слушаются." if float(body_caps.grip) < 0.18 else ""
		"inspect","listen","rest","wait": return ""
		"retreat": return modules.zombies.availability(_state.zombies, {"kind":"retreat","location":_state.location})
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
			if verb == "bandage":
				return "" if modules.physiology.anatomy.can_treat(_state.body.anatomy, "bandage", str(args.get("part",""))) else "Здесь нет открытой раны, которую можно перевязать."
			return modules.world.availability(_state.world,{"kind":"help_nina","npc_id":"nina","location":_state.location})
		"wash_wound":
			if not modules.physiology.anatomy.can_treat(_state.body.anatomy, "wash", str(args.get("part",""))): return "На выбранном участке нет раны для промывания."
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
	var previous_progress: int = int(_state.work_progress.get(_work_key(descriptor.id,_state.location), 0))
	_state.action = {"id":descriptor.id,"title":descriptor.title,
		"elapsed_s":mini(previous_progress, int(descriptor.duration_s) - 1),
		"duration_s":int(descriptor.duration_s), "base_duration_s":int(descriptor.base_duration_s),
		"ability_factor":float(descriptor.ability_factor), "parameters":params,
		"start_location":_state.location}
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
		modules.acoustics.advance(_state.acoustics, float(dt))
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
		body_context.exertion = 0.55 if verb in ["retreat","prop_move","prop_brace","prop_dismantle"] else (0.42 if verb in ["move","gather_wood","hunt","plant","repair_cart"] else (0.1 if verb in ["rest","sleep","wait","dry_clothes","listen"] else 0.22))
		body_context.sleeping = verb in ["sleep","rest"]
		_append_events(modules.physiology.advance(_state.body,dt,body_context))
		_append_events(modules.world.advance(_state.world,dt,{"weather":_state.environment.weather,"rooms":_state.environment.rooms,"hour":fmod(16.0 + 20.0 / 60.0 + float(_state.time_s)/3600.0,24.0)}))

		# Sound sources are physical world events, not a shared enemy-alert flag.
		# The acoustic clock runs in the same fixed-step transaction as the world.
		var graph: Dictionary = modules.world.locations()
		var noise_db: float = _action_noise_db(verb)
		if noise_db > 0.0:
			modules.acoustics.emit(_state.acoustics, graph, _state.location, _action_sound_kind(verb), noise_db, "player")
		if bool(_state.items.electricity.radio_on):
			modules.acoustics.emit(_state.acoustics, graph, _state.location, "radio", 65.0, "player_radio")
		for room_id: String in _state.environment.rooms:
			if bool(_state.environment.rooms[room_id].burning):
				modules.acoustics.emit(_state.acoustics, graph, room_id, "fire", 46.0, "stove_" + room_id)
		var acoustic_environment: Dictionary = _state.environment.duplicate(false)
		acoustic_environment["doors"] = _state.zombies.doors
		var infected_events: Array = modules.zombies.advance(_state.zombies,float(dt),
			{"player_location":_state.location,"graph":graph,"acoustics":_state.acoustics,
			 "acoustic_model":modules.acoustics,"environment":acoustic_environment,
			 "player_light":_player_light(),"player_mobility":float(modules.physiology.capabilities(_state.body).mobility),
			 "temperature_k":float(_state.environment.weather.temp_k)})
		var tactile_contact: bool = false
		for event: Dictionary in infected_events:
			if event.get("type","") == "infected_contact":
				_body("infected_contact",event)
				tactile_contact = true
		_append_events(infected_events)
		modules.props.reconcile_breaches(_state.props,_state.zombies.doors)
		_state.time_s += dt
		action.elapsed_s += dt
		remaining -= dt
		_state.revision += 1
		if tactile_contact and verb not in ["retreat","shove","break_grapple"]:
			if verb in WORK_IDS: _state.work_progress[_work_key(action.id,action.start_location)] = int(action.elapsed_s)
			_log("danger","Чьи-то руки резко цепляются за вас. Действие прервано; прошло реальное время.")
			_state.action = {}
		elif not _state.body.alive or (not _state.body.conscious and verb != "wait"):
			_log("danger","Действие прервано: " + ("вы потеряли сознание." if _state.body.alive else "жизненные функции угасли."))
			_state.action = {}
		elif not modules.physiology.action_limit(_state.body, verb).is_empty():
			if verb in WORK_IDS: _state.work_progress[_work_key(action.id,action.start_location)] = int(action.elapsed_s)
			_log("interrupted", "Работа или движение прерваны: тело не позволяет их продолжать. Потраченное время и травмы сохраняются.")
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

func _player_light() -> float:
	# Same reduced-order illumination as the public perception model.
	# Passing brightness is NOT passing a secret target: AI must still
	# share a location and pass a distance check to see anyone.
	var hour: float = fmod(16.0+20.0/60.0+float(_state.time_s)/3600.0,24.0)
	var light: float = maxf(0.0,sin(PI*(hour-6.0)/12.0))
	light *= 1.0-clampf(float(_state.environment.weather.rain),0.0,1.0)*0.3
	var room: Dictionary = _state.environment.rooms.get(_state.location,{})
	if not room.is_empty():
		light *= 0.35 if bool(room.window_open) else 0.25
		if bool(room.burning): light += 0.37
	if bool(_state.items.electricity.lamp_on): light += 0.63
	return clampf(light,0.0,1.0)

func _action_sound_kind(verb: String) -> String:
	match verb:
		"prop_move","prop_brace","prop_unbrace","prop_dismantle": return "work"
		"ground_drop": return "impact"
		"move", "retreat", "shove", "break_grapple": return "footsteps"
		"gather_wood", "repair_cart", "clean_chimney", "repair_radio": return "work"
		"hunt": return "impact"
		"switch_radio": return "radio"
		"fill_water", "boil_water": return "water"
		"ventilate", "seal_window", "light_fire": return "metal"
		"talk", "trade", "share_food": return "voice"
	return "environment"

func _action_noise_db(verb: String) -> float:
	# Simplified acoustic source-level assumptions at 1 metre; see docs/10.
	match verb:
		"prop_dismantle": return 82.0
		"prop_move","prop_brace": return 76.0
		"prop_unbrace": return 69.0
		"prop_inspect": return 30.0
		"ground_drop": return 55.0
		"sleep", "wait": return 12.0
		"listen": return 18.0
		"inspect": return 38.0
		"move": return 54.0
		"gather_wood", "clean_chimney", "repair_cart": return 76.0
		"hunt": return 85.0
		"switch_radio": return 62.0
		"retreat", "shove", "break_grapple": return 58.0
		"door_open", "door_close", "door_brace", "door_unbrace": return 64.0
	return 48.0

func _append_events(events: Array) -> void:
	for event: Dictionary in events:
		_trace(str(event.get("type","event")),event)

		var event_type: String = str(event.get("type",""))
		var event_location: String = str(event.get("location", ""))
		# Actual NPC activity becomes a spatial sound stimulus. Its identity
		# stays in developer trace, not in the player's sensory journal.
		if event_type in ["npc_arrival", "npc_water"] and modules.world.locations().has(event_location):
			modules.acoustics.emit(_state.acoustics, modules.world.locations(), event_location,
				"footsteps" if event_type == "npc_arrival" else "water",
				57.0 if event_type == "npc_arrival" else 54.0, "npc")
			continue
		if event_type in ["infected_door_hit","infected_door_breach","infected_fall","infected_collapse"]:
			modules.acoustics.emit(_state.acoustics,modules.world.locations(),event_location,
				"impact",98.0 if event_type == "infected_door_breach" else (85.0 if event_type == "infected_door_hit" else 79.0),
				str(event.get("actor_id","world_collision")),float(event.get("offset_m",0.0)))
			continue
		# Heard approach is rendered from actual acoustic propagation, not a raw
		# simulation event which would disclose a silent/unseen infected.
		if str(event.get("type","")) == "infected_approach": continue
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

		"prop_inspect":
			var object_id: String = str(params.get("object_id",""))
			var info: Dictionary = Props.DATA[object_id]
			_log("observation","Осмотрено: "+str(info.title)+". "+str(info.material)+", около %.1f кг." % float(info.mass_kg))
		"prop_move":
			var object_id: String = str(params.get("object_id",""))
			modules.props.apply(_state.props,object_id,verb,str(params.get("other","")))
			_log("action","Перемещено: "+str(Props.DATA[object_id].title))
		"prop_brace":
			var object_id: String = str(params.get("object_id",""))
			var other: String = str(params.get("other",""))
			var weight: float = modules.props.brace_weight(object_id,_state.props.entities[object_id])
			var outcome: Dictionary = modules.zombies.door_action(_state.zombies,modules.world.locations(),_state.location,other,"brace",weight)
			if bool(outcome.get("ok",false)):
				modules.props.apply(_state.props,object_id,verb,other)
				_log("action","Мебель придвинута к двери; сопротивление прохода возросло.")
		"prop_unbrace":
			var object_id: String = str(params.get("object_id",""))
			var entry: Dictionary = _state.props.entities[object_id]
			var key: String = str(entry.placement).substr(5)
			var ends: PackedStringArray = key.split("|")
			var other: String = ends[1] if ends[0]==_state.location else ends[0]
			var weight: float = modules.props.brace_weight(object_id,entry)
			var outcome: Dictionary = modules.zombies.door_action(_state.zombies,modules.world.locations(),_state.location,other,"clear_prop",weight)
			if bool(outcome.get("ok",false)):
				modules.props.apply(_state.props,object_id,verb)
				_log("action","Предмет отодвинут, дверь больше не удерживается им.")
		"prop_dismantle":
			var object_id: String = str(params.get("object_id",""))
			var result: Dictionary = modules.props.apply(_state.props,object_id,verb)
			var stash: Dictionary = _state.ground.get(_state.location,{}).duplicate(true)
			for item: String in result.salvage:
				stash[item] = int(stash.get(item,0))+int(result.salvage[item])
			_state.ground[_state.location] = stash
			_state.items.tool_wear_j += 5000.0
			_log("action","Разобрано: "+str(Props.DATA[object_id].title)+". Детали остались на земле.")
		"ground_take":
			var item: String = str(params.get("item",""))
			_item("add_item",{"item":item,"amount":1})
			_state.ground[_state.location][item] -= 1
			if _state.ground[_state.location][item]==0: _state.ground[_state.location].erase(item)
			_log("action","Подобрано: "+str(Items.TITLES[item]))
		"ground_drop":
			var item: String = str(params.get("item",""))
			_item("remove_item",{"item":item,"amount":1})
			var stash: Dictionary = _state.ground.get(_state.location,{}).duplicate(true)
			stash[item] = int(stash.get(item,0))+1
			_state.ground[_state.location] = stash
			_log("action","Оставлено: "+str(Items.TITLES[item]))
		"listen":
			var hearing_penalty: float = 0.0
			if float(_state.body.blood_kg) < 4.0: hearing_penalty += 8.0
			if float(_state.body.hypoxia_s) > 40.0: hearing_penalty += 9.0
			if float(_state.body.fatigue) > 0.7: hearing_penalty += 4.0
			var heard: Array = modules.acoustics.hear(_state.acoustics, _state.location,
				modules.world.locations(), _state.environment, 23.0 + hearing_penalty, 8.0)
			_log("observation", "Вы прислушиваетесь. " + (str(heard[0].text) if not heard.is_empty() else "Различить определённый источник звука не удаётся."))

		"retreat","shove","break_grapple":
			var caps: Dictionary = modules.physiology.capabilities(_state.body)
			var effort: float = clampf((float(caps.grip)+float(caps.mobility))*0.55,0.0,1.0)
			var outcome: Dictionary = modules.zombies.apply(_state.zombies,{"kind":verb,
				"location":_state.location,"effort":effort})
			if not outcome.get("ok",false):
				_log("danger",str(outcome.get("reason","Не удалось освободиться.")))
			else:
				_log("action","Удаётся оттолкнуть фигуру и получить немного пространства." if verb == "shove"
					else "Вырываетесь из хватки." if verb == "break_grapple" else "Вы отступаете, разрывая дистанцию.")
		"door_open","door_close","door_brace","door_unbrace":
			var other: String = str(params.get("other",""))
			var step_kind: String = verb.substr(5)
			var outcome: Dictionary = modules.zombies.door_action(_state.zombies,
				modules.world.locations(),_state.location,other,step_kind,1.0 if verb == "door_brace" else 0.0)
			if outcome.get("ok",false):
				if verb == "door_brace": _consume("wood",1)
				elif verb == "door_unbrace":
					var key: String = modules.props.door_key(_state.location,other)
					var prop_weight: float = modules.props.brace_at(_state.props,key)
					var wood: int = maxi(0,int(round(float(outcome.get("recovered_kg",0.0))-prop_weight)))
					if wood>0: _item("add_item",{"item":"wood","amount":wood})
					modules.props.release_door(_state.props,key)
				_log("action","Дверь и проход физически изменили состояние.")
			else:
				_log("interrupted",str(outcome.get("reason","Дверь не поддалась.")))
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
			_body("bandage", {"part":str(params.get("part",""))})
		"wash_wound":
			_item("remove_water",{"mass_kg":0.1})
			_body("wash_wound", {"part":str(params.get("part",""))})
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
	_emit_completion_sound(verb)

func _emit_completion_sound(verb: String) -> void:
	# Short impacts when a physical operation actually completes, independent
	# of the quieter repeated sounds produced during its execution.
	var sound: Dictionary = {}
	match verb:
		"ventilate": sound = {"kind":"metal", "db":66.0}
		"door_open", "door_close", "door_brace", "door_unbrace": sound = {"kind":"metal","db":71.0}
		"shove", "break_grapple": sound = {"kind":"impact","db":77.0}
		"add_fuel": sound = {"kind":"impact", "db":68.0}
		"light_fire": sound = {"kind":"fire", "db":51.0}
		"clean_chimney", "repair_radio": sound = {"kind":"metal", "db":74.0}
		"repair_cart": sound = {"kind":"metal", "db":79.0}
		"fill_water": sound = {"kind":"water", "db":56.0}
		"switch_radio": sound = {"kind":"radio", "db":64.0}
		"move": sound = {"kind":"footsteps", "db":58.0}
	if not sound.is_empty():
		modules.acoustics.emit(_state.acoustics, modules.world.locations(), _state.location,
			str(sound.kind), float(sound.db), "player")

func snapshot() -> Dictionary:
	var Observer: Script = load("res://src/application/observer.gd")
	return Observer.new().build(_state,modules)

func debug_snapshot() -> Dictionary:
	return _state.duplicate(true)

func export_state() -> Dictionary:
	return _state.duplicate(true)

func restore_state(data: Dictionary) -> Dictionary:
	var upgraded: Dictionary = data.duplicate(true)
	if not upgraded.has("zombies") and upgraded.has("seed") and (upgraded.seed is int or upgraded.seed is float):
		# Use a String key on insertion: the save validator rejects non-String keys.
		upgraded["zombies"] = modules.zombies.initial_state(int(upgraded.seed))
		upgraded["zombies"]["time_s"] = float(upgraded.get("time_s",0))
	if upgraded.has("zombies") and upgraded.zombies is Dictionary and int(upgraded.zombies.get("schema_version",0)) in [1,2]:
		upgraded["zombies"] = modules.zombies.migrate_state(upgraded.zombies)
	if not upgraded.has("props") and upgraded.has("time_s"):
		upgraded["props"] = modules.props.initial_state()
	if not upgraded.has("acoustics") and upgraded.has("time_s"):
		upgraded["acoustics"] = modules.acoustics.initial_state()
		upgraded["acoustics"]["time_s"] = float(upgraded.get("time_s", 0))

	if upgraded.has("body") and upgraded.body is Dictionary and not upgraded.body.has("anatomy"):
		upgraded.body["anatomy"] = _legacy_anatomy(upgraded.body)
	if upgraded.has("world") and upgraded.world is Dictionary and upgraded.world.get("npcs") is Dictionary:
		for npc_id: String in upgraded.world.npcs:
			var old_body: Dictionary = upgraded.world.npcs[npc_id].get("body", {})
			if not old_body.has("anatomy"): old_body["anatomy"] = _legacy_anatomy(old_body)
	var reason: String = validate_state(upgraded)
	if reason != "": return _result(false,reason)
	_state = upgraded.duplicate(true)
	# Old first-night quest fields remain for save compatibility, but do not govern play.
	_state.goals = []
	_state.won = false
	return _result(true,"Сохранение загружено.")

func _legacy_anatomy(body: Dictionary) -> Dictionary:
	var layer: Dictionary = modules.physiology.anatomy.initial_state(false)
	var old_area: float = float(body.get("wound_m2", 0.0))
	if old_area > 0.0:
		modules.physiology.anatomy.injure(layer, {
			"part":"left_arm",
			"wound_m2":minf(0.2, maxf(0.0, old_area)),
			"bleeding_kg_s":clampf(float(body.get("bleeding_kg_s",0.0)),0.0,0.02),
			"contamination":clampf(float(body.get("infection",0.0)),0.0,1.0)})
		if bool(body.get("bandaged",false)):
			modules.physiology.anatomy.treat(layer, "bandage", "left_arm")
	layer.adrenaline = 0.0
	layer.pain_felt = layer.pain_raw
	return layer

func validate_state(data: Dictionary) -> String:
	if data.get("schema_version",0) != 1 or data.get("build","") != BUILD or data.get("content_hash","") != CONTENT_HASH: return "Несовместимая версия сохранения или контента."
	for key: String in ["seed","time_s","revision","location","body","environment","world","items","zombies","acoustics","action","journal","trace","action_log","work_progress","knowledge","goals","won","consumed","ground","props"]:
		if not data.has(key): return "Сохранение неполное: " + key
	if not _finite_tree(data): return "Сохранение содержит недопустимые численные значения."
	var acoustic_reason: String = modules.acoustics.validate_state(data.acoustics, modules.world.locations())
	if acoustic_reason != "": return acoustic_reason
	var infected_reason: String = modules.zombies.validate_state(data.zombies, modules.world.locations())
	if infected_reason != "": return infected_reason
	var graph: Dictionary = modules.world.locations()
	var prop_issue: String = modules.props.validate_state(data.props,graph,data.zombies.doors)
	if prop_issue!="": return prop_issue
	if not data.location is String or not graph.has(data.location): return "В сохранении неизвестное место."
	for field: String in ["seed","time_s","revision"]:
		if not _whole(data[field]) or float(data[field]) < 0.0 or float(data[field]) > 9007199254740991.0: return "Недопустимое целое поле: " + field
	for pair: Array in [["body",modules.physiology.initial_state()],["environment",modules.environment.initial_state()],["world",modules.world.initial_state()],["items",modules.items.initial_state()]]:
		if not data[pair[0]] is Dictionary or not _same_shape(pair[1],data[pair[0]]): return "Повреждена схема модуля: " + str(pair[0])
	for key: String in ["action","work_progress","knowledge","consumed","ground"]:
		if not data[key] is Dictionary: return "Повреждено поле " + key
	for site: String in data.ground:
		if not graph.has(site) or not data.ground[site] is Dictionary: return "Повреждены предметы на земле."
		for item: String in data.ground[site]:
			if not Items.MASS.has(item) or not _whole(data.ground[site][item]) or int(data.ground[site][item])<0: return "Недопустимые припасы на земле."
	for key: String in ["journal","trace","action_log","goals"]:
		if not data[key] is Array: return "Повреждена очередь " + key
	if not data.won is bool: return "Повреждено состояние целей."
	if data.journal.size() > MAX_JOURNAL or data.trace.size() > MAX_TRACE or data.action_log.size() > 2048: return "Превышен размер журнала."
	if not _nonnegative(data.body) or not _nonnegative(data.items) or not _nonnegative(data.environment) or not _nonnegative(data.world) or not _nonnegative(data.zombies) or not _nonnegative(data.acoustics): return "Отрицательная физическая величина."
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
	var injury_reason: String = modules.physiology.anatomy.validate_state(data.body.anatomy)
	if injury_reason != "": return injury_reason
	for npc_id: String in data.world.npcs:
		injury_reason = modules.physiology.anatomy.validate_state(data.world.npcs[npc_id].body.anatomy)
		if injury_reason != "": return injury_reason
	if not data.action.is_empty():
		var reason: String = _validate_saved_action(data.action,data.location,graph)
		if reason != "": return reason
	for id: String in data.work_progress:
		var job: PackedStringArray = id.split("@")
		if job.size() != 2 or not _base(str(job[0])) in WORK_IDS or (not graph.has(job[1]) and job[1] != "player") or not _whole(data.work_progress[id]) or data.work_progress[id] >= _duration(_base(str(job[0]))) * 4 or data.work_progress[id] < 0: return "Некорректный прогресс работы."
	for entry: Variant in data.journal:
		if not entry is Dictionary or not entry.get("text") is String or not entry.get("type") is String or not _whole(entry.get("time_s")) or not entry.get("location") is String: return "Повреждена запись журнала."
	return ""

func _work_key(id: String, location: String) -> String:
	return id + "@" + ("player" if id == "craft_bandage" else location)

func _duration(id: String) -> int:
	return int({"inspect":60,"listen":20,"retreat":30,"shove":18,"break_grapple":12,"door_open":25,"door_close":25,"door_brace":90,"door_unbrace":60,"clean_chimney":600,"add_fuel":60,"light_fire":180,"extinguish":60,"ventilate":30,"seal_window":900,"boil_water":1200,"cook":900,"dry_clothes":1800,"fill_water":180,"gather_wood":1200,"hunt":3600,"plant":1200,"water_garden":180,"harvest":1200,"talk":300,"share_food":120,"trade":300,"help_nina":600,"drink":30,"eat":300,"craft_bandage":300,"bandage":180,"wash_wound":120,"rest":1800,"sleep":7200,"wait":600,"repair_radio":1500,"switch_radio":30,"switch_lamp":30,"repair_cart":1800,"prop_inspect":25,"prop_move":120,"prop_brace":180,"prop_unbrace":150,"prop_dismantle":600,"ground_take":45,"ground_drop":30}.get(id,0))

func _validate_saved_action(action: Dictionary, location: String, graph: Dictionary) -> String:
	for key: String in ["id","title","elapsed_s","duration_s","parameters","start_location"]:
		if not action.has(key): return "Повреждено незавершённое действие."
	if not action.id is String or not action.title is String or not action.parameters is Dictionary or not action.start_location is String: return "Неверный тип действия."
	if not _whole(action.elapsed_s) or not _whole(action.duration_s) or action.elapsed_s < 0 or action.duration_s <= action.elapsed_s or action.duration_s > 86400: return "Недопустимый прогресс действия."
	if action.start_location != location: return "Работа относится к другому месту."
	var verb: String = _base(action.id)
	if action.has("base_duration_s") or action.has("ability_factor"):
		if not _whole(action.get("base_duration_s")) or not (action.get("ability_factor") is float or action.get("ability_factor") is int):
			return "Повреждены параметры длительности действия."
		var factor: float = float(action.ability_factor)
		if not is_finite(factor) or factor < 0.30 or factor > 1.0: return "Неверный функциональный множитель."
		var base: int = int(action.base_duration_s)
		if base <= 0 or (verb not in ["move","prop_move"] and base != _duration(verb)) or int(action.duration_s) != maxi(base, ceili(float(base) / factor)):
			return "Длительность действия не соответствует сохранённым возможностям тела."
	if verb.begins_with("prop_"):
		var object_id: String = str(action.parameters.get("object_id",""))
		var other: String = str(action.parameters.get("other",""))
		if not Props.DATA.has(object_id) or action.id != verb+":"+object_id+(":"+other if verb in ["prop_move","prop_brace"] else ""): return "Неизвестный предмет действия."
		if verb in ["prop_move","prop_brace"] and not graph[location].connections.has(other): return "Неизвестная цель перемещения."
	elif verb.begins_with("ground_"):
		var item: String = str(action.parameters.get("item",""))
		if not Items.MASS.has(item) or action.id != verb+":"+item: return "Недопустимый предмет."
	elif verb.begins_with("door_"):
		var other: String = str(action.parameters.get("other",""))
		if action.id != verb + ":" + other or not graph[location].connections.has(other):
			return "Несуществующий проход в сохранении."
	elif verb == "move":
		var target: String = str(action.parameters.get("target",""))
		if action.id != "move:" + target or not graph[location].connections.has(target): return "Недопустимый путь действия."
	elif verb in ["talk","trade","share_food"]:
		var npc: String = str(action.parameters.get("npc_id",""))
		if npc not in ["nina","pavel"] or action.id != verb + ":" + npc or (not action.has("base_duration_s") and action.duration_s != _duration(verb)): return "Недопустимая цель действия."
	elif verb in ["bandage", "wash_wound"] and ":" in str(action.id):
		var part: String = str(action.parameters.get("part", ""))
		if part not in Anatomy.PARTS or action.id != verb + ":" + part: return "Неизвестная цель перевязки."
	elif action.id != verb or _duration(verb) <= 0 or (not action.has("base_duration_s") and action.duration_s != _duration(verb)): return "Неизвестное действие в сохранении."
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

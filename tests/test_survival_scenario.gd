extends SceneTree
const Kernel = preload("res://src/core/kernel.gd")
var game = Kernel.new(1998)
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func act(id: String, args: Dictionary = {}) -> void:
	var result: Dictionary = game.command(id,args)
	if not result.ok:
		check(false,"Rejected %s: %s" % [id,result.message])
		return
	var state: Dictionary = game.debug_snapshot()
	var inventory_before: Dictionary = state.items.inventory.duplicate(true)
	check(not game.command(id,args).ok,"Concurrent duplicate action is rejected")
	check(game.debug_snapshot().items.inventory == inventory_before,"Blocked duplicate consumes no items")
	game.step(state.action.duration_s)
	state = game.debug_snapshot()
	print("%s t=%d core=%.2f water=%.2f room=%.1f fuel=%.2f" % [id,state.time_s,state.body.core_k,state.body.water_kg,state.environment.rooms.shelter.temp_k,state.environment.rooms.shelter.fuel_kg])
func _initialize() -> void:
	var boil_count: int = 0
	for id: String in ["craft_bandage","bandage","craft_bandage","clean_chimney","add_fuel","add_fuel","light_fire","seal_window","move:yard","move:well","fill_water","move:yard","move:shelter","boil_water","eat","move:yard","move:clinic","help_nina","move:yard","move:workshop","repair_radio","switch_radio","switch_radio","move:yard","move:forest","gather_wood","gather_wood","gather_wood","move:yard","drink","move:well","fill_water","move:yard","move:shelter","boil_water","add_fuel","add_fuel","add_fuel","add_fuel","add_fuel","eat","dry_clothes"]:
		act(id)
		if id == "boil_water":
			boil_count += 1
			# Keep first visit timing stable; finish treatment after forest/top-up.
			if boil_count == 2:
				for attempt: int in range(4):
					if game.debug_snapshot().items.water.boil_exposure_s >= 60.0:
						break
					act("boil_water")
				check(game.debug_snapshot().items.water.boil_exposure_s >= 60.0,"Repeated physical heating reaches treatment exposure")
	var benchmark_start: int = Time.get_ticks_usec()
	var benchmark_sim_start: int = game.debug_snapshot().time_s
	var guard: int = 0
	while game.debug_snapshot().time_s < 49200 and game.debug_snapshot().body.alive and guard < 80:
		guard += 1
		var state: Dictionary = game.debug_snapshot()
		if state.environment.rooms.shelter.fuel_kg < 0.5 and state.items.inventory.wood > 0:
			act("add_fuel")
		elif float(state.body.water_kg) + float(state.body.gut_water_kg) < 40.5 and state.items.water.volume_kg >= 0.5 and state.items.water.temp_k <= 323.15:
			act("drink")
		elif state.items.inventory.ration > 0 and state.body.energy_j < 14000000.0:
			act("eat")
		else:
			act("rest")
	var end: Dictionary = game.debug_snapshot()
	check(end.body.alive and end.body.conscious,"Alive and conscious at dawn")
	check(end.time_s >= 49200,"Reached dawn")
	check(end.world.npcs.nina.helped,"Helped Nina")
	check(end.items.electricity.radio_repaired,"Repaired radio")
	check(not end.won and end.goals.is_empty(),"No campaign victory or quests at dawn")
	var player_drawn: float = float(end.items.water.volume_kg) + float(end.body.skills.get("drink",0)) * 0.25 - 0.5
	var npc_drawn: float = 0.0
	for npc: Dictionary in end.world.npcs.values():
		npc_drawn += float(npc.water_kg) + float(npc.water_consumed_kg) - 0.35
	check(is_equal_approx(1000.0 - float(end.world.resources.well_water_kg),player_drawn+npc_drawn),"Well transfers conserve player/NPC water")
	check(int(end.items.inventory.ration) + int(end.consumed.get("ration",0)) == 3,"Rations remain finite and accounted")
	check(int(end.items.inventory.cloth) + int(end.consumed.get("cloth",0)) + int(end.consumed.get("bandage",0)) == 3,"Cloth/bandage conversion accounted")
	print("benchmark: simulated_s=%d wall_ms=%.3f actions=%d" % [end.time_s-benchmark_sim_start,(Time.get_ticks_usec()-benchmark_start)/1000.0,guard])
	print("survival scenario: %d failures; final=%s" % [failures,JSON.stringify({"body":end.body,"goals":end.goals})])
	_test_mobile_trade()
	quit(failures)
func _test_mobile_trade() -> void:
	var probe = Kernel.new(1998)
	for id: String in ["move:yard","move:workshop"]:
		check(probe.command(id).ok,"Trade fixture can walk")
		probe.step(probe.debug_snapshot().action.duration_s)
	var before: Dictionary = probe.debug_snapshot()
	check(not probe.command("trade:pavel").ok,"Travelling NPC cannot trade remotely")
	check(probe.debug_snapshot().items.inventory == before.items.inventory,"Absent NPC trade consumes nothing")
	check(probe.command("rest").ok,"Wait locally for NPC return")
	probe.step(1800)
	before = probe.debug_snapshot()
	check(probe.command("trade:pavel").ok,"Present NPC permits trade")
	check(not probe.command("trade:pavel").ok,"Concurrent second trade rejected")
	probe.step(300)
	var after: Dictionary = probe.debug_snapshot()
	check(after.items.inventory.cloth == before.items.inventory.cloth + 2,"Trade transfers cloth once")
	check(after.world.npcs.pavel.cloth == before.world.npcs.pavel.cloth - 2,"Trade subtracts same NPC stock")
	check(after.items.inventory.ration == before.items.inventory.ration - 1,"Trade consumes exactly one ration")
	print("mobile trade checks complete; cumulative failures=%d" % failures)

extends SceneTree
const Kernel = preload("res://src/core/kernel.gd")
var failures: int = 0
func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)
func rejected(k: RefCounted, data: Dictionary, text: String) -> void:
	var before: Dictionary = k.export_state()
	check(not k.restore_state(data).ok, text)
	check(k.export_state() == before, text + " leaves live state unchanged")
	k.restore_state(before)
func _initialize() -> void:
	var k = Kernel.new(1998)
	var initial: Dictionary = k.export_state()
	for field: String in ["build","content_hash","schema_version"]:
		var bad: Dictionary = initial.duplicate(true)
		bad[field] = "foreign" if field != "schema_version" else 2
		rejected(k,bad,"reject incompatible " + field)
	for path: Array in [["body","water_kg"],["body","blood_kg"],["body","energy_j"],["items","electricity","battery_j"],["environment","rooms","shelter","fuel_kg"],["world","resources","well_water_kg"],["world","resources","fauna_kg"],["world","npcs","nina","water_kg"],["world","npcs","nina","travel_s"]]:
		var bad: Dictionary = initial.duplicate(true)
		var at: Dictionary = bad
		for i in range(path.size()-1): at = at[path[i]]
		at[path[-1]] = -1.0
		rejected(k,bad,"reject negative " + "/".join(path))
	for field: String in ["seed","revision"]:
		var bad: Dictionary = initial.duplicate(true)
		bad[field] = 0.5
		rejected(k,bad,"reject fractional " + field)
	var bad_location: Dictionary = initial.duplicate(true)
	bad_location.world.npcs.nina.location = "nowhere"
	rejected(k,bad_location,"reject unknown NPC location")
	for bad_progress: Dictionary in [{"unknown_action":10},{"repair_radio":1500},{"repair_cart":0.5},{"repair_cart":-1}]:
		var bad: Dictionary = initial.duplicate(true)
		bad.work_progress = bad_progress
		rejected(k,bad,"reject malformed persistent work progress " + str(bad_progress))
	var extra_npc: Dictionary = initial.duplicate(true)
	extra_npc.world.npcs.ghost = {}
	rejected(k,extra_npc,"reject unknown malformed NPC")
	var extra_room: Dictionary = initial.duplicate(true)
	extra_room.environment.rooms.yard = {}
	rejected(k,extra_room,"reject unknown malformed room")
	var graph_tamper: Dictionary = initial.duplicate(true)
	graph_tamper.world.locations.yard.connections.forest = 1.0
	rejected(k,graph_tamper,"reject modified canonical graph")
	var unknown_item: Dictionary = initial.duplicate(true)
	unknown_item.items.inventory["injected"] = 999
	rejected(k,unknown_item,"reject unknown inventory id")
	check(k.command("inspect").ok,"valid action fixture")
	var fractional_before: Dictionary = k.export_state()
	check(not k.step(0.5).ok,"fractional time step rejected")
	check(k.export_state() == fractional_before,"fractional time step does not mutate action or simulation")
	var pending: Dictionary = k.export_state()
	k.cancel()
	for patch: Dictionary in [{"id":"bogus"},{"duration_s":0.5},{"elapsed_s":0.5},{"parameters":[]},{"start_location":"nowhere"},{"id":"move:nowhere","parameters":{"target":"nowhere"}}]:
		var bad: Dictionary = pending.duplicate(true)
		bad.action.merge(patch,true)
		rejected(k,bad,"reject malformed pending action " + str(patch))
	for command: String in ["nonsense","move:nowhere","talk:nowhere","trade:__proto__","inspect; rm -rf /","move:yard:extra"]:
		var before: Dictionary = k.export_state()
		check(not k.command(command).ok,"reject invalid command " + command)
		check(k.export_state() == before,"invalid command preserves state " + command)
	var before_drink: Dictionary = k.export_state()
	check(not k.command("drink",{"mass_kg":-1}).ok,"reject negative drink")
	check(k.export_state() == before_drink,"invalid resource request preserves state")
	var transfer = Kernel.new(1998)
	var old: Dictionary = transfer.export_state()
	check(transfer.command("add_fuel").ok,"start wood transfer")
	transfer.step(60)
	var added: Dictionary = transfer.export_state()
	check(old.items.inventory.wood - added.items.inventory.wood == 1 and added.environment.rooms.shelter.fuel_kg - old.environment.rooms.shelter.fuel_kg == 1.0,"wood transferred exactly once")
	check(transfer.command("drink").ok,"start water transfer")
	var drink_start: Dictionary = transfer.export_state()
	transfer.step(30)
	var drank: Dictionary = transfer.export_state()
	check(is_equal_approx(drink_start.items.water.volume_kg - drank.items.water.volume_kg,0.25),"drink removes exact water mass")
	check(is_equal_approx((drank.body.water_kg + drank.body.gut_water_kg + drank.body.water_lost_kg) - (drink_start.body.water_kg + drink_start.body.gut_water_kg + drink_start.body.water_lost_kg),0.25),"drink conserves water including physiology sinks")
	# NPC can leave during a social action; completion must revalidate before transfers.
	var social = Kernel.new(1998)
	var fixture: Dictionary = social.export_state()
	fixture.location = "workshop"
	fixture.world.npcs.pavel.water_kg = 0.35
	check(social.restore_state(fixture).ok,"social fixture restore")
	check(social.command("trade:pavel").ok,"trade starts beside NPC")
	var stock: Dictionary = social.export_state()
	social.step(300)
	var departed: Dictionary = social.export_state()
	check(departed.items.inventory.ration == stock.items.inventory.ration and departed.items.inventory.cloth == stock.items.inventory.cloth and departed.world.npcs.pavel.cloth == stock.world.npcs.pavel.cloth,"departing NPC cancels trade without inventory effects")
	var replay = Kernel.new(1998)
	check(replay.command("rest").ok,"replay starts")
	replay.step(120)
	var save_json: String = JSON.stringify(replay.export_state())
	var loaded = Kernel.new(7)
	var normalized: Dictionary = JSON.parse_string(save_json)
	check(loaded.restore_state(normalized).ok,"JSON mid-action load")
	check(replay.restore_state(normalized).ok,"normalize numeric JSON representation")
	replay.step(1800)
	loaded.step(1800)
	check(replay.export_state() == loaded.export_state(),"deterministic continuation across save JSON")
	print("Validation tests: failures=",failures)
	quit(1 if failures else 0)

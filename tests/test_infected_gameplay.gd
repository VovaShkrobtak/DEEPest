extends SceneTree
## Gameplay integration of door physics, save/load, hands-on combat and no HP.
const Kernel = preload("res://src/core/kernel.gd")
const Body = preload("res://src/domain/physiology.gd")
var errors: Array[String] = []

func _initialize() -> void:
	var k = Kernel.new(1998)
	var start: Dictionary = k.export_state()
	check(_available(k,"door_close:yard"), "Shelter has a real actionable exit door")
	check(k.command("door_close:yard").ok, "Player can close door")
	check(k.step(25).ok and not bool(k.export_state().zombies.doors["shelter|yard"].open), "Closed door persists in WorldState")
	var before_failed_move: Dictionary = k.export_state()
	check(not k.command("move:yard").ok, "Player cannot walk through a closed portal")
	check(k.export_state() == before_failed_move, "Blocked movement never spends time")
	check(k.command("door_brace:yard").ok, "Player can brace a real closed door")
	check(k.step(90).ok, "Brace consumes real action time")
	var braced: Dictionary = k.export_state()
	check(is_equal_approx(float(braced.zombies.doors["shelter|yard"].brace_kg),1.0), "Real barrier records added wood mass")
	check(int(braced.items.inventory.wood) == int(start.items.inventory.wood)-1, "Exactly one physical wood unit consumed")
	check(not k.command("door_open:yard").ok, "Braced door prevents immediate opening")
	var loaded = Kernel.new(1)
	check(loaded.restore_state(JSON.parse_string(JSON.stringify(braced))).ok, "Door and brace survive save/load")
	check(loaded.export_state().zombies.doors == JSON.parse_string(JSON.stringify(braced.zombies.doors)), "Door mechanical history unchanged after restore")
	check(k.command("door_unbrace:yard").ok, "Player can recover intact brace")
	k.step(60)
	check(is_equal_approx(float(k.export_state().zombies.doors["shelter|yard"].brace_kg),0.0), "Portal unbraced")
	check(int(k.export_state().items.inventory.wood) == int(start.items.inventory.wood), "Wood restored once only")
	check(k.command("door_open:yard").ok, "Door can reopen after releasing brace")
	k.step(25)
	check(bool(k.export_state().zombies.doors["shelter|yard"].open), "Door can be traversed again")
	check(k.command("move:yard").ok, "Navigation resumes after opening")
	k.cancel()
	var broken: Dictionary = k.export_state()
	broken.zombies.doors["shelter|yard"].damage_j = -1.0
	var before_corrupt: Dictionary = k.export_state()
	check(not k.restore_state(broken).ok and k.export_state() == before_corrupt, "Impossible barrier damage rejected atomically")
	var fake: Dictionary = k.export_state()
	fake.zombies.agents["infected_99"] = fake.zombies.agents["infected_01"].duplicate(true)
	check(not k.restore_state(fake).ok, "Player cannot forge extra infected population")

	# Contact is tactile, persistent and uses real regional physiology.
	var struggle = Kernel.new(1998)
	var nearby: Dictionary = struggle.export_state()
	nearby.zombies.agents.infected_01.location = "shelter"
	nearby.zombies.agents.infected_01.distance_m = 1.0
	nearby.zombies.agents.infected_01.obstacle_site = "shelter"
	check(struggle.restore_state(nearby).ok, "Existing infected moved in fixture without cloning")
	var original_wound: float = float(struggle.export_state().body.wound_m2)
	check(struggle.command("rest").ok, "Can begin real work with unknown nearby threat")
	struggle.step(10)
	var grapple: Dictionary = struggle.export_state()
	check(grapple.action.is_empty(), "Unexpected tactile grab interrupts work instead of running timer blindly")
	check(float(grapple.body.wound_m2) > original_wound, "Physical contact produces real local injury")
	check(float(grapple.zombies.agents.infected_01.grapple_s) > 0.0, "Holding state lasts across ticks")
	check(_available(struggle,"break_grapple"), "Escape affordance exists during actual hold")
	var escape_order: Dictionary = struggle.command("break_grapple")
	check(escape_order.ok, "Player can attempt escape from physically close body")
	if escape_order.ok:
		struggle.step(12)
		check(is_zero_approx(float(struggle.export_state().zombies.agents.infected_01.grapple_s)), "Struggle releases actual hold")
	check(struggle.export_state().zombies.agents.size() == 3, "Persistent actors never duplicate during contact")
	var feel: String = JSON.stringify(struggle.snapshot())
	check(not feel.contains("infected_01"), "Public description does not expose hidden actor IDs")

	# The underlying walking simulation must respect actual door breaches.
	var breached = Kernel.new(1998)
	var fixture: Dictionary = breached.export_state()
	fixture.zombies.doors["shelter|yard"].open = false
	fixture.zombies.agents.infected_01.location = "yard"
	fixture.zombies.agents.infected_01.distance_m = 0.0
	fixture.zombies.agents.infected_01.obstacle_site = "yard"
	fixture.zombies.agents.infected_01.target_location = "shelter"
	fixture.zombies.agents.infected_01.mode = "investigate"
	fixture.zombies.agents.infected_01.memory_s = 360.0
	fixture.zombies.agents.infected_01.alert_s = 360.0
	check(breached.restore_state(fixture).ok, "Closed-door infected investigation fixture validates")
	check(breached.command("wait").ok, "World can continue while player stays indoors")
	breached.step(240)
	var after_breach: Dictionary = breached.export_state()
	check(bool(after_breach.zombies.doors["shelter|yard"].open), "Infected can physically breach blocked entry over time")
	check(float(after_breach.zombies.doors["shelter|yard"].damage_j) > 0.0, "Door damage permanently recorded")
	check(after_breach.zombies.agents.size() == 3, "Breaching does not spawn replacements")
	print("Infected gameplay integration: ","PASS" if errors.is_empty() else JSON.stringify(errors))
	quit(0 if errors.is_empty() else 1)
func _available(kernel: RefCounted, id: String) -> bool:
	for option: Dictionary in kernel.available_actions():
		if str(option.get("id","")) == id and bool(option.get("enabled",false)): return true
	return false
func check(ok: bool, msg: String) -> void:
	if not ok: errors.append(msg)

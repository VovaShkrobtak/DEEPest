extends SceneTree
## Infected decision loops and physical obstacle/contact regressions.
const Zombies = preload("res://src/domain/zombies.gd")
const Sound = preload("res://src/domain/acoustics.gd")
const World = preload("res://src/domain/world.gd")
const Env = preload("res://src/domain/environment.gd")
var errors: Array[String] = []

func _initialize() -> void:
	var z = Zombies.new()
	var audio = Sound.new()
	var graph: Dictionary = World.new().locations()
	var environment: Dictionary = Env.new().initial_state(1998)
	environment.weather.wind_m_s = 0.0
	environment.weather.rain = 0.0
	var base: Dictionary = z.initial_state(1998)
	var repeated: Dictionary = z.initial_state(1998)
	check(base == repeated and base.agents.size() == 3, "Seeded fixed existing infected population")
	var auditory: Dictionary = base.duplicate(true)
	auditory.agents.infected_01.location = "yard"
	auditory.agents.infected_01.distance_m = 30.0
	var pulse: Dictionary = audio.initial_state()
	audio.emit(pulse,graph,"yard","metal",108.0,"world_gate")
	var context: Dictionary = {"player_location":"clinic","graph":graph,"environment":environment,
		"acoustics":pulse,"acoustic_model":audio}
	z.advance(auditory,10.0,context)
	check(auditory.agents.infected_01.target_location == "yard", "AI investigates emitted sound, not invisible player position")
	check(auditory.agents.infected_01.mode == "investigate", "Heard stimulus enters investigative state")
	pulse.events.clear()
	z.advance(auditory,450.0,context)
	check(auditory.agents.infected_01.target_location == "", "Lost auditory trace eventually abandoned")
	check(auditory.agents.infected_01.mode == "wander", "Search times out without fresh evidence")
	check(auditory.agents.size() == 3, "No respawning on prolonged time advances")

	var visible: Dictionary = base.duplicate(true)
	visible.agents.infected_01.location = "yard"
	visible.agents.infected_01.distance_m = 15.0
	visible.agents.infected_01.obstacle_site = "yard"
	z.advance(visible,10.0,{"graph":graph,"environment":environment,
		"player_location":"yard","player_light":1.0})
	check(visible.agents.infected_01.mode == "pursue" and visible.agents.infected_01.target_location == "yard",
		"Visible person stimulates direct pursuit in same unobstructed coarse place")
	var dark: Dictionary = base.duplicate(true)
	dark.agents.infected_01.location = "yard"
	dark.agents.infected_01.distance_m = 15.0
	dark.agents.infected_01.obstacle_site = "yard"
	z.advance(dark,10.0,{"graph":graph,"environment":environment,
		"player_location":"yard","player_light":0.0})
	check(dark.agents.infected_01.target_location == "", "Darkness prevents omniscient visual acquisition")

	var blocked: Dictionary = base.duplicate(true)
	var traveler: Dictionary = blocked.agents.infected_01
	traveler.location = "yard"
	traveler.distance_m = 0.0
	traveler.obstacle_site = "yard"
	var barrier: Dictionary = z.door_action(blocked,graph,"yard","shelter","close")
	check(barrier.ok, "Visible physical portal is closed")
	var noise: Dictionary = audio.initial_state()
	audio.emit(noise,graph,"shelter","metal",132.0,"player")
	var facing: Dictionary = {"graph":graph,"environment":environment,"acoustic_model":audio,
		"acoustics":noise,"player_location":"clinic","player_light":0.0}
	var impact_events: Array = z.advance(blocked,10.0,facing)
	check(traveler.location == "yard" and not z.nav.is_open(blocked.doors,"yard","shelter"),
		"Closed door blocks pursuit despite valid acoustic target")
	check(impact_events.any(func(e: Dictionary): return str(e.get("type","")) == "infected_door_hit"),
		"Contact with obstacle accumulates physical impact")
	var before_damage: float = float(blocked.doors["shelter|yard"].damage_j)
	check(before_damage > 0.0, "Door retains energy damage across ticks")
	var after_barrier_events: Array = z.advance(blocked,250.0,facing)
	check(z.nav.is_open(blocked.doors,"yard","shelter"), "Repeated real impacts breach finite door")
	check(after_barrier_events.any(func(e: Dictionary): return str(e.get("type","")) == "infected_traverse" and str(e.get("location","")) == "shelter"),
		"Passage traversed only after physically breaching door (event persists even if search moves on)")

	var stumble: Dictionary = base.duplicate(true)
	stumble.agents.infected_01.location = "yard"
	stumble.agents.infected_01.distance_m = 10.0
	stumble.agents.infected_01.rng_state = 1
	stumble.agents.infected_01.stability = 0.0
	var fall_events: Array = z.advance(stumble,10.0,{"graph":graph,"environment":environment,"player_location":"clinic"})
	check(fall_events.any(func(e: Dictionary): return str(e.get("type","")) == "infected_fall"), "Debris causes deterministic seeded fall")
	check(stumble.agents.infected_01.posture == "fallen", "Incapacitated agent remains on ground")
	var injured_limb: float = float(stumble.agents.infected_01.leg_integrity)
	z.advance(stumble,70.0,{"graph":graph,"environment":environment,"player_location":"clinic"})
	check(stumble.agents.infected_01.posture != "fallen", "Fall recovery consumes actual simulated time")
	check(float(stumble.agents.infected_01.leg_integrity) <= injured_limb, "Fall does not heal tissue")

	var grapple: Dictionary = base.duplicate(true)
	grapple.agents.infected_01.location = "shelter"
	grapple.agents.infected_01.distance_m = 1.0
	var first_contact: Array = z.advance(grapple,10.0,{"graph":graph,"environment":environment,"player_location":"shelter"})
	check(first_contact.any(func(e: Dictionary): return str(e.get("type","")) == "infected_contact"),
		"True proximity causes physical contact")
	check(float(grapple.agents.infected_01.grapple_s) > 0.0, "Contact establishes persistent mechanical hold")
	var failed: Dictionary = z.apply(grapple,{"kind":"retreat","location":"shelter","effort":0.1})
	check(not failed.ok and failed.get("held",false), "Low strength cannot magically retreat through grip")
	var released: Dictionary = z.apply(grapple,{"kind":"break_grapple","location":"shelter","effort":1.0})
	check(released.ok and is_zero_approx(float(grapple.agents.infected_01.grapple_s)), "Struggle can release grip")
	var shove_fixture: Dictionary = base.duplicate(true)
	shove_fixture.agents.infected_01.location = "shelter"
	shove_fixture.agents.infected_01.distance_m = 1.0
	shove_fixture.agents.infected_01.stability = 0.42
	var shove: Dictionary = z.apply(shove_fixture,{"kind":"shove","location":"shelter","effort":1.0})
	check(shove.ok and shove.fell and shove_fixture.agents.infected_01.posture == "fallen",
		"Physical impulse can unbalance an already unstable body")

	var legacy: Dictionary = base.duplicate(true)
	legacy.schema_version = 1
	legacy.erase("doors")
	for id: String in legacy.agents:
		var defaults: Dictionary = z._new_agent(1998,0)
		for key: String in defaults:
			if key not in ["location","distance_m","target_location","alert_s","contact_cooldown_s",
				"leg_integrity","tissue_integrity","hearing_threshold_db","close_reported"]:
				legacy.agents[id].erase(key)
	var migrated: Dictionary = z.migrate_state(legacy)
	check(migrated.schema_version == 2 and z.validate_state(migrated,graph).is_empty(),
		"Old agent identity and positions migrate to new behavior schema")
	var corrupt: Dictionary = migrated.duplicate(true)
	corrupt.agents.infected_01.posture = "flying"
	check(not z.validate_state(corrupt,graph).is_empty(), "Invalid posture rejected")
	var bad_door: Dictionary = migrated.duplicate(true)
	bad_door.doors["shelter|yard"].brace_kg = -5.0
	check(not z.validate_state(bad_door,graph).is_empty(), "Tampered barriers rejected")
	print("Infected behavior 2.0: ","PASS" if errors.is_empty() else JSON.stringify(errors))
	quit(0 if errors.is_empty() else 1)
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label)

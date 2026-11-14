extends SceneTree
const ZombieModel = preload("res://src/domain/zombies.gd")
const Kernel = preload("res://src/core/kernel.gd")
const World = preload("res://src/domain/world.gd")
const Acoustics = preload("res://src/domain/acoustics.gd")
const EnvModel = preload("res://src/domain/environment.gd")
var failures: int = 0

func check(value: bool, title: String) -> void:
	if not value:
		failures += 1
		push_error(title)

func _initialize() -> void:
	var model = ZombieModel.new()
	var a: Dictionary = model.initial_state(1998)
	var b: Dictionary = model.initial_state(1998)
	check(a == b, "same seed fixes initial infected state")
	check(a.agents.size() == 3, "finite, persistent infected population")
	var graph: Dictionary = World.new().locations()
	var acoustic_model = Acoustics.new()
	var environment: Dictionary = EnvModel.new().initial_state(1998)
	var quiet: Dictionary = a.duplicate(true)
	var muted: Dictionary = acoustic_model.initial_state()
	model.advance(quiet, 60.0, {"player_location":"forest","graph":graph,
		"acoustics":muted,"acoustic_model":acoustic_model,"environment":environment})
	var loud: Dictionary = a.duplicate(true)
	var stimulus: Dictionary = acoustic_model.initial_state()
	check(acoustic_model.emit(stimulus, graph, "forest", "impact", 105.0, "player"), "player generates physical sound")
	model.advance(loud, 60.0, {"player_location":"forest","graph":graph,
		"acoustics":stimulus,"acoustic_model":acoustic_model,"environment":environment})
	check(loud.agents.infected_01.distance_m < quiet.agents.infected_01.distance_m, "sound level attracts without omniscient pursuit")
	check(loud.agents.infected_01.target_location == "forest" and quiet.agents.infected_01.target_location == "", "target inferred from source sound, never player coordinate alone")
	check(not model.observe(a,"shelter").warnings.size() > 0, "distant infected unseen")
	var contact: Dictionary = model.initial_state(4)
	contact.agents.infected_01.location = "shelter"
	contact.agents.infected_01.distance_m = 1.0
	var ev: Array = model.advance(contact, 10.0, {"player_location":"shelter","graph":graph,"noise_db":0.0})
	check(ev.size() > 0 and ev.back().type == "infected_contact", "physical contact emits a single trauma event")
	check(model.advance(contact, 10.0, {"player_location":"shelter","graph":graph,"noise_db":0.0}).is_empty(), "contact cooldown prevents per-frame injury")
	check(model.availability(contact, {"kind":"retreat","location":"shelter"}).is_empty(), "retreat possible when infected close")
	model.apply(contact, {"kind":"retreat","location":"shelter"})
	check(contact.agents.infected_01.distance_m > 1.5, "retreat actually creates distance")
	check(model.validate_state(contact,graph).is_empty(), "infected state valid after movement")
	var invalid: Dictionary = contact.duplicate(true)
	invalid.agents.infected_01.distance_m = -5.0
	check(not model.validate_state(invalid,graph).is_empty(), "negative distance rejected")
	var k = Kernel.new(1998)
	var legacy: Dictionary = k.export_state()
	legacy.erase("zombies")
	var migration: Dictionary = k.restore_state(legacy)
	check(migration.ok, "legacy first-night save gains infected population: " + str(migration.get("message","")))
	check(k.debug_snapshot().zombies.agents.size() == 3, "migration retains infected entities")
	var fixture: Dictionary = k.export_state()
	fixture.zombies.agents.infected_01.location = fixture.location
	fixture.zombies.agents.infected_01.distance_m = 1.0
	check(k.restore_state(fixture).ok, "player contact fixture accepted by save validation")
	var blood: float = k.debug_snapshot().body.bleeding_kg_s
	check(k.command("wait").ok, "waiting under threat starts")
	k.step(10)
	check(k.debug_snapshot().body.bleeding_kg_s > blood, "contact wounds body via physiology API")
	check(k.snapshot().threat_warnings.size() > 0, "observer exposes nearby threat without exact stats")
	print("Zombie model: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(1 if failures else 0)

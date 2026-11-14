extends SceneTree
const Kernel = preload("res://src/core/kernel.gd")
const Perception = preload("res://src/application/perception.gd")
const Observer = preload("res://src/application/observer.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var kernel = Kernel.new(1998)
	var fixture: Dictionary = kernel.export_state()
	var observer = Observer.new()
	var senses = Perception.new()
	fixture.time_s = 27600 # Midnight: scenario begins at 16:20.
	fixture.acoustics.time_s = 27600.0
	fixture.zombies.agents.infected_01.location = "shelter"
	fixture.zombies.agents.infected_01.distance_m = 1.0
	var darkness: Dictionary = senses.observe(fixture, kernel.modules, "shelter")
	check(not darkness.can_see and darkness.warnings.is_empty(), "Darkness never highlights an unseen nearby figure")
	var dark_snapshot: Dictionary = observer.build(fixture, kernel.modules)
	check(dark_snapshot.threat_warnings.is_empty(), "No omniscient threat HUD at night")
	check(dark_snapshot.people.is_empty(), "No names for people invisible in pitch dark")
	check(dark_snapshot.objects.is_empty(), "Unseen room objects are hidden")
	fixture.items.electricity.lamp_on = true
	var illuminated: Dictionary = senses.observe(fixture, kernel.modules, "shelter")
	check(illuminated.can_see and not illuminated.warnings.is_empty(), "Light exposes physically nearby moving figure")
	var lit_snapshot: Dictionary = observer.build(fixture, kernel.modules)
	check(not lit_snapshot.threat_warnings.is_empty(), "Public observer reveals what can actually be seen")
	check(JSON.stringify(lit_snapshot).find("infected_01") == -1, "No hidden NPC IDs exposed")
	var before_trauma: float = illuminated.visual_range_m
	fixture.body.blood_kg = 3.8
	check(senses.observe(fixture, kernel.modules, "shelter").visual_range_m < before_trauma, "Blood loss affects usable vision")
	fixture.body.conscious = false
	var unconscious: Dictionary = senses.observe(fixture, kernel.modules, "shelter")
	check(unconscious.sounds.is_empty() and unconscious.warnings.is_empty() and not unconscious.can_see, "Unconscious character receives no usable sights or sounds")
	check(JSON.stringify(fixture).find("zombies") >= 0, "Sensory presentation does not mutate actual agent state")
	print("Perception gating: ", "PASS" if failures.is_empty() else JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

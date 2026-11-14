extends SceneTree
## Source identity remains hidden, sound is physical, and memory survives saves.
const Kernel = preload("res://src/core/kernel.gd")
const Sound = preload("res://src/domain/acoustics.gd")
const World = preload("res://src/domain/world.gd")
const EnvironmentModel = preload("res://src/domain/environment.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var kernel = Kernel.new(1998)
	var fixture: Dictionary = kernel.export_state()
	# A person arrives in the same room at night. Player hears the footsteps,
	# but lack of illumination must not reveal their name or face.
	fixture.time_s = 27600
	fixture.acoustics.time_s = 27600.0
	fixture.world.npcs.pavel.location = "yard"
	fixture.world.npcs.pavel.destination = "shelter"
	fixture.world.npcs.pavel.travel_s = 60.0
	fixture.world.npcs.pavel.water_kg = 2.0
	check(kernel.restore_state(fixture).ok, "Midnight NPC fixture restores")
	check(kernel.command("inspect").ok, "Night inspection starts")
	check(kernel.step(60).ok, "World advances during inspection")
	var seen: Dictionary = kernel.snapshot()
	check(seen.people.is_empty(), "Unseen arrival does not reveal NPC identity")
	check(not seen.hearing.is_empty(), "Arrival emits spatial hearing cue")
	var public_text: String = JSON.stringify(seen.hearing)
	check(public_text.contains("шаги"), "Acoustic text reports footsteps")
	check(not public_text.contains("Павел") and not public_text.contains("pavel"), "Footstep cues contain no private NPC identity")
	var journal: String = JSON.stringify(seen.journal)
	check(not journal.contains("Павел приходит"), "Raw simulation arrival does not leak into public journal")
	var before_save: Dictionary = kernel.export_state()
	var transferred = Kernel.new(2)
	check(transferred.restore_state(JSON.parse_string(JSON.stringify(before_save))).ok, "Recent acoustic events round-trip via JSON")
	check(JSON.stringify(transferred.snapshot().hearing) == JSON.stringify(seen.hearing), "Restored sound perception is deterministic")

	var model = Sound.new()
	var graph: Dictionary = World.new().locations()
	var environment: Dictionary = EnvironmentModel.new().initial_state()
	environment.weather.wind_m_s = 0.0
	environment.weather.rain = 1.0
	var sound_state: Dictionary = model.initial_state()
	model.emit(sound_state, graph, "yard", "metal", 48.0, "world")
	var event: Dictionary = sound_state.events[0]
	check(not model.can_hear(event, "yard", 0.0, 23.0, graph, environment, 8.0), "Focused listening cannot magically beat physical rain masking")
	print("Auditory narrative integration: ", "PASS" if failures.is_empty() else JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

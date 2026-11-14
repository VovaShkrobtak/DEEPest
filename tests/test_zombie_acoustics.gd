extends SceneTree
const Zombies = preload("res://src/domain/zombies.gd")
const Acoustics = preload("res://src/domain/acoustics.gd")
const EnvironmentModel = preload("res://src/domain/environment.gd")
const WorldModel = preload("res://src/domain/world.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var zombies = Zombies.new()
	var sounds = Acoustics.new()
	var environment: Dictionary = EnvironmentModel.new().initial_state(1998)
	environment.weather.wind_m_s = 0.0
	environment.weather.rain = 0.0
	var graph: Dictionary = WorldModel.new().locations()
	var original: Dictionary = zombies.initial_state(13)
	original.agents.infected_01.location = "yard"
	original.agents.infected_01.distance_m = 10.0
	original.agents.infected_01.hearing_threshold_db = 38.0
	var quiet: Dictionary = original.duplicate(true)
	zombies.advance(quiet, 10.0, {"player_location":"shelter", "graph":graph, "environment":environment,
		"acoustic_model":sounds, "acoustics":sounds.initial_state()})
	check(quiet.agents.infected_01.target_location == "", "Enemy never knows player position from context alone")
	var closed: Dictionary = original.duplicate(true)
	var pulse: Dictionary = sounds.initial_state()
	check(sounds.emit(pulse, graph, "shelter", "work", 78.0, "player"), "Physical source exists indoors")
	zombies.advance(closed, 10.0, {"player_location":"shelter", "graph":graph, "environment":environment,
		"acoustic_model":sounds, "acoustics":pulse})
	check(closed.agents.infected_01.target_location == "", "Closed-window path muffles 78 dB source below threshold")
	var opened: Dictionary = original.duplicate(true)
	var open_pulse: Dictionary = sounds.initial_state()
	sounds.emit(open_pulse, graph, "shelter", "work", 78.0, "player")
	environment.rooms.shelter.window_open = true
	zombies.advance(opened, 10.0, {"player_location":"shelter", "graph":graph, "environment":environment,
		"acoustic_model":sounds, "acoustics":open_pulse})
	check(opened.agents.infected_01.target_location == "shelter", "Opening window permits acoustic target acquisition")
	var wet: Dictionary = original.duplicate(true)
	var wet_pulse: Dictionary = sounds.initial_state()
	sounds.emit(wet_pulse, graph, "shelter", "work", 75.0, "player")
	environment.weather.rain = 1.0
	zombies.advance(wet, 10.0, {"player_location":"shelter", "graph":graph, "environment":environment,
		"acoustic_model":sounds, "acoustics":wet_pulse})
	check(wet.agents.infected_01.target_location == "", "Rain masks the same otherwise-audible source")
	print("Infected acoustic hearing: ", "PASS" if failures.is_empty() else JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

extends SceneTree
const Zombies = preload("res://src/domain/zombies.gd")
const Anatomy = preload("res://src/domain/anatomy.gd")
const Sound = preload("res://src/domain/acoustics.gd")
const World = preload("res://src/domain/world.gd")
const EnvironmentModel = preload("res://src/domain/environment.gd")
const Kernel = preload("res://src/core/kernel.gd")
var errors: Array[String] = []

func _initialize() -> void:
	var m = Zombies.new()
	var anatomy = Anatomy.new()
	var graph: Dictionary = World.new().locations()
	var weather: Dictionary = EnvironmentModel.new().initial_state()
	weather.weather.rain = 0.0
	var base: Dictionary = m.initial_state(1998)
	var fall: Dictionary = base.duplicate(true)
	var agent: Dictionary = fall.agents.infected_01
	agent.location = "yard"
	agent.distance_m = 10.0
	agent.rng_state = 1
	agent.stability = 0.0
	var pristine_leg: Dictionary = agent.anatomy.duplicate(true)
	var original_blood: float = float(agent.blood_kg)
	m.advance(fall,10.0,{"graph":graph,"environment":weather,"player_location":"clinic"})
	var left_wounds: int = int(agent.anatomy.parts.left_leg.wounds.size())
	var right_wounds: int = int(agent.anatomy.parts.right_leg.wounds.size())
	check(left_wounds+right_wounds == 1, "Fall applies wound to ONE physical limb rather than generic HP")
	var injured_leg: String = "left_leg" if left_wounds > 0 else "right_leg"
	check(float(agent.anatomy.parts[injured_leg].tissues.bone) < float(pristine_leg.parts[injured_leg].tissues.bone),
		"Landing impact damages specific bone")
	check(float(agent.anatomy.parts[injured_leg].tissues.muscle) < 1.0,
		"Landing impact damages real muscle")
	m.advance(fall,60.0,{"graph":graph,"environment":weather,"player_location":"clinic"})
	check(float(agent.blood_kg) < original_blood and float(agent.blood_loss_kg) > 0.0,
		"Open fall wound reduces circulating blood by conserved mass")
	check(agent.anatomy.parts[injured_leg].wounds[0].infection >= 0.0, "Local wound retains contamination/infection evolution")
	check(m.validate_state(fall,graph).is_empty(), "Regional injury persists in valid infected save")

	var eyes: Dictionary = base.duplicate(true)
	var blind: Dictionary = eyes.agents.infected_01
	blind.location = "yard"
	blind.distance_m = 8.0
	blind.obstacle_site = "yard"
	anatomy.injure_sense(blind.anatomy,"left_eye",1.0)
	anatomy.injure_sense(blind.anatomy,"right_eye",1.0)
	m.advance(eyes,10.0,{"graph":graph,"environment":weather,"player_location":"yard","player_light":1.0})
	check(str(blind.target_location) == "", "Two damaged eyes prevent visual tracking even at noon")
	var ears: Dictionary = base.duplicate(true)
	var deaf: Dictionary = ears.agents.infected_01
	deaf.location = "yard"
	deaf.distance_m = 8.0
	deaf.obstacle_site = "yard"
	anatomy.injure_sense(deaf.anatomy,"left_ear",1.0)
	anatomy.injure_sense(deaf.anatomy,"right_ear",1.0)
	var audio = Sound.new()
	var pulse: Dictionary = audio.initial_state()
	audio.emit(pulse,graph,"yard","metal",100.0,"player")
	m.advance(ears,10.0,{"graph":graph,"environment":weather,
		"player_location":"clinic","player_light":0.0,"acoustics":pulse,"acoustic_model":audio})
	check(str(deaf.target_location) == "", "Two damaged ears prevent audible stimulus acquisition")
	var normal: Dictionary = base.duplicate(true)
	normal.agents.infected_01.location = "yard"
	normal.agents.infected_01.distance_m = 8.0
	m.advance(normal,10.0,{"graph":graph,"environment":weather,
		"player_location":"clinic","player_light":0.0,"acoustics":pulse,"acoustic_model":audio})
	check(str(normal.agents.infected_01.target_location) == "yard", "Functional ears detect identical physical event")

	var corpse: Dictionary = base.duplicate(true)
	corpse.agents.infected_01.location = "shelter"
	corpse.agents.infected_01.distance_m = 0.7
	corpse.agents.infected_01.blood_kg = 1.9
	var before_contacts: int = int(corpse.contacts)
	m.advance(corpse,40.0,{"graph":graph,"environment":weather,"player_location":"shelter"})
	check(not bool(corpse.agents.infected_01.alive), "Circulatory collapse creates persistent nonmoving body")
	check(int(corpse.contacts) == before_contacts, "Corpse cannot grapple or injure living player")
	check(corpse.agents.size() == 3, "Deaths do not trigger zombie respawn")
	check(m.validate_state(corpse,graph).is_empty(), "Corpse remains valid saved entity")

	var old: Dictionary = base.duplicate(true)
	old.schema_version = 2
	for id: String in old.agents:
		for field: String in ["anatomy","blood_kg","blood_loss_kg","mass_kg","alive"]:
			old.agents[id].erase(field)
	var upgraded: Dictionary = m.migrate_state(old)
	check(upgraded.schema_version == 3 and m.validate_state(upgraded,graph).is_empty(),
		"V2 infected save migrates to localized-tissue model without new actors")
	var real = Kernel.new(1998)
	var legacy: Dictionary = real.export_state()
	legacy.zombies = old
	check(real.restore_state(legacy).ok, "Real kernel migrates V2 infected save")
	check(real.export_state().zombies.agents.size() == 3, "All original IDs survive upgrade")
	var roundtrip = Kernel.new(1998)
	check(roundtrip.restore_state(JSON.parse_string(JSON.stringify(real.export_state()))).ok,
		"V3 infected anatomy and blood survive JSON save roundtrip")
	print("Infected anatomy and senses: ","PASS" if errors.is_empty() else JSON.stringify(errors))
	quit(0 if errors.is_empty() else 1)
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label)

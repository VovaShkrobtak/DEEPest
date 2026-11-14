extends SceneTree
## Body capabilities constrain kernel commands, save state and observable senses.
const Kernel = preload("res://src/core/kernel.gd")
const Body = preload("res://src/domain/physiology.gd")
const Perception = preload("res://src/application/perception.gd")
const Anatomy = preload("res://src/domain/anatomy.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var model = Body.new()
	var normal = Kernel.new(1998)
	var fast_movement: int = _duration(normal, "move:yard")
	var injured = Kernel.new(1998)
	var case: Dictionary = injured.export_state()
	model.apply(case.body, {"kind":"trauma", "part":"left_leg",
		"tissue_damage":{"bone":0.70,"muscle":0.3}, "wound_m2":0.0004,
		"bleeding_kg_s":0.00001, "contamination":0.25})
	check(injured.restore_state(case).ok, "Localized leg trauma can be restored")
	check(_duration(injured, "move:yard") > fast_movement, "Injured leg slows actual travel time")
	check(injured.command("move:yard").ok, "A painful but usable leg still permits travel")
	check(int(injured.export_state().action.duration_s) > fast_movement, "Real action duration uses locomotor deficit")
	injured.cancel()
	var immobile = Kernel.new(1998)
	var disabled: Dictionary = immobile.export_state()
	for part: String in ["left_leg", "right_leg"]:
		model.apply(disabled.body, {"kind":"trauma","part":part,
			"tissue_damage":{"bone":1.0,"muscle":0.9,"nerve":1.0}})
	check(immobile.restore_state(disabled).ok, "Bilateral nonfunctional legs validate as injured body")
	var before: Dictionary = immobile.export_state()
	check(not immobile.command("move:yard").ok, "Movement denied by physiological locomotor failure")
	check(not immobile.command("retreat").ok, "Retreat cannot bypass locomotor failure")
	check(immobile.export_state() == before, "Rejected motion never advances time or mutates resources")
	var worker = Kernel.new(1998)
	check(worker.command("craft_bandage").ok, "Craft starts with functional hands")
	check(worker.step(40).ok, "Partially completed work advances through time")
	var work_fixture: Dictionary = worker.export_state()
	var old_cloth: int = int(work_fixture.items.inventory.cloth)
	for part: String in ["left_arm","right_arm"]:
		model.apply(work_fixture.body, {"kind":"trauma","part":part,
			"tissue_damage":{"nerve":0.96,"bone":0.75,"muscle":0.85}})
	check(worker.restore_state(work_fixture).ok, "Mid-work upper limb injury persists")
	check(worker.step(10).ok, "Action step handles newly incapacitated hands")
	var stopped: Dictionary = worker.export_state()
	check(stopped.action.is_empty() and stopped.work_progress.has("craft_bandage@player"),
		"Precision work interrupts and retains elapsed real work")
	check(int(stopped.items.inventory.cloth) == old_cloth, "No craft reward or consumed item on interruption")
	check(not worker.command("craft_bandage").ok, "Disabled hands prevent starting precision craft")
	var treated = Kernel.new(1998)
	var wounds: Dictionary = treated.export_state()
	wounds.items.inventory.bandage = 2
	model.apply(wounds.body, {"kind":"trauma","part":"right_leg",
		"wound_m2":0.0005,"bleeding_kg_s":0.00004,
		"contamination":0.6, "tissue_damage":{"skin":0.08}})
	check(treated.restore_state(wounds).ok, "Additional local wound can be saved")
	check(treated.command("bandage:right_leg").ok, "Player can target injured right leg")
	check(treated.step(int(treated.export_state().action.duration_s)).ok, "Targeted field dressing finishes")
	var after_dressing: Dictionary = treated.export_state()
	check(bool(after_dressing.body.anatomy.parts.right_leg.wounds[0].bandaged), "Right leg wound receives bandage")
	check(not bool(after_dressing.body.anatomy.parts.left_arm.wounds[0].bandaged), "Old left-arm wound stays undressed")
	check(after_dressing.body.anatomy.parts.right_leg.tissues.skin < 1.0, "Bandage does not restore torn skin")
	check(int(after_dressing.items.inventory.bandage) == 1, "One actual bandage consumed")
	var water: Dictionary = after_dressing.duplicate(true)
	water.items.water.boil_exposure_s = 60.0
	check(treated.restore_state(water).ok, "Clean-water setup restored")
	var initial_contamination: float = float(water.body.anatomy.parts.right_leg.wounds[0].contamination)
	var left_contamination: float = float(water.body.anatomy.parts.left_arm.wounds[0].contamination)
	check(treated.command("wash_wound:right_leg").ok, "Can wash selected wound")
	check(treated.step(int(treated.export_state().action.duration_s)).ok, "Washing is a real-time action")
	var washed: Dictionary = treated.export_state()
	check(float(washed.body.anatomy.parts.right_leg.wounds[0].contamination) < initial_contamination,
		"Only targeted surface contamination decreases")
	check(is_equal_approx(float(washed.body.anatomy.parts.left_arm.wounds[0].contamination), left_contamination),
		"Untargeted older wound retains surface contamination")
	check(not treated.command("bandage:no_such_limb").ok, "Forged target never starts action")
	var bad: Dictionary = treated.export_state()
	bad.body.anatomy.parts.right_leg.tissues.nerve = 2.0
	var valid: Dictionary = treated.export_state()
	check(not treated.restore_state(bad).ok and treated.export_state() == valid,
		"Invalid tissue integrity rejected atomically")
	var ancient = Kernel.new(1998)
	var legacy: Dictionary = ancient.export_state()
	legacy.body.erase("anatomy")
	for id: String in legacy.world.npcs:
		legacy.world.npcs[id].body.erase("anatomy")
	check(ancient.restore_state(legacy).ok, "Legacy save migrates player and NPC regional tissue states")
	check(ancient.export_state().body.anatomy.parts.left_arm.wounds.size() == 1,
		"Legacy injury remains local instead of vanishing")
	var sensory = Kernel.new(1998)
	var sensory_fixture: Dictionary = sensory.export_state()
	sensory_fixture.time_s = 18000
	sensory_fixture.acoustics.time_s = 18000.0
	model.apply(sensory_fixture.body, {"kind":"sensory_injury","organ":"left_eye","damage":1.0})
	model.apply(sensory_fixture.body, {"kind":"sensory_injury","organ":"right_eye","damage":1.0})
	model.apply(sensory_fixture.body, {"kind":"sensory_injury","organ":"left_ear","damage":1.0})
	model.apply(sensory_fixture.body, {"kind":"sensory_injury","organ":"right_ear","damage":1.0})
	check(sensory.restore_state(sensory_fixture).ok, "Blindness/deafness persist in validated save")
	var sensory_result: Dictionary = Perception.new().observe(sensory.export_state(), sensory.modules, "shelter")
	check(not sensory_result.can_see, "Bilateral eye trauma makes daylight unusable for vision")
	check(not sensory_result.can_hear, "Bilateral ear trauma prevents usable hearing")
	check(sensory_result.visible.is_empty(), "No unseen enemies leaked after blindness")
	print("Physiological action integration: ", "PASS" if failures.is_empty() else JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

func _duration(kernel: RefCounted, id: String) -> int:
	for action: Dictionary in kernel.available_actions():
		if action.id == id: return int(action.duration_s)
	return -1
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

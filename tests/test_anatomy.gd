extends SceneTree
const Anatomy = preload("res://src/domain/anatomy.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var m = Anatomy.new()
	var body: Dictionary = m.initial_state()
	check(m.validate_state(body).is_empty(), "Default anatomical state validates")
	check(body.parts.size() == 7 and body.senses.size() == 4, "Separate anatomical regions and organs")
	check(body.parts.left_arm.wounds.size() == 1, "Old starting injury has a local arm location")
	var before: float = m.capabilities(body, 5.0, 0.0).mobility
	check(m.injure(body, {"part":"left_leg", "tissue_damage":{"bone":0.9,"muscle":0.5,"nerve":0.2}, "wound_m2":0.0007, "bleeding_kg_s":0.00002, "contamination":0.4}), "Leg injury applied locally")
	check(m.capabilities(body, 5.0, 0.0).mobility < before * 0.6, "Leg tissue damage changes movement capability")
	check(m.capabilities(body, 5.0, 0.0).grip > 0.8, "Leg injury does not destroy hand functionality")
	check(m.injure(body, {"part":"right_arm", "tissue_damage":{"nerve":0.8,"muscle":0.5}}), "Nerve trauma in right arm")
	check(m.capabilities(body, 5.0, 0.0).precision < 0.6, "Fine motor depends on functional nerves in both hands")
	check(m.injure_sense(body, "left_eye", 1.0), "Eye damaged independently")
	check(m.capabilities(body, 5.0, 0.0).vision < 0.7, "Damage reduces vision")
	check(m.injure_sense(body, "right_ear", 1.0), "One ear can be damaged")
	check(m.capabilities(body, 5.0, 0.0).hearing_loss_db < 10.0, "Other functioning ear partly compensates")
	check(m.injure_sense(body, "left_ear", 1.0), "Second ear damaged")
	check(m.capabilities(body, 5.0, 0.0).hearing_loss_db > 55.0, "Bilateral deafness prevents distant speech hearing")
	var pain_raw: float = body.pain_raw
	var pain_felt: float = body.pain_felt
	check(pain_felt < pain_raw and body.adrenaline > 0.0, "Adrenaline can temporarily mask perceived pain")
	var untreated: Dictionary = body.duplicate(true)
	var dressed: Dictionary = body.duplicate(true)
	check(m.treat(dressed, "bandage", "left_leg"), "Local bandage applied")
	var treated_blood: float = float(m.advance(dressed, 300.0, 0.0, 0.0, 5.0).bleeding_kg)
	var raw_blood: float = float(m.advance(untreated, 300.0, 0.0, 0.0, 5.0).bleeding_kg)
	check(treated_blood < raw_blood, "Only dressing physically reduces wound bleed")
	check(dressed.parts.left_leg.tissues.bone < 0.2, "Bandage does not repair a broken leg")
	check(dressed.parts.left_leg.infection >= 0.0 and treated_blood > 0.0, "Infection and ongoing blood loss are persistent")
	m.advance(dressed, 7200.0, 0.0, 0.0, 5.0)
	check(dressed.adrenaline < body.adrenaline and dressed.pain_felt >= pain_felt, "Adrenaline fades while tissue injury remains")
	var invalid: Dictionary = body.duplicate(true)
	invalid.parts.left_leg.tissues.bone = 1.8
	check(not m.validate_state(invalid).is_empty(), "Damage integrity >1 rejected")
	check(not m.injure(body, {"part":"no_place", "wound_m2":0.3}), "Invalid injury site rejected")
	print("Anatomy: ", "PASS" if failures.is_empty() else JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

extends SceneTree
const Presenter = preload("res://src/application/presentation.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var presenter = Presenter.new()
	var snapshot: Dictionary = {
		"body":{"sensations":["Во рту сухо."],"warnings":[]},
		"conditions":{"temp_label":"холодно","warnings":[]},
		"people":[], "threat_warnings":[], "action":{}
	}
	var catalog: Array = [
		{"id":"inspect","category":"Мир","enabled":true,"duration_s":60},
		{"id":"retreat","category":"Опасность","enabled":false,"reason":"Враг далеко.","duration_s":30},
		{"id":"talk:nina","category":"Люди","enabled":true,"duration_s":300},
		{"id":"move:yard","category":"Путь","enabled":true,"duration_s":120}
	]
	var before: String = JSON.stringify(snapshot)
	var out: Dictionary = presenter.build(snapshot, catalog)
	check(out.attention == "exploration", "No invisible enemy triggers danger UI")
	check(out.urgent_actions.is_empty(), "No unseen urgent actions")
	check(out.actions.size() == 2, "Hidden enemy and absent people affordances excluded")
	check(JSON.stringify(out).find("Враг далеко") == -1, "Hidden proximity reason never leaks")
	check(JSON.stringify(snapshot) == before, "Presentation is read-only")
	check(out.status[0].text == "Во рту сухо.", "Body sensation is presented")
	check(not str(out.people_empty).contains("мёртв"), "Empty state does not invent fate")
	snapshot["threat_warnings"] = ["Слышны шаркающие шаги."]
	catalog[1]["enabled"] = true
	out = presenter.build(snapshot, catalog)
	check(out.attention == "alert" and out.threat_observed, "Only perceived threat activates danger mode")
	check(out.urgent_actions.size() >= 1, "Perceived danger exposes immediate affordances")
	snapshot["threat_warnings"] = []
	snapshot["action"] = {"title":"Работа"}
	out = presenter.build(snapshot, catalog)
	check(out.attention == "work", "Active action drives work layout")
	print("Presentation contract: ", "PASS" if failures.is_empty() else JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	if not condition: failures.append(label)

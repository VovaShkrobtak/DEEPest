extends SceneTree
const Parser = preload("res://src/application/parser.gd")
var failures: int = 0
func check(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		failures += 1
func _initialize() -> void:
	var parser = Parser.new()
	var actions: Array = [{"id":"move:well","title":"К колодцу"},{"id":"move:yard","title":"Во двор"},{"id":"drink","title":"Пить","enabled":false},{"id":"talk:nina","title":"Нина"},{"id":"talk:pavel","title":"Павел"}]
	check(parser.parse("идти к колодцу", actions).id == "move:well", "Location morphology")
	check(parser.parse("выпить 500мл", actions).parameters.mass_kg == 0.5, "Millilitres")
	check(parser.parse("drink 0,5л", actions).parameters.mass_kg == 0.5, "Decimal comma")
	check(parser.parse("пить пол-литра", actions).parameters.mass_kg == 0.5, "Half litre")
	check(not parser.parse("пить -5л", actions).ok, "Reject negative quantity")
	check(not parser.parse("пить 10л", actions).ok, "Reject over limit")
	check(not parser.parse("пить - 5л", actions).ok, "Reject malformed negative")
	check(not parser.parse("пить пол-литра -5л", actions).ok, "Reject mixed quantities")
	check(parser.parse("осмотреться", actions).id == "inspect", "Inspection verb")
	check(not parser.parse("пить много литров", actions).ok, "Reject malformed quantity")
	check(not parser.parse("перелить воду", actions).ok, "Unsupported pour not drink")
	check(not parser.parse("поговорить", actions).ok, "Ambiguous person")
	check(parser.parse("поговорить с Ниной", actions).id == "talk:nina", "Person morphology")
	check(parser.parse("drink", actions).ok, "Disabled action can parse")
	check(not parser.parse("abracadabra", actions).ok, "Unknown verb")
	print("parser: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

extends Control
## Low-cost, purely schematic top-down map. No simulation reads or writes.
## Never draw an NPC, infected or sound source at an invented coordinate.
signal route_selected(target: String)

const FONT = preload("res://assets/fonts/OpenSans-Regular.ttf")
const BG := Color("172226")
const FLOOR := Color("5b554b")
const FLOOR_ALT := Color("424c4c")
const WALL := Color("c4b79c")
const ACCENT := Color("dfbc78")
const BLUE := Color("91bac4")
const INK := Color("f2e9d7")
const FADED := Color("b0b9b7")

var diagram: Dictionary = {}
var highlighted_route: String = ""

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0.0, 265.0)

func set_diagram(value: Dictionary) -> void:
	diagram = value.duplicate(true)
	highlighted_route = ""
	queue_redraw()

func _plot() -> Rect2:
	return Rect2(Vector2(12.0, 12.0),
		Vector2(maxf(1.0, size.x - 24.0), maxf(1.0, size.y - 24.0)))

func _point(plot: Rect2, x: float, y: float) -> Vector2:
	return plot.position + Vector2(plot.size.x * x, plot.size.y * y)

func _rect(plot: Rect2, x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(_point(plot, x, y), Vector2(plot.size.x * w, plot.size.y * h))

func _text(value: String, position: Vector2, font_size: int = 12,
		color: Color = INK, centered: bool = false) -> void:
	if value.is_empty():
		return
	var origin := position
	if centered:
		origin.x -= FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	draw_string(FONT, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	var plot := _plot()
	draw_rect(plot, BG, true)
	match str(diagram.get("mode", "")):
		"house":
			_draw_house(plot)
		"yard":
			_draw_yard(plot)

func _room(plan: Rect2, x: float, y: float, w: float, h: float,
		title: String, alt: bool = false) -> void:
	var area := _rect(plan, x, y, w, h)
	draw_rect(area, FLOOR_ALT if alt else FLOOR, true)
	draw_rect(area, WALL, false, 3.0)
	_text(title, area.position + Vector2(7.0, 19.0), 12)

func _draw_house(plot: Rect2) -> void:
	# This is an illustrative floor plan; the world still treats shelter as one location.
	var plan_width: float = minf(plot.size.x, plot.size.y * 1.60)
	var plan := Rect2(
		Vector2(plot.get_center().x - plan_width * 0.5, plot.position.y),
		Vector2(plan_width, plot.size.y))
	_room(plan, 0.06, 0.06, 0.42, 0.43, "Жилая")
	_room(plan, 0.48, 0.06, 0.46, 0.43, "Кухня", true)
	_room(plan, 0.06, 0.49, 0.30, 0.34, "Кладовая", true)
	_room(plan, 0.36, 0.49, 0.58, 0.34, "Сени")
	# Furniture is conceptual scenery, not a physical item location.
	draw_rect(_rect(plan, 0.11, 0.24, 0.21, 0.12), Color("92795f"), true)
	draw_rect(_rect(plan, 0.74, 0.14, 0.14, 0.15), Color("a07653"), true)
	_text("печь", _point(plan, 0.71, 0.37), 11, FADED)
	draw_rect(_rect(plan, 0.72, 0.06, 0.11, 0.014), BLUE, true)
	draw_rect(_rect(plan, 0.06, 0.30, 0.012, 0.12), BLUE, true)
	# Door gaps represent an illustration, not physical collision portals.
	draw_rect(_rect(plan, 0.465, 0.28, 0.030, 0.12), FLOOR, true)
	draw_rect(_rect(plan, 0.25, 0.475, 0.13, 0.030), FLOOR, true)
	draw_rect(_rect(plan, 0.64, 0.475, 0.13, 0.030), FLOOR_ALT, true)
	draw_rect(_rect(plan, 0.345, 0.65, 0.030, 0.12), FLOOR, true)
	_text("Дом — вы здесь", _point(plan, 0.50, 0.57), 12, ACCENT, true)
	# Only the known connection to the yard can be clicked.
	if _has_route("yard"):
		var exit_pos := _point(plan, 0.50, 0.90)
		draw_line(_point(plan, 0.50, 0.83), exit_pos, ACCENT, 3.0)
		draw_circle(exit_pos, 13.0, ACCENT)
		_text("Двор", exit_pos + Vector2(0.0, 31.0), 12, INK, true)

func _draw_yard(plot: Rect2) -> void:
	var center := _point(plot, 0.50, 0.50)
	var routes: Array = diagram.get("routes", [])
	for record: Dictionary in routes:
		var pos: Dictionary = record.get("pos", {})
		var target := _point(plot, float(pos.get("x", 0.5)), float(pos.get("y", 0.5)))
		draw_line(center, target, WALL, 2.0)
	draw_circle(center, 22.0, FLOOR)
	draw_circle(center, 22.0, ACCENT, false, 2.0)
	_text("ВЫ", center + Vector2(0.0, 4.0), 12, ACCENT, true)
	for record: Dictionary in routes:
		var pos: Dictionary = record.get("pos", {})
		var target := _point(plot, float(pos.get("x", 0.5)), float(pos.get("y", 0.5)))
		var hovered := highlighted_route == str(record.get("id", ""))
		draw_circle(target, 15.0 if hovered else 12.0, ACCENT if hovered else FLOOR_ALT)
		draw_circle(target, 15.0 if hovered else 12.0, WALL, false, 2.0)
		_text(str(record.get("title", "")), target + Vector2(0.0, 28.0), 12, INK, true)
		_text("%d м" % int(round(float(record.get("distance_m", 0.0)))),
			target + Vector2(0.0, 42.0), 10, FADED, true)

func _has_route(target: String) -> bool:
	for route: Dictionary in diagram.get("routes", []):
		if str(route.get("id", "")) == target:
			return true
	return false

func route_position(target: String) -> Vector2:
	# Exposed for touch hit-testing and regression tests.
	if not _has_route(target):
		return Vector2(-1.0, -1.0)
	var plot := _plot()
	if str(diagram.get("mode", "")) == "house":
		var width: float = minf(plot.size.x, plot.size.y * 1.60)
		var plan := Rect2(Vector2(plot.get_center().x - width * 0.5, plot.position.y),
			Vector2(width, plot.size.y))
		return _point(plan, 0.50, 0.90) if target == "yard" else Vector2(-1.0, -1.0)
	if str(diagram.get("mode", "")) == "yard":
		for route: Dictionary in diagram.get("routes", []):
			if str(route.get("id", "")) == target:
				var pos: Dictionary = route.get("pos", {})
				return _point(plot, float(pos.get("x", 0.5)), float(pos.get("y", 0.5)))
	return Vector2(-1.0, -1.0)

func route_at(point: Vector2) -> String:
	for route: Dictionary in diagram.get("routes", []):
		var target: String = str(route.get("id", ""))
		if route_position(target).distance_to(point) <= 27.0:
			return target
	return ""

func _gui_input(event: InputEvent) -> void:
	var position := Vector2(-1.0, -1.0)
	var pressed := false
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		pressed = mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
		position = mouse.position
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		pressed = touch.pressed
		position = touch.position
	if pressed:
		var selected: String = route_at(position)
		if not selected.is_empty():
			route_selected.emit(selected)
			accept_event()
	elif event is InputEventMouseMotion:
		var next_route: String = route_at(event.position)
		if next_route != highlighted_route:
			highlighted_route = next_route
			queue_redraw()

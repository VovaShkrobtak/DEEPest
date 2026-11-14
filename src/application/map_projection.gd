extends RefCounted
## Read-only map projection. Only the public observation snapshot is allowed here.
## Positions are diagram layout coordinates, NEVER simulated positions or directions.
const TITLES := {
	"shelter": "Дом", "yard": "Двор", "well": "Колодец",
	"forest": "Лес", "clinic": "Медпункт",
	"workshop": "Мастерская", "garden": "Огород"
}
const YARD_LAYOUT := {
	"shelter": {"x": 0.50, "y": 0.14},
	"well": {"x": 0.20, "y": 0.31},
	"forest": {"x": 0.19, "y": 0.74},
	"clinic": {"x": 0.80, "y": 0.30},
	"workshop": {"x": 0.80, "y": 0.72},
	"garden": {"x": 0.50, "y": 0.84}
}

func build(snapshot: Dictionary) -> Dictionary:
	var current: String = str(snapshot.get("location_id", ""))
	if current not in ["shelter", "yard"]:
		return {}
	var available: Variant = snapshot.get("routes", {})
	if not available is Dictionary:
		return {}
	var links: Array = []
	var keys: Array = available.keys()
	keys.sort()
	for target_value: Variant in keys:
		var target: String = str(target_value)
		if not TITLES.has(target):
			continue
		var distance: float = float(available[target_value])
		if not is_finite(distance) or distance <= 0.0:
			continue
		links.append({
			"id": target,
			"title": str(TITLES[target]),
			"distance_m": distance,
			"pos": YARD_LAYOUT.get(target, {"x": 0.5, "y": 0.5}).duplicate(true)
		})
	return {"mode": "house" if current == "shelter" else "yard",
		"location_id": current, "routes": links}

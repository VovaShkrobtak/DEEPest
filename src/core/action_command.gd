extends RefCounted
## Typed external command boundary. Module payloads are SI dictionaries.
var id: String
var parameters: Dictionary
var expected_revision: int

func _init(action_id: String = "", args: Dictionary = {}, revision: int = -1) -> void:
	id = action_id
	parameters = args.duplicate(true)
	expected_revision = revision

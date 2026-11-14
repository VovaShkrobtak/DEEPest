extends SceneTree

class FakeKernel extends RefCounted:
	var state: Dictionary = {'time_s': 120.0, 'action': {'kind': 'repair', 'remaining_s': 35.0}}
	func export_state() -> Dictionary:
		return state.duplicate(true)
	func restore_state(data: Dictionary) -> Dictionary:
		if not data.has('time_s') or not data.has('action'):
			return {'ok': false, 'message': 'Invalid world'}
		state = data.duplicate(true)
		return {'ok': true, 'message': 'Restored'}

func _initialize() -> void:
	var script: Script = load('res://src/adapters/save_store.gd')
	if script == null:
		push_error('Missing save store')
		quit(1)
		return
	var path: String = '/tmp/deepest_save_store_test.json'
	for suffix: String in ['', '.tmp', '.bak1', '.bak2']:
		DirAccess.remove_absolute(path + suffix)
	var store: RefCounted = script.new(path)
	var kernel: FakeKernel = FakeKernel.new()
	assert(store.save(kernel).ok)
	kernel.state.time_s = 240.0
	assert(store.save(kernel).ok)
	kernel.state.time_s = 999.0
	assert(store.load_into(kernel).ok)
	assert(kernel.state.time_s == 240.0 and kernel.state.action.remaining_s == 35.0)
	_write(path, 'broken primary')
	var recovered: Dictionary = store.load_into(kernel)
	assert(recovered.ok and 'резерв' in recovered.message)
	assert(kernel.state.time_s == 120.0)
	_write(path + '.bak1', 'broken backup')
	var before: Dictionary = kernel.state.duplicate(true)
	assert(not store.load_into(kernel).ok)
	assert(kernel.state == before)
	assert(store.save(kernel).ok)
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	envelope.format = 999
	_write(path, JSON.stringify(envelope))
	_write(path + '.bak1', 'broken backup')
	assert(not store.load_into(kernel).ok)
	assert(kernel.state == before)
	_write(path + '.tmp', JSON.stringify({'format': 1}))
	assert(not store.load_into(kernel).ok)
	assert(store.save(kernel).ok)
	var missing: Dictionary = kernel.state.duplicate(true)
	kernel.state = {'time_s': 0.0}
	assert(store.save(kernel).ok)
	kernel.state = missing
	# Semantically invalid current save can recover a structurally valid backup.
	assert(store.load_into(kernel).ok)
	assert(kernel.state == missing)
	var safe: Dictionary = kernel.state.duplicate(true)
	kernel.state.time_s = NAN
	assert(not store.save(kernel).ok)
	kernel.state = safe
	_write(path + '.bak1', 'bad')
	_write(path + '.bak2', 'bad')
	var damaged: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	damaged.checksum = 'wrong'
	_write(path, JSON.stringify(damaged))
	assert(not store.load_into(kernel).ok)
	assert(kernel.state == safe)
	_write(path, 'x'.repeat(4 * 1024 * 1024 + 1))
	assert(not store.load_into(kernel).ok)
	assert(kernel.state == safe)
	print('PASS save store: mid-action, backup recovery, rejection, future format, interrupted temp')
	quit(0)

func _write(path: String, value: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

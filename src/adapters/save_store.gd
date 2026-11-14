extends RefCounted

const FORMAT: int = 1
const BUILD: String = '0.1.0'
const CONTENT_HASH: String = 'deepest-first-playable-content-v1'
const MAX_BYTES: int = 4 * 1024 * 1024
var _path: String

func _init(path: String = 'user://survival.json') -> void:
	_path = ProjectSettings.globalize_path(path)

func save(kernel: Object) -> Dictionary:
	var payload: Dictionary = kernel.export_state()
	if not _finite_tree(payload):
		return _result(false, 'Сохранение отклонено: недопустимые числа или структура.')
	var payload_json: String = JSON.stringify(payload)
	var envelope: Dictionary = {'format': FORMAT, 'build': BUILD, 'content_hash': CONTENT_HASH,
		'payload_json': payload_json, 'checksum': payload_json.sha256_text()}
	var text: String = JSON.stringify(envelope)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return _result(false, 'Сохранение превышает предел размера.')
	var parent: String = _path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(parent) != OK:
		return _result(false, 'Не удалось создать каталог сохранения.')
	var temporary: String = _path + '.tmp'
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _result(false, 'Не удалось записать временный файл.')
	file.store_string(text)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK or not _read(temporary).ok:
		return _result(false, 'Проверка записанного файла не пройдена.')
	if FileAccess.file_exists(_path + '.bak2'):
		if DirAccess.remove_absolute(_path + '.bak2') != OK:
			return _result(false, 'Не удалось обновить резервные копии.')
	if FileAccess.file_exists(_path + '.bak1'):
		if DirAccess.rename_absolute(_path + '.bak1', _path + '.bak2') != OK:
			return _result(false, 'Не удалось переместить резервную копию.')
	if FileAccess.file_exists(_path):
		if DirAccess.rename_absolute(_path, _path + '.bak1') != OK:
			return _result(false, 'Не удалось сохранить предыдущую версию.')
	if DirAccess.rename_absolute(temporary, _path) != OK:
		return _result(false, 'Не удалось завершить сохранение; предыдущая версия в резервной копии.')
	return _result(true, 'Игра сохранена.')

func load_into(kernel: Object) -> Dictionary:
	var original: Dictionary = kernel.export_state().duplicate(true)
	var last_message: String = 'Сохранение не найдено.'
	for suffix: String in ['', '.bak1', '.bak2']:
		var decoded: Dictionary = _read(_path + suffix)
		if not decoded.ok:
			last_message = decoded.message
			continue
		var restored: Dictionary = kernel.restore_state(decoded.payload)
		if restored.get('ok', false):
			return _result(true, 'Игра загружена.' if suffix.is_empty() else 'Игра восстановлена из резервной копии ' + suffix + '.')
		# Defensive rollback for adapters whose restore implementation partially mutates.
		kernel.restore_state(original.duplicate(true))
		last_message = str(restored.get('message', 'Состояние мира недопустимо.'))
	return _result(false, 'Загрузка отклонена. ' + last_message)

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _result(false, 'Файл не найден.')
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _result(false, 'Файл недоступен.')
	if file.get_length() <= 0 or file.get_length() > MAX_BYTES:
		file.close()
		return _result(false, 'Недопустимый размер файла.')
	var raw: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary:
		return _result(false, 'Повреждён JSON сохранения.')
	var envelope: Dictionary = parser.data
	for key: String in ['format', 'build', 'content_hash', 'payload_json', 'checksum']:
		if not envelope.has(key):
			return _result(false, 'Отсутствует поле сохранения: ' + key)
	if envelope.format != FORMAT or envelope.build != BUILD or envelope.content_hash != CONTENT_HASH:
		return _result(false, 'Несовместимая версия сохранения или данных.')
	if not envelope.payload_json is String or not envelope.checksum is String:
		return _result(false, 'Неверный тип данных сохранения.')
	var encoded: String = envelope.payload_json
	if encoded.sha256_text() != envelope.checksum:
		return _result(false, 'Контрольная сумма не совпадает.')
	if parser.parse(encoded) != OK or not parser.data is Dictionary:
		return _result(false, 'Повреждён мир сохранения.')
	var payload: Dictionary = parser.data
	if payload.is_empty() or not _finite_tree(payload):
		return _result(false, 'Недопустимое состояние мира.')
	return {'ok': true, 'message': '', 'payload': payload}

func _finite_tree(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	if value is float:
		return is_finite(value)
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _finite_tree(value[key], depth + 1):
				return false
		return true
	if value is Array:
		for element: Variant in value:
			if not _finite_tree(element, depth + 1):
				return false
		return true
	return value == null or value is String or value is int or value is bool

func _result(ok: bool, message: String) -> Dictionary:
	return {'ok': ok, 'message': message}

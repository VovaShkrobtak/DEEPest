extends Control
## All simulation writes go through Kernel commands. Containers own all layout.
const Kernel = preload("res://src/core/kernel.gd")
const SaveStore = preload("res://src/adapters/save_store.gd")
const Parser = preload("res://src/application/parser.gd")
const INK = Color("e9e5da")
const MUTED = Color("a1adae")
const AMBER = Color("d6ae68")
const BACKGROUND = Color("10191d")
const CARD = Color("182328")
const TABS = ["Мир", "Вещи", "Тело", "Люди", "Журнал", "Знания", "Настройки"]
var kernel = Kernel.new(1998)
var save_store = SaveStore.new()
var autosave_path: String = "user://autosave.json"
var autosave_store
var autosave_protected: bool = false
var keyboard_inset: int = 0
var keyboard_poll: float = 0.0
var parser = Parser.new()
var snapshot: Dictionary = {}
var selected_tab: String = "Мир"
var text_scale: float = 1.0
var reduced_motion: bool = true
var debug_visible: bool = false
var message: String = "Вы здесь. Прислушайтесь к себе и осмотритесь."
var root_column: VBoxContainer
var page: VBoxContainer
var side: VBoxContainer
var navigation: BoxContainer
var layout: HBoxContainer
var main_scroll: ScrollContainer
var command_input: LineEdit
var clock_label: Label
var notice: Label
var running_progress: ProgressBar
var running_text: Label
var action_panel: VBoxContainer
var action_timer: Timer
var mobile: bool = false
var rebuilding: bool = false
var new_seed: int = 1998
var goals_expanded: bool = false
var settings_path: String = "user://interface.cfg"

func _ready() -> void:
	autosave_store = SaveStore.new(autosave_path)
	_resume_autosave()
	get_tree().auto_accept_quit = false
	_load_settings()
	_install_theme()
	_build_shell()
	action_timer = Timer.new()
	action_timer.wait_time = 0.15
	action_timer.timeout.connect(_advance)
	add_child(action_timer)
	resized.connect(_responsive)
	_refresh()

func _install_theme() -> void:
	var skin := Theme.new()
	skin.default_font = load("res://assets/fonts/OpenSans-Regular.ttf")
	skin.default_font_size = int(16 * text_scale)
	skin.set_color("font_color", "Label", INK)
	skin.set_color("font_color", "Button", INK)
	skin.set_color("font_disabled_color", "Button", Color("728086"))
	skin.set_constant("separation", "VBoxContainer", 12)
	skin.set_constant("separation", "HBoxContainer", 16)
	for mode in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("25343a") if mode == "hover" else CARD
		style.border_color = AMBER if mode in ["pressed", "focus"] else Color("344247")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		skin.set_stylebox(mode, "Button", style)
	var entry := StyleBoxFlat.new()
	entry.bg_color = Color("0d1519")
	entry.set_border_width_all(1)
	entry.border_color = Color("43545a")
	entry.content_margin_left = 14
	entry.content_margin_right = 14
	skin.set_stylebox("normal", "LineEdit", entry)
	skin.set_color("font_color", "LineEdit", INK)
	theme = skin

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	root_column = VBoxContainer.new()
	margin.add_child(root_column)
	var masthead := HBoxContainer.new()
	root_column.add_child(masthead)
	var brand := _label("DEEPest", 30, INK)
	brand.add_theme_font_override("font", load("res://assets/fonts/OpenSans-Semibold.ttf"))
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	masthead.add_child(brand)
	clock_label = _label("", 13, AMBER)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	masthead.add_child(clock_label)
	root_column.add_child(_label("П О Л Е В О Й   Д Н Е В Н И К   /   В Ы Ж И В А Н И Е", 10, MUTED))
	root_column.add_child(HSeparator.new())
	layout = HBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(layout)
	navigation = VBoxContainer.new()
	navigation.custom_minimum_size.x = 146
	layout.add_child(navigation)
	main_scroll = ScrollContainer.new()
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(main_scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.add_child(page)
	side = VBoxContainer.new()
	side.custom_minimum_size.x = 236
	layout.add_child(side)
	notice = _label("", 13, AMBER)
	root_column.add_child(notice)
	var command_row := HBoxContainer.new()
	root_column.add_child(command_row)
	command_input = LineEdit.new()
	command_input.placeholder_text = "Что вы хотите сделать?"
	command_input.custom_minimum_size.y = 48
	command_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_input.text_submitted.connect(_submit)
	command_row.add_child(command_input)
	var submit_button := _button("→", func(): _submit(command_input.text))
	submit_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	submit_button.custom_minimum_size.x = 56
	command_row.add_child(submit_button)

func _label(value: String, font_size: int = 16, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(font_size * text_scale))
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(callback)
	return button

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _section(parent: Node, title: String, body: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_label(title, 12, AMBER))
	if not body.is_empty():
		box.add_child(_label(body, 15))
	return box

func _refresh() -> void:
	if not is_instance_valid(page): return
	snapshot = kernel.snapshot()
	_rebuild_content()
	if not snapshot.get("action", {}).is_empty():
		action_timer.start()
	else:
		action_timer.stop()

func _rebuild_content() -> void:
	_clear(page)
	_clear(side)
	_clear(navigation)
	mobile = size.x < 980 or text_scale > 1.4
	for tab in TABS:
		var tab_button := _button(("· " if tab == selected_tab else "") + tab, _select_tab.bind(tab))
		if tab == selected_tab:
			tab_button.add_theme_color_override("font_color", AMBER)
		navigation.add_child(tab_button)
	clock_label.text = "%s\n%s" % [snapshot.get("time_label", "08:00"), snapshot.get("date_label", "14 ноября 1998")]
	notice.text = message
	notice.max_lines_visible = 3 if mobile else 2
	page.add_child(_label("ОКРЕСТНОСТИ / ДЕНЬ %s" % snapshot.get("day", 1), 11, MUTED))
	page.add_child(_label(str(snapshot.get("location_title", "Неизвестное место")), 27, INK))
	if mobile:
		var weather: Dictionary = snapshot.get("conditions", {})
		page.add_child(_label(str(weather.get("weather_label", "")) + " · " + str(weather.get("temp_label", "")), 12, MUTED))
		var warnings: Array = snapshot.get("body", {}).get("warnings", []) + weather.get("warnings", [])
		if not warnings.is_empty(): _section(page, "ОБРАТИТЕ ВНИМАНИЕ", "\n".join(warnings))
	_terminal_banner()
	if not snapshot.get("action", {}).is_empty(): _running_action()
	if selected_tab == "Мир": _world_page()
	elif selected_tab == "Вещи": _items_page()
	elif selected_tab == "Тело": _body_page()
	elif selected_tab == "Люди":
		_entries(snapshot.get("people", []), "РЯДОМ НИКОГО НЕ ВИДНО")
		_actions(page, ["Люди", "social"])
	elif selected_tab == "Журнал": _journal_page()
	elif selected_tab == "Знания": _knowledge_page()
	elif selected_tab == "Настройки": _settings_page()
	_build_conditions(page if mobile else side)
	_responsive()

func _select_tab(tab: String) -> void:
	selected_tab = tab
	main_scroll.scroll_vertical = 0
	_rebuild_content()

func _world_page() -> void:
	var description := "\n".join(snapshot.get("description", []))
	_section(page, "ЗДЕСЬ И СЕЙЧАС", description)
	var goals: Array = snapshot.get("goals", [])
	if not goals.is_empty():
		var completed: int = 0
		var next_goal: String = "Все начальные ориентиры выполнены."
		for goal: Dictionary in goals:
			if goal.get("done", false): completed += 1
		for goal: Dictionary in goals:
			if not goal.get("done", false):
				next_goal = str(goal.get("title", ""))
				break
		if mobile and not goals_expanded:
			var compact := _button("Ориентиры %d/%d · %s ↓" % [completed, goals.size(), next_goal], func(): goals_expanded = true; _rebuild_content())
			compact.add_theme_font_size_override("font_size", int(12 * text_scale))
			page.add_child(compact)
		else:
			var box := _section(page, "ПЕРВЫЕ ОРИЕНТИРЫ · %d / %d" % [completed, goals.size()])
			if goals_expanded:
				for goal: Dictionary in goals:
					box.add_child(_label(("✓  " if goal.get("done", false) else "○  ") + str(goal.get("title", "")), 14, MUTED if goal.get("done", false) else INK))
			else:
				box.add_child(_label("○  " + next_goal, 14))
			var toggle := _button("Свернуть ориентиры" if goals_expanded else "Все ориентиры ↓", func(): goals_expanded = not goals_expanded; _rebuild_content())
			toggle.add_theme_font_size_override("font_size", int(12 * text_scale))
			box.add_child(toggle)
	page.add_child(_label("ВАШ СЛЕДУЮЩИЙ ШАГ", 12, AMBER))
	_actions(page)
	if not snapshot.get("objects", []).is_empty():
		page.add_child(_label("ПРИМЕТЫ МЕСТА", 12, MUTED))
		_entries(snapshot.objects, "")

func _actions(parent: Node, categories: Array = []) -> void:
	if not snapshot.get("alive", true): return
	var groups: Dictionary = {}
	for action: Dictionary in kernel.available_actions():
		if not snapshot.get("conscious", true) and str(action.id).get_slice(":", 0) != "wait": continue
		var category: String = str(action.get("category", "other"))
		if not categories.is_empty() and not category in categories: continue
		if not groups.has(category): groups[category] = []
		groups[category].append(action)
	var titles: Dictionary = {"inspect": "НАБЛЮДЕНИЕ", "observation": "НАБЛЮДЕНИЕ", "world": "ВОКРУГ ВАС", "travel": "МАРШРУТЫ", "move": "МАРШРУТЫ", "movement": "МАРШРУТЫ", "body": "ЗАБОТА О СЕБЕ", "care": "ЗАБОТА О СЕБЕ", "rest": "ОТДЫХ", "water": "ВОДА", "food": "ЕДА", "items": "ВЕЩИ", "inventory": "ВЕЩИ", "equipment": "СНАРЯЖЕНИЕ", "social": "ЛЮДИ", "craft": "РАБОТА", "crafting": "РАБОТА", "shelter": "УБЕЖИЩЕ", "fire": "ТЕПЛО И ОГОНЬ", "other": "ДОСТУПНЫЕ ДЕЙСТВИЯ"}
	for category: String in groups:
		parent.add_child(_label(str(titles.get(category, category.to_upper())), 11, MUTED))
		var grid := GridContainer.new()
		grid.columns = 1 if mobile else 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		parent.add_child(grid)
		for action: Dictionary in groups[category]:
			var duration: float = float(action.get("duration_s", 0))
			var caption: String = str(action.get("title", action.id))
			if duration > 0: caption += "  ·  " + _duration(duration)
			var button := _button(caption, _perform.bind(str(action.id), action.get("parameters", {})))
			button.set_meta("action_id", action.id)
			button.disabled = not action.get("enabled", true)
			var card := VBoxContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(card)
			card.add_child(button)
			var detail: String = str(action.get("description", "")) if not button.disabled else str(action.get("reason", "Сейчас недоступно"))
			if not detail.is_empty(): card.add_child(_label(detail, 12, MUTED))

func _duration(seconds: float) -> String:
	if seconds < 60: return "%d с" % int(seconds)
	return "%d мин" % int(ceil(seconds / 60.0))

func _running_action() -> void:
	var action: Dictionary = snapshot.action
	var box := _section(page, "ДЕЙСТВИЕ ВО ВРЕМЕНИ", str(action.get("title", "Выполняется действие")))
	var progress := ProgressBar.new()
	running_progress = progress
	progress.max_value = maxf(float(action.get("duration_s", 1)), 1.0)
	progress.value = float(action.get("elapsed_s", 0))
	progress.show_percentage = false
	progress.custom_minimum_size.y = 5
	box.add_child(progress)
	running_text = _label("Прошло %s / %s" % [_duration(float(action.get("elapsed_s", 0))), _duration(progress.max_value)], 12, MUTED)
	box.add_child(running_text)
	box.add_child(_button("Прервать действие", _cancel))

func _items_page() -> void:
	var inventory: Dictionary = snapshot.get("inventory", {})
	_section(page, "С СОБОЙ", str(inventory.get("load_text", "")) + "\n" + str(inventory.get("water_text", "")))
	_entries(inventory.get("items", []), "Вещей не видно")
	_entries(inventory.get("equipment", []), "")
	page.add_child(_label("ДЕЙСТВИЯ С ВЕЩАМИ", 12, AMBER))
	_actions(page, ["items", "inventory", "water", "food", "equipment", "Вещи", "Вода и еда", "Ремесло"])

func _body_page() -> void:
	var body: Dictionary = snapshot.get("body", {})
	_section(page, "ОЩУЩЕНИЯ", "\n".join(body.get("sensations", [])))
	_entries(body.get("details", []), "")
	_actions(page, ["body", "rest", "care", "Тело"])

func _entries(entries: Array, empty: String) -> void:
	if entries.is_empty() and not empty.is_empty(): _section(page, empty)
	for entry in entries:
		if entry is Dictionary:
			_section(page, str(entry.get("title", entry.get("id", "Наблюдение"))), str(entry.get("text", "")))
		else: _section(page, "НАБЛЮДЕНИЕ", str(entry))

func _journal_page() -> void:
	page.add_child(_label("Последние наблюдения. Новые записи сверху.", 13, MUTED))
	var entries: Array = snapshot.get("journal", []).duplicate()
	entries.reverse()
	for entry in entries.slice(0, 80):
		_section(page, str(entry.get("time_label", "")) + " · НАБЛЮДЕНИЕ", str(entry.get("text", "")))

func _knowledge_page() -> void:
	_section(page, "ВРЕМЯ И ВЫБОР", "Мир меняется, пока вы действуете. Осмотритесь, оцените ощущения и выберите следующий шаг. Длительное действие можно прервать; уже прошедшее время не возвращается.")
	_section(page, "ВОДА", "Прозрачность и запах не доказывают безопасность. Кипячение требует времени и топлива; химические примеси от него не исчезают.")
	_section(page, "ХОЛОД И НОЧЛЕГ", "Влажная одежда и сквозняк усиливают холод. Закрытое окно уменьшает приток воздуха, но помещение не согревается мгновенно. Дымящая печь — повод проверить вентиляцию.")
	_section(page, "СВОБОДНЫЙ ВВОД", "Введите название доступного действия, например «осмотреться». Если команда неясна, мир останется на месте. Все действия доступны и через кнопки.")

func _build_conditions(parent: Node) -> void:
	var conditions: Dictionary = snapshot.get("conditions", {})
	var box := _section(parent, "УСЛОВИЯ", str(conditions.get("weather_label", "")) + "\n" + str(conditions.get("temp_label", "")))
	box.add_child(_label("Время идёт только при действии", 12, MUTED))
	var body: Dictionary = snapshot.get("body", {})
	var senses := _section(parent, "САМОЧУВСТВИЕ", "\n".join(body.get("sensations", [])))
	for warning in body.get("warnings", []) + conditions.get("warnings", []): senses.add_child(_label(str(warning), 13, AMBER))
	var inv: Dictionary = snapshot.get("inventory", {})
	_section(parent, "ЗАПАСЫ", str(inv.get("water_text", "")) + "\n" + str(inv.get("load_text", "")))
	parent.add_child(_label("АВТОНОМНО · БЕЗ СЕТИ\nСЕВЕРНАЯ ПРОВИНЦИЯ, 1998", 10, MUTED))

func _settings_page() -> void:
	_section(page, "ВАШ ДНЕВНИК", "Сохранение включает мир, вещи и незавершённое действие.")
	page.add_child(_button("Сохранить прохождение", _save_game))
	page.add_child(_button("Загрузить сохранение", _load_game))
	var seed_box := _section(page, "НОВЫЙ МИР", "Зерно мира определяет воспроизводимое начало.")
	var seed_entry := SpinBox.new()
	seed_entry.min_value = 1
	seed_entry.max_value = 999999999
	seed_entry.value = new_seed
	seed_entry.custom_minimum_size.y = 48
	seed_entry.value_changed.connect(func(value: float): new_seed = int(value))
	seed_box.add_child(seed_entry)
	seed_box.add_child(_button("Новое прохождение…", _confirm_new))
	var box := _section(page, "ЧИТАЕМОСТЬ", "Размер текста: %d%%" % int(text_scale * 100))
	for scale_value in [1.0, 1.25, 1.5, 2.0]:
		box.add_child(_button("%d%%" % int(scale_value * 100), _set_scale.bind(scale_value)))
	var motion := CheckButton.new()
	motion.text = "Сокращённое движение"
	motion.button_pressed = reduced_motion
	motion.custom_minimum_size.y = 48
	motion.toggled.connect(func(value: bool): reduced_motion = value; _save_settings())
	box.add_child(motion)
	page.add_child(_button("Диагностика разработчика", _toggle_debug))
	if debug_visible:
		_section(page, "DEBUG · СКРЫТЫЕ ДАННЫЕ МОДЕЛИ", JSON.stringify(kernel.debug_snapshot(), "  "))

func _perform(id: String, parameters: Dictionary = {}) -> void:
	var result: Dictionary = kernel.command(id, parameters)
	message = str(result.get("message", ""))
	if result.get("ok", false):
		autosave_protected = false
		main_scroll.scroll_vertical = 0
		if kernel.snapshot().get("action", {}).is_empty(): _autosave()
	_refresh()

func _advance() -> void:
	if kernel.snapshot().get("action", {}).is_empty():
		action_timer.stop()
		return
	var result: Dictionary = kernel.step(30.0)
	if not str(result.get("message", "")).is_empty(): message = str(result.message)
	snapshot = kernel.snapshot()
	if snapshot.get("action", {}).is_empty():
		if not snapshot.get("journal", []).is_empty(): message = str(snapshot.journal.back().get("text", message))
		_autosave()
		_refresh()
		return
	# Keep controls stable while fingers are down; update only the running indicators.
	clock_label.text = "%s\n%s" % [snapshot.get("time_label", ""), snapshot.get("date_label", "")]
	if is_instance_valid(running_progress):
		running_progress.value = float(snapshot.action.get("elapsed_s", 0))
	if is_instance_valid(running_text):
		running_text.text = "Прошло %s / %s" % [_duration(float(snapshot.action.get("elapsed_s", 0))), _duration(float(snapshot.action.get("duration_s", 0)))]
	notice.text = message

func _cancel() -> void:
	var result: Dictionary = kernel.cancel()
	message = str(result.get("message", "Действие прервано"))
	if result.get("ok", false):
		autosave_protected = false
		_autosave()
	_refresh()

func _submit(value: String) -> void:
	if value.strip_edges().is_empty(): return
	var parsed: Dictionary = parser.parse(value, kernel.available_actions())
	if parsed.get("ok", false): _perform(str(parsed.id), parsed.get("parameters", {}))
	else:
		message = str(parsed.get("message", "Команда не распознана. Выберите доступное действие."))
		_refresh()
	command_input.clear()

func _save_game() -> void:
	var result: Dictionary = save_store.save(kernel)
	message = str(result.get("message", "Сохранено"))
	_refresh()

func _load_game() -> void:
	var result: Dictionary = save_store.load_into(kernel)
	message = str(result.get("message", "Загружено"))
	if result.get("ok", false):
		autosave_protected = false
		_autosave()
	_refresh()

func _confirm_new() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Новое прохождение"
	dialog.dialog_text = "Начать заново с зерном %d?\nНесохранённые изменения будут потеряны." % new_seed
	dialog.ok_button_text = "Начать"
	dialog.cancel_button_text = "Отмена"
	dialog.confirmed.connect(func(): kernel = Kernel.new(new_seed); message = "Начинается новый день."; selected_tab = "Мир"; autosave_protected = false; _autosave(); _refresh(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(mini(480, int(size.x) - 32), 220))

func _set_scale(value: float) -> void:
	text_scale = value
	_install_theme()
	_save_settings()
	_rebuild_content()

func _toggle_debug() -> void:
	debug_visible = not debug_visible
	_rebuild_content()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("interface", "text_scale", text_scale)
	config.set_value("interface", "reduced_motion", reduced_motion)
	config.save(settings_path)

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		text_scale = clampf(float(config.get_value("interface", "text_scale", 1.0)), 1.0, 2.0)
		reduced_motion = bool(config.get_value("interface", "reduced_motion", true))

func _responsive() -> void:
	if not is_instance_valid(navigation) or rebuilding: return
	var should_mobile: bool = size.x < 980 or text_scale > 1.4
	if should_mobile != mobile:
		rebuilding = true
		mobile = should_mobile
		_rebuild_content()
		rebuilding = false
	# Mobile navigation is a compact dropdown, leaving the reading column full width.
	navigation.visible = not mobile
	side.visible = not mobile
	var selector = root_column.get_node_or_null("MobileNavigation")
	if mobile and selector == null:
		var dropdown := OptionButton.new()
		dropdown.name = "MobileNavigation"
		dropdown.custom_minimum_size.y = 48
		for tab in TABS: dropdown.add_item(tab)
		dropdown.item_selected.connect(func(index: int): _select_tab(TABS[index]))
		root_column.add_child(dropdown)
		root_column.move_child(dropdown, 3)
		selector = dropdown
	if selector != null:
		selector.visible = mobile
		selector.select(TABS.find(selected_tab))

func _terminal_banner() -> void:
	var box: VBoxContainer
	if not snapshot.get("alive", true):
		box = _section(page, "ИСТОРИЯ ЗАВЕРШЕНА", "Ваш персонаж погиб. Сохранённый мир и журнал можно просмотреть; начните новое прохождение, чтобы продолжить игру.")
		command_input.editable = false
	elif not snapshot.get("conscious", true):
		box = _section(page, "БЕЗ СОЗНАНИЯ", "Вы не можете действовать. Дайте времени пройти; исход зависит от условий и состояния организма.")
		box.add_child(_button("Дать времени пройти", _perform.bind("wait", {})))
		command_input.editable = false
	elif snapshot.get("won", false):
		box = _section(page, "ВЫ ВСТРЕТИЛИ УТРО", "Первые ориентиры выполнены. Убежище обжито, запасы подготовлены, связь восстановлена. Можно продолжать жить в этом мире или начать заново.")
		command_input.editable = true
	else:
		command_input.editable = true
		return
	box.add_child(_button("Новое прохождение…", _confirm_new))
	box.add_child(_button("Сохранения и настройки", _select_tab.bind("Настройки")))

func _resume_autosave() -> void:
	var exists: bool = false
	for suffix: String in ["", ".bak1", ".bak2"]:
		if FileAccess.file_exists(autosave_path + suffix): exists = true
	if not exists: return
	var result: Dictionary = autosave_store.load_into(kernel)
	message = str(result.get("message", "Не удалось восстановить автосохранение."))
	autosave_protected = not result.get("ok", false) or message.contains("резервной")
	if result.get("ok", false) and not autosave_protected:
		message = "Продолжено последнее прохождение. " + message

func _autosave() -> void:
	if autosave_protected or autosave_store == null: return
	var result: Dictionary = autosave_store.save(kernel)
	if not result.get("ok", false):
		message = "Автосохранение: " + str(result.get("message", "ошибка записи"))
		if is_instance_valid(notice): notice.text = message

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_autosave()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()
		get_tree().quit()

func _process(delta: float) -> void:
	keyboard_poll += delta
	if keyboard_poll < 0.2 or not is_instance_valid(root_column): return
	keyboard_poll = 0.0
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): return
	var height: int = DisplayServer.virtual_keyboard_get_height()
	if height == keyboard_inset: return
	keyboard_inset = height
	var window_height: float = maxf(float(DisplayServer.window_get_size().y), 1.0)
	var inset: float = float(height) * size.y / window_height
	root_column.get_parent().offset_bottom = -inset

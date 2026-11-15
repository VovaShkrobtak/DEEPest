extends Control
## All simulation writes go through Kernel commands. Containers own all layout.
const Kernel = preload("res://src/core/kernel.gd")
const SaveStore = preload("res://src/adapters/save_store.gd")
const Parser = preload("res://src/application/parser.gd")
const Presentation = preload("res://src/application/presentation.gd")
const MapProjection = preload("res://src/application/map_projection.gd")
const VisualMap = preload("res://src/adapters/visual_map.gd")
const INK = Color("e9e5da")
const MUTED = Color("a1adae")
const AMBER = Color("d6ae68")
const BACKGROUND = Color("10191d")
const CARD = Color("182328")
const TABS = ["Мир", "Действия", "Вещи", "Тело", "Люди", "Журнал", "Знания", "Настройки"]
const QUICK_TABS = ["Мир", "Действия", "Вещи", "Тело"]
var kernel = Kernel.new(1998)
var save_store = SaveStore.new()
var autosave_path: String = "user://autosave.json"
var autosave_store
var autosave_protected: bool = false
var keyboard_inset: int = 0
var keyboard_poll: float = 0.0
var parser = Parser.new()
var presentation = Presentation.new()
var view: Dictionary = {}
var navigation_collapsed: bool = false
var status_collapsed: bool = false
var high_contrast: bool = false
var ui_sound_enabled: bool = false
var ui_audio: AudioStreamPlayer
var mobile_menu_open: bool = false
var snapshot: Dictionary = {}
var selected_tab: String = "Мир"
var text_scale: float = 1.0
var reduced_motion: bool = true
var portrait_mode: bool = false # Android: landscape by default.
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
var brand_label: Label
var notice: Label
var running_progress: ProgressBar
var running_text: Label
var action_panel: VBoxContainer
var mobile_status: VBoxContainer
var mobile_nav: HBoxContainer
var mobile_selector: OptionButton
var nav_toggle: Button
var status_toggle: Button
var action_timer: Timer
var mobile: bool = false
var rebuilding: bool = false
var _scroll_touch_active: bool = false
var _scroll_touch_index: int = -1
var _scroll_touch_start: Vector2 = Vector2.ZERO
var _scroll_touch_dragged: bool = false
var new_seed: int = 1998
var settings_path: String = "user://interface.cfg"

func _ready() -> void:
	autosave_store = SaveStore.new(autosave_path)
	_resume_autosave()
	get_tree().auto_accept_quit = false
	_load_settings()
	_apply_orientation()
	_update_design_scale()
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
	skin.set_color("font_disabled_color", "Button", Color("a2b3b8") if high_contrast else Color("728086"))
	skin.set_constant("separation", "VBoxContainer", 12)
	skin.set_constant("separation", "HBoxContainer", 16)
	for mode in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("25343a") if mode == "hover" else CARD
		style.border_color = AMBER if mode in ["pressed", "focus"] else (Color("6a858d") if high_contrast else Color("344247"))
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
	brand_label = _label("DEEPest", 27, INK)
	brand_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand_label.clip_text = true
	var brand: Label = brand_label
	brand.add_theme_font_override("font", load("res://assets/fonts/OpenSans-Semibold.ttf"))
	masthead.add_child(brand)
	nav_toggle = _button("≡ Разделы", _toggle_navigation)
	nav_toggle.autowrap_mode = TextServer.AUTOWRAP_OFF
	nav_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	nav_toggle.custom_minimum_size.x = 48
	masthead.add_child(nav_toggle)
	status_toggle = _button("Состояние", _toggle_status)
	status_toggle.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	status_toggle.custom_minimum_size.x = 48
	masthead.add_child(status_toggle)
	clock_label = _label("", 12, AMBER)
	clock_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	clock_label.clip_text = true
	clock_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	masthead.add_child(clock_label)
	root_column.add_child(_label("ПОЛЕВОЙ ДНЕВНИК  ·  ВЫЖИВАНИЕ БЕЗ СЮЖЕТА", 10, MUTED))
	root_column.add_child(HSeparator.new())
	mobile_selector = OptionButton.new()
	mobile_selector.custom_minimum_size.y = 48
	for tab in TABS: mobile_selector.add_item(tab)
	mobile_selector.item_selected.connect(func(index: int): mobile_menu_open = false; _select_tab(TABS[index]))
	root_column.add_child(mobile_selector)
	mobile_status = VBoxContainer.new()
	root_column.add_child(mobile_status)


	layout = HBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(layout)
	navigation = VBoxContainer.new()
	navigation.custom_minimum_size.x = 160
	layout.add_child(navigation)
	main_scroll = ScrollContainer.new()
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_scroll.scroll_deadzone = 12
	# An actual touch target, not a 4px-wide decorative scrollbar.
	var scroll_bar: VScrollBar = main_scroll.get_v_scroll_bar()
	scroll_bar.custom_minimum_size.x = 36
	var scrollbar_track := StyleBoxFlat.new()
	scrollbar_track.bg_color = Color("15252a")
	scrollbar_track.set_corner_radius_all(7)
	scrollbar_track.content_margin_left = 4
	scrollbar_track.content_margin_right = 4
	scroll_bar.add_theme_stylebox_override("scroll",scrollbar_track)
	for state_name in ["grabber","grabber_highlight","grabber_pressed"]:
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color("9fbac4") if state_name=="grabber" else AMBER
		thumb.set_corner_radius_all(8)
		thumb.content_margin_left = 5
		thumb.content_margin_right = 5
		scroll_bar.add_theme_stylebox_override(state_name,thumb)
	main_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(main_scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.add_child(page)
	side = VBoxContainer.new()
	side.custom_minimum_size.x = 248
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
	mobile_nav = HBoxContainer.new()
	mobile_nav.add_theme_constant_override("separation", 4)
	root_column.add_child(mobile_nav)

func _label(value: String, font_size: int = 16, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(font_size * text_scale))
	label.add_theme_color_override("font_color", Color("d9e5e9") if high_contrast and color == MUTED else color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# PASS allows wheel/trackpad scroll to reach the parent ScrollContainer.
	# Finger drags are handled by _input and never activate a button.
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.pressed.connect(func() -> void:
		if _scroll_touch_dragged: return
		_play_ui_click()
		callback.call()
	)
	return button


func _play_ui_click() -> void:
	# Purely interface audio: never submit a world acoustic event.
	if not ui_sound_enabled: return
	if not is_instance_valid(ui_audio):
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = 22050.0
		generator.buffer_length = 0.1
		ui_audio = AudioStreamPlayer.new()
		ui_audio.stream = generator
		ui_audio.volume_db = -24.0
		add_child(ui_audio)
	ui_audio.stop()
	ui_audio.play()
	var playback := ui_audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null: return
	for index in range(mini(320, playback.get_frames_available())):
		var t: float = float(index) / 22050.0
		var sample: float = sin(TAU * 520.0 * t) * exp(-115.0 * t) * 0.07
		playback.push_frame(Vector2(sample, sample))

func _flash_notice() -> void:
	if reduced_motion or not is_instance_valid(notice): return
	notice.modulate.a = 0.6
	var tween := create_tween()
	tween.tween_property(notice, "modulate:a", 1.0, 0.16)

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _section(parent: Node, title: String, body: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.set_corner_radius_all(6)
	style.content_margin_left = 12 if mobile else 18
	style.content_margin_right = 12 if mobile else 18
	style.content_margin_top = 12
	style.content_margin_bottom = 14
	if high_contrast:
		style.set_border_width_all(1)
		style.border_color = Color("526a72")
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
	_clear(mobile_status)
	_clear(mobile_nav)
	mobile = size.x < 980 or get_window().size.x < 980 or OS.get_name() == "Android" or text_scale > 1.4
	view = presentation.build(snapshot, kernel.available_actions())
	for tab in TABS:
		var tab_button := _button(("●  " if tab == selected_tab else "") + tab, _select_tab.bind(tab))
		if tab == selected_tab: tab_button.add_theme_color_override("font_color", AMBER)
		navigation.add_child(tab_button)
	clock_label.text = str(snapshot.get("time_label", "08:00")) if mobile else "%s\n%s" % [snapshot.get("time_label", "08:00"), snapshot.get("date_label", "14 ноября 1998")]
	notice.text = message
	notice.max_lines_visible = 2
	_build_mobile_status()
	_build_mobile_navigation()
	page.add_child(_label("МЕСТО / ДЕНЬ %s" % snapshot.get("day", 1), 11, MUTED))
	page.add_child(_label(str(snapshot.get("location_title", "Неизвестное место")), 26, INK))
	if view.get("threat_observed", false):
		_render_signals(page, view.get("environment", []), true)
	_terminal_banner()
	if not snapshot.get("action", {}).is_empty(): _running_action()
	match selected_tab:
		"Мир": _world_page()
		"Действия": _actions_page()
		"Вещи": _items_page()
		"Тело": _body_page()
		"Люди":
			_entries(snapshot.get("people", []), str(view.get("people_empty", "Никого не видно.")))
			_actions(page, ["Люди"])
		"Журнал": _journal_page()
		"Знания": _knowledge_page()
		"Настройки": _settings_page()
	_build_conditions(side)
	_responsive()

func _build_mobile_navigation() -> void:
	for tab in QUICK_TABS:
		var label_text: String = "● " + tab if selected_tab == tab else tab
		var tab_button := _button(label_text, _select_tab.bind(tab))
		tab_button.add_theme_font_size_override("font_size", int(12 * text_scale))
		tab_button.custom_minimum_size.y = 52
		mobile_nav.add_child(tab_button)
	var more := _button("Ещё ▾", _toggle_mobile_menu)
	more.add_theme_font_size_override("font_size", int(12 * text_scale))
	more.custom_minimum_size.y = 52
	mobile_nav.add_child(more)

func _build_mobile_status() -> void:
	if status_collapsed: return
	var warnings: Array = view.get("status", [])
	var lines: Array[String] = []
	for record: Dictionary in warnings.slice(0, 2):
		lines.append(str(record.get("text", "")))
	if lines.is_empty(): lines.append(str(view.get("no_symptoms", "")))
	var box := _section(mobile_status, "ВАШИ ОЩУЩЕНИЯ", "\n".join(lines))
	if int(view.get("status_more", 0)) > 0 or warnings.size() > 2:
		box.add_child(_button("Открыть состояние →", _select_tab.bind("Тело")))

func _toggle_navigation() -> void:
	if mobile:
		_toggle_mobile_menu()
	else:
		navigation_collapsed = not navigation_collapsed
		_save_settings()
		_responsive()

func _toggle_mobile_menu() -> void:
	mobile_menu_open = not mobile_menu_open
	_responsive()

func _toggle_status() -> void:
	status_collapsed = not status_collapsed
	_save_settings()
	_rebuild_content()


func _render_signals(parent: Node, signals: Array, only_danger: bool = false) -> void:
	if signals.is_empty(): return
	var chosen: Array = []
	for observation: Dictionary in signals:
		if only_danger and str(observation.get("severity", "")) != "danger": continue
		chosen.append(observation)
	if chosen.is_empty(): return
	var box := _section(parent, "ЗАМЕЧЕННЫЕ ПРИЗНАКИ" if only_danger else "ВАШИ ОЩУЩЕНИЯ")
	for observation: Dictionary in chosen:
		var important: bool = str(observation.get("severity", "")) in ["danger", "warning"]
		var prefix: String = "!  " if important else "·  "
		box.add_child(_label(prefix + str(observation.get("text", "")), 14, AMBER if important else INK))


func _select_tab(tab: String) -> void:
	selected_tab = tab
	main_scroll.scroll_vertical = 0
	_rebuild_content()


func _world_page() -> void:
	_section(page, "ЗДЕСЬ И СЕЙЧАС", "\n".join(snapshot.get("description", [])))
	_build_visual_map()
	if not view.get("urgent_actions", []).is_empty():
		_section(page, "НЕМЕДЛЕННЫЕ ВОЗМОЖНОСТИ", "Доступные варианты основаны на замеченных признаках, а не на скрытом положении угроз.")
		for action: Dictionary in view.get("urgent_actions", []):
			_action_card(page, action)
	var main: Array = []
	for descriptor: Dictionary in view.get("actions", []):
		if str(descriptor.id) in ["inspect", "listen", "drink", "bandage"] and bool(descriptor.get("enabled", false)):
			main.append(descriptor)
	for descriptor: Dictionary in main.slice(0, 4):
		_action_card(page, descriptor)
	page.add_child(_button("Все действия и взаимодействия →", _select_tab.bind("Действия")))
	if not snapshot.get("objects", []).is_empty():
		page.add_child(_label("ЗАМЕЧЕННЫЕ ДЕТАЛИ", 12, MUTED))
		_entries(snapshot.get("objects", []), "")

func _build_visual_map() -> void:
	var diagram: Dictionary = MapProjection.new().build(snapshot)
	if diagram.is_empty():
		return
	var box: VBoxContainer = _section(page, "СХЕМА МЕСТА")
	var visual = VisualMap.new()
	visual.custom_minimum_size.y = 275.0 if mobile else 305.0
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visual.set_diagram(diagram)
	visual.route_selected.connect(_on_map_route_selected)
	box.add_child(visual)
	box.add_child(_label("Условная планировка; комнаты и положение мебели пока не моделируются. "
		+ "Точки двора обозначают реальные маршруты, но не географические координаты.", 12, MUTED))
	var nearby: Array[String] = []
	for person: Dictionary in snapshot.get("people", []):
		nearby.append(str(person.get("title", "Человек")))
	if not nearby.is_empty():
		box.add_child(_label("Видно рядом: " + ", ".join(nearby), 12, INK))
	var heard: Array = snapshot.get("hearing", [])
	if not heard.is_empty():
		box.add_child(_label("Слышно: " + str(heard[0].get("text", "Неясный звук")), 12, AMBER))
	var warnings: Array = snapshot.get("threat_warnings", [])
	if not warnings.is_empty():
		box.add_child(_label("Признаки опасности: " + str(warnings[0]), 12, AMBER))


func _on_map_route_selected(target: String) -> void:
	# A schematic never bypasses the authoritative action catalogue.
	for descriptor: Dictionary in view.get("actions", []):
		if str(descriptor.get("id", "")) == "move:" + target and bool(descriptor.get("enabled", false)):
			_perform(str(descriptor.id), descriptor.get("parameters", {}))
			return


func _actions_page() -> void:
	_section(page, "ЧТО МОЖНО СДЕЛАТЬ", "Доступность проверяет симуляция при выборе. Время и трудность ниже — приблизительная оценка, не гарантия исхода.")
	_actions(page)

func _actions(parent: Node, categories: Array = []) -> void:
	if not snapshot.get("alive", true): return
	var groups: Dictionary = {}
	for descriptor: Dictionary in view.get("actions", []):
		if not snapshot.get("conscious", true) and str(descriptor.id) != "wait": continue
		var category: String = str(descriptor.get("category", "Прочее"))
		if not categories.is_empty() and category not in categories: continue
		if not groups.has(category): groups[category] = []
		groups[category].append(descriptor)
	var titles: Dictionary = {"Мир":"НАБЛЮДАТЬ И ЖДАТЬ", "Опасность":"ПРИЗНАКИ ОПАСНОСТИ", "Путь":"ПЕРЕДВИЖЕНИЕ", "Ремесло":"РАБОТА И РЕМОНТ", "Вода и еда":"ПИТАНИЕ И ВОДА", "Убежище":"УКРЫТИЕ", "Тело":"ЗАБОТА О СЕБЕ", "Вещи":"СНАРЯЖЕНИЕ", "Предметы":"ОКРУЖАЮЩИЕ ПРЕДМЕТЫ", "Люди":"ОБЩЕНИЕ"}
	for category: String in groups:
		parent.add_child(_label(str(titles.get(category, category.to_upper())), 12, AMBER))
		var grid := GridContainer.new()
		grid.columns = 1 if mobile else 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		parent.add_child(grid)
		for descriptor: Dictionary in groups[category]:
			_action_card(grid, descriptor)

func _action_card(parent: Node, descriptor: Dictionary) -> void:
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var button := _button(str(descriptor.get("title", descriptor.get("id", ""))), _perform.bind(str(descriptor.id), descriptor.get("parameters", {})))
	button.set_meta("action_id", descriptor.id)
	button.disabled = not bool(descriptor.get("enabled", true))
	card.add_child(button)
	var time_hint: String = str(descriptor.get("time_hint", ""))
	var detail: String = str(descriptor.get("description", "")) if not button.disabled else str(descriptor.get("reason", "Сейчас недоступно"))
	var commentary: String = time_hint + (" · " if not time_hint.is_empty() and not detail.is_empty() else "") + detail
	if not commentary.is_empty(): card.add_child(_label(commentary, 12, MUTED))


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
	running_text = _label("Время проходит. Работу можно прервать; затраты и изменения останутся.", 12, MUTED)
	box.add_child(running_text)
	box.add_child(_button("Прервать действие", _cancel))



func _items_page() -> void:
	var inventory: Dictionary = snapshot.get("inventory",{})
	_section(page,"ПЕРЕНОСИМЫЕ ВЕЩИ",str(inventory.get("load_text",""))+"\n"+str(inventory.get("water_text","")))
	_stock_grid(inventory.get("items",[]),"ground_drop","С СОБОЙ",
		"Ваши вещи. Можно оставить одну единицу или целую стопку; груз разгрузится только после выполнения действия.")
	_stock_grid(snapshot.get("ground_items",[]),"ground_take","НА ЭТОМ МЕСТЕ",
		"Вещи останутся именно в этом доме, на улице или в другой локации. Их можно подобрать позже.")
	_assembly_builder(inventory.get("items",[]))
	var constructions: Array = snapshot.get("assemblies",[])
	if not constructions.is_empty():
		var structure_box: VBoxContainer = _section(page,"СОБРАННЫЕ КОНСТРУКЦИИ","Постоянные объекты этого места. Они не занимают место в рюкзаке.")
		for structure: Dictionary in constructions:
			structure_box.add_child(_label(str(structure.title)+" · "+str(structure.text),13))
	_actions(page,["Конструкции"])
	_entries(inventory.get("equipment",[]),"")
	page.add_child(_label("СНАРЯЖЕНИЕ, ПИТАНИЕ И РАБОТА",12,AMBER))
	_actions(page,["Вещи","Вода и еда","Ремесло"])

func _stock_grid(entries: Array,verb: String,title: String,explanation: String) -> void:
	var section: VBoxContainer = _section(page,title,explanation)
	if entries.is_empty():
		section.add_child(_label("Пока ничего не видно." if verb=="ground_take" else "Снаряжение пусто.",13,MUTED))
		return
	var grid := GridContainer.new()
	grid.columns = 1 if main_scroll.size.x < 470 else (2 if mobile else 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	section.add_child(grid)
	for record: Dictionary in entries:
		var id: String = str(record.get("id",""))
		var quantity: int = int(record.get("quantity",0))
		if quantity<=0: continue
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tile_style := StyleBoxFlat.new()
		tile_style.bg_color = Color("203036")
		tile_style.set_corner_radius_all(8)
		tile_style.content_margin_left = 10
		tile_style.content_margin_right = 10
		tile_style.content_margin_top = 12
		tile_style.content_margin_bottom = 10
		tile.add_theme_stylebox_override("panel",tile_style)
		grid.add_child(tile)
		var content := VBoxContainer.new()
		tile.add_child(content)
		content.add_child(_label(str(record.get("title",id)),15,INK))
		content.add_child(_label("× %d  ·  %.2f кг" % [quantity,float(record.get("total_mass_kg",0.0))],12,MUTED))
		content.add_child(_label("Оставить здесь:" if verb=="ground_drop" else "Подобрать:",12,AMBER))
		var commands := HBoxContainer.new()
		commands.add_theme_constant_override("separation",6)
		content.add_child(commands)
		var once: Button = _button("1",_perform.bind(verb+":"+id,{"amount":1}))
		once.tooltip_text = "Оставить одну единицу" if verb=="ground_drop" else "Подобрать одну единицу"
		commands.add_child(once)
		if quantity>1:
			var whole: Button = _button("Всё",_perform.bind(verb+":"+id,{"amount":quantity}))
			whole.tooltip_text = "Оставить всю стопку" if verb=="ground_drop" else "Подобрать всё"
			commands.add_child(whole)

func _assembly_builder(entries: Array) -> void:
	var box: VBoxContainer = _section(page,"ВЗАИМОДЕЙСТВИЯ 2.0 · СБОРКА",
		"Выберите две детали и материал крепления. Сборка зависит от количества материалов, состояния рук и инструмента; готовая конструкция останется на месте.")
	var available: Dictionary = {}
	for entry: Dictionary in entries:
		available[str(entry.id)] = entry
	var selectors := GridContainer.new()
	selectors.columns = 1 if main_scroll.size.x<600 else 3
	selectors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_theme_constant_override("h_separation",8)
	selectors.add_theme_constant_override("v_separation",8)
	box.add_child(selectors)
	var a: OptionButton = _material_choice(selectors,"Деталь 1",available,["wood","cloth","wire","parts"])
	var b: OptionButton = _material_choice(selectors,"Деталь 2",available,["wood","cloth","wire","parts"])
	var link: OptionButton = _material_choice(selectors,"Соединить при помощи",available,["wire","cloth","parts"])
	var button: Button = _button("Собрать конструкцию",_assemble_selected.bind(a,b,link))
	button.disabled = a.disabled or b.disabled or link.disabled
	box.add_child(button)

func _material_choice(parent: Node,title: String,available: Dictionary,allowed: Array[String]) -> OptionButton:
	var field := VBoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	field.add_child(_label(title,12,MUTED))
	var chooser := OptionButton.new()
	chooser.custom_minimum_size.y = 48
	chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chooser.clip_text = true
	for key: String in allowed:
		if not available.has(key): continue
		var index: int = chooser.item_count
		chooser.add_item(str(available[key].get("title",key)))
		chooser.set_item_metadata(index,key)
	if chooser.item_count==0:
		chooser.add_item("Нет материалов")
		chooser.disabled = true
	field.add_child(chooser)
	return chooser

func _assemble_selected(a: OptionButton,b: OptionButton,link: OptionButton) -> void:
	if a.disabled or b.disabled or link.disabled: return
	_perform("assembly_build",{"a":str(a.get_selected_metadata()),
		"b":str(b.get_selected_metadata()),"link":str(link.get_selected_metadata())})

func _body_page() -> void:
	var body: Dictionary = snapshot.get("body", {})
	_section(page, "САМООЩУЩЕНИЕ", str(body.get("condition", "Вы прислушиваетесь к себе.")))
	_render_signals(page, view.get("status", []))
	if view.get("status", []).is_empty(): _section(page, "ОЩУЩЕНИЯ", str(view.get("no_symptoms", "")))
	if int(view.get("status_more", 0)) > 0:
		for sensation in body.get("sensations", []):
			page.add_child(_label(str(sensation), 14))
		for warning in body.get("warnings", []):
			page.add_child(_label(str(warning), 14, AMBER))
	_entries(body.get("details", []), "")
	_actions(page, ["Тело"])


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
	var entries: Array = snapshot.get("journal", [])
	var memory := _section(page, "ПАМЯТЬ О ПРОШЕДШЕМ", "Это записи прошлых наблюдений. Обстановка могла измениться с тех пор.")
	var latest: Array = entries.slice(maxi(0, entries.size() - 6))
	latest.reverse()
	for entry: Dictionary in latest:
		memory.add_child(_label(str(entry.get("time_label", "")) + " · " + str(entry.get("text", "")), 13))
	_section(page, "ВРЕМЯ И ВЫБОР", "Мир меняется, пока вы действуете. Осмотритесь, оцените ощущения и выберите следующий шаг. Длительное действие можно прервать; уже прошедшее время не возвращается.")
	_section(page, "ВОДА", "Прозрачность и запах не доказывают безопасность. Кипячение требует времени и топлива; химические примеси от него не исчезают.")
	_section(page, "ХОЛОД И НОЧЛЕГ", "Влажная одежда и сквозняк усиливают холод. Закрытое окно уменьшает приток воздуха, но помещение не согревается мгновенно. Дымящая печь — повод проверить вентиляцию.")
	_section(page, "ЗАРАЖЁННЫЕ", "Шум может привлечь заражённых, но они не знают, где вы, без признаков присутствия. Прислушивайтесь, следите за обстановкой и выбирайте момент для работы. Отступление занимает время.")
	_section(page, "СВОБОДНЫЙ ВВОД", "Введите название доступного действия, например «осмотреться». Если команда неясна, мир останется на месте. Все действия доступны и через кнопки.")


func _build_conditions(parent: Node) -> void:
	var box := _section(parent, "УСЛОВИЯ", str(snapshot.get("conditions", {}).get("weather_label", "")) + "\n" + str(snapshot.get("conditions", {}).get("temp_label", "")))
	box.add_child(_label("Время проходит при игровых действиях", 12, MUTED))
	var symptoms: Array = view.get("status", [])
	var senses := _section(parent, "ВАШИ ОЩУЩЕНИЯ", str(view.get("no_symptoms", "")) if symptoms.is_empty() else "")
	for record: Dictionary in symptoms:
		senses.add_child(_label(str(record.get("text", "")), 13, AMBER if record.get("severity", "") == "warning" else INK))
	if int(view.get("status_more", 0)) > 0:
		senses.add_child(_button("Все ощущения →", _select_tab.bind("Тело")))
	var inv: Dictionary = snapshot.get("inventory", {})
	_section(parent, "С СОБОЙ", str(inv.get("water_text", "")) + "\n" + str(inv.get("load_text", "")))
	parent.add_child(_label("ОФЛАЙН · БЕЗ КВЕСТОВ\nСЕВЕРНАЯ ПРОВИНЦИЯ, 1998", 10, MUTED))


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
	var contrast := CheckButton.new()
	contrast.text = "Высокий контраст"
	contrast.button_pressed = high_contrast
	contrast.custom_minimum_size.y = 48
	contrast.toggled.connect(_set_contrast)
	box.add_child(contrast)
	var motion := CheckButton.new()
	motion.text = "Сокращённое движение"
	motion.button_pressed = reduced_motion
	motion.custom_minimum_size.y = 48
	motion.toggled.connect(func(value: bool): reduced_motion = value; _save_settings())
	box.add_child(motion)
	var sound := CheckButton.new()
	sound.text = "Тихие звуки интерфейса (не слышны в игровом мире)"
	sound.button_pressed = ui_sound_enabled
	sound.custom_minimum_size.y = 48
	sound.toggled.connect(func(enabled: bool): ui_sound_enabled = enabled; _save_settings())
	box.add_child(sound)
	var orientation := _section(page, "ОРИЕНТАЦИЯ ЭКРАНА", "Android: по умолчанию горизонтально. Вертикальный режим включается вручную.")
	var portrait_toggle := CheckButton.new()
	portrait_toggle.text = "Вертикальный режим (Android)"
	portrait_toggle.button_pressed = portrait_mode
	portrait_toggle.custom_minimum_size.y = 48
	portrait_toggle.toggled.connect(_set_portrait_mode)
	orientation.add_child(portrait_toggle)
	var panels := _section(page, "ПАНЕЛИ", "На компьютере панели разделов и ощущений скрываются независимо. На телефоне вкладки расположены у нижнего края.")
	panels.add_child(_button("Сбросить расположение панелей", _reset_panels))
	_section(page, "УПРАВЛЕНИЕ", "Ctrl + 1…8 — открыть вкладку. Esc — закрыть мобильный список разделов. Командная строка работает полностью офлайн.")
	page.add_child(_button("Диагностика разработчика", _toggle_debug))
	if debug_visible:
		_section(page, "DEBUG · СКРЫТЫЕ ДАННЫЕ МОДЕЛИ", JSON.stringify(kernel.debug_snapshot(), "  "))

func _perform(id: String, parameters: Dictionary = {}) -> void:
	var remembered_scroll: int = main_scroll.scroll_vertical
	var result: Dictionary = kernel.command(id, parameters)
	message = str(result.get("message", ""))
	if result.get("ok", false):
		autosave_protected = false
		if kernel.snapshot().get("action", {}).is_empty(): _autosave()
	_refresh()
	call_deferred("_restore_scroll_position",remembered_scroll)
	_flash_notice()

func _restore_scroll_position(value: int) -> void:
	if is_instance_valid(main_scroll): main_scroll.scroll_vertical = value

func _live_notice(observation: Dictionary, fallback: String) -> String:
	# Use the public observation only; no hidden threat coordinates or domain state.
	var nearby: Array = observation.get("threat_warnings", [])
	if not nearby.is_empty(): return "ВНИМАНИЕ · " + str(nearby[0])
	for source in ["conditions", "body"]:
		var warnings: Array = observation.get(source, {}).get("warnings", [])
		if not warnings.is_empty(): return "САМОЧУВСТВИЕ / СРЕДА · " + str(warnings[0])
	return fallback

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
		var remembered_scroll: int = main_scroll.scroll_vertical
		_refresh()
		call_deferred("_restore_scroll_position",remembered_scroll)
		return
	# Keep controls stable while fingers are down; update only the running indicators.
	clock_label.text = str(snapshot.get("time_label", "")) if mobile else "%s\n%s" % [snapshot.get("time_label", ""), snapshot.get("date_label", "")]
	if is_instance_valid(running_progress):
		running_progress.value = float(snapshot.action.get("elapsed_s", 0))
	if is_instance_valid(running_text):
		running_text.text = "Время проходит. Работу можно прервать; затраты и изменения останутся."
	notice.text = _live_notice(snapshot, message)

func _cancel() -> void:
	var result: Dictionary = kernel.cancel()
	message = str(result.get("message", "Действие прервано"))
	if result.get("ok", false):
		autosave_protected = false
		_autosave()
	_refresh()
	_flash_notice()

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
	dialog.confirmed.connect(func(): kernel = Kernel.new(new_seed); message = "Новый мир. Только выживание."; selected_tab = "Мир"; autosave_protected = false; _autosave(); _refresh(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(mini(480, int(size.x) - 32), 220))

func _set_contrast(value: bool) -> void:
	high_contrast = value
	_install_theme()
	_save_settings()
	_rebuild_content()

func _reset_panels() -> void:
	navigation_collapsed = false
	status_collapsed = false
	mobile_menu_open = false
	_save_settings()
	_rebuild_content()

func _set_scale(value: float) -> void:
	text_scale = value
	_install_theme()
	_save_settings()
	_rebuild_content()

func _toggle_debug() -> void:
	debug_visible = not debug_visible
	_rebuild_content()

func _apply_orientation() -> void:
	# Android-only: respect saved preference; do not rotate desktop windows.
	if OS.get_name() == "Android":
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT if portrait_mode else DisplayServer.SCREEN_LANDSCAPE)

func _set_portrait_mode(enabled: bool) -> void:
	portrait_mode = enabled
	_save_settings()
	_apply_orientation()
	_rebuild_content()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("interface", "text_scale", text_scale)
	config.set_value("interface", "reduced_motion", reduced_motion)
	config.set_value("interface", "portrait_mode", portrait_mode)
	config.set_value("interface", "navigation_collapsed", navigation_collapsed)
	config.set_value("interface", "status_collapsed", status_collapsed)
	config.set_value("interface", "high_contrast", high_contrast)
	config.set_value("interface", "ui_sound_enabled", ui_sound_enabled)
	config.save(settings_path)

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		text_scale = clampf(float(config.get_value("interface", "text_scale", 1.0)), 1.0, 2.0)
		reduced_motion = bool(config.get_value("interface", "reduced_motion", true))
		portrait_mode = bool(config.get_value("interface", "portrait_mode", false))
		navigation_collapsed = bool(config.get_value("interface", "navigation_collapsed", false))
		status_collapsed = bool(config.get_value("interface", "status_collapsed", false))
		high_contrast = bool(config.get_value("interface", "high_contrast", false))
		ui_sound_enabled = bool(config.get_value("interface", "ui_sound_enabled", false))

func _update_design_scale() -> void:
	# Portrait mode has its own logical design size: landscape 1280x720 would
	# otherwise become a 1280x2700 canvas and shrink touch controls to unreadability.
	var window: Window = get_window()
	var portrait: bool = window.size.y > window.size.x
	var compact_landscape: bool = OS.get_name() == "Android" or window.size.x < 1100
	var desired: Vector2i = Vector2i(420, 900) if portrait else (Vector2i(960, 540) if compact_landscape else Vector2i(1280, 720))
	if window.content_scale_size != desired:
		window.content_scale_size = desired


func _responsive() -> void:
	_update_design_scale()
	if not is_instance_valid(navigation) or rebuilding: return
	var should_mobile: bool = size.x < 980 or get_window().size.x < 980 or OS.get_name() == "Android" or text_scale > 1.4
	if should_mobile != mobile:
		rebuilding = true
		mobile = should_mobile
		_rebuild_content()
		rebuilding = false
	navigation.visible = not mobile and not navigation_collapsed
	side.visible = not mobile and not status_collapsed
	mobile_status.visible = mobile and not status_collapsed
	mobile_nav.visible = mobile
	mobile_selector.visible = mobile and mobile_menu_open
	if mobile_selector.visible:
		mobile_selector.select(TABS.find(selected_tab))
	brand_label.add_theme_font_size_override("font_size", int((18 if mobile else 27) * text_scale))
	nav_toggle.text = "≡" if mobile else ("≡ Разделы" if navigation_collapsed else "◀ Разделы")
	status_toggle.text = ("◉" if status_collapsed else "◌") if mobile else ("◉ Состояние" if status_collapsed else "◌ Скрыть")


func _terminal_banner() -> void:
	var box: VBoxContainer
	if not snapshot.get("alive", true):
		box = _section(page, "ПЕРСОНАЖ ПОГИБ", "Жизнь этого выжившего закончилась. Здесь нет финала: другое прохождение начнётся в новом мире.")
		command_input.editable = false
	elif not snapshot.get("conscious", true):
		box = _section(page, "БЕЗ СОЗНАНИЯ", "Вы не можете действовать. Дайте времени пройти; исход зависит от условий и состояния организма.")
		box.add_child(_button("Дать времени пройти", _perform.bind("wait", {})))
		command_input.editable = false
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

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	if not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE and mobile_menu_open:
		mobile_menu_open = false
		_responsive()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed or event.meta_pressed:
		var index: int = int(event.keycode) - KEY_1
		if index >= 0 and index < TABS.size():
			_select_tab(TABS[index])
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# Process ScreenDrag at viewport level: Buttons otherwise absorb drag,
	# so a finger moving over their faces cannot scroll the action list.
	if not is_instance_valid(main_scroll): return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_scroll_touch_dragged = false
			var bar: VScrollBar = main_scroll.get_v_scroll_bar()
			_scroll_touch_active = main_scroll.get_global_rect().has_point(touch.position) and not bar.get_global_rect().has_point(touch.position)
			_scroll_touch_index = touch.index if _scroll_touch_active else -1
			_scroll_touch_start = touch.position
		elif touch.index==_scroll_touch_index:
			_scroll_touch_active = false
			_scroll_touch_index = -1
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if not _scroll_touch_active or drag.index!=_scroll_touch_index: return
		if (drag.position-_scroll_touch_start).length()>12.0: _scroll_touch_dragged = true
		if _scroll_touch_dragged:
			main_scroll.scroll_vertical = maxi(0,main_scroll.scroll_vertical-roundi(drag.relative.y))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.pressed and mouse.button_index==MOUSE_BUTTON_LEFT: _scroll_touch_dragged = false

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

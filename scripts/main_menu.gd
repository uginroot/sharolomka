extends Control

const Maps = preload("res://scripts/maps.gd")
const Icons = preload("res://scripts/icons.gd")
const TouchScroll = preload("res://scripts/touch_scroll.gd")

var scroll: ScrollContainer
var list: VBoxContainer
var lbl_u: Label
var btn_profile: Button
var legacy_root: VBoxContainer
var legacy_box: VBoxContainer
var legacy_stars: Label
var profiles_root: VBoxContainer
var profiles_box: VBoxContainer
var del_confirm: ConfirmationDialog
var del_slot := 0
var confirm: ConfirmationDialog
var margin: MarginContainer
var main_box: VBoxContainer
var settings_box: VBoxContainer
var settings_root: VBoxContainer
var settings_scroll: ScrollContainer


func _ready() -> void:
	# меню статично: кадры рисуются только при изменениях
	OS.low_processor_usage_mode = true

	var bg := ColorRect.new()
	bg.color = GameData.C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	_apply_margins()
	get_viewport().size_changed.connect(_apply_margins)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)

	var title := Label.new()
	title.text = tr("ШАРОЛОМКА")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", GameData.font_bold)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(title)

	var ur := HBoxContainer.new()
	ur.alignment = BoxContainer.ALIGNMENT_CENTER
	ur.add_theme_constant_override("separation", 12)
	vb.add_child(ur)
	btn_profile = Button.new()
	btn_profile.custom_minimum_size = Vector2(0, 50)
	btn_profile.pressed.connect(_show_screen.bind("profiles"))
	ur.add_child(btn_profile)
	var pill := PanelContainer.new()
	pill.theme_type_variation = "Pill"
	ur.add_child(pill)
	lbl_u = Label.new()
	lbl_u.add_theme_font_override("font", GameData.font_bold)
	lbl_u.add_theme_font_size_override("font_size", 28)
	lbl_u.add_theme_color_override("font_color", GameData.C_GOLD)
	pill.add_child(lbl_u)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	sc.add_child(list)
	scroll = sc
	var ts = TouchScroll.new()   # прокрутка списка уровней пальцем, даже с кнопки «Играть»
	ts.target = sc
	add_child(ts)

	var ver := Label.new()
	ver.text = "v" + str(ProjectSettings.get_setting("application/config/version", "dev"))
	ver.theme_type_variation = "Muted"
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_font_size_override("font_size", 17)
	ver.name = "Version"
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	vb.add_child(brow)
	var bleg := Button.new()
	bleg.text = tr("Наследие")
	bleg.theme_type_variation = "AccentButton"
	bleg.custom_minimum_size.y = 58
	bleg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bleg.pressed.connect(_show_screen.bind("legacy"))
	brow.add_child(bleg)
	var bset := Button.new()
	bset.text = tr("Настройки")
	bset.custom_minimum_size.y = 58
	bset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bset.pressed.connect(_show_settings.bind(true))
	brow.add_child(bset)
	vb.add_child(ver)
	main_box = vb

	# --- экран настроек: прокручиваемый список + кнопки внизу
	settings_root = VBoxContainer.new()
	settings_root.add_theme_constant_override("separation", 12)
	settings_root.visible = false
	margin.add_child(settings_root)
	settings_scroll = ScrollContainer.new()
	settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_root.add_child(settings_scroll)
	settings_box = VBoxContainer.new()
	settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_box.add_theme_constant_override("separation", 14)
	settings_scroll.add_child(settings_box)
	var ts2 = TouchScroll.new()
	ts2.target = settings_scroll
	add_child(ts2)
	var reset := Button.new()
	reset.text = tr("Сбросить весь прогресс")
	reset.custom_minimum_size.y = 54
	reset.modulate = Color(1, 0.75, 0.75, 0.85)
	reset.pressed.connect(_ask_reset)
	settings_root.add_child(reset)
	var back := Button.new()
	back.text = tr("Назад")
	back.theme_type_variation = "AccentButton"
	back.custom_minimum_size.y = 60
	back.pressed.connect(_show_settings.bind(false))
	settings_root.add_child(back)

	legacy_root = _screen_root(tr("Наследие"))
	var lp := PanelContainer.new()
	lp.theme_type_variation = "Pill"
	lp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	legacy_root.add_child(lp)
	legacy_root.move_child(lp, 1)
	legacy_stars = Label.new()
	legacy_stars.add_theme_font_override("font", GameData.font_bold)
	legacy_stars.add_theme_font_size_override("font_size", 28)
	legacy_stars.add_theme_color_override("font_color", GameData.C_GOLD)
	lp.add_child(legacy_stars)
	legacy_box = _screen_list(legacy_root)
	profiles_root = _screen_root(tr("Профили"))
	profiles_box = _screen_list(profiles_root)
	del_confirm = ConfirmationDialog.new()
	del_confirm.title = tr("Удалить")
	del_confirm.dialog_text = tr("Удалить профиль?")
	del_confirm.ok_button_text = tr("Удалить")
	del_confirm.cancel_button_text = tr("Отмена")
	add_child(del_confirm)
	del_confirm.confirmed.connect(_do_delete_slot)

	confirm = ConfirmationDialog.new()
	confirm.title = tr("Сброс")
	confirm.dialog_text = tr("Удалить весь прогресс?")
	confirm.ok_button_text = tr("Удалить")
	confirm.cancel_button_text = tr("Отмена")
	add_child(confirm)
	confirm.confirmed.connect(_do_reset)
	_fill()
	if GameData.has_meta("open_settings"):
		GameData.remove_meta("open_settings")
		_show_settings(true)


## Экран-подложка: заголовок, прокручиваемый список, кнопка «Назад».
func _screen_root(title_text: String) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.visible = false
	margin.add_child(root)
	var t := Label.new()
	t.text = title_text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", GameData.font_bold)
	t.add_theme_font_size_override("font_size", 44)
	root.add_child(t)
	var back := Button.new()
	back.text = tr("Назад")
	back.theme_type_variation = "AccentButton"
	back.custom_minimum_size.y = 60
	back.pressed.connect(_show_screen.bind("main"))
	root.add_child(back)
	return root


func _screen_list(root: VBoxContainer) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	root.move_child(sc, root.get_child_count() - 2)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	sc.add_child(box)
	var ts = TouchScroll.new()
	ts.target = sc
	add_child(ts)
	return box


func _show_screen(name: String) -> void:
	main_box.visible = name == "main"
	settings_root.visible = name == "settings"
	legacy_root.visible = name == "legacy"
	profiles_root.visible = name == "profiles"
	match name:
		"main":
			_fill()
		"settings":
			_fill_settings()
		"legacy":
			_fill_legacy()
		"profiles":
			_fill_profiles()


## «Наследие»: ветки — цепочки узлов слева направо (каждый требует предыдущий).
## «Наследие» — по образцу прокачки: ветки карточками, каждое улучшение на своей подложке — название и уровень,
## описание, строка «значение: сейчас → после покупки» и кнопка ★ (яркая, если хватает звёзд).
func _fill_legacy() -> void:
	for c in legacy_box.get_children():
		c.queue_free()
	legacy_stars.text = "★ %d" % GameData.stars
	var intro := Label.new()
	intro.text = tr("★ даются за цели уровней и за полную расчистку больших карт. Улучшения «Наследия» действуют на всех уровнях.")
	intro.theme_type_variation = "Muted"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legacy_box.add_child(intro)
	for br in GameData.META_BRANCHES:
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		legacy_box.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		card.add_child(v)
		var bt := Label.new()
		bt.text = tr(br)
		bt.theme_type_variation = "Title"
		v.add_child(bt)
		var bd := Label.new()
		bd.text = tr(GameData.META_BRANCH_DESC[br])
		bd.theme_type_variation = "Muted"
		v.add_child(bd)
		for md in GameData.META:
			if md["branch"] == br:
				v.add_child(_meta_panel(md))


func _meta_panel(md: Dictionary) -> Control:
	var id: String = md["id"]
	var lv := GameData.meta_level(id)
	var mx := int(md["max"])
	var req := String(md["req"])
	var locked := req != "" and GameData.meta_level(req) <= 0
	var maxed := mx > 0 and lv >= mx
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 22 if req != "" else 0)   # зависимое — с отступом
	var pan := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(1, 1, 1, 0.05)
	psb.border_color = Color(0.55, 0.9, 0.65, 0.35) if lv > 0 else Color(1, 1, 1, 0.08)
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(12)
	psb.content_margin_left = 12
	psb.content_margin_right = 10
	psb.content_margin_top = 8
	psb.content_margin_bottom = 8
	pan.add_theme_stylebox_override("panel", psb)
	pan.name = "Meta_" + id
	wrap.add_child(pan)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 4)
	pan.add_child(ev)
	var top := HBoxContainer.new()
	ev.add_child(top)
	var nm := Label.new()
	nm.text = ("↳ " if req != "" else "") + tr(md["name"])
	nm.add_theme_font_override("font", GameData.font_bold)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var lvl := Label.new()
	lvl.theme_type_variation = "Muted"
	lvl.text = (tr("ур. %d/%d") % [lv, mx]) if mx > 0 else (tr("ур. %d") % lv)
	lvl.name = "Level"
	top.add_child(lvl)
	var ds := Label.new()
	ds.text = tr(md["desc"])
	ds.theme_type_variation = "Muted"
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev.add_child(ds)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	ev.add_child(row)
	var vn := Label.new()
	vn.text = tr(md["value"])
	row.add_child(vn)
	var vv := Label.new()
	vv.theme_type_variation = "Muted"
	vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vv.name = "Value"
	if locked:
		vn.visible = false   # у закрытого — только подсказка, без названия значения
		vv.text = tr("Откроется после «%s»") % tr(GameData.meta_def(req)["name"])
	elif maxed:
		vv.text = "%s (%s)" % [GameData.meta_value(id, lv), tr("макс.")]
	else:
		vv.text = "%s → %s" % [GameData.meta_value(id, lv), GameData.meta_value(id, lv + 1)]
	row.add_child(vv)
	var b := Button.new()
	b.custom_minimum_size = Vector2(120, 56)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.name = "Buy"
	if maxed:
		b.text = tr("макс.")
		b.disabled = true
	else:
		b.text = "★ %d" % GameData.meta_cost(id)
		b.disabled = not GameData.meta_can_buy(id)
		if not b.disabled:
			b.theme_type_variation = "AccentButton"
	b.pressed.connect(_buy_meta.bind(id))
	row.add_child(b)
	return wrap


func _buy_meta(id: String) -> void:
	if GameData.meta_buy(id):
		Sfx.play("gold" if GameData.TYPES.has(id) else "buy", 0.03)
	_fill_legacy()


## «Профили»: три отдельных прохождения.
func _fill_profiles() -> void:
	for c in profiles_box.get_children():
		c.queue_free()
	for n in range(1, GameData.SLOTS + 1):
		var sm := GameData.slot_summary(n)
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		profiles_box.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		card.add_child(h)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tv)
		var nm := Label.new()
		nm.text = tr("Профиль %d") % n
		nm.theme_type_variation = "Title"
		tv.add_child(nm)
		var info := Label.new()
		info.theme_type_variation = "Muted"
		info.text = tr("Пусто") if sm.is_empty() else "★ %d · %s" % [sm["stars"], tr("уровней пройдено: %d") % sm["done"]]
		tv.add_child(info)
		var pick := Button.new()
		pick.custom_minimum_size = Vector2(130, 52)
		pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if n == GameData.slot:
			pick.text = "✓"
			pick.disabled = true
		else:
			pick.text = tr("Выбрать") if not sm.is_empty() else tr("Новая игра")
			pick.theme_type_variation = "AccentButton"
			pick.pressed.connect(_pick_slot.bind(n))
		h.add_child(pick)
		if not sm.is_empty():
			var del := Button.new()
			del.text = "✕"
			del.custom_minimum_size = Vector2(52, 52)
			del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			del.pressed.connect(_ask_delete_slot.bind(n))
			h.add_child(del)


func _pick_slot(n: int) -> void:
	GameData.select_slot(n)
	_fill_profiles()


func _ask_delete_slot(n: int) -> void:
	del_slot = n
	del_confirm.popup_centered()


func _do_delete_slot() -> void:
	GameData.delete_slot(del_slot)
	_fill_profiles()


func _apply_margins() -> void:
	var t := 0.0
	var b := 0.0
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var win := Vector2(DisplayServer.window_get_size())
		if win.y > 0.0:
			var k := get_viewport_rect().size.y / win.y
			t = safe.position.y * k
			b = maxf(0.0, (win.y - safe.end.y) * k)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", int(t + 40.0))
	margin.add_theme_constant_override("margin_bottom", int(b + 24.0))


func _show_settings(show: bool) -> void:
	_show_screen("settings" if show else "main")


func _setting_row(title: String, hint: String, control: Control) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	settings_box.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = "Title"
	tv.add_child(t)
	if hint != "":
		var hl := Label.new()
		hl.text = hint
		hl.theme_type_variation = "Muted"
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(hl)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(control)


## Строка настроек с элементом под текстом — для длинных названий и ползунков (не раздвигает экран).
func _setting_block(title: String, hint: String, control: Control) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	settings_box.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = "Title"
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	if hint != "":
		var hl := Label.new()
		hl.text = hint
		hl.theme_type_variation = "Muted"
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(hl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(control)


func _toggle(on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = tr("Вкл") if on else tr("Выкл")
	b.custom_minimum_size = Vector2(120, 54)
	if on:
		b.theme_type_variation = "AccentButton"
	b.pressed.connect(cb)
	return b


func _fill_settings() -> void:
	for c in settings_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = tr("Настройки")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", GameData.font_bold)
	title.add_theme_font_size_override("font_size", 44)
	settings_box.add_child(title)

	# переключатели — сверху, сетка языков — ниже (на телефоне строки не должны уходить под край)
	_setting_row(tr("Музыка"), "", _slider(GameData.music_vol, _set_music_vol))
	_setting_row(tr("Звуки игры"), "", _slider(GameData.sfx_vol, _set_sfx_vol))
	_setting_row(tr("Вибрация"), tr("Короткий отклик, когда начинается прицел"), _toggle(GameData.vibration_on, _toggle_vibration))
	var mg := HSlider.new()
	mg.min_value = 1
	mg.max_value = 5
	mg.step = 1
	mg.value = GameData.magnet_deg
	mg.custom_minimum_size = Vector2(200, 44)
	var mg_lbl := Label.new()
	mg_lbl.text = "±%d°" % GameData.magnet_deg
	mg_lbl.custom_minimum_size.x = 60
	mg.value_changed.connect(func(v):
		GameData.magnet_deg = int(v)
		mg_lbl.text = "±%d°" % int(v))
	mg.drag_ended.connect(func(_c): GameData.save_settings())
	var mgr := HBoxContainer.new()
	mgr.add_child(mg)
	mgr.add_child(mg_lbl)
	mg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setting_block(tr("Залипание к ключевым углам"), tr("В режиме «ключевые» прицел притягивается к углам, кратным 45°, если он ближе этого"), mgr)
	_setting_row(tr("Экономия батареи"), tr("30 кадров в секунду вместо 60"), _toggle(GameData.eco_mode, _toggle_eco))
	_setting_row(tr("Не блокировать экран"), tr("Пока игра открыта, экран не затемняется и телефон не блокируется"), _toggle(GameData.keep_screen, _toggle_screen))
	# язык: «Как в системе» + кнопки с названиями языков на них самих
	var langs := GridContainer.new()
	langs.columns = 2   # крупный шрифт: в три колонки длинные названия обрезались
	langs.add_theme_constant_override("h_separation", 8)
	langs.add_theme_constant_override("v_separation", 8)
	for l in [""] + GameData.LANGS:
		var b := Button.new()
		b.text = tr("Как в системе") if l == "" else GameData.LANG_NAMES[l]
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		if l == GameData.lang_choice:
			b.theme_type_variation = "AccentButton"
		b.pressed.connect(_set_lang.bind(l))
		langs.add_child(b)
	var lang_card := PanelContainer.new()
	lang_card.theme_type_variation = "Card"
	settings_box.add_child(lang_card)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	lang_card.add_child(lv)
	var lt := Label.new()
	lt.text = tr("Язык")
	lt.theme_type_variation = "Title"
	lv.add_child(lt)
	lv.add_child(langs)


func _set_lang(l: String) -> void:
	GameData.lang_choice = l
	GameData.apply_settings()
	GameData.save_settings()
	# перестраиваем меню на новом языке
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	GameData.set_meta("open_settings", true)


func _toggle_eco() -> void:
	GameData.eco_mode = not GameData.eco_mode
	GameData.apply_settings()
	GameData.save_settings()
	_fill_settings()


## Ползунок громкости 0..100% (0 — выключено).
func _slider(value: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(240, 44)
	s.value_changed.connect(cb)
	s.drag_ended.connect(func(_c): GameData.save_settings())
	return s


func _set_music_vol(v: float) -> void:
	GameData.music_vol = v
	GameData.apply_settings()
	Sfx.apply()


func _set_sfx_vol(v: float) -> void:
	GameData.sfx_vol = v
	GameData.apply_settings()
	Sfx.apply()
	Sfx.play("tap", 0.0)


func _toggle_music() -> void:
	GameData.music_on = not GameData.music_on
	Sfx.apply()
	GameData.save_settings()
	_fill_settings()


func _toggle_sfx() -> void:
	GameData.sfx_on = not GameData.sfx_on
	Sfx.apply()
	GameData.save_settings()
	_fill_settings()


func _toggle_vibration() -> void:
	GameData.vibration_on = not GameData.vibration_on
	GameData.save_settings()
	GameData.vibrate(40)   # сразу показать, как ощущается
	_fill_settings()


func _toggle_screen() -> void:
	GameData.keep_screen = not GameData.keep_screen
	GameData.apply_settings()
	GameData.save_settings()
	_fill_settings()


func _ask_reset() -> void:
	confirm.popup_centered()


func _do_reset() -> void:
	GameData.reset_all()
	_show_settings(false)


func _fill() -> void:
	for c in list.get_children():
		c.queue_free()
	lbl_u.text = "★ %d" % GameData.stars
	btn_profile.text = tr("Профиль %d") % GameData.slot
	# пройденные и открытые уровни + следующий закрытый; уровни бесконечны
	var count := maxi(Maps.HANDMADE, GameData.maps_unlocked + 1)
	var current_card: Control = null
	for i in count:
		var mp: Dictionary = Maps.get_map(i)
		var locked: bool = i >= GameData.maps_unlocked
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		if locked:
			card.modulate = Color(1, 1, 1, 0.5)
		list.add_child(card)
		if i == GameData.maps_unlocked - 1:
			current_card = card
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		card.add_child(h)
		var num := Label.new()
		num.text = str(i + 1)
		num.custom_minimum_size.x = 48
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_override("font", GameData.font_bold)
		num.add_theme_font_size_override("font_size", 32)
		num.add_theme_color_override("font_color", GameData.C_ACCENT.lightened(0.3))
		h.add_child(num)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 2)
		h.add_child(tv)
		var name := Label.new()
		name.text = Maps.title(mp, tr)
		name.theme_type_variation = "Title"
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tv.add_child(name)
		var info := Label.new()
		info.theme_type_variation = "Muted"
		var status := tr("%d × %d клеток") % [mp["w"], mp["h"]]
		if GameData.maps_done.has(mp["id"]):
			status += tr(" · цель выполнена")
		info.text = status
		tv.add_child(info)
		# статистика: время первого прохождения, лучшее, текущее время начатого уровня
		var parts := []
		var stt: Dictionary = GameData.map_stats.get(mp["id"], {})
		if not stt.is_empty():
			parts.append(tr("Пройдено за %s") % GameData.fmt_time(stt["first"]))
			if int(stt["runs"]) > 1:
				parts.append(tr("лучшее %s") % GameData.fmt_time(stt["best"]))
		var cur := _saved_time(mp)
		if cur > 0.0:
			parts.append(tr("сейчас %s") % GameData.fmt_time(cur))
		var st_txt := " · ".join(parts)
		if st_txt != "":
			var sl := Label.new()
			sl.theme_type_variation = "Muted"
			sl.add_theme_color_override("font_color", GameData.C_GOLD)
			sl.text = st_txt
			sl.name = "Stats"
			tv.add_child(sl)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 56)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if locked:
			b.icon = Icons.lock(40)
			b.text = tr("Закрыта")
			b.disabled = true
		elif GameData.map_states.has(mp["id"]):
			b.text = tr("Продолжить")
			b.theme_type_variation = "AccentButton"
		else:
			b.text = tr("Играть")
			b.theme_type_variation = "AccentButton"
		b.pressed.connect(_open.bind(i))
		h.add_child(b)
	# прокручиваем к текущему уровню
	if current_card != null:
		_scroll_to.call_deferred(current_card)


## Время начатого уровня (из сводки профиля; 0, если не начат).
func _saved_time(mp: Dictionary) -> float:
	var st = GameData.map_states.get(mp["id"], {})
	return float(st.get("time", 0.0)) if typeof(st) == TYPE_DICTIONARY else 0.0


func _scroll_to(card: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(card):
		scroll.ensure_control_visible(card)


func _open(i: int) -> void:
	OS.low_processor_usage_mode = false
	GameData.current_map = i
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not main_box.visible:
			_show_screen("main")
		else:
			get_tree().quit()

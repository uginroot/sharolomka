extends Control

const Maps = preload("res://scripts/maps.gd")
const Icons = preload("res://scripts/icons.gd")

var maps: Array
var list: VBoxContainer
var lbl_u: Label
var confirm: ConfirmationDialog
var margin: MarginContainer
var main_box: VBoxContainer
var settings_box: VBoxContainer


func _ready() -> void:
	# меню статично: кадры рисуются только при изменениях
	OS.low_processor_usage_mode = true
	maps = Maps.get_maps()

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
	vb.add_child(ur)
	var pill := PanelContainer.new()
	pill.theme_type_variation = "Pill"
	ur.add_child(pill)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 8)
	pill.add_child(ph)
	var gi := TextureRect.new()
	gi.texture = Icons.gem(40)
	gi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gi.custom_minimum_size = Vector2(28, 28)
	gi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(gi)
	lbl_u = Label.new()
	lbl_u.add_theme_font_override("font", GameData.font_bold)
	lbl_u.add_theme_color_override("font_color", GameData.C_GEM)
	ph.add_child(lbl_u)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	sc.add_child(list)

	var bset := Button.new()
	bset.text = tr("Настройки")
	bset.custom_minimum_size.y = 58
	bset.pressed.connect(_show_settings.bind(true))
	vb.add_child(bset)
	main_box = vb

	# --- экран настроек
	settings_box = VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 14)
	settings_box.visible = false
	margin.add_child(settings_box)

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
	main_box.visible = not show
	settings_box.visible = show
	if show:
		_fill_settings()
	else:
		_fill()


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
	title.add_theme_font_size_override("font_size", 40)
	settings_box.add_child(title)

	# язык: «Как в системе» + кнопки с названиями языков на них самих
	var langs := HBoxContainer.new()
	langs.add_theme_constant_override("separation", 8)
	for l in [""] + GameData.LANGS:
		var b := Button.new()
		b.text = tr("Как в системе") if l == "" else GameData.LANG_NAMES[l]
		b.custom_minimum_size = Vector2(0, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_setting_row(tr("Экономия батареи"), tr("30 кадров в секунду вместо 60"), _toggle(GameData.eco_mode, _toggle_eco))
	_setting_row(tr("Не гасить экран"), tr("Пока открыта игра"), _toggle(GameData.keep_screen, _toggle_screen))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_box.add_child(spacer)
	var reset := Button.new()
	reset.text = tr("Сбросить весь прогресс")
	reset.custom_minimum_size.y = 54
	reset.modulate = Color(1, 0.75, 0.75, 0.85)
	reset.pressed.connect(_ask_reset)
	settings_box.add_child(reset)
	var back := Button.new()
	back.text = tr("Назад")
	back.theme_type_variation = "AccentButton"
	back.custom_minimum_size.y = 60
	back.pressed.connect(_show_settings.bind(false))
	settings_box.add_child(back)


func _set_lang(l: String) -> void:
	GameData.lang_choice = l
	GameData.apply_settings()
	GameData.save_game()
	# перестраиваем меню на новом языке
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	GameData.set_meta("open_settings", true)


func _toggle_eco() -> void:
	GameData.eco_mode = not GameData.eco_mode
	GameData.apply_settings()
	GameData.save_game()
	_fill_settings()


func _toggle_screen() -> void:
	GameData.keep_screen = not GameData.keep_screen
	GameData.apply_settings()
	GameData.save_game()
	_fill_settings()


func _ask_reset() -> void:
	confirm.popup_centered()


func _do_reset() -> void:
	GameData.reset_all()
	_show_settings(false)


func _fill() -> void:
	for c in list.get_children():
		c.queue_free()
	lbl_u.text = "%d" % GameData.u
	for i in maps.size():
		var mp: Dictionary = maps[i]
		var locked: bool = i >= GameData.maps_unlocked
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		if locked:
			card.modulate = Color(1, 1, 1, 0.5)
		list.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		card.add_child(h)
		var num := Label.new()
		num.text = str(i + 1)
		num.custom_minimum_size.x = 36
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_override("font", GameData.font_bold)
		num.add_theme_font_size_override("font_size", 30)
		num.add_theme_color_override("font_color", GameData.C_ACCENT.lightened(0.3))
		h.add_child(num)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 2)
		h.add_child(tv)
		var name := Label.new()
		name.text = tr(mp["name"])
		name.theme_type_variation = "Title"
		tv.add_child(name)
		var info := Label.new()
		info.theme_type_variation = "Muted"
		var status := tr("%d × %d клеток") % [mp["w"], mp["h"]]
		if GameData.maps_done.has(mp["id"]):
			status += tr(" · цель выполнена")
		info.text = status
		tv.add_child(info)
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


func _open(i: int) -> void:
	OS.low_processor_usage_mode = false
	GameData.current_map = i
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if settings_box != null and settings_box.visible:
			_show_settings(false)
		else:
			get_tree().quit()

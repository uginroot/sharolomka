extends Control

const Maps = preload("res://scripts/maps.gd")

var maps: Array
var list: VBoxContainer
var lbl_u: Label
var confirm: ConfirmationDialog
var btn_eco: Button
var btn_screen: Button


func _ready() -> void:
	# Меню статично: перерисовываем экран только когда что-то изменилось.
	OS.low_processor_usage_mode = true
	maps = Maps.get_maps()
	theme = GameData.make_theme()

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 28)
	m.add_theme_constant_override("margin_right", 28)
	m.add_theme_constant_override("margin_top", 60)
	m.add_theme_constant_override("margin_bottom", 30)
	add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	m.add_child(vb)

	var title := Label.new()
	title.text = "ШАРОЛОМКА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vb.add_child(title)

	lbl_u = Label.new()
	lbl_u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl_u)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)

	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	sc.add_child(list)

	var srow := HBoxContainer.new()
	vb.add_child(srow)
	btn_eco = Button.new()
	btn_eco.custom_minimum_size.y = 56
	btn_eco.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_eco.pressed.connect(_toggle_eco)
	srow.add_child(btn_eco)
	btn_screen = Button.new()
	btn_screen.custom_minimum_size.y = 56
	btn_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_screen.pressed.connect(_toggle_screen)
	srow.add_child(btn_screen)

	var reset := Button.new()
	reset.text = "Сбросить весь прогресс"
	reset.custom_minimum_size.y = 56
	vb.add_child(reset)

	confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Удалить весь прогресс?"
	confirm.ok_button_text = "Удалить"
	confirm.cancel_button_text = "Отмена"
	add_child(confirm)
	reset.pressed.connect(_ask_reset)
	confirm.confirmed.connect(_do_reset)

	_fill()


func _toggle_eco() -> void:
	GameData.eco_mode = not GameData.eco_mode
	GameData.apply_settings()
	GameData.save_game()
	_fill()


func _toggle_screen() -> void:
	GameData.keep_screen = not GameData.keep_screen
	GameData.apply_settings()
	GameData.save_game()
	_fill()


func _ask_reset() -> void:
	confirm.popup_centered()


func _do_reset() -> void:
	GameData.reset_all()
	_fill()


func _fill() -> void:
	for c in list.get_children():
		c.queue_free()
	lbl_u.text = "U-баллы: %d" % GameData.u
	btn_eco.text = "Экономия: %s" % ("30 FPS" if GameData.eco_mode else "выкл")
	btn_screen.text = "Экран: %s" % ("не гаснет" if GameData.keep_screen else "как обычно")
	for i in maps.size():
		var mp: Dictionary = maps[i]
		var b := Button.new()
		b.custom_minimum_size.y = 84
		var status := ""
		if i >= GameData.maps_unlocked:
			status = "  (закрыта)"
			b.disabled = true
		elif GameData.map_states.has(mp["id"]):
			status = "  — продолжить"
		elif GameData.maps_done.has(mp["id"]):
			status = "  — пройдена"
		b.text = "%d. %s  %d×%d%s" % [i + 1, mp["name"], mp["w"], mp["h"], status]
		b.pressed.connect(_open.bind(i))
		list.add_child(b)


func _open(i: int) -> void:
	OS.low_processor_usage_mode = false
	GameData.current_map = i
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()

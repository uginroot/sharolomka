extends Control

const Maps = preload("res://scripts/maps.gd")
const Icons = preload("res://scripts/icons.gd")

var maps: Array
var list: VBoxContainer
var lbl_u: Label
var confirm: ConfirmationDialog
var btn_eco: Button
var btn_screen: Button
var margin: MarginContainer


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
	title.text = "ШАРОЛОМКА"
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

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
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
	reset.custom_minimum_size.y = 50
	reset.modulate = Color(1, 0.75, 0.75, 0.8)
	vb.add_child(reset)

	confirm = ConfirmationDialog.new()
	confirm.title = "Сброс"
	confirm.dialog_text = "Удалить весь прогресс?"
	confirm.ok_button_text = "Удалить"
	confirm.cancel_button_text = "Отмена"
	add_child(confirm)
	reset.pressed.connect(_ask_reset)
	confirm.confirmed.connect(_do_reset)
	_fill()


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
	lbl_u.text = "%d" % GameData.u
	btn_eco.text = "Экономия: %s" % ("30 FPS" if GameData.eco_mode else "выкл")
	btn_screen.text = "Экран: %s" % ("не гаснет" if GameData.keep_screen else "гаснет")
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
		name.text = mp["name"]
		name.theme_type_variation = "Title"
		tv.add_child(name)
		var info := Label.new()
		info.theme_type_variation = "Muted"
		var status := "%d × %d клеток" % [mp["w"], mp["h"]]
		if GameData.maps_done.has(mp["id"]):
			status += " · цель выполнена"
		info.text = status
		tv.add_child(info)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 56)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if locked:
			b.icon = Icons.lock(40)
			b.text = "Закрыта"
			b.disabled = true
		elif GameData.map_states.has(mp["id"]):
			b.text = "Продолжить"
			b.theme_type_variation = "AccentButton"
		else:
			b.text = "Играть"
			b.theme_type_variation = "AccentButton"
		b.pressed.connect(_open.bind(i))
		h.add_child(b)


func _open(i: int) -> void:
	OS.low_processor_usage_mode = false
	GameData.current_map = i
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()

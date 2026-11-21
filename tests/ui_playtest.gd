extends Node
## UI-автотест: проходит игру касаниями, как игрок, и сохраняет скриншоты.
## Нужен настоящий рендер (на сервере — через xvfb):
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 720x1600 res://tests/ui_playtest.tscn
## Скриншоты: build/screens/*.png. Код выхода = число упавших проверок.

var failures := 0
var shots := 0
var out_dir := ""


func _ready() -> void:
	out_dir = ProjectSettings.globalize_path("res://build/screens")
	DirAccess.make_dir_recursive_absolute(out_dir)
	# узел переезжает в корень, чтобы пережить смену сцен
	_start.call_deferred()


func _start() -> void:
	reparent(get_tree().root)
	GameData.reset_all()
	GameData.lang_choice = "ru"
	GameData.apply_settings()
	GameData.unlocked["splash"] = true
	GameData.u = 7
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(0.6)
	await _run()
	print("\nUI-проверок упало: %d, скриншоты: %s" % [failures, out_dir])
	get_tree().quit(failures)


func check(cond: bool, msg: String) -> void:
	print(("  ok  " if cond else "  ✗   ") + msg)
	if not cond:
		failures += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _find(node: Node, text: String) -> Control:
	if node is Button and node.is_visible_in_tree() and text in node.text:
		return node
	for c in node.get_children():
		var r = _find(c, text)
		if r != null:
			return r
	return null


func _touch(pos: Vector2, pressed: bool, idx := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(pos: Vector2, rel: Vector2, idx := 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)


func _tap_at(p: Vector2) -> void:
	_touch(p, true)
	await get_tree().process_frame
	_touch(p, false)
	await get_tree().process_frame
	await get_tree().process_frame


func _tap(text: String) -> bool:
	var b = _find(get_tree().root, text)
	if b == null:
		check(false, "кнопка «%s» найдена" % text)
		return false
	await _tap_at(b.get_global_rect().get_center())
	return true


## Два пальца: раздвинуть на spread пикселей и сдвинуть на shift.
func _two_fingers(spread: float, shift: Vector2) -> void:
	var c := get_viewport().get_visible_rect().size * 0.5
	var a := c - Vector2(80, 0)
	var b := c + Vector2(80, 0)
	_touch(a, true, 0)
	_touch(b, true, 1)
	await get_tree().process_frame
	for k in 10:
		var na := a + Vector2(-spread / 20.0, 0) + shift / 10.0
		var nb := b + Vector2(spread / 20.0, 0) + shift / 10.0
		_drag(na, na - a, 0)
		_drag(nb, nb - b, 1)
		a = na
		b = nb
		await get_tree().process_frame
	_touch(a, false, 0)
	_touch(b, false, 1)
	await get_tree().process_frame


func _shot(name: String) -> void:
	OS.low_processor_usage_mode = false
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, shots, name])
	shots += 1


func _run() -> void:
	await _shot("menu")
	check(await _tap("Играть"), "в меню нажимается «Играть»")
	await _wait(1.5)
	var g = get_tree().current_scene
	check(g.name == "Game", "открылась игра")
	check(g.balls.size() == 1, "на старте один шар")
	await _wait(2.0)
	await _shot("game_start")

	# рогатка: нажать и оттянуть вниз — шар летит вверх
	var vs := get_viewport().get_visible_rect().size
	g.rubles = 5000
	await _wait(0.2)
	var n_before: int = g.balls.size()
	# нажимаем в открытую клетку у старта
	g.cam.position = g.start_pos
	g._clamp_cam()
	var p: Vector2 = (g.start_pos - g.cam.position) * g.zoom + vs * 0.5
	_touch(p, true)
	await _wait(0.35)   # удержание — начинается прицел
	check(g.sling, "удержание пальца включает прицел")
	await _shot("hold")
	for k in 6:
		_drag(p + Vector2(0, 25 * (k + 1)), Vector2(0, 25))
		await get_tree().process_frame
	await _shot("sling_aim")
	_touch(p + Vector2(0, 150), false)
	await get_tree().process_frame
	check(g.balls.size() == n_before + 1, "рогатка: оттянуть и отпустить — выстрел")
	var pw: Vector2 = g._screen_to_world(p)
	check(g.balls[-1].pos.distance_to(g._launch_from(pw)) < 40.0, "рогатка: шар вылетел из точки нажатия")
	check(absf(g.aim_angle + 90.0) < 1.0, "рогатка: оттянули вниз — летит вверх")
	# отмена: вытянуть за область наведения
	_touch(p, true)
	await _wait(0.35)
	for k in 8:
		_drag(p + Vector2(40 * (k + 1), 0), Vector2(40, 0))
		await get_tree().process_frame
	await _shot("sling_cancel")
	_touch(p + Vector2(320, 0), false)
	await get_tree().process_frame
	check(g.balls.size() == n_before + 1, "рогатка: за областью наведения — отмена")
	var a0: float = g.aim_angle

	# одним пальцем сразу повёл — перемещение карты, без выстрела
	var cam0: Vector2 = g.cam.position
	var n_pan: int = g.balls.size()
	_touch(p, true)
	await get_tree().process_frame
	for k in 8:
		_drag(p + Vector2(0, 30 * (k + 1)), Vector2(0, 30))
		await get_tree().process_frame
	_touch(p + Vector2(0, 240), false)
	await _wait(0.4)
	check(g.cam.position.distance_to(cam0) > 20.0, "одним пальцем карта двигается")
	check(g.balls.size() == n_pan and not g.sling, "перемещение карты не стреляет")
	# щипок не сбивает прицел и меняет масштаб
	var a1: float = g.aim_angle
	var z0: float = g.zoom
	await _two_fingers(200.0, Vector2.ZERO)
	check(g.zoom > z0 * 1.2, "щипок увеличивает масштаб")
	check(is_equal_approx(g.aim_angle, a1), "щипок не сбивает прицел")

	# цена следующего шара на фишке
	var chip: Button = g.chips["basic"]
	check(chip.text.begins_with("×") and "·" in chip.text, "на фишке шара видна цена: %s" % chip.text)
	check(_find(get_tree().root, "Выстрел") == null, "кнопки «Выстрел» больше нет")

	# сдвиг карты двумя пальцами двигает точку выстрела
	var c0: Vector2 = g.cam.position
	await _two_fingers(0.0, Vector2(0, 250))
	check(g.cam.position.distance_to(c0) > 20.0, "два пальца двигают карту")
	await _wait(1.0)
	await _shot("fired")

	# окно прокачки
	check(await _tap("Прокачка"), "кнопка «Прокачка» нажимается")
	check(g.upg.visible, "окно прокачки открылось")
	await _wait(0.4)
	await _shot("upgrades")
	var dmg0: int = g.dmg_lvl["basic"]
	var dmg_btn: Button = g.shop_refs["basic"]["dmg"]["button"]
	await _tap_at(dmg_btn.get_global_rect().get_center())
	check(int(g.dmg_lvl["basic"]) == dmg0 + 1, "покупка урона касанием")
	var tabs: TabContainer = g.upg.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 1
	await _wait(0.3)
	await _shot("perks")
	check(await _tap("Вернуться к игре"), "кнопка «Вернуться к игре»")
	check(not g.upg.visible, "окно прокачки закрылось")

	# сброс: включить, выстрелить рогаткой — перезапускается бездельник, новый шар не покупается
	g._select("basic")
	await _wait(0.2)
	check(await _tap("Сброс"), "кнопка «Сброс» нажимается")
	check(g.reset_armed, "сброс включил режим перезапуска")
	var n_reset: int = g.balls.size()
	var r_reset: int = g.rubles
	var pr := Vector2(vs.x * 0.5, vs.y * 0.5)
	g.cam.position = g.start_pos
	g._clamp_cam()
	pr = (g.start_pos - g.cam.position) * g.zoom + vs * 0.5
	_touch(pr, true)
	await _wait(0.35)
	for k in 5:
		_drag(pr + Vector2(0, 25 * (k + 1)), Vector2(0, 25))
		await get_tree().process_frame
	await _shot("reset_aim")
	_touch(pr + Vector2(0, 125), false)
	await get_tree().process_frame
	check(g.balls.size() == n_reset and g.rubles >= r_reset, "перезапуск бездельника без покупки")
	check(not g.reset_armed and g.reset_cd["basic"] > 25.0, "после перезапуска начался кулдаун")
	await _wait(3.0)
	await _shot("game_later")

	# меню и «Продолжить»
	var destroyed: int = g.destroyed
	var ball_spots: Array = g.balls.map(func(b): return b.pos)
	var menu_btn: Button = g.top_bar.find_children("*", "Button", true, false)[0]
	await _tap_at(menu_btn.get_global_rect().get_center())
	await _wait(1.0)
	check(get_tree().current_scene.name == "MainMenu", "кнопка меню возвращает в меню")
	await _shot("menu_after")
	check(await _tap("Продолжить"), "в меню есть «Продолжить»")
	await _wait(1.5)
	var g2 = get_tree().current_scene
	check(g2.name == "Game" and g2.destroyed >= destroyed, "игра продолжилась с сохранённым прогрессом")
	check(g2.field_root.get_child_count() > 0, "открытая часть карты рисуется после загрузки")
	check(g2.balls.size() == ball_spots.size(), "после «Продолжить» столько же шаров")
	await _shot("continued")

	# английский язык через экран настроек
	var menu_btn2: Button = g2.top_bar.find_children("*", "Button", true, false)[0]
	await _tap_at(menu_btn2.get_global_rect().get_center())
	await _wait(1.0)
	check(await _tap("Настройки"), "в меню есть «Настройки»")
	await _wait(0.3)
	check(await _tap("English"), "в настройках можно выбрать English")
	await _wait(1.0)
	check(GameData.lang == "en", "язык переключился на английский")
	await _shot("settings_en")
	check(await _tap("Back"), "кнопка Back в настройках")
	await _wait(0.3)
	await _shot("menu_en")
	check(await _tap("Continue"), "в английском меню есть Continue")
	await _wait(1.5)
	var g3 = get_tree().current_scene
	g3.rubles = 50000
	await _wait(0.3)
	await _shot("game_en")
	await _tap("Upgrades")
	await _wait(0.4)
	await _shot("upgrades_en")
	GameData.lang_choice = "ru"
	GameData.apply_settings()

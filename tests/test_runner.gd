extends Node
## Автотесты игры. Запуск:
##   godot --headless --path . res://tests/test_runner.tscn
## Код выхода = число упавших тестов. Можно запустить один тест: ... -- test_fog_invariant
##
## Каждый тест создаёт свежую карту, гоняет симуляцию напрямую через _sim(dt) и проверяет
## инварианты. Сохранения перед каждым тестом стираются.

const GAME := preload("res://scenes/game.tscn")
const DT := 1.0 / 60.0

var failures := 0
var current := ""
var game = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := OS.get_cmdline_user_args()
	var names: Array = []
	for m in get_method_list():
		var n: String = m["name"]
		if n.begins_with("test_") and (only.is_empty() or n in only):
			names.append(n)
	names.sort()
	var t0 := Time.get_ticks_msec()
	for n in names:
		current = n
		var f0 := failures
		var s0 := Time.get_ticks_msec()
		await call(n)
		_free_game()
		var ok := failures == f0
		print("%s  %s  (%d ms)" % ["PASS" if ok else "FAIL", n, Time.get_ticks_msec() - s0])
	print("\n%d тестов, упало: %d, %.1f с" % [names.size(), failures, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(failures)


# ---------------------------------------------------------------- помощники

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("[%s] %s" % [current, msg])
		print("    ✗ " + msg)


func new_game(map_index: int, setup: Callable = Callable()):
	_free_game()
	GameData.reset_all()
	GameData.lang = "ru"
	GameData.apply_settings()
	GameData.current_map = map_index
	if setup.is_valid():
		setup.call()
	seed(12345)
	game = GAME.instantiate()
	add_child(game)
	await get_tree().process_frame
	return game


func _free_game() -> void:
	if game != null:
		game.queue_free()
		game = null


func unlock_all(perk: int = 0, sup: bool = false) -> void:
	for t in GameData.TYPE_ORDER:
		GameData.unlocked[t] = true
		GameData.perks[t] = perk
		GameData.supers[t] = sup


func fire_n(g, t: String, n: int) -> void:
	g.rubles = 1_000_000_000
	g.selected = t
	for k in n:
		g._fire()
		g.aim_angle += 47.0


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / 40.0)), int(floor(p.y / 40.0)))


## Шарик может находиться только в пустой видимой клетке
## (пробойник — ещё и внутри видимого квадрата, сквозь который пролетает).
func ball_position_ok(g, b) -> String:
	var c := cell_of(b.pos)
	if c.x < 0 or c.y < 0 or c.x >= g.W or c.y >= g.H:
		return "шарик за краем карты %s" % c
	if not g._vis_at(c.x, c.y):
		return "шарик %s в тумане в клетке %s" % [b.type, c]
	var k: int = g._kind_at(c.x, c.y)
	if k == 2:
		return "шарик %s внутри стены %s" % [b.type, c]
	if k == 1 and b.type != "pierce":
		return "шарик %s внутри квадрата %s" % [b.type, c]
	return ""


func sim(g, seconds: float, each: Callable = Callable()) -> bool:
	var frames := int(seconds / DT)
	for f in frames:
		g._sim(DT)
		if each.is_valid() and f % 10 == 0:
			if not each.call(g):
				return false
	return true


# ---------------------------------------------------------------- тесты

## Все карты создаются, у старта пусто и видно, точка выстрела есть.
func test_maps_generate() -> void:
	var maps = preload("res://scripts/maps.gd").get_maps()
	for i in maps.size():
		var g = await new_game(i)
		var s: Vector2i = g.start_cell
		check(s == Vector2i(g.W / 2, g.H / 2), "%s: старт не в центре" % maps[i]["id"])
		check(g._kind_at(s.x, s.y) == 0 and g._vis_at(s.x, s.y), "%s: стартовая клетка не пустая/не видна" % maps[i]["id"])
		check(g._launch_point() != null, "%s: нет точки выстрела" % maps[i]["id"])
		check(g.balls.size() == 1, "%s: на новой карте должен быть 1 бесплатный шар" % maps[i]["id"])


## Маленькие карты проходимы: каждый квадрат достижим от старта через нестены.
func test_small_maps_reachable() -> void:
	var maps = preload("res://scripts/maps.gd").get_maps()
	for i in maps.size():
		var g = await new_game(i)
		if not g.track_all:
			continue
		var seen := {}
		var stack := [g.start_cell]
		seen[g.start_cell] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + o
				if seen.has(n) or n.x < 0 or n.y < 0 or n.x >= g.W or n.y >= g.H:
					continue
				var k: int = g._kind_at(n.x, n.y)
				if k == 2 or k == 3:
					continue
				seen[n] = true
				stack.append(n)
		var bricks := 0
		var unreachable := 0
		for y in g.H:
			for x in g.W:
				if g._kind_at(x, y) == 1:
					bricks += 1
					if not seen.has(Vector2i(x, y)):
						unreachable += 1
		check(unreachable == 0, "%s: недостижимых квадратов %d из %d" % [maps[i]["id"], unreachable, bricks])


## Каждый тип шара (без перков и с максимальными перками) не уходит в туман и стены и приносит прогресс.
func test_ball_types_invariants() -> void:
	for t in GameData.TYPE_ORDER:
		for variant in [[0, false], [5, true]]:
			var g = await new_game(3, func(): unlock_all(variant[0], variant[1]))
			g.balls.clear()
			fire_n(g, t, 6)
			var d0: int = g.destroyed
			var err := [""]
			sim(g, 40.0, func(gg):
				for b in gg.balls:
					var e := ball_position_ok(gg, b)
					if e != "":
						err[0] = e
						return false
				return true)
			var tag := "%s перк=%d супер=%s" % [t, variant[0], variant[1]]
			check(err[0] == "", tag + ": " + err[0])
			check(g.destroyed - d0 > 30, "%s: мало прогресса за 40 с (%d)" % [tag, g.destroyed - d0])


## Туман: каждая пустая клетка видна, каждая видимая клетка — рядом с пустой.
func test_fog_invariant() -> void:
	var g = await new_game(2, func(): unlock_all(2, false))
	fire_n(g, "basic", 20)
	fire_n(g, "splash", 5)
	sim(g, 30.0)
	var bad_hidden_empty := 0
	var bad_far_visible := 0
	for y in range(g.ey0, g.ey1 + 1):
		for x in range(g.ex0, g.ex1 + 1):
			var k: int = g._kind_at(x, y)
			var v: bool = g._vis_at(x, y)
			if k == 0 and not v:
				bad_hidden_empty += 1
			if v and k != 0:
				var near := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if g._kind_at(x + dx, y + dy) == 0:
							near = true
				if not near:
					bad_far_visible += 1
	check(bad_hidden_empty == 0, "пустых клеток в тумане: %d" % bad_hidden_empty)
	check(bad_far_visible == 0, "видимых клеток не у пустоты (виден не только первый слой): %d" % bad_far_visible)


## Рубли = снятые жизни, счётчики квадратов в кусках сходятся.
func test_economy_and_counters() -> void:
	var g = await new_game(1, func(): unlock_all(3, false))
	var hp0 := 0
	for c in g.chunks:
		for li in 1024:
			if c.kind[li] == 1:
				hp0 += c.hp[li]
	fire_n(g, "basic", 10)
	fire_n(g, "splash", 4)
	fire_n(g, "poison", 4)
	var r0: int = g.rubles
	sim(g, 30.0)
	var hp1 := 0
	for c in g.chunks:
		for li in 1024:
			if c.kind[li] == 1:
				hp1 += c.hp[li]
	check(g.rubles - r0 == hp0 - hp1, "рубли %d ≠ снятые жизни %d" % [g.rubles - r0, hp0 - hp1])
	var alive := 0
	for ck in g.chunks.size():
		var c = g.chunks[ck]
		var solid := 0
		for li in 1024:
			if c.kind[li] == 1 or c.kind[li] == 2:
				solid += 1
			if c.kind[li] == 1:
				alive += 1
		check(solid == c.solid, "кусок %d: solid %d, а пересчёт %d" % [ck, c.solid, solid])
	check(alive == g.alive, "alive %d, а пересчёт %d" % [g.alive, alive])
	check(g.total - g.destroyed == g.alive, "total-destroyed ≠ alive")


## Выстрел: списывает цену, цена растёт, шар появляется в точке выстрела.
func test_fire() -> void:
	var g = await new_game(0)
	g.rubles = 1000
	var c0: int = g._ball_cost("basic")
	var lp = g._launch_point()
	g._fire()
	check(g.rubles == 1000 - c0, "выстрел списал не ту сумму")
	check(g.balls.size() == 2, "после выстрела должно быть 2 шара")
	check(g.balls[1].pos.distance_to(lp) < 0.01, "шар появился не в точке выстрела")
	check(g._ball_cost("basic") > c0, "цена следующего шара не выросла")
	g.rubles = 0
	g._fire()
	check(g.balls.size() == 2, "выстрел без денег сработал")


## Точка выстрела всегда в пустой видимой клетке, даже если центр экрана над квадратом.
func test_launch_point_snaps() -> void:
	var g = await new_game(2)
	g.cam.position = g.start_pos + Vector2(0, -40.0 * 4)
	var lp = g._launch_point()
	check(lp != null, "нет точки выстрела рядом со стартом")
	if lp != null:
		var c := cell_of(lp)
		check(g._kind_at(c.x, c.y) == 0 and g._vis_at(c.x, c.y), "точка выстрела не в пустой видимой клетке")
	g.cam.position = Vector2(40.0 * 3, 40.0 * 3)
	g._clamp_cam()
	var lp2 = g._launch_point()
	if lp2 != null:
		var c2 := cell_of(lp2)
		check(g._kind_at(c2.x, c2.y) == 0, "точка выстрела в непустой клетке")


## Центр поля доходит до края открытой части без увеличения.
func test_camera_reaches_edges() -> void:
	var g = await new_game(2, func(): unlock_all())
	fire_n(g, "basic", 20)
	sim(g, 20.0)
	var z: float = g.zoom
	for target in [Vector2(-1e6, -1e6), Vector2(1e6, 1e6)]:
		g.cam.position = target
		g._clamp_cam()
		var c: Vector2 = g._screen_center_world()
		var a := Vector2(maxi(0, g.ex0 - 1), maxi(0, g.ey0 - 1)) * 40.0
		var b := Vector2(mini(g.W, g.ex1 + 2), mini(g.H, g.ey1 + 2)) * 40.0
		var corner := a if target.x < 0 else b
		check(c.distance_to(corner) < 1.0, "центр %s не дошёл до угла %s" % [c, corner])
	check(is_equal_approx(g.zoom, z), "масштаб изменился при перемещении")


## Сохранение и загрузка дают ту же карту.
func test_save_load_roundtrip() -> void:
	var g = await new_game(3, func(): unlock_all())
	fire_n(g, "basic", 15)
	sim(g, 20.0)
	g._save_state()
	var destroyed: int = g.destroyed
	var rubles: int = g.rubles
	var counts: Dictionary = g.counts.duplicate()
	var snap := {}
	for ck in g.chunks.size():
		var c = g.chunks[ck]
		if c != null and c.changed:
			snap[ck] = [c.hp.duplicate(), c.vis.duplicate()]
	game.queue_free()
	game = null
	await get_tree().process_frame
	game = GAME.instantiate()
	add_child(game)
	await get_tree().process_frame
	var g2 = game
	check(g2.destroyed == destroyed, "destroyed %d → %d" % [destroyed, g2.destroyed])
	check(g2.rubles == rubles, "рубли %d → %d" % [rubles, g2.rubles])
	check(g2.counts == counts, "число шаров не совпало")
	var bad := 0
	for ck in snap:
		var c = g2.chunks[ck]
		if c == null or c.hp != snap[ck][0] or c.vis != snap[ck][1]:
			bad += 1
	check(bad == 0, "после загрузки отличаются кусков: %d из %d" % [bad, snap.size()])
	var nodes := 0
	for ck in snap:
		if g2.chunks[ck].node != null:
			nodes += 1
	check(nodes > 0, "после загрузки открытая часть не рисуется (нет узлов кусков)")


## Маленькую карту можно пройти полностью, после цели открывается следующая.
func test_meadow_completes() -> void:
	var g = await new_game(0, func(): unlock_all(5, false))
	fire_n(g, "splash", 10)
	fire_n(g, "pierce", 10)
	for k in 6:
		g._buy_dmg("splash")
	sim(g, 120.0, func(gg): return gg.alive > 0)
	check(g.alive == 0, "за 120 с осталось квадратов: %d" % g.alive)
	check(g.goal_done or g.destroyed >= g.goal, "цель не засчитана")
	g._check_goal()
	check(GameData.maps_unlocked >= 2, "следующая карта не открылась")


## Сброс: раз в 30 с, возвращает шар в точку выстрела.
func test_reset_cooldown() -> void:
	var g = await new_game(2)
	sim(g, 3.0)
	g._reset_stuck()
	var lp = g._launch_point()
	check(g.balls[0].pos.distance_to(lp) < 0.01, "шар не вернулся в точку выстрела")
	check(g.reset_cd["basic"] > 29.0, "кулдаун сброса не запущен")
	var p: Vector2 = g.balls[0].pos
	sim(g, 1.0)
	g._reset_stuck()
	check(g.balls[0].pos != lp or p != lp, "сброс сработал во время кулдауна")


## Огромная карта 10000×10000 загружается быстро и не создаёт лишних кусков.
func test_huge_map_lazy() -> void:
	var t0 := Time.get_ticks_msec()
	var g = await new_game(6, func(): unlock_all())
	var ms := Time.get_ticks_msec() - t0
	var n := 0
	for c in g.chunks:
		if c != null:
			n += 1
	check(ms < 3000, "карта 10000×10000 грузится %d мс" % ms)
	check(n < 40, "на старте создано кусков: %d" % n)


## Производительность: 200 шаров на большой карте — укладываемся в бюджет кадра.
func test_performance_budget() -> void:
	var g = await new_game(6, func(): unlock_all(3, false))
	for t in GameData.TYPE_ORDER:
		fire_n(g, t, 40)
	sim(g, 2.0)
	var t0 := Time.get_ticks_usec()
	sim(g, 5.0)
	var per_frame := (Time.get_ticks_usec() - t0) / (5.0 / DT) / 1000.0
	print("    шаров %d, %.2f мс на кадр симуляции" % [g.balls.size(), per_frame])
	check(per_frame < 4.0, "симуляция %.2f мс на кадр — слишком медленно" % per_frame)


## У каждой строки в tr("...") есть английский перевод с теми же плейсхолдерами.
func test_translations_complete() -> void:
	var en: Dictionary = preload("res://scripts/i18n.gd").EN
	var re := RegEx.new()
	re.compile('tr\\("((?:[^"\\\\]|\\\\.)*)"\\)')
	var ph := RegEx.new()
	ph.compile("%[-0-9.]*[dsf%]")
	var keys := {}
	for f in DirAccess.get_files_at("res://scripts"):
		if not f.ends_with(".gd") or f == "i18n.gd":
			continue
		var src := FileAccess.get_file_as_string("res://scripts/" + f)
		for m in re.search_all(src):
			keys[m.get_string(1).replace("\\n", "\n").replace('\\"', '"')] = f
	# названия и описания шаров и карт тоже переводятся
	for t in GameData.TYPE_ORDER:
		for k in ["name", "desc", "perk", "perk_desc", "super", "super_desc"]:
			keys[GameData.TYPES[t][k]] = "game_data.gd"
	for mp in preload("res://scripts/maps.gd").get_maps():
		keys[mp["name"]] = "maps.gd"
	var missing := 0
	for k in keys:
		if not en.has(k):
			missing += 1
			check(false, "нет перевода (%s): %s" % [keys[k], k])
			continue
		var a := ph.search_all(k).map(func(m): return m.get_string())
		var b := ph.search_all(en[k]).map(func(m): return m.get_string())
		check(a == b, "плейсхолдеры не совпадают: «%s» → «%s»" % [k, en[k]])
	print("    строк для перевода: %d" % keys.size())


func _cyrillic_texts(node: Node, out: Array) -> void:
	var cyr := RegEx.new()
	cyr.compile("[А-Яа-яЁё]")
	var txt := ""
	if node is Label or node is Button:
		txt = node.text
	if node is TabContainer:
		for i in node.get_tab_count():
			txt += node.get_tab_title(i)
	if txt != "" and cyr.search(txt) != null and not (txt in GameData.LANG_NAMES.values()):
		out.append(txt)
	for c in node.get_children():
		_cyrillic_texts(c, out)


## В русском режиме интерфейс русский (у Godot запасной язык по умолчанию английский — ловим это).
func test_russian_ui() -> void:
	var g = await new_game(2)
	check(tr("Прокачка") == "Прокачка", "в русском режиме перевод не русский: %s" % tr("Прокачка"))
	check(g.btn_fire.text.begins_with("Выстрел"), "кнопка выстрела не на русском: %s" % g.btn_fire.text)


## На английском в интерфейсе игры и меню нет русских букв.
func test_english_ui() -> void:
	var g = await new_game(2, func():
		unlock_all(2, true)
		GameData.lang = "en"
		GameData.apply_settings())
	g.rubles = 100000
	g._show_upgrades(true)
	g._refresh_ui()
	var bad := []
	_cyrillic_texts(g.ui_root, bad)
	check(bad.is_empty(), "русский текст в английской игре: %s" % str(bad))
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._show_settings(true)
	await get_tree().process_frame
	var bad2 := []
	_cyrillic_texts(menu, bad2)
	menu._show_settings(false)
	await get_tree().process_frame
	_cyrillic_texts(menu, bad2)
	check(bad2.is_empty(), "русский текст в английском меню: %s" % str(bad2))
	menu.queue_free()
	GameData.lang = "ru"
	GameData.apply_settings()


## Рогатка: оттягивание назад стреляет вперёд, вытягивание за область — отмена, касание — ничего.
func test_slingshot() -> void:
	var g = await new_game(2)
	g.rubles = 100000
	var c := Vector2(360, 700)
	var n0: int = g.balls.size()
	g._sling_begin(c)
	g._sling_move(c + Vector2(0, 120))      # тянем вниз
	check(absf(g.aim_angle - (-90.0)) < 0.5, "оттянули вниз — направление вверх, а не %.1f" % g.aim_angle)
	g._sling_release()
	check(g.balls.size() == n0 + 1, "отпускание после оттягивания стреляет")
	var a: float = g.aim_angle
	g._sling_begin(c)
	g._sling_move(c + Vector2(100, 0))
	g._sling_move(c + Vector2(400, 0))      # за пределами области наведения
	check(g.sling_cancel, "вытянули за область — режим отмены")
	g._sling_release()
	check(g.balls.size() == n0 + 1, "отмена не стреляет")
	check(is_equal_approx(g.aim_angle, a), "отмена возвращает прежнее направление")
	g._sling_begin(c)
	g._sling_move(c + Vector2(5, 5))        # просто касание
	g._sling_release()
	check(g.balls.size() == n0 + 1, "короткое касание не стреляет")
	g.snap_mode = 2
	g._sling_begin(c)
	g._sling_move(c + Vector2(-100, 30))
	check(is_equal_approx(fposmod(g.aim_angle, 90.0), 0.0), "режим 90° округляет направление")
	g._sling_abort()

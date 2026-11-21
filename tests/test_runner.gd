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
	print("Важно: ошибка скрипта внутри теста прерывает его без FAIL — CI ищет такие ошибки в выводе.")
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
	GameData.lang_choice = "ru"
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
	g.coins = 1_000_000_000
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
		check(g._launch_from(g.start_pos) != null, "%s: со старта нельзя выстрелить" % maps[i]["id"])
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


## Монеты = снятые жизни, счётчики квадратов в кусках сходятся.
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
	var r0: int = g.coins
	sim(g, 30.0)
	var hp1 := 0
	for c in g.chunks:
		for li in 1024:
			if c.kind[li] == 1:
				hp1 += c.hp[li]
	check(g.coins - r0 == hp0 - hp1, "монеты %d ≠ снятые жизни %d" % [g.coins - r0, hp0 - hp1])
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


## Выстрел: списывает цену, цена растёт, шар появляется в точке; кнопка стреляет из места последнего выстрела.
func test_fire() -> void:
	var g = await new_game(0)
	g.coins = 1000
	var c0: int = g._ball_cost("basic")
	var p: Vector2 = g.start_pos + Vector2(10, 5)
	g._fire(p)
	check(g.coins == 1000 - c0, "выстрел списал не ту сумму")
	check(g.balls.size() == 2, "после выстрела должно быть 2 шара")
	check(g.balls[1].pos.distance_to(p) < 0.01, "шар появился не в точке выстрела")
	check(g._ball_cost("basic") > c0, "цена следующего шара не выросла")
	g._fire()
	check(g.balls[2].pos.distance_to(p) < 0.01, "кнопка «Выстрел» стреляет не из места последнего выстрела")
	g.coins = 0
	g._fire()
	check(g.balls.size() == 3, "выстрел без денег сработал")


## Точка вылета — ровно точка нажатия в пустой открытой клетке; на квадрат или в туман — нельзя.
func test_launch_from_press() -> void:
	var g = await new_game(2)
	var s: Vector2 = g.start_pos
	var a = g._launch_from(s + Vector2(3, -4))
	check(a != null and a.distance_to(s + Vector2(3, -4)) < 0.01, "в пустой клетке шар вылетает не из точки нажатия")
	var brick := Vector2.ZERO
	for y in range(g.ey0, g.ey1 + 1):
		for x in range(g.ex0, g.ex1 + 1):
			if g._vis_at(x, y) and g._kind_at(x, y) == 1:
				brick = (Vector2(x, y) + Vector2(0.5, 0.5)) * 40.0
	check(g._launch_from(brick) == null, "нажатие на квадрат разрешило выстрел (сдвигало точку)")
	check(g._launch_from(s + Vector2(40.0 * 30, 0)) == null, "нажатие в далёкий туман разрешило выстрел")
	# у стены/квадрата точка сдвигается не больше чем на радиус шара
	for y in range(g.ey0, g.ey1 + 1):
		for x in range(g.ex0, g.ex1 + 1):
			if g._kind_at(x, y) == 0 and g._vis_at(x, y) and g._kind_at(x, y - 1) == 1:
				var edge := Vector2(x * 40.0 + 20.0, y * 40.0 + 1.0)
				var p = g._launch_from(edge)
				check(p != null and p.distance_to(edge) <= 9.0, "у края клетки точка сдвинута слишком сильно")
				return


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
	var coins: int = g.coins
	var counts: Dictionary = g.counts.duplicate()
	var bpos: Array = g.balls.map(func(b): return [b.type, b.pos, b.vel.normalized()])
	var last: Vector2 = g.last_launch
	var snap := {}
	for ck in g.chunks.size():
		var c = g.chunks[ck]
		if c != null and c.changed:
			snap[ck] = [c.hp.duplicate(), c.vis.duplicate()]
	game.queue_free()
	game = null
	await get_tree().process_frame
	game = GAME.instantiate()
	add_child(game)   # _ready отрабатывает сразу; проверяем до первого кадра, пока шары не сдвинулись
	var g2 = game
	check(g2.destroyed == destroyed, "destroyed %d → %d" % [destroyed, g2.destroyed])
	check(g2.coins == coins, "монеты %d → %d" % [coins, g2.coins])
	check(g2.counts == counts, "число шаров не совпало")
	check(g2.balls.size() == bpos.size(), "после загрузки другое число шаров")
	var moved := 0
	for i in mini(bpos.size(), g2.balls.size()):
		var b = g2.balls[i]
		if b.type != bpos[i][0] or b.pos.distance_to(bpos[i][1]) > 0.01 or b.vel.normalized().distance_to(bpos[i][2]) > 0.001:
			moved += 1
	check(moved == 0, "после «Продолжить» шаров не на своих местах: %d" % moved)
	check(g2.last_launch.distance_to(last) < 0.01, "не восстановилось место последнего выстрела")
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


## «Сброс» включает режим: следующий выстрел рогаткой бесплатно перезапускает бездельника; кулдаун 30 с.
func test_reset_relaunches_idler() -> void:
	var g = await new_game(2)
	g.coins = 100000
	g._fire(g.start_pos)
	g._fire(g.start_pos + Vector2(5, 0))
	sim(g, 3.0)
	g.balls[0].earned = 100
	g.balls[1].earned = 0
	g.balls[2].earned = 50
	var idler = g.balls[1]
	var n0: int = g.balls.size()
	var r0: int = g.coins
	g._reset_stuck()
	check(g.reset_armed, "«Сброс» не включил режим перезапуска")
	g.cam.position = g.start_pos
	g._clamp_cam()
	var c: Vector2 = (g.start_pos - g.cam.position) * g.zoom + get_viewport().get_visible_rect().size * 0.5
	g._sling_begin(c)
	g._sling_move(c + Vector2(0, 100))
	var from = g.sling_from
	g._sling_release()
	check(g.balls.size() == n0, "перезапуск купил новый шар")
	check(g.coins == r0, "перезапуск списал монеты")
	check(from != null and idler.pos.distance_to(from) < 0.01, "перезапущен не бездельник или не из точки нажатия")
	check(absf(rad_to_deg(idler.vel.angle()) + 90.0) < 0.5, "бездельник полетел не в направлении прицела")
	check(not g.reset_armed and g.reset_cd["basic"] > 29.0, "после перезапуска не начался кулдаун")
	g._reset_stuck()
	check(not g.reset_armed, "во время кулдауна сброс включился")
	# выключение повторным нажатием
	g.reset_cd["basic"] = 0.0
	g._reset_stuck()
	g._reset_stuck()
	check(not g.reset_armed, "повторное нажатие не выключило сброс")
	# без денег рогатка не стреляет
	g.coins = 0
	g._sling_begin(c)
	g._sling_move(c + Vector2(0, 100))
	g._sling_release()
	check(g.balls.size() == n0, "без денег рогатка выстрелила")


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


## У каждой строки в tr("...") есть перевод на каждый язык с теми же плейсхолдерами.
func test_translations_complete() -> void:
	var I18n = preload("res://scripts/i18n.gd")
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
	for t in GameData.TYPE_ORDER:
		for k in ["name", "desc", "perk", "perk_desc", "super", "super_desc"]:
			keys[GameData.TYPES[t][k]] = "game_data.gd"
	for mp in preload("res://scripts/maps.gd").get_maps():
		keys[mp["name"]] = "maps.gd"
	for th in preload("res://scripts/maps.gd").THEMES:
		keys[th["name"]] = "maps.gd (темы)"
	check(I18n.LANGS.size() >= 16, "языков меньше 16")
	for code in I18n.LANGS:
		if code == "ru":
			continue
		var tab: Dictionary = I18n.table(code)
		var missing := 0
		for k in keys:
			if not tab.has(k):
				missing += 1
				if missing <= 3:
					check(false, "%s: нет перевода (%s): %s" % [code, keys[k], k])
				continue
			var a := ph.search_all(k).map(func(m): return m.get_string())
			var b := ph.search_all(tab[k]).map(func(m): return m.get_string())
			check(a == b, "%s: плейсхолдеры не совпадают: «%s» → «%s»" % [code, k, tab[k]])
			check(String(tab[k]).strip_edges() != "", "%s: пустой перевод «%s»" % [code, k])
		check(missing == 0, "%s: всего без перевода %d" % [code, missing])
		for k in tab:
			check(keys.has(k), "%s: лишний ключ (строка больше не используется): %s" % [code, k])
	print("    строк: %d, языков: %d" % [keys.size(), I18n.LANGS.size()])


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
	check(g.btn_reset.text.begins_with("Сброс"), "кнопка сброса не на русском: %s" % g.btn_reset.text)


## Нижняя панель не шире экрана, даже когда открыты все 5 типов и цены большие.
func test_bottom_bar_fits() -> void:
	var g = await new_game(2, func(): unlock_all())
	for t in GameData.TYPE_ORDER:
		g.counts[t] = 40
	g._refresh_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	var vw: float = get_viewport().get_visible_rect().size.x
	check(g.bottom_bar.size.x <= vw + 0.5, "нижняя панель %.0f px шире экрана %.0f px" % [g.bottom_bar.size.x, vw])
	for t in g.chips:
		var r: Rect2 = g.chips[t].get_global_rect()
		check(r.end.x <= vw + 0.5, "фишка %s за краем экрана" % t)
	check(g.chips["basic"].get_meta("price").text != "", "на фишке нет цены")


## На любом языке, кроме русского, в интерфейсе игры и меню нет русских букв.
func test_foreign_ui() -> void:
	for code in GameData.LANGS:
		if code == "ru":
			continue
		var g = await new_game(2, func():
			unlock_all(2, true)
			GameData.lang_choice = code
			GameData.apply_settings())
		g.coins = 100000
		g._show_upgrades(true)
		g._refresh_ui()
		var bad := []
		_cyrillic_texts(g.ui_root, bad)
		check(bad.is_empty(), "%s: русский текст в игре: %s" % [code, str(bad)])
		var menu = load("res://scenes/main_menu.tscn").instantiate()
		add_child(menu)
		await get_tree().process_frame
		var bad2 := []
		_cyrillic_texts(menu, bad2)
		menu._show_settings(true)
		await get_tree().process_frame
		var bad3 := []
		_cyrillic_texts(menu, bad3)
		menu.queue_free()
		check(bad2.is_empty(), "%s: русский текст в меню: %s" % [code, str(bad2)])
		check(bad3.is_empty(), "%s: русский текст в настройках: %s" % [code, str(bad3)])
	GameData.lang_choice = "ru"
	GameData.apply_settings()


## Рогатка: оттягивание назад стреляет вперёд, вытягивание за область — отмена, касание — ничего.
func test_slingshot() -> void:
	var g = await new_game(2)
	g.coins = 100000
	g.cam.position = g.start_pos
	g._clamp_cam()
	var c: Vector2 = (g.start_pos - g.cam.position) * g.zoom + get_viewport().get_visible_rect().size * 0.5   # экранная точка старта
	var n0: int = g.balls.size()
	g._sling_begin(c)
	g._sling_move(c + Vector2(0, 120))      # тянем вниз
	check(absf(g.aim_angle - (-90.0)) < 0.5, "оттянули вниз — направление вверх, а не %.1f" % g.aim_angle)
	var from = g.sling_from
	g._sling_release()
	check(g.balls.size() == n0 + 1, "отпускание после оттягивания стреляет")
	check(from != null and g.balls[-1].pos.distance_to(g._launch_from(g._screen_to_world(c))) < 0.01, "шар вылетел не из точки нажатия")
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
	# нажатие в туман — выстрела нет
	var far: Vector2 = c + Vector2(0, -40.0 * 30 * g.zoom)
	g._sling_begin(far)
	g._sling_move(far + Vector2(0, 100))
	g._sling_release()
	check(g.balls.size() == n0 + 1, "рогатка из тумана выстрелила")


## Жест одним пальцем: сразу повёл — двигается карта; подержал — прицел; короткое касание — ничего.
func test_gesture_hold_vs_pan() -> void:
	var g = await new_game(2, func(): unlock_all())
	fire_n(g, "basic", 20)
	sim(g, 15.0)
	g.balls.clear()
	g.coins = 100000
	g.cam.position = g.start_pos
	g._clamp_cam()
	var c: Vector2 = (g.start_pos - g.cam.position) * g.zoom + get_viewport().get_visible_rect().size * 0.5
	# 1. сразу повёл — перемещение карты, без прицела и выстрела
	var cam0: Vector2 = g.cam.position
	g._press_down(c)
	g._hold_tick(0.05)
	g._press_drag(c + Vector2(0, 60), Vector2(0, 60))
	check(g.panning and not g.sling, "быстрый сдвиг пальца не перешёл в перемещение карты")
	g._hold_tick(0.5)
	check(not g.sling, "после начала перемещения прицел всё равно включился")
	g._press_up()
	check(g.cam.position != cam0, "карта не сдвинулась")
	check(g.balls.size() == 0, "перемещение карты выстрелило")
	# 2. подержал — прицел, оттянул и отпустил — выстрел
	g.cam.position = g.start_pos
	g._clamp_cam()
	c = (g.start_pos - g.cam.position) * g.zoom + get_viewport().get_visible_rect().size * 0.5
	g._press_down(c)
	g._hold_tick(0.1)
	check(not g.sling, "прицел включился раньше удержания")
	g._hold_tick(0.2)
	check(g.sling, "после удержания прицел не включился")
	g._press_drag(c + Vector2(0, 100), Vector2(0, 100))
	g._press_up()
	check(g.balls.size() == 1, "прицел с удержанием не выстрелил")
	# 3. короткое касание — ничего
	g._press_down(c)
	g._hold_tick(0.1)
	g._press_up()
	g._hold_tick(0.5)
	check(not g.sling and g.balls.size() == 1, "короткое касание что-то сделало")


## Язык по умолчанию — язык системы: русский для русской системы, для любой другой — английский.
func test_default_language() -> void:
	for pair in [["ru", "ru"], ["ru_RU", "ru"], ["en", "en"], ["en_US", "en"], ["de_DE", "de"], ["es_MX", "es"],
			["pt_PT", "pt_BR"], ["pt_BR", "pt_BR"], ["zh_TW", "zh_CN"], ["zh", "zh_CN"], ["ja", "ja"], ["ar_EG", "ar"],
			["hi_IN", "hi"], ["bn", "bn"], ["uk", "en"], ["kk", "en"], ["xx", "en"]]:
		check(GameData.system_lang(pair[0]) == pair[1], "система %s → %s, а не %s" % [pair[0], GameData.system_lang(pair[0]), pair[1]])
	var keep: String = GameData.lang_choice
	GameData.lang_choice = ""
	GameData.apply_settings()
	check(GameData.lang == GameData.system_lang(OS.get_locale()), "без выбора язык не системный")
	# выбор игрока сохраняется и побеждает систему; старый автоматический ключ "lang" игнорируется
	GameData.lang_choice = "en"
	GameData.save_game()
	GameData.lang_choice = ""
	GameData.load_game()
	check(GameData.lang_choice == "en", "выбранный язык не сохранился")
	var f := FileAccess.open(GameData.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"u": 0, "lang": "ru"}))
	f.close()
	GameData.load_game()
	check(GameData.lang_choice == "", "старое автоматическое значение языка считается выбором игрока")
	GameData.lang_choice = keep
	GameData.apply_settings()


## Старое сохранение (до v0.14), где монеты назывались "rubles", загружается без потери денег.
func test_old_save_currency_key() -> void:
	var g = await new_game(2)
	g.coins = 12345
	g._save_state()
	var path: String = g._save_path()
	var f := FileAccess.open(path, FileAccess.READ)
	var d: Dictionary = f.get_var()
	f.close()
	d["rubles"] = d["coins"]
	d.erase("coins")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_var(d)
	f.close()
	game.queue_free()
	game = null
	await get_tree().process_frame
	game = GAME.instantiate()
	add_child(game)
	check(game.coins == 12345, "монеты из старого ключа rubles не загрузились: %d" % game.coins)


## Цены не переполняются на больших уровнях (раньше могли стать отрицательными), числа читаемы.
func test_costs_no_overflow() -> void:
	var g = await new_game(0)
	for n in [0, 50, 150, 400, 2000]:
		g.counts["basic"] = n
		g.dmg_lvl["basic"] = n
		g.spd_lvl["basic"] = mini(n, 10)
		check(g._ball_cost("basic") > 0, "цена шара при n=%d: %d" % [n, g._ball_cost("basic")])
		check(g._dmg_cost("basic") > 0, "цена урона при ур.%d: %d" % [n, g._dmg_cost("basic")])
	g.counts["basic"] = 2000
	g.coins = 1_000_000_000_000_000_000
	var n0: int = g.balls.size()
	g._fire(g.start_pos)
	check(g.balls.size() == n0, "огромная цена позволила купить шар (раньше цена переполнялась в минус)")
	g.coins = 4_100_000_000_000_000_000
	g._fire(g.start_pos)
	check(g.coins >= 0, "после покупки по предельной цене монеты ушли в минус")
	for v in [999, 1500, 2_500_000, 3_000_000_000, 4_000_000_000_000, 5e15, 7e18]:
		var s: String = GameData.fmt(v)
		check(s.length() <= 7, "fmt(%s) = «%s» слишком длинно" % [str(v), s])


## Генерация карт не зависит от встроенного hash() Godot (может поменяться в новой версии движка).
func test_seed_stable() -> void:
	var g = await new_game(0)
	for id in ["meadow", "heart", "garden", "yard", "mountains", "ocean", "night"]:
		check(g._seed_of(id) == hash(id), "сид %s: %d ≠ hash() %d" % [id, g._seed_of(id), hash(id)])
	# значения зафиксированы: при их изменении все сохранённые карты «переедут»
	var locked := {"meadow": 226223394, "heart": 261227161, "garden": 4282245238, "yard": 2090931477,
		"mountains": 855852931, "ocean": 269460523, "night": 268492639}
	for id in locked:
		check(g._seed_of(id) == locked[id], "сид %s изменился: %d" % [id, g._seed_of(id)])


## В сохранении открытой части хранится и тип клеток — карта не «переедет» при изменении генератора.
func test_saved_chunks_keep_walls() -> void:
	var g = await new_game(2, func(): unlock_all())
	fire_n(g, "basic", 20)
	sim(g, 15.0)
	g._save_state()
	var f := FileAccess.open(g._save_path(), FileAccess.READ)
	var d: Dictionary = f.get_var()
	f.close()
	var ok := 0
	for ck in d["chunks"]:
		var b: Array = d["chunks"][ck]
		if int(b[1]) == 1024 * 6:
			ok += 1
	check(ok == d["chunks"].size() and ok > 0, "в сохранении кусков с типами клеток %d из %d" % [ok, d["chunks"].size()])
	# подменяем генератор: стены из сохранения должны остаться на месте
	var walls := {}
	for ck in d["chunks"]:
		var c = g.chunks[int(ck)]
		for li in 1024:
			if c.kind[li] == 2 and c.vis[li] == 1:
				walls[Vector2i(int(ck), li)] = true
	game.queue_free()
	game = null
	await get_tree().process_frame
	game = GAME.instantiate()
	game.set_meta("test_no_pictures", true)
	add_child(game)
	var moved := 0
	for k in walls:
		if game.chunks[k.x] == null or game.chunks[k.x].kind[k.y] != 2:
			moved += 1
	check(moved == 0, "видимые стены пропали после смены генератора: %d из %d" % [moved, walls.size()])


## Повреждённый или недописанный файл сохранения не ломает игру; запись атомарная (через временный файл).
func test_save_robust() -> void:
	var g = await new_game(2)
	g.coins = 777
	g._save_state()
	var path: String = g._save_path()
	# недописанный временный файл (как будто телефон выключился посреди записи) не мешает загрузке
	var t := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	t.store_string("мусор")
	t.close()
	game.queue_free()
	game = null
	await get_tree().process_frame
	game = GAME.instantiate()
	add_child(game)
	check(game.coins == 777, "загрузка сломалась из-за недописанного временного файла")
	# совсем битый основной файл — игра стартует, а не падает
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not a save")
	f.close()
	game.queue_free()
	game = null
	await get_tree().process_frame
	game = GAME.instantiate()
	add_child(game)
	check(game.balls.size() >= 1, "игра не стартовала с битым сохранением")


## Хаос-тест: тысяча случайных действий игрока; после каждого — проверка инвариантов.
func test_chaos() -> void:
	for map_i in [1, 3]:
		var g = await new_game(map_i, func(): unlock_all(2, false))
		var rng := RandomNumberGenerator.new()
		rng.seed = 777 + map_i
		g.coins = 200000
		var vs := get_viewport().get_visible_rect().size
		for step in 1000:
			var a := rng.randi() % 12
			match a:
				0, 1, 2:
					g._select(GameData.TYPE_ORDER[rng.randi() % 5])
					var lp = g._launch_from(g.start_pos + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)))
					if lp != null:
						g.aim_angle = rng.randf_range(-180, 180)
						g._fire(lp)
				3:
					g._buy_dmg(GameData.TYPE_ORDER[rng.randi() % 5])
				4:
					g._buy_spd(GameData.TYPE_ORDER[rng.randi() % 5])
				5:
					g._reset_stuck()
				6:
					var p := Vector2(rng.randf() * vs.x, rng.randf() * vs.y)
					g._press_down(p)
					g._hold_tick(0.3)
					g._press_drag(p + Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200)), Vector2.ZERO)
					g._press_up()
				7:
					var p2 := Vector2(rng.randf() * vs.x, rng.randf() * vs.y)
					g._press_down(p2)
					g._press_drag(p2 + Vector2(40, 30), Vector2(40, 30))
					g._press_up()
				8:
					g._set_zoom(g.zoom * rng.randf_range(0.5, 2.0), vs * 0.5)
				9:
					g._cycle_snap()
				10:
					g._show_upgrades(rng.randf() < 0.5)
				11:
					g._save_state()
			sim(g, 0.2)
			for b in g.balls:
				var e := ball_position_ok(g, b)
				if e != "":
					check(false, "шаг %d: %s" % [step, e])
					return
			if g.coins < 0:
				check(false, "шаг %d: монеты ушли в минус" % step)
				return
		var solid_bad := 0
		for c in g.chunks:
			if c == null:
				continue
			var s := 0
			for li in 1024:
				if c.kind[li] == 1 or c.kind[li] == 2:
					s += 1
			if s != c.solid:
				solid_bad += 1
		check(solid_bad == 0, "карта %d: расхождение solid в %d кусках" % [map_i, solid_bad])
		var counted := {}
		for b in g.balls:
			counted[b.type] = int(counted.get(b.type, 0)) + 1
		for t in GameData.TYPE_ORDER:
			check(int(counted.get(t, 0)) == int(g.counts[t]), "карта %d: шаров %s %d, а куплено %d" % [map_i, t, int(counted.get(t, 0)), g.counts[t]])


## Перерисовка поля не чаще 10 раз в секунду (батарея).
func test_redraw_throttle() -> void:
	var g = await new_game(2, func(): unlock_all())
	fire_n(g, "splash", 20)
	var redraws := [0]
	for c in g.chunks:
		if c != null and c.node != null:
			c.node.draw.connect(func(): redraws[0] += 1)
	for f in 60:
		await get_tree().process_frame
	var per_chunk_frames: float = float(redraws[0]) / maxf(1.0, float(g.field_root.get_child_count()))
	print("    перерисовок куска за 60 кадров: %.1f" % per_chunk_frames)
	check(per_chunk_frames <= 12.0, "кусок перерисовывается %.1f раз за 60 кадров (больше 10/с)" % per_chunk_frames)


## Повреждённый save.json (неверные типы полей) не роняет игру и не даёт мусорных значений.
func test_corrupt_global_save() -> void:
	var f := FileAccess.open(GameData.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"u": "много", "unlocked": [1, 2], "perks": {"basic": 99}, "maps_unlocked": -5,
		"maps_done": "x", "map_states": 7, "lang_choice": "de"}))
	f.close()
	GameData.load_game()
	check(GameData.u == 0, "u из строки: %s" % str(GameData.u))
	check(GameData.perks["basic"] == GameData.PERK_MAX, "перк не ограничен максимумом: %d" % GameData.perks["basic"])
	check(GameData.maps_unlocked >= 1, "открытых карт меньше одной")
	check(typeof(GameData.map_states) == TYPE_DICTIONARY and typeof(GameData.maps_done) == TYPE_DICTIONARY, "словари из мусора")
	GameData.reset_all()


## Золотой квадрат: разрушение включает «золотую лихорадку» (урон ×2 на 15 с).
func test_golden_frenzy() -> void:
	var g = await new_game(2)
	var gold_id := -1
	for ck in g.chunks.size():
		var c = g.chunks[ck]
		if c == null:
			continue
		for li in 1024:
			if c.gold[li] == 1 and c.kind[li] == 1:
				gold_id = ((ck / g.cw) * 32 + (li >> 5)) * g.W + (ck % g.cw) * 32 + (li & 31)
				break
		if gold_id >= 0:
			break
	check(gold_id >= 0, "на карте нет золотых квадратов")
	if gold_id < 0:
		return
	g._damage(gold_id, 1_000_000, null)
	check(g.frenzy_t > 14.0, "лихорадка не началась")
	g.frenzy_t = 29.0
	g._on_destroyed(gold_id % g.W, gold_id / g.W, gold_id)   # повторно — флаг уже снят, лихорадка не растёт
	check(g.frenzy_t <= 30.0, "лихорадка копится больше 30 с")
	g.frenzy_t = 15.0
	g.balls.clear()
	g._fire(g.start_pos)
	var b = g.balls[0]
	var dmg0: int = g.st_dmg[0]
	var target := -1
	for y in range(g.ey0, g.ey1 + 1):
		for x in range(g.ex0, g.ex1 + 1):
			if g._kind_at(x, y) == 1 and g._hp_of(y * g.W + x) > dmg0 * 2:
				target = y * g.W + x
	var hp0: int = g._hp_of(target)
	g._hit_cell(b, target)
	check(hp0 - g._hp_of(target) == dmg0 * 2, "в лихорадку урон не удвоен: %d вместо %d" % [hp0 - g._hp_of(target), dmg0 * 2])
	sim(g, 16.0)
	check(g.frenzy_t == 0.0, "лихорадка не закончилась")


## Финал маленькой карты: последние квадраты открываются, шары добивают их сами.
func test_finale_completes() -> void:
	var g = await new_game(1, func(): unlock_all())
	var ids := []
	for ck in g.chunks.size():
		var c = g.chunks[ck]
		for li in 1024:
			if c.kind[li] == 1:
				ids.append(((ck / g.cw) * 32 + (li >> 5)) * g.W + (ck % g.cw) * 32 + (li & 31))
	ids.shuffle()
	var keep: int = int(g.total * 0.05)
	for i in ids.size() - keep:
		g._damage(ids[i], 1_000_000, null)
	g._check_goal()
	check(g.finale, "финал не начался при %d оставшихся" % g.alive)
	var hidden := 0
	for id in g.finale_ids:
		if not g._vis_id(id):
			hidden += 1
	check(hidden == 0, "в финале скрыто квадратов: %d" % hidden)
	g.coins = 100_000_000
	fire_n(g, "basic", 10)
	for k in 10:
		g._buy_dmg("basic")   # урон ×22 — финал проверяет наведение, а не терпение
	var t0: float = g.time_acc
	sim(g, 90.0, func(gg):
		gg._check_goal()
		return gg.alive > 0)
	check(g.alive == 0, "за 90 с финала осталось квадратов: %d" % g.alive)
	print("    финал на %d квадратов занял %.0f с" % [keep, g.time_acc - t0])


## Урон: на каждом 10-м уровне — дополнительное удвоение.
func test_damage_milestones() -> void:
	var g = await new_game(0)
	var base: float = GameData.TYPES["basic"]["damage"]
	for pair in [[0, 1], [9, 10], [10, 22], [19, 40], [20, 84]]:
		g.dmg_lvl["basic"] = pair[0]
		check(g._damage_of("basic") == int(base * pair[1]), "урон на ур.%d: %d, а не %d" % [pair[0], g._damage_of("basic"), int(base * pair[1])])


## Постоянный бонус монет за выполненные цели карт.
func test_coin_bonus() -> void:
	var g = await new_game(2, func():
		GameData.maps_done = {"meadow": true, "heart": true})
	check(is_equal_approx(g.coin_mult, 1.5), "бонус за 2 карты %.2f, а не 1.5" % g.coin_mult)
	var id := -1
	for y in g.H:
		for x in g.W:
			if id < 0 and g._kind_at(x, y) == 1 and g._hp_of(y * g.W + x) >= 10:
				id = y * g.W + x
	check(id >= 0, "не нашёлся квадрат с 10+ жизнями")
	var c0: int = g.coins
	g._damage(id, 10, null)
	check(g.coins - c0 == 15, "10 урона при бонусе +50%% дали %d монет" % (g.coins - c0))


## Темп игры (бот из симулятора баланса): первые карты проходятся быстро и без долгих пауз без покупок.
func test_balance_pacing() -> void:
	var bot = load("res://tests/balance_sim.gd").new()
	bot.rng.seed = 42
	var limits := [[0, 8.0, 60.0], [1, 12.0, 90.0]]
	for lim in limits:
		var g = await new_game(lim[0], func(): GameData.maps_done = {} if lim[0] == 0 else {"meadow": true})
		var r: Dictionary = bot._play(g, lim[1])
		check(g.goal_done, "%s: цель не достигнута за %.0f мин" % [g.map["id"], lim[1]])
		check(r["max_wait"] <= lim[2], "%s: пауза без покупок %.0f с (больше %.0f)" % [g.map["id"], r["max_wait"], lim[2]])
		print("    %s: цель за %s мин, самая долгая пауза %.0f с" % [g.map["id"], r["goal_min"], r["max_wait"]])
	bot.free()


## Бесконечные уровни: любой номер даёт корректную карту, одинаковую при каждом вызове; сложность растёт.
func test_endless_levels() -> void:
	var Maps = preload("res://scripts/maps.gd")
	var prev_goal := 0
	var prev_hp := 0.0
	for i in [7, 8, 9, 20, 50, 200, 1000]:
		var a: Dictionary = Maps.get_map(i)
		var b: Dictionary = Maps.get_map(i)
		check(a == b, "уровень %d каждый раз разный" % (i + 1))
		check(a["id"] == "lv%d" % (i + 1), "id уровня %d: %s" % [i + 1, a["id"]])
		check(a["w"] <= 10000 and a["h"] <= 12500, "уровень %d слишком большой" % (i + 1))
		check(int(a["goal"]) > prev_goal and float(a["hp_base"]) > prev_hp, "сложность уровня %d не растёт" % (i + 1))
		check(int(a["goal"]) > 0 and int(a["goal"]) < 9_000_000_000_000_000_000, "цель уровня %d переполнена" % (i + 1))
		for tp in a["templates"]:
			check(Maps.templates().has(tp), "у уровня %d нет шаблона %s" % [i + 1, tp])
		prev_goal = int(a["goal"])
		prev_hp = float(a["hp_base"])
	# уровень за пределами нарисованных реально запускается
	for i in [7, 18, 63]:
		var g = await new_game(i, func(): GameData.maps_unlocked = i + 1)
		check(g.map["id"] == "lv%d" % (i + 1), "открылась не та карта")
		check(g._kind_at(g.start_cell.x, g.start_cell.y) == 0 and g._launch_from(g.start_pos) != null, "уровень %d: со старта нельзя выстрелить" % (i + 1))
		fire_n(g, "basic", 10)
		var err := [""]
		sim(g, 10.0, func(gg):
			for bb in gg.balls:
				var e := ball_position_ok(gg, bb)
				if e != "":
					err[0] = e
					return false
			return true)
		check(err[0] == "", "уровень %d: %s" % [i + 1, err[0]])
		check(g.destroyed > 0, "уровень %d: ничего не разбивается" % (i + 1))
	# все шаблоны строятся: у каждой картинки есть полость и вход
	var g2 = await new_game(7)
	for name in Maps.templates():
		var reg: Dictionary = g2._build_picture([[name, Rect2i(5, 5, 30, 30)]], Rect2i(4, 4, 32, 32))
		var cav := 0
		for v in reg["mask"]:
			if v == 4:
				cav += 1
		check(cav > 0, "у шаблона %s нет полости с входом" % name)


## Меню показывает открытые уровни и следующий закрытый — даже далеко за нарисованными.
func test_menu_endless() -> void:
	GameData.reset_all()
	GameData.lang_choice = "ru"
	GameData.apply_settings()
	GameData.maps_unlocked = 15
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	check(menu.list.get_child_count() == 16, "в меню %d уровней, а должно быть 16 (15 открыто + следующий)" % menu.list.get_child_count())
	var last_title: String = menu.list.get_child(15).get_child(0).get_child(1).get_child(0).text
	check(last_title.ends_with("16"), "название 16-го уровня: %s" % last_title)
	menu.queue_free()
	GameData.reset_all()


## «Мастерство»: бесконечная трата U, +10% урона всем шарам за уровень, сохраняется.
func test_mastery() -> void:
	var g = await new_game(2)
	var d0: int = g._damage_of("splash")
	GameData.u = 100
	g._mastery_up()
	check(GameData.mastery == 1 and GameData.u == 95, "мастерство не купилось за 5 U")
	g._mastery_up()
	check(GameData.mastery == 2 and GameData.u == 88, "второй уровень мастерства стоил не 7 U")
	check(g._damage_of("splash") == int(round(d0 * 1.2)), "урон с мастерством 2: %d, а не %d" % [g._damage_of("splash"), int(round(d0 * 1.2))])
	GameData.save_game()
	GameData.mastery = 0
	GameData.load_game()
	check(GameData.mastery == 2, "мастерство не сохранилось")
	GameData.mastery = 1000
	check(GameData.mastery_cost() > 0 and g._damage_of("basic") > 0, "мастерство 1000 сломало числа")


## Раскладки картинок — узоры, а не россыпь: в кольце один мотив, левая половина зеркальная, детерминировано.
func test_layouts() -> void:
	var g = await new_game(3)   # «Кошачий двор», кольца
	check(g.map["layout"] == "rings", "у «Кошачьего двора» не кольца")
	var by_ring := {}
	var slots := 0
	var flips_ok := true
	for ry in range(0, g.H / g.region_size + 1):
		for rx in range(0, g.W / g.region_size + 1):
			var s: Array = g._layout_slot(rx, ry)
			if s.is_empty():
				continue
			slots += 1
			var c: Vector2 = (Vector2(rx, ry) + Vector2(0.5, 0.5)) * g.region_size
			var d: Vector2 = c - (Vector2(g.start_cell) + Vector2(0.5, 0.5))
			var ring := int(round(d.length() / g.region_size))
			if by_ring.has(ring) and by_ring[ring] != s[0]:
				check(false, "в кольце %d разные мотивы: %s и %s" % [ring, by_ring[ring], s[0]])
			by_ring[ring] = s[0]
			if bool(s[2]) != (d.x < 0.0):
				flips_ok = false
			check(s == g._layout_slot(rx, ry), "раскладка недетерминирована")
	check(slots > 10, "картинок слишком мало: %d" % slots)
	check(flips_ok, "левая половина не зеркальная")
	# у всех раскладок есть картинки, и бесконечные уровни получают разные узоры
	var seen := {}
	for i in range(7, 20):
		seen[preload("res://scripts/maps.gd").get_map(i)["layout"]] = true
	check(seen.size() >= 4, "у бесконечных уровней мало разных узоров: %s" % str(seen.keys()))


## Звуки: все загружены, выключатель работает, частые звуки ограничены по частоте.
func test_audio() -> void:
	for s in Sfx.SOUNDS:
		check(Sfx.players[s].stream != null, "звук %s не загрузился" % s)
	check(Sfx.music.stream != null and Sfx.music.stream.loop, "музыка не загрузилась или не зациклена")
	GameData.sfx_on = true
	Sfx._last.clear()
	var n0: int = int(Sfx.played.get("hit", 0))
	Sfx.play("hit")
	Sfx.play("hit")   # сразу второй — отсекается ограничителем
	check(int(Sfx.played.get("hit", 0)) == n0 + 1, "ограничитель частоты ударов не сработал")
	GameData.sfx_on = false
	var b0: int = int(Sfx.played.get("buy", 0))
	Sfx._last.clear()
	Sfx.play("buy")
	check(int(Sfx.played.get("buy", 0)) == b0, "звук играет при выключенных звуках")
	GameData.sfx_on = true
	# игровые события озвучены
	var g = await new_game(2)
	Sfx._last.clear()
	var l0: int = int(Sfx.played.get("launch", 0))
	g.coins = 1000
	g._fire(g.start_pos)
	check(int(Sfx.played.get("launch", 0)) == l0 + 1, "выстрел без звука")


## Вибрация при начале прицела — только если включена; настройки звука и вибрации сохраняются.
func test_vibration_and_settings() -> void:
	var g = await new_game(2)
	var c: Vector2 = get_viewport().get_visible_rect().size * 0.5
	GameData.vibration_on = true
	var v0: int = GameData.vibrations
	g._press_down(c)
	g._hold_tick(0.3)
	g._press_cancel()
	check(GameData.vibrations == v0 + 1, "нет вибрации при начале прицела")
	GameData.vibration_on = false
	g._press_down(c)
	g._hold_tick(0.3)
	g._press_cancel()
	check(GameData.vibrations == v0 + 1, "вибрация при выключенной настройке")
	GameData.music_on = false
	GameData.sfx_on = false
	GameData.save_game()
	GameData.music_on = true
	GameData.sfx_on = true
	GameData.vibration_on = true
	GameData.load_game()
	check(not GameData.music_on and not GameData.sfx_on and not GameData.vibration_on, "настройки звука/вибрации не сохранились")
	GameData.music_on = true
	GameData.sfx_on = true
	GameData.vibration_on = true
	GameData.save_game()


## Граница карты и сетка в тумане: слои есть и перерисовываются при движении камеры.
func test_border_and_fog_grid() -> void:
	var g = await new_game(0)
	check(g.frame_node != null and g.border_node != null, "нет слоёв границы и сетки")
	var draws := [0]
	g.border_node.draw.connect(func(): draws[0] += 1)
	g.cam.position += Vector2(80, 0)
	g._clamp_cam()
	await get_tree().process_frame
	await get_tree().process_frame
	check(draws[0] >= 1, "граница не перерисовалась при движении камеры")

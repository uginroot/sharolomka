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
	# окно как у телефона (портрет 720×1280): без этого в режиме без экрана окно 64×64, видимая область
	# 1280×1280, и проверки вёрстки «не вылезает за экран» шли на ширине 1280 (найдено в v0.32)
	get_window().size = Vector2i(720, 1280)
	await get_tree().process_frame
	await get_tree().process_frame
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
	_apply_tree(game)
	await get_tree().process_frame
	return game


func _free_game() -> void:
	if game != null:
		game.queue_free()
		game = null


var _pending_unlock := false   # открыть все типы на создаваемом уровне (unlock_all)


## Открыть на создаваемом уровне все шесть типов (в игре — по 1 U). Параметры — для совместимости старых вызовов.
func unlock_all(_perk: int = 0, _sup: bool = false) -> void:
	_pending_unlock = true


func _apply_tree(g) -> void:
	if not _pending_unlock:
		return
	for t in GameData.TYPE_ORDER:
		g.unl[t] = true
	g._rebuild_rows()
	_pending_unlock = false


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
		# старт — в центре карты, у сцен — в заданной точке переднего плана
		var want := Vector2i(g.W / 2, g.H / 2)
		if maps[i].has("start"):
			want = Vector2i(int(float(maps[i]["start"][0]) * g.W), int(float(maps[i]["start"][1]) * g.H))
		check(s == want, "%s: старт не там, где задан" % maps[i]["id"])
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
	# монеты = снятые жизни × множитель (бонус стаи Пронизывающих: 10 шт. = 2 ступени = +10%)
	var expect := int(floor((hp0 - hp1) * g.coin_mult))
	check(absi(g.coins - r0 - expect) <= 1, "монеты %d ≠ снятые жизни %d × %.2f" % [g.coins - r0, hp0 - hp1, g.coin_mult])
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
		g._buy_track("splash", "impact")
	# как в игре: проверка цели запускает финал, который ведёт шары к последним квадратам
	# (без неё последний квадрат добивался случайно — тест «плавал», найдено при переносе v0.27)
	sim(g, 120.0, func(gg):
		gg._check_goal()
		return gg.alive > 0)
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
		for k in ["name", "desc"]:
			keys[GameData.TYPES[t][k]] = "game_data.gd"
		for tr_ in GameData.TYPES[t]["tracks"]:
			keys[tr_["name"]] = "game_data.gd (ветки)"
	for f in GameData.FLEET_DESC:
		keys[GameData.FLEET_DESC[f]] = "game_data.gd (бонус стаи)"
	for mp in preload("res://scripts/maps.gd").get_maps():
		keys[mp["name"]] = "maps.gd"
	for id in preload("res://scripts/picture_maps.gd").PICS:
		keys[preload("res://scripts/picture_maps.gd").PICS[id]["name"]] = "picture_maps.gd"
	for tp in GameData.EVOS:
		for e in GameData.EVOS[tp]:
			keys[e["name"]] = "game_data.gd (эволюции)"
			keys[e["desc"]] = "game_data.gd (эволюции)"
			for tr_ in e["tracks"]:
				keys[tr_["name"]] = "game_data.gd (ветки эволюций)"
	for br in GameData.META_BRANCHES:
		keys[br] = "game_data.gd (ветки)"
	for m in GameData.META:
		if m.has("name"):
			keys[m["name"]] = "game_data.gd (Наследие)"
			keys[m["desc"]] = "game_data.gd (Наследие)"
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
	check(g.btn_reset.text == "Вернуть шар", "кнопка «Вернуть шар» не на русском: %s" % g.btn_reset.text)


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
	check(g.top_bar.size.x <= vw + 0.5, "верхняя панель %.0f px шире экрана" % g.top_bar.size.x)
	# нижний ряд: прокачка, угол, сброс — в этом порядке; меню справа вверху; надписи не вылезают на всех языках
	var row: HBoxContainer = g.btn_snap.get_parent()
	check(row.get_child(0).text == tr("Прокачка") and row.get_child(1) == g.btn_snap and row.get_child(2) == g.btn_reset,
		"порядок нижних кнопок не «прокачка, угол, сброс»")
	check(g.btn_snap.get_parent().get_parent().get_parent().get_parent() == g.bottom_bar, "выбор угла не внизу")
	var top_row: HBoxContainer = g.lbl_rub.get_parent().get_parent().get_parent()
	check(top_row.get_child(top_row.get_child_count() - 1) is Button, "кнопка меню не справа вверху")
	var bar_h := -1.0
	for code in ["ru", "de", "hi", "vi"]:
		GameData.lang_choice = code
		GameData.apply_settings()
		for mode in [0, 1, 2]:
			g.snap_mode = mode
			for armed in [false, true]:
				g.reset_armed = armed
				g.reset_cd["basic"] = 0.0 if armed else 28.0
				g._refresh_ui()
				await get_tree().process_frame
				for bb in [row.get_child(0), g.btn_snap, g.btn_reset]:
					check(bb.get_global_rect().end.x <= vw + 0.5, "%s: кнопка «%s» за краем экрана" % [code, bb.text])
					var fsz: int = bb.get_theme_font_size("font_size")
					var w1: float = GameData.font.get_string_size(bb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
					# с переносом строки текст может занимать 2 строки — ширина самого длинного слова должна влезать
					# мерить ширину имеет смысл, только если встроенный шрифт содержит все символы: иначе в окружении
					# без системных шрифтов (CI) меряются запасные глифы, а на телефоне шрифт письменности есть
					var covered := true
					for ch in bb.text:
						if not GameData.font.has_char(ch.unicode_at(0)):
							covered = false
					if not covered:
						continue
					# надпись — целиком в одну строку (шрифт ужимается): высота кнопки не меняется
					var sb: StyleBox = bb.get_theme_stylebox("normal")
					var room: float = bb.size.x - sb.get_content_margin(SIDE_LEFT) - sb.get_content_margin(SIDE_RIGHT)
					if bb.icon != null:
						room -= float(bb.get_theme_constant("icon_max_width")) + float(bb.get_theme_constant("h_separation"))
					var need: float = GameData.font.get_string_size(bb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, bb.get_theme_font_size("font_size")).x
					check(need <= room + 0.5, "%s: надпись не помещается в одну строку: «%s» (%.0f > %.0f)" % [code, bb.text, need, room])
				# высота нижней панели одна и та же во всех состояниях и на всех языках
				if bar_h < 0.0:
					bar_h = g.bottom_bar.size.y
				check(is_equal_approx(g.bottom_bar.size.y, bar_h), "%s: нижняя панель прыгнула: %.0f → %.0f (режим %d, включён %s)" % [code, bar_h, g.bottom_bar.size.y, mode, armed])
	g.reset_armed = false
	GameData.lang_choice = "ru"
	GameData.apply_settings()
	# окно прокачки: карточки и узлы дерева не шире экрана (крупный шрифт, длинные слова)
	for code in ["ru", "de", "vi"]:
		GameData.lang_choice = code
		GameData.apply_settings()
		g._rebuild_rows()
		g._show_upgrades(true)
		for k in 3:
			await get_tree().process_frame
		for t in g.shop_refs:
			for id in g.shop_refs[t].get("tracks", {}):
				var lb: Label = g.shop_refs[t]["tracks"][id]["label"]
				var bt: Button = g.shop_refs[t]["tracks"][id]["button"]
				check(bt.get_global_rect().end.x <= vw + 0.5, "%s: кнопка ветки «%s» за краем экрана" % [code, lb.text])
		g._show_upgrades(false)
	GameData.lang_choice = "ru"
	GameData.apply_settings()


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
		menu._show_screen("legacy")
		await get_tree().process_frame
		_cyrillic_texts(menu, bad3)
		menu._show_screen("profiles")
		await get_tree().process_frame
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
	g.snap_mode = 1
	g._sling_begin(c)
	g._sling_move(c + Vector2(-100, 30))
	check(is_equal_approx(fposmod(g.aim_angle, 45.0), 0.0), "режим 45° округляет направление")
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


## Язык по умолчанию — язык системы; выбор хранится в общих настройках, старый ключ "lang" игнорируется.
func test_default_language() -> void:
	for pair in [["ru", "ru"], ["ru_RU", "ru"], ["en", "en"], ["en_US", "en"], ["de_DE", "de"], ["es_MX", "es"],
			["pt_PT", "pt_BR"], ["pt_BR", "pt_BR"], ["zh_TW", "zh_CN"], ["zh", "zh_CN"], ["ja", "ja"], ["ar_EG", "ar"],
			["hi_IN", "hi"], ["bn", "bn"], ["uk", "en"], ["kk", "en"], ["xx", "en"]]:
		check(GameData.system_lang(pair[0]) == pair[1], "система %s → %s, а не %s" % [pair[0], GameData.system_lang(pair[0]), pair[1]])
	var keep: String = GameData.lang_choice
	GameData.lang_choice = ""
	GameData.apply_settings()
	check(GameData.lang == GameData.system_lang(OS.get_locale()), "без выбора язык не системный")
	GameData.lang_choice = "en"
	GameData.save_settings()
	GameData.lang_choice = ""
	GameData.load_settings()
	check(GameData.lang_choice == "en", "выбранный язык не сохранился в общих настройках")
	GameData.lang_choice = keep
	GameData.apply_settings()
	GameData.save_settings()


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
		g.tlvl["basic"]["impact"] = n
		g.tlvl["basic"]["speed"] = n
		check(g._ball_cost("basic") > 0, "цена шара при n=%d: %d" % [n, g._ball_cost("basic")])
		check(g._track_cost("basic", "impact") > 0, "цена удара при ур.%d: %d" % [n, g._track_cost("basic", "impact")])
		check(g._speed("basic") <= g.MAX_SPEED + 0.01, "скорость выше предела при ур.%d" % n)
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
					g._select(GameData.TYPE_ORDER[rng.randi() % 6])
					var lp = g._launch_from(g.start_pos + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)))
					if lp != null:
						g.aim_angle = rng.randf_range(-180, 180)
						g._fire(lp)
				3:
					var tt: String = GameData.TYPE_ORDER[rng.randi() % 6]
					g._buy_track(tt, GameData.TYPES[tt]["tracks"][rng.randi() % GameData.TYPES[tt]["tracks"].size()]["id"])
				4:
					g._buy_track(GameData.TYPE_ORDER[rng.randi() % 6], "speed")
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
			check(int(counted.get(t, 0)) == int(g.counts[t]) + int(g.extra[t]), "карта %d: шаров %s %d, а куплено %d (+%d из залпов)" % [map_i, t, int(counted.get(t, 0)), g.counts[t], g.extra[t]])


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


## Повреждённый save.json профиля (неверные типы полей) не роняет игру и не даёт мусорных значений.
func test_corrupt_global_save() -> void:
	GameData.write_atomic(GameData.save_path(), JSON.stringify({"stars": "много", "meta": [1, 2],
		"maps_unlocked": -5, "maps_done": "x", "map_states": 7}))
	GameData.load_game()
	check(GameData.stars == 0, "звёзды из строки: %s" % str(GameData.stars))
	check(GameData.meta.is_empty(), "«Наследие» из мусора: %s" % str(GameData.meta))
	check(GameData.maps_unlocked >= 1, "открытых уровней меньше одного")
	check(typeof(GameData.map_states) == TYPE_DICTIONARY and typeof(GameData.maps_done) == TYPE_DICTIONARY, "словари из мусора")
	GameData.write_atomic(GameData.save_path(), JSON.stringify({"stars": 3, "meta": {"frenzy": 99, "sniper": 7}}))
	GameData.load_game()
	check(GameData.meta_level("frenzy") == 5, "уровни «Наследия» не ограничены максимумом")
	check(GameData.stars == 3 + 2 and not GameData.meta.has("sniper"), "★ за «Арсенал» не вернулись при битом уровне")
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
		g._buy_track("basic", "impact")   # урон ×11 — финал проверяет наведение, а не терпение
	var t0: float = g.time_acc
	sim(g, 90.0, func(gg):
		gg._check_goal()
		return gg.alive > 0)
	check(g.alive == 0, "за 90 с финала осталось квадратов: %d" % g.alive)
	print("    финал на %d квадратов занял %.0f с" % [keep, g.time_acc - t0])


## Ветки за монеты (как в pixel-rikoshet): «Сила удара» +1 (Отбойник +3) за уровень; цены — заданные, дальше ×1.7.
func test_tracks() -> void:
	var g = await new_game(0)
	check(g._damage_of("basic") == 1 and g._damage_of("pierce") == 8 and g._damage_of("poison") == 0, "базовый урон не как в каталоге")
	g.tlvl["basic"]["impact"] = 4
	g.tlvl["pierce"]["impact"] = 2
	check(g._damage_of("basic") == 5 and g._damage_of("pierce") == 14, "«Сила удара» не линейная")
	g.tlvl["basic"]["impact"] = 0
	var costs := []
	for k in 5:
		costs.append(g._track_cost("basic", "impact"))
		g.tlvl["basic"]["impact"] = k + 1
	check(costs[0] == 50 and costs[1] == 112 and costs[2] == 240, "заданные цены ветки: %s" % str(costs))
	check(costs[3] == int(round(240 * 1.7)) and costs[4] == int(round(240 * 1.7 * 1.7)), "после заданных цен не ×1.7: %s" % str(costs))
	# цена пуска: (база + 5·n)·1.12ⁿ
	g.counts["sniper"] = 10
	check(g._ball_cost("sniper") == int(round((50 + 50) * pow(1.12, 10))), "цена пуска не по формуле")


## Бонус монет из «Наследия»: +10% за уровень «Бонуса монет».
func test_coin_bonus() -> void:
	var g = await new_game(2, func():
		GameData.meta = {"coin_bonus": 5})
	check(is_equal_approx(g.coin_mult, 1.5), "бонус за 5 уровней %.2f, а не 1.5" % g.coin_mult)
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


## «Наследие»: цепочки, цена, максимум, звёзды; эффекты на старте уровня.
func test_legacy() -> void:
	GameData.reset_all()
	GameData.stars = 30
	check(not GameData.meta_buy("start_coins"), "«Стартовые монеты» купились без «Бонуса монет» (цепочка)")
	check(GameData.meta_buy("coin_bonus") and GameData.meta_cost("coin_bonus") == 2, "цена «Бонуса монет» не растёт")
	check(GameData.meta_buy("start_coins"), "«Стартовые монеты» не купились после «Бонуса монет»")
	check(GameData.meta_buy("start_balls") and GameData.meta_buy("dmg_bonus"), "не купились «Стартовые шары» и «Урон»")
	GameData.stars = 100
	for k in 7:
		GameData.meta_buy("start_balls")
	check(GameData.meta_level("start_balls") == 5, "превышен максимум «Стартовых шаров»")
	GameData.save_game()
	var lv: Dictionary = GameData.meta.duplicate()
	GameData.load_game()
	check(GameData.meta == lv, "«Наследие» не сохранилось")
	# эффекты на старте уровня
	GameData.meta["start_u"] = 2
	GameData.meta["u_find"] = 1
	var keep := GameData.meta.duplicate()
	var g = await new_game(2, func(): GameData.meta = keep.duplicate(); GameData.refresh_unlocked())
	check(g.balls.size() == 6, "стартовых шаров %d, а должно быть 6" % g.balls.size())
	check(g.coins == 90, "стартовых монет %d, а должно быть 90" % g.coins)
	check(g.run_u == 2, "стартовых U %d, а должно быть 2" % g.run_u)
	check(is_equal_approx(GameData.dmg_mult(), 1.1), "«Урон» не дал +10%")
	# «Арсенал» убран: потраченные на него ★ возвращаются
	GameData.write_atomic(GameData.save_path(), JSON.stringify({"stars": 1, "meta": {"splash": 1, "sniper": 1}}))
	GameData.load_game()
	check(GameData.stars == 1 + 1 + 2 and not GameData.meta.has("splash"), "★ за «Арсенал» не вернулись: %d" % GameData.stars)


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
	GameData.music_vol = 0.0
	GameData.sfx_vol = 0.35
	GameData.save_settings()
	GameData.music_vol = 0.8
	GameData.sfx_vol = 0.8
	GameData.vibration_on = true
	GameData.load_settings()
	GameData.apply_settings()
	check(not GameData.music_on and is_equal_approx(GameData.sfx_vol, 0.35) and not GameData.vibration_on,
		"громкость/вибрация не сохранились в общих настройках")
	GameData.music_vol = 0.8
	GameData.sfx_vol = 0.8
	GameData.vibration_on = true
	GameData.apply_settings()
	GameData.save_settings()


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


## Отдалиться можно до всей карты — граница видна даже на огромной карте; в меню виден номер версии.
func test_whole_map_visible() -> void:
	var g = await new_game(6)   # «Звёздная ночь», 10000×10000
	g._update_zoom_limits()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	g._set_zoom(0.000001, vs * 0.5)
	var v: Rect2 = g._view_rect()
	check(v.size.x >= g.wpx * 0.99 or v.size.y >= g.hpx * 0.99,
		"при максимальном отдалении карта 10000×10000 не помещается: вид %s" % str(v.size))
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var ver: Label = menu.find_child("Version", true, false)
	check(ver != null and ver.text.begins_with("v"), "в меню нет номера версии")
	menu.queue_free()



## Открытие типа за 1 U, бонусы стаи по ступеням, яд по тикам, удар по соседям, аура Знаменосца.
func test_balls_and_fleet() -> void:
	var g = await new_game(2)
	check(g.unl["basic"] and not g.unl["sniper"], "на старте уровня открыт не только Пронизывающий")
	g.run_u = 2
	g._unlock_type("sniper")
	check(g.unl["sniper"] and g.run_u == 1, "тип не открылся за 1 U")
	# бонусы стаи: ступени 5, 10, 20…80
	for pair in [[4, 0], [5, 1], [10, 2], [19, 2], [20, 3], [80, 9], [200, 9]]:
		check(GameData.fleet_steps(pair[0]) == pair[1], "ступень для %d шаров: %d" % [pair[0], GameData.fleet_steps(pair[0])])
	var s0: float = g._speed("basic")
	g.counts["sniper"] = 10
	g._recalc_stats()
	check(is_equal_approx(g._speed("basic"), s0 * 1.1), "Гесиевые не ускорили всех (+10% на 2-й ступени)")
	g.counts["pierce"] = 5
	g._recalc_stats()
	check(g._damage_of("basic") == 2, "Отбойники не дали +1 к удару всем")
	# яд: Антониевый не бьёт, а копит тики
	g.unl["poison"] = true
	g.coins = 10000
	g.selected = "poison"
	g._fire(g.start_pos)
	var pb = g.balls[-1]
	var id := -1
	for y in range(g.ey0, g.ey1 + 1):
		for x in range(g.ex0, g.ex1 + 1):
			if id < 0 and g._kind_at(x, y) == 1 and g._vis_at(x, y) and g._hp_of(y * g.W + x) >= 3:
				id = y * g.W + x
	var hp0: int = g._hp_of(id)
	g._hit_cell(pb, id)
	g._hit_cell(pb, id)
	check(g._hp_of(id) == hp0 and g.poisons[id]["left"] == 2, "Антониевый ударил напрямую или тики не копятся")
	g._tick_poison(2.5)
	check(g._hp_of(id) == hp0 - 2, "яд снял не 2 HP за 2 тика")
	# Знаменосец: бафф шарам в круге
	g.unl["banner"] = true
	g.selected = "banner"
	g._fire(g.start_pos)
	g.selected = "basic"
	g._fire(g.start_pos)
	var bb = g.balls[-1]
	g._update_aura()
	check(bb.buff_t > 0.9 and is_equal_approx(bb.buff, 0.3), "шар в круге Знаменосца не получил бафф")


## Профили: прогресс раздельный, настройки общие, удаление чистит только свой профиль.
func test_profiles() -> void:
	GameData.select_slot(1)
	GameData.reset_all()
	GameData.stars = 7
	GameData.maps_done = {"meadow": true}
	GameData.save_game()
	GameData.select_slot(2)
	check(GameData.stars == 0 and GameData.maps_done.is_empty(), "второй профиль не пустой")
	GameData.stars = 3
	GameData.save_game()
	check(GameData.slot_summary(1)["stars"] == 7 and GameData.slot_summary(2)["stars"] == 3, "сводки профилей перепутаны")
	GameData.music_vol = 0.4
	GameData.save_settings()
	GameData.select_slot(1)
	check(GameData.stars == 7 and is_equal_approx(GameData.music_vol, 0.4), "профиль 1 не восстановился или настройки не общие")
	GameData.delete_slot(2)
	check(GameData.slot_summary(2).is_empty() and GameData.slot_summary(1)["stars"] == 7, "удаление задело чужой профиль")
	GameData.music_vol = 0.8
	GameData.save_settings()
	GameData.reset_all()


## Старое сохранение (один профиль в корне) переносится в профиль 1: пройденные карты → ★, типы шаров открыты.
func test_migration() -> void:
	GameData.write_atomic("user://save.json", JSON.stringify({"u": 40, "unlocked": {"basic": true, "splash": true, "sniper": true},
		"maps_done": {"meadow": true, "heart": true, "garden": true}, "maps_unlocked": 4, "mastery": 3,
		"lang_choice": "de", "music_on": false}))
	GameData._migrate_old_save()
	GameData.load_settings()
	GameData.load_game()
	check(GameData.stars == 3 + 4 + 5 + 3 + 1 + 2, "звёзд после переноса %d, а должно быть 18" % GameData.stars)
	check(GameData.maps_unlocked == 4 and GameData.maps_done.size() == 3, "пройденные уровни не перенеслись")
	check(GameData.lang_choice == "de" and GameData.music_vol == 0.0, "настройки не перенеслись")
	check(not FileAccess.file_exists("user://save.json"), "старый файл не удалён")
	GameData.lang_choice = "ru"
	GameData.music_vol = 0.8
	GameData.apply_settings()
	GameData.save_settings()
	GameData.reset_all()



## Нет денег при начале прицела: стрелка красная, но как только монет хватает — можно стрелять без движения пальца.
func test_sling_money_arrives() -> void:
	var g = await new_game(2)
	g.cam.position = g.start_pos
	g._clamp_cam()
	var c: Vector2 = (g.start_pos - g.cam.position) * g.zoom + get_viewport().get_visible_rect().size * 0.5
	g.coins = 0
	var n0: int = g.balls.size()
	g._sling_begin(c)
	g._sling_move(c + Vector2(0, 100))
	check(g._sling_blocked(), "без денег рогатка не заблокирована")
	g.coins = 1000   # деньги пришли, палец не двигался
	check(not g._sling_blocked(), "деньги появились, а стрелка осталась красной до движения пальца")
	g._sling_release()
	check(g.balls.size() == n0 + 1, "после появления денег отпускание не выстрелило")



## Настройки: названия языков не обрезаются (крупный шрифт).
func test_settings_lang_buttons_fit() -> void:
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._show_settings(true)
	for k in 3:
		await get_tree().process_frame
	var font: Font = GameData.font
	for b in menu.settings_box.find_children("*", "Button", true, false):
		if b.text in GameData.LANG_NAMES.values() or b.text == tr("Как в системе"):
			var need: float = font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 20.0
			check(b.size.x >= need, "кнопка языка «%s» уже текста (%.0f < %.0f)" % [b.text, b.size.x, need])
	# ни один элемент настроек не выходит за правый край экрана
	var vw: float = get_viewport().get_visible_rect().size.x
	for c in menu.settings_box.find_children("*", "Control", true, false):
		if (c is Button or c is HSlider or c is Label) and c.is_visible_in_tree():
			check(c.get_global_rect().end.x <= vw + 0.5, "в настройках за краем экрана: %s «%s»" % [c.get_class(), c.text if "text" in c else ""])
	menu.queue_free()



## Режим «ключевые»: к углам, кратным 45°, притягивает только вблизи (±magnet_deg), остальное свободно; подпись угла.
func test_key_angle_snap() -> void:
	var g = await new_game(0)
	g.snap_mode = 2
	GameData.magnet_deg = 2
	for pair in [[-43.0, -45.0], [-47.0, -45.0], [-48.0, -48.0], [-30.0, -30.0], [1.5, 0.0], [-88.0, -90.0], [-85.0, -85.0], [178.0, 180.0]]:
		check(is_equal_approx(g._snap(pair[0]), pair[1]), "±2°: %.1f → %.1f, а не %.1f" % [pair[0], g._snap(pair[0]), pair[1]])
	GameData.magnet_deg = 5
	check(is_equal_approx(g._snap(-40.0), -45.0) and is_equal_approx(g._snap(-39.0), -39.0), "±5° работает неверно")
	GameData.magnet_deg = 2
	# три режима по кругу, 90° больше нет
	g.snap_mode = 0
	var names := []
	for k in 3:
		g._cycle_snap()
		names.append(g.btn_snap.text)
	check(names == ["45°", "ключевые", "любой"], "режимы угла: %s" % str(names))
	# подпись угла: как на транспортире
	for pair in [[0.0, 0], [-90.0, 90], [90.0, 270], [-45.0, 45], [180.0, 180], [-135.0, 135]]:
		check(g._angle_deg(pair[0]) == pair[1], "угол %.0f подписан как %d, а не %d" % [pair[0], g._angle_deg(pair[0]), pair[1]])
	# настройка сохраняется
	GameData.magnet_deg = 4
	GameData.save_settings()
	GameData.magnet_deg = 2
	GameData.load_settings()
	check(GameData.magnet_deg == 4, "ширина притяжения не сохранилась")
	GameData.magnet_deg = 2
	GameData.save_settings()



## «Не блокировать экран»: сохраняется в общих настройках и применяется заново при возвращении в игру.
func test_keep_screen() -> void:
	GameData.keep_screen = true
	GameData.save_settings()
	GameData.keep_screen = false
	GameData.load_settings()
	check(GameData.keep_screen, "настройка «Не блокировать экран» не сохранилась")
	var n0: int = GameData.keep_on_applied
	GameData._notification(NOTIFICATION_APPLICATION_RESUMED)
	check(GameData.keep_on_applied == n0 + 1, "при возвращении в игру флаг не применён заново")
	GameData.keep_screen = false
	GameData.save_settings()
	GameData.apply_settings()



## Мягкий край тумана: открытие клетки у края куска перерисовывает соседний кусок (там светится его туман).
func test_fog_edge_neighbors() -> void:
	var g = await new_game(2)
	# соседние куски с узлами по вертикальной границе 32
	var x := 31
	var y: int = g.start_cell.y
	for k in [0, 1]:
		var ck: int = ((x + k) >> 5) + (y >> 5) * g.cw
		g._get_chunk(ck)
		g._ensure_node(ck)
	var right: int = ((x + 1) >> 5) + (y >> 5) * g.cw
	g.dirty.clear()
	var c = g.chunks[(x >> 5) + (y >> 5) * g.cw]
	c.vis[((y & 31) << 5) | (x & 31)] = 0
	g._reveal(x - 1, y)   # открывает и клетку x=31 у края куска
	check(g.dirty.has(right), "соседний кусок не помечен к перерисовке — край тумана там не обновится")
	check(g.chunks[right].fog_dirty, "у соседнего куска не сброшен кэш края тумана")



func _brick_near(g, from: Vector2i, min_hp: int = 1) -> int:
	for r in range(1, 40):
		for y in range(from.y - r, from.y + r + 1):
			for x in range(from.x - r, from.x + r + 1):
				if x >= 0 and y >= 0 and x < g.W and y < g.H and g._kind_at(x, y) == 1 and g._vis_at(x, y) and g._hp_of(y * g.W + x) >= min_hp:
					return y * g.W + x
	return -1


## Эволюции: цены (5, затем 10 U; ветка N стоит N U), только для открытых шаров, сохраняются с уровнем.
func test_evolution_purchase() -> void:
	var g = await new_game(2)
	g.run_u = 100
	g._buy_evo("splash", "lightning")
	check(not g._has_evo("splash", "lightning") and g.run_u == 100, "эволюция купилась у закрытого шара")
	g._unlock_type("splash")
	g._buy_evo("splash", "lightning")
	check(g._has_evo("splash", "lightning") and g.run_u == 94, "первая эволюция стоила не 5 U: осталось %d" % g.run_u)
	g._buy_evo("splash", "area")
	check(g._has_evo("splash", "area") and g.run_u == 84, "вторая эволюция стоила не 10 U: осталось %d" % g.run_u)
	for k in 3:
		g._buy_ladder("splash", "lightning_rate")
	check(g._el("splash", "lightning_rate") == 3 and g.run_u == 78, "ветка стоила не 1+2+3 U: осталось %d" % g.run_u)
	g._buy_ladder("splash", "sprint_cap")
	check(g.run_u == 78, "купилась ветка чужой эволюции")
	g._unlock_type("banner")
	g._buy_evo("banner", "war_banner")
	for k in 12:
		g.run_u = 100
		g._buy_ladder("banner", "war_banner_cry")
	check(is_equal_approx(g._ev("banner", "war_banner_cry"), 3.0) and g._ladder_maxed("banner", "war_banner_cry"), "«Боевой клич» ушёл ниже 3 с")
	g._save_state()
	var keep_u: int = g.run_u
	game.queue_free()
	game = null
	await get_tree().process_frame
	game = GAME.instantiate()
	add_child(game)
	check(game._has_evo("splash", "lightning") and game._el("splash", "lightning_rate") == 3 and game.run_u == keep_u,
		"эволюции и ветки не сохранились с уровнем")
	var g2 = await new_game(3)
	check(g2.evo["splash"].is_empty(), "на новом уровне эволюции не сброшены")


## Механики эволюций Пронизывающего, Гесиевого и Никитиевого.
func test_evolution_mechanics_a() -> void:
	var g = await new_game(2, func(): unlock_all())
	g.run_u = 1000
	# Разведка: удар открывает туман вокруг
	g._buy_evo("basic", "scout")
	g.balls.clear()
	g.coins = 100000
	g.selected = "basic"
	g._fire(g.start_pos)
	var b = g.balls[0]
	var id := _brick_near(g, g.start_cell)
	var hidden_before := 0
	var cx: int = id % g.W
	var cy: int = id / g.W
	for yy in range(cy - 2, cy + 3):
		for xx in range(cx - 2, cx + 3):
			if not g._vis_at(xx, yy):
				hidden_before += 1
	g._hit_cell(b, id)
	var hidden_after := 0
	for yy in range(cy - 2, cy + 3):
		for xx in range(cx - 2, cx + 3):
			if not g._vis_at(xx, yy) and (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) <= 4:
				hidden_after += 1
	check(hidden_after == 0, "Разведка не открыла туман вокруг удара (было скрыто %d)" % hidden_before)
	# Прошивка: клетка за целью по линии полёта получает долю силы
	g._buy_evo("basic", "stitch")
	var tgt := _brick_near(g, g.start_cell, 1)
	var tx: int = tgt % g.W
	var ty: int = tgt / g.W
	var behind := -1
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if g._kind_at(tx + o.x, ty + o.y) == 1 and g._hp_of((ty + o.y) * g.W + tx + o.x) >= 4:
			behind = (ty + o.y) * g.W + tx + o.x
			b.vel = Vector2(o) * 300.0
			break
	if behind >= 0:
		var h0: int = g._hp_of(behind)
		g._stitch(tgt, 4, b)
		check(g._hp_of(behind) < h0, "Прошивка не задела клетку за целью")
	# Спринтер: разгон без ударов до предела, удар сбрасывает
	g._buy_evo("sniper", "sprint")
	g.balls.clear()
	g._spawn_ball("sniper", -90.0, g.start_pos)
	var s = g.balls[0]
	s.sprint = 0.0
	for k in 200:
		s.sprint = minf(g._ev("sniper", "sprint_cap"), s.sprint + g._ev("sniper", "sprint_rate") * 0.1)
	check(s.sprint > 0.15, "Спринтер не разгоняется")
	g._hit_cell(s, _brick_near(g, g.start_cell))
	check(s.sprint == 0.0, "удар по породе не сбросил разгон")
	# Дробовик: один пуск — веер, цена растёт как за один, скидка на пуск
	g.balls.clear()
	g.counts["sniper"] = 0
	g.extra["sniper"] = 0
	var p0: int = g._ball_cost("sniper")
	g._buy_evo("sniper", "shotgun")
	check(g._ball_cost("sniper") == p0, "Дробовик без ветки изменил цену")
	g.selected = "sniper"
	g.coins = 100000
	g._fire(g.start_pos)
	check(g.balls.size() == 3 and g.counts["sniper"] == 1 and g.extra["sniper"] == 2, "залп Дробовика: шаров %d, пусков %d" % [g.balls.size(), g.counts["sniper"]])
	for k in 4:
		g._buy_ladder("sniper", "shotgun_cheap")
	var nodisc := int(round((50.0 + 5.0) * 1.12))
	check(g._ball_cost("sniper") < nodisc, "«Массовое производство» не снизило цену: %d" % g._ball_cost("sniper"))
	# Площадь: удар по соседям на радиус 2 (сила удара прокачана — доля по соседу целая, без случайности)
	g._buy_evo("splash", "area")
	g.coins = 100000
	for k in 3:
		g._buy_track("splash", "impact")
	g.balls.clear()
	g._spawn_ball("splash", 0.0, g.start_pos)
	var rb = g.balls[0]
	var far := -1
	var center := -1
	for y in g.H:
		for x in range(0, g.W - 2):
			if center < 0 and g._kind_at(x, y) == 1 and g._kind_at(x + 2, y) == 1 and g._hp_of(y * g.W + x) >= 12 and g._hp_of(y * g.W + x + 2) > 4:
				center = y * g.W + x
				far = y * g.W + x + 2
	check(center >= 0, "нет пары квадратов для проверки «Площади»")
	if center >= 0:
		g._reveal(center % g.W, center / g.W)
		g._reveal(far % g.W, far / g.W)
		var hf: int = g._hp_of(far)
		g._hit_cell(rb, center)
		check(g._hp_of(far) < hf, "Площадь не достала клетку на расстоянии 2")
	# Молния: разряд бьёт открытую породу вокруг шара
	g._buy_evo("splash", "lightning")
	for k in 8:
		g._buy_ladder("splash", "lightning_range")
	var lid := _brick_near(g, g.start_cell, 3)
	var lx: int = lid % g.W
	var ly: int = lid / g.W
	rb.pos = (Vector2(lx, ly) + Vector2(0.5, 0.5)) * 40.0 + Vector2(0, 40)
	var hl: int = g._hp_of(lid)
	for k in 12:
		g._lightning(rb)
	check(g._hp_of(lid) < hl, "Молния не задела открытую породу рядом")


## Механики эволюций Антониевого, Отбойника и Знаменосца.
func test_evolution_mechanics_b() -> void:
	var g = await new_game(2, func(): unlock_all())
	g.run_u = 1000
	g.balls.clear()
	# Инфекция: при 100%+ шансе яд наверняка переходит на соседа
	g._buy_evo("poison", "infection")
	for k in 4:
		g._buy_ladder("poison", "infection_chance")
	g._spawn_ball("poison", 0.0, g.start_pos)
	var pb = g.balls[0]
	var pid := -1
	for y in range(g.ey0, g.ey1 + 1):
		for x in range(g.ex0, g.ex1 + 1):
			if pid < 0 and g._kind_at(x, y) == 1 and (g._kind_at(x + 1, y) == 1 or g._kind_at(x - 1, y) == 1 or g._kind_at(x, y + 1) == 1 or g._kind_at(x, y - 1) == 1):
				pid = y * g.W + x
	var n0: int = g.poisons.size()
	g._hit_cell(pb, pid)
	check(g.poisons.size() >= n0 + 2, "Инфекция не перешла на соседа (отравлено %d)" % (g.poisons.size() - n0))
	# Разъедание: отравленная клетка получает больше урона
	g._buy_evo("poison", "corrosion")
	var cid := _brick_near(g, g.start_cell, 30)
	if cid >= 0:
		g._apply_poison(cid, 100, pb)
		var h0: int = g._hp_of(cid)
		var hits := 0
		for k in 20:
			g._damage(cid, 1, null)
		check(h0 - g._hp_of(cid) > 20, "Разъедание не усилило урон по отравленной клетке: %d за 20 ударов по 1" % (h0 - g._hp_of(cid)))
	# Гравитация: цель — самая крепкая видимая клетка в радиусе
	g._buy_evo("pierce", "gravity")
	g._spawn_ball("pierce", 0.0, g.start_pos)
	var gb = g.balls[-1]
	var tgt: Vector2 = g._gravity_target(gb)
	if tgt.x >= 0.0:
		var tcell: int = int(tgt.y / 40.0) * g.W + int(tgt.x / 40.0)
		var mx := 0
		var r := int(g._ev("pierce", "gravity_range"))
		var cx := int(gb.pos.x / 40.0)
		var cy := int(gb.pos.y / 40.0)
		for yy in range(cy - r, cy + r + 1):
			for xx in range(cx - r, cx + r + 1):
				if (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) <= r * r and g._vis_at(xx, yy) and g._kind_at(xx, yy) == 1:
					mx = maxi(mx, g._hp_of(yy * g.W + xx))
		check(g._hp_of(tcell) == mx, "Гравитация выбрала не самую крепкую клетку (%d < %d)" % [g._hp_of(tcell), mx])
	# Клещ: не разбил с удара — бурит до конца
	g._buy_evo("pierce", "kleshch")
	var kid := _brick_near(g, g.start_cell, 30)
	g._spawn_ball("pierce", 0.0, g.start_pos)
	var kb = g.balls[-1]
	kb.vel = Vector2(300, 0)
	g._hit_cell(kb, kid)
	check(kb.drill_id == kid, "Клещ не впился в клетку, которую не разбил")
	for k in 600:
		g._sim(0.05)
		if g._hp_of(kid) <= 0:
			break
	check(g._hp_of(kid) <= 0 and kb.drill_id == -1, "Клещ не добурил клетку")
	# Боевое знамя и Попутный ветер
	g._buy_evo("banner", "war_banner")
	g._buy_evo("banner", "tailwind")
	g.balls.clear()
	g._spawn_ball("banner", 0.0, g.start_pos)
	g._spawn_ball("basic", 0.0, g.start_pos + Vector2(10, 0))
	g.counts["banner"] = 1
	g.time_acc = 30.5   # момент боевого клича (раз в 10 с)
	g._update_aura()
	var bb = g.balls[1]
	check(bb.buff > 0.39 and bb.spd_buff > 0.09, "аура: урон +%.2f, скорость +%.2f" % [bb.buff, bb.spd_buff])
	check(g.aura_r_now >= g._aura_radius() * 1.99, "боевой клич не расширил круг")



## Подписи прокачки — значения с единицами («сейчас → после покупки»), а не номера уровней.
func test_upgrade_captions_values() -> void:
	var g = await new_game(2, func(): unlock_all())
	g.run_u = 1000
	for t in GameData.TYPE_ORDER:
		for e in GameData.EVOS[t]:
			g._buy_evo(t, e["id"])
	g._show_upgrades(true)
	g._refresh_ui()
	var expect := {"scout_radius": "2 кл → 3 кл", "scout_find": "0% → 10%", "lightning_rate": "0.25/с → 0.5/с",
		"shotgun_balls": "×3 → ×4", "war_banner_cry": "10 с → 9 с", "infection_fade": "−10% → −8%",
		"sprint_rate": "1%/с → 1.5%/с", "kleshch_grip": "1/с → 1.25/с"}
	for t in GameData.TYPE_ORDER:
		for e in GameData.EVOS[t]:
			for trk in e["tracks"]:
				var cap: String = g._ev_caption(t, trk["id"])
				check("→" in cap, "у ветки %s нет «сейчас → после»: %s" % [trk["id"], cap])
				check(not ("ур." in cap), "в подписи ветки номер уровня вместо значения: %s" % cap)
				if expect.has(trk["id"]):
					check(cap.ends_with(expect[trk["id"]]), "%s: «%s», ждали «…%s»" % [trk["id"], cap, expect[trk["id"]]])
	for t in g.shop_refs:
		if g.shop_refs[t].has("tracks"):
			for id in g.shop_refs[t]["tracks"]:
				var c: String = g._track_caption(t, id)
				check("→" in c, "у ветки за монеты %s/%s нет значений: %s" % [t, id, c])
	check(g._track_caption("poison", "cadence").ends_with("1/с → 1.5/с"), "частота яда без единиц: %s" % g._track_caption("poison", "cadence"))
	check(g._track_caption("banner", "radius").ends_with("3 кл → 4 кл"), "радиус ауры без единиц: %s" % g._track_caption("banner", "radius"))
	check(g._track_caption("basic", "speed").begins_with("Скорость: ") and g._track_caption("basic", "speed").ends_with("кл/с"), "скорость: %s" % g._track_caption("basic", "speed"))
	check(g._ev_caption("sniper", "shotgun_cheap").begins_with("Массовое производство: 0% → −5%"), "скидка на нулевом уровне: %s" % g._ev_caption("sniper", "shotgun_cheap"))



## Карты-сцены: форма (снаружи — стена-фон), рисунок из стен, свободный старт, все квадраты достижимы.
func test_scene_maps() -> void:
	for i in [2, 3]:
		var g = await new_game(i)
		check(g.has_shape and g.map.has("scene"), "карта %d не сцена" % i)
		var walls := 0
		var voids := 0
		for y in g.H:
			for x in g.W:
				var k: int = g._kind_at(x, y)
				if g._void_at(x, y):
					voids += 1
					check(k == 2, "за формой карты не стена: (%d,%d) %d" % [x, y, k])
				elif k == 2:
					walls += 1
		check(voids > 0, "у карты %d нет области за формой" % i)
		check(walls > 150, "в сцене %d мало линий рисунка: %d" % [i, walls])
		check(g._kind_at(g.start_cell.x, g.start_cell.y) == 0, "старт сцены %d занят" % i)
		# достижимость: от старта по свободным и квадратам (квадраты проходимы — их разбивают)
		var seen := {}
		var q := [g.start_cell]
		seen[g.start_cell] = true
		while not q.is_empty():
			var c: Vector2i = q.pop_back()
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nc: Vector2i = c + o
				if seen.has(nc) or nc.x < 0 or nc.y < 0 or nc.x >= g.W or nc.y >= g.H:
					continue
				if g._kind_at(nc.x, nc.y) == 2:
					continue
				seen[nc] = true
				q.append(nc)
		var lost := 0
		for y in g.H:
			for x in g.W:
				if g._kind_at(x, y) == 1 and not seen.has(Vector2i(x, y)):
					lost += 1
		check(lost == 0, "в сцене %d недостижимых квадратов: %d" % [i, lost])
		check(g.shape_pts.size() == 0 or g.shape_pts.size() > 100, "контур формы")



## Статистика уровней: время первого прохождения, лучшее, число прохождений; сохраняется; видна в меню.
func test_map_stats() -> void:
	var g = await new_game(0)
	g.play_time = 0.0
	g._process(0.5)
	check(g.play_time > 0.0, "время уровня не идёт")
	g.play_time = 1052.0
	g._save_state()
	check(is_equal_approx(float(GameData.map_states["meadow"]["time"]), 1052.0), "время не попало в сводку профиля")
	GameData.record_completion("meadow", 1052.0)
	GameData.record_completion("meadow", 900.0)
	GameData.record_completion("meadow", 1200.0)
	var e: Dictionary = GameData.map_stats["meadow"]
	check(is_equal_approx(e["first"], 1052.0) and is_equal_approx(e["best"], 900.0) and e["runs"] == 3, "статистика: %s" % str(e))
	GameData.save_game()
	GameData.map_stats = {}
	GameData.load_game()
	check(GameData.map_stats.has("meadow") and int(GameData.map_stats["meadow"]["runs"]) == 3, "статистика не сохранилась")
	check(GameData.fmt_time(1052.0) == "17:32" and GameData.fmt_time(3910.0) == "1:05:10", "формат времени")
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var lbl: Label = menu.list.get_child(0).find_child("Stats", true, false)
	check(lbl != null and "17:32" in lbl.text and "15:00" in lbl.text, "в меню нет статистики: %s" % (lbl.text if lbl else "—"))
	menu.queue_free()
	GameData.reset_all()



## Статистика шаров уровня: весь урон по типу и среднее в секунду за последние 10 с; сохраняется с уровнем.
func test_ball_damage_stats() -> void:
	var g = await new_game(2, func(): unlock_all())
	g.balls.clear()
	g._spawn_ball("splash", 0.0, g.start_pos)
	g._spawn_ball("basic", 0.0, g.start_pos)
	var rb = g.balls[0]
	var bb = g.balls[1]
	var id := -1
	for y in g.H:
		for x in g.W:
			if id < 0 and g._kind_at(x, y) == 1 and g._hp_of(y * g.W + x) >= 60:
				id = y * g.W + x
	check(id >= 0, "нет квадрата с 60+ жизнями")
	g.time_acc = 100.0
	g._damage(id, 30, rb)
	g._damage(id, 10, bb)
	check(g.dmg_total["splash"] == 30 and g.dmg_total["basic"] == 10, "урон не засчитан типам: %s" % str(g.dmg_total))
	check(is_equal_approx(g._dps("splash"), 3.0), "среднее за 10 с: %.2f, а не 3" % g._dps("splash"))
	g.time_acc = 105.5
	g._damage(id, 20, rb)
	check(is_equal_approx(g._dps("splash"), 5.0), "среднее за 10 с после второго удара: %.2f" % g._dps("splash"))
	g.time_acc = 111.2   # первая секунда (100) выпала из окна
	check(is_equal_approx(g._dps("splash"), 2.0), "устаревший урон не выпал из окна: %.2f" % g._dps("splash"))
	g.time_acc = 130.0
	check(g._dps("splash") == 0.0 and g.dmg_total["splash"] == 50, "окно не обнулилось или потерян итог")
	# яд засчитывается Антониевому
	g._spawn_ball("poison", 0.0, g.start_pos)
	g._apply_poison(id, 3, g.balls[-1])
	for k in 40:
		g._sim(0.1)
	check(g.dmg_total["poison"] > 0, "урон яда не засчитан Антониевому")
	# строка в карточке и сохранение
	g._show_upgrades(true)
	g._refresh_ui()
	var total: int = g.dmg_total["splash"]   # шары продолжали летать, пока шёл яд, — урон мог вырасти
	check(g.shop_refs["splash"]["stat"].text.begins_with(GameData.fmt(total) + " · "), "статистика в заголовке карточки: %s" % g.shop_refs["splash"]["stat"].text)
	g._save_state()
	game.queue_free()
	game = null
	await get_tree().process_frame
	game = GAME.instantiate()
	add_child(game)
	check(game.dmg_total["splash"] == total, "итог урона не сохранился с уровнем: %d ≠ %d" % [game.dmg_total["splash"], total])



## Верхняя панель неподвижна: при смене монет и U блоки не меняют ни положение, ни ширину.
func test_top_bar_stable() -> void:
	var g = await new_game(2)
	var row: HBoxContainer = g.lbl_rub.get_parent().get_parent().get_parent()
	var snap := func() -> Array:
		var r := []
		for c in row.get_children():
			r.append(c.get_global_rect())
		return r
	var cases := [[0, 0], [7, 3], [12345, 42], [987654321, 999], [8.9e17, 1234], [3.0e18, 8888]]
	var ref: Array = []
	for code in ["ru", "de", "zh_CN", "ar"]:
		GameData.lang_choice = code
		GameData.apply_settings()
		for cs in cases:
			g.coins = int(cs[0])
			g.run_u = int(cs[1])
			g._refresh_ui()
			await get_tree().process_frame
			await get_tree().process_frame
			var now: Array = snap.call()
			if ref.is_empty() or code != "ru" and cs == cases[0]:
				ref = now
				continue
			for k in now.size():
				check(now[k].is_equal_approx(ref[k]), "%s, монеты %s, U %d: блок %d сдвинулся %s → %s" % [code, GameData.fmt(g.coins), g.run_u, k, str(ref[k]), str(now[k])])
	GameData.lang_choice = "ru"
	GameData.apply_settings()



## Прогресс: числа и проценты; процент вниз (100% — только при полной расчистке); подпись помещается целиком.
func test_progress_label() -> void:
	var gg = GAME.instantiate()
	check(gg._pct_text(0.004) == "0.4%", "0.4%")
	check(gg._pct_text(0.0999) == "9.9%" and gg._pct_text(0.5) == "50%" and gg._pct_text(0.9999) == "99%" and gg._pct_text(1.0) == "100%",
		"проценты: %s %s %s %s" % [gg._pct_text(0.0999), gg._pct_text(0.5), gg._pct_text(0.9999), gg._pct_text(1.0)])
	gg.free()
	var g = await new_game(2)
	g.destroyed = 1234
	g._refresh_ui()
	check(g.lbl_prog.text.begins_with("1.2K из ") and g.lbl_prog.text.ends_with("%"), "подпись малой карты: %s" % g.lbl_prog.text)
	var g2 = await new_game(4)
	var font: Font = g2.lbl_prog.get_theme_font("font")
	var fsz: int = g2.lbl_prog.get_theme_font_size("font_size")
	for code in ["ru", "de", "fr", "vi", "id"]:
		GameData.lang_choice = code
		GameData.apply_settings()
		for st in [[123456, false], [79999, false], [350000, true]]:
			g2.destroyed = st[0]
			g2.goal_done = st[1]
			g2._refresh_ui()
			await get_tree().process_frame
			var need: float = font.get_string_size(g2.lbl_prog.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
			check(need <= g2.lbl_prog.size.x + 0.5, "%s: подпись прогресса не помещается: «%s» (%.0f > %.0f)" % [code, g2.lbl_prog.text, need, g2.lbl_prog.size.x])
	check(g2.lbl_prog.text.ends_with("437%") or "%" in g2.lbl_prog.text, "после цели нет процента: %s" % g2.lbl_prog.text)
	GameData.lang_choice = "ru"
	GameData.apply_settings()



## Предел веток: следующий уровень ничего не меняет — покупка недоступна и ничего не списывает
## (скорость упиралась в потолок 50 кл/с, а деньги уходили; скидка −50%, залп по полшара, разгон).
func test_upgrade_caps() -> void:
	var g = await new_game(2, func(): unlock_all())
	g.coins = 9_000_000_000_000_000
	var bought := 0
	for k in 80:
		if g._track_maxed("sniper", "speed"):
			break
		g._buy_track("sniper", "speed")
		bought += 1
	check(g._track_maxed("sniper", "speed"), "скорость Гесиевого не дошла до предела за 80 покупок")
	check(is_equal_approx(g._speed("sniper"), g.MAX_SPEED), "предел не равен потолку скорости")
	var c0: int = g.coins
	var lv0: int = g._tl("sniper", "speed")
	g._buy_track("sniper", "speed")
	check(g.coins == c0 and g._tl("sniper", "speed") == lv0, "на пределе покупка списала деньги")
	var cap: String = g._track_caption("sniper", "speed")
	check(cap.ends_with("(макс.)") and not ("→" in cap), "подпись на пределе: %s" % cap)
	g._show_upgrades(true)
	g._refresh_ui()
	var btn: Button = g.shop_refs["sniper"]["tracks"]["speed"]["button"]
	check(btn.disabled and btn.text == "макс.", "кнопка на пределе: «%s», disabled=%s" % [btn.text, btn.disabled])
	# ни одна ветка за монеты не берёт деньги, если подпись не меняется
	for t in GameData.TYPE_ORDER:
		for d in GameData.TYPES[t]["tracks"]:
			for k in 30:
				var before: String = g._track_caption(t, d["id"])
				var cc: int = g.coins
				g._buy_track(t, d["id"])
				if g.coins != cc:
					check("→" in before, "%s/%s: списано без изменения значения: %s" % [t, d["id"], before])
	# эволюции: скидка до −50%, залп +1 шар за уровень, U на пределе не списываются
	g.run_u = 100000
	g._buy_evo("sniper", "shotgun")
	var v0: int = g._volley_size()
	g._buy_ladder("sniper", "shotgun_balls")
	check(g._volley_size() == v0 + 1, "уровень «Шаров в залпе» не добавил шар: %d → %d" % [v0, g._volley_size()])
	for k in 15:
		g._buy_ladder("sniper", "shotgun_cheap")
	check(g._el("sniper", "shotgun_cheap") == 10 and g._ladder_maxed("sniper", "shotgun_cheap"), "скидка не остановилась на −50%%: ур. %d" % g._el("sniper", "shotgun_cheap"))
	var u0: int = g.run_u
	g._buy_ladder("sniper", "shotgun_cheap")
	check(g.run_u == u0, "на пределе скидки списаны U")
	g._buy_evo("sniper", "sprint")
	for k in 40:
		g._buy_ladder("sniper", "sprint_cap")
	check(g._ladder_maxed("sniper", "sprint_cap"), "предел разгона не учитывает потолок скорости")
	for t in GameData.TYPE_ORDER:
		for e in GameData.EVOS[t]:
			g._buy_evo(t, e["id"])
			for tr_ in e["tracks"]:
				for k in 12:
					var before: String = g._ev_caption(t, tr_["id"])
					var uu: int = g.run_u
					g._buy_ladder(t, tr_["id"])
					if g.run_u != uu:
						check("→" in before and before.split("→")[0].strip_edges().get_slice(": ", 1) != before.split("→")[1].strip_edges(),
							"%s: U списаны без изменения значения: %s" % [tr_["id"], before])



## Тип шара читается по силуэту: у всех типов разные текстуры, тот же значок на фишке и в карточке, подсветка выбранного.
func test_ball_markers() -> void:
	var g = await new_game(2, func(): unlock_all())
	var imgs := {}
	for tp in GameData.TYPE_ORDER:
		check(g.ball_icons.has(tp), "нет силуэта для %s" % tp)
		imgs[tp] = g.ball_icons[tp].get_image()
	var types: Array = GameData.TYPE_ORDER
	for i in types.size():
		for j in range(i + 1, types.size()):
			var a: Image = imgs[types[i]]
			var b: Image = imgs[types[j]]
			# сравниваем форму (альфу), а не цвет: силуэты должны различаться и без цвета
			var diff := 0
			for y in range(0, a.get_height(), 2):
				for x in range(0, a.get_width(), 2):
					if absf(a.get_pixel(x, y).a - b.get_pixel(x, y).a) > 0.5:
						diff += 1
			var shape_same: bool = diff < 8
			var white_a := 0
			var white_b := 0
			for y in range(0, a.get_height(), 2):
				for x in range(0, a.get_width(), 2):
					var pa := a.get_pixel(x, y)
					var pb := b.get_pixel(x, y)
					if pa.a > 0.5 and pa.r > 0.9 and pa.g > 0.9 and pa.b > 0.9:
						white_a += 1
					if pb.a > 0.5 and pb.r > 0.9 and pb.g > 0.9 and pb.b > 0.9:
						white_b += 1
			# разные либо контур, либо белый рисунок внутри (блик, капля, обод) — кроме пары без отличий
			check(not shape_same or absi(white_a - white_b) > 6 or types[i] + types[j] == "basicsniper",
				"силуэты %s и %s не различаются" % [types[i], types[j]])
	# значки на фишках различаются у ВСЕХ пар — включая Пронизывающий/Гесиевый (шлейф нарисован в значке)
	for i in types.size():
		for j in range(i + 1, types.size()):
			var a2: Image = g.ui_icons[types[i]].get_image()
			var b2: Image = g.ui_icons[types[j]].get_image()
			var d2 := 0
			for y in range(0, a2.get_height(), 2):
				for x in range(0, a2.get_width(), 2):
					if absf(a2.get_pixel(x, y).a - b2.get_pixel(x, y).a) > 0.5:
						d2 += 1
					else:
						var pa := a2.get_pixel(x, y)
						var pb := b2.get_pixel(x, y)
						if pa.a > 0.5 and (pa.r > 0.9 and pa.g > 0.9 and pa.b > 0.9) != (pb.r > 0.9 and pb.g > 0.9 and pb.b > 0.9):
							d2 += 1
			check(d2 > 40, "значки %s и %s на фишках почти одинаковы (отличий %d)" % [types[i], types[j], d2])
	# флажок Знаменосца крупный: над шаром заметная непрозрачная область
	var bimg: Image = g.ui_icons["banner"].get_image()
	var flag := 0
	for y in int(bimg.get_height() * 0.25):
		for x in bimg.get_width():
			if bimg.get_pixel(x, y).a > 0.5:
				flag += 1
	check(flag > 120, "флажок Знаменосца слишком мелкий: %d px" % flag)
	g._refresh_ui()
	var chip_icon: TextureRect = null
	for n in g.chips["splash"].find_children("*", "TextureRect", true, false):
		chip_icon = n
	check(chip_icon != null and chip_icon.texture == g.ui_icons["splash"], "на фишке не значок типа")
	g._select("pierce")
	check(g.highlight_type == "pierce" and g.highlight_t > 1.0, "выбор типа не включил подсветку")
	for k in 15:
		g._sim(0.1)
	check(g.highlight_t == 0.0, "подсветка не погасла")



## «Вернуть шар»: надпись постоянная, состояние — оформлением; перезарядка заполняет фон; виден шар, который вернётся.
func test_recall_button() -> void:
	var g = await new_game(2)
	g.coins = 100000
	g._fire(g.start_pos)
	g._fire(g.start_pos)
	g._refresh_ui()
	var t0: String = g.btn_reset.text
	var h0: float = g.btn_reset.size.y
	g._reset_stuck()
	g._refresh_ui()
	await get_tree().process_frame
	check(g.reset_armed and g.btn_reset.text == t0 and g.btn_reset.theme_type_variation == "AccentButton", "включённый режим: текст «%s», стиль %s" % [g.btn_reset.text, g.btn_reset.theme_type_variation])
	check(is_equal_approx(g.btn_reset.size.y, h0), "кнопка изменила высоту при включении")
	check(g._idler("basic") != null, "нет шара, который вернётся")
	g.reset_armed = false
	g.reset_cd["basic"] = 15.0
	g._refresh_ui()
	await get_tree().process_frame
	check(g.btn_reset.text == t0 and g.btn_reset.disabled, "перезарядка: текст «%s», disabled=%s" % [g.btn_reset.text, g.btn_reset.disabled])
	check(is_equal_approx(g.btn_reset.size.y, h0), "кнопка изменила высоту при перезарядке")



## Капля Антониевого развёрнута кончиком против полёта (как шлейф Гесиевого).
func test_drop_orientation() -> void:
	var gg = GAME.instantiate()
	for v in [Vector2(300, 0), Vector2(0, 300), Vector2(-200, -200), Vector2(10, -400)]:
		var tip := Vector2(0, -1).rotated(gg._drop_rot(v))
		check(tip.dot(-v.normalized()) > 0.999, "кончик капли не против полёта для %s: %s" % [str(v), str(tip)])
	gg.free()
	# в значке для интерфейса капля «летит» вправо — кончик слева: силуэт выступает от центра влево дальше, чем вправо
	var g = await new_game(2)
	var img: Image = g.ui_icons["poison"].get_image()
	var w := img.get_width()
	var minx := w
	var maxx := 0
	for y in img.get_height():
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
	var h := w / 2.0
	check(h - minx > maxx - h + 3.0, "у значка капли кончик не слева: влево %.0f, вправо %.0f" % [h - minx, maxx - h])



## Карты-картины (Fluent Emoji): рисунок есть, старт свободен, за формой стена, все квадраты достижимы;
## на втором круге бесконечных уровней картина зеркальная.
func test_picture_maps() -> void:
	var Maps = preload("res://scripts/maps.gd")
	for i in [4, 5, 6, 7]:
		var g = await new_game(i, func(): GameData.maps_unlocked = i + 1)
		check(g.map.has("pic") and g.has_shape, "карта %d не картина" % i)
		var W: int = g.W
		var H: int = g.H
		var walls := 0
		var free := PackedByteArray()
		free.resize(W * H)
		for y in H:
			for x in W:
				var k: int = g._kind_at(x, y)
				if g._void_at(x, y):
					check(k == 2, "карта %d: за формой не стена (%d,%d)" % [i, x, y])
					if k != 2:
						return
				elif k == 2:
					walls += 1
				else:
					free[y * W + x] = 1
		check(walls > 2000, "карта %d: мало линий рисунка: %d" % [i, walls])
		check(g._kind_at(g.start_cell.x, g.start_cell.y) == 0, "карта %d: старт занят" % i)
		# достижимость — обход по всей карте
		var seen := PackedByteArray()
		seen.resize(W * H)
		var q := PackedInt32Array([g.start_cell.y * W + g.start_cell.x])
		seen[q[0]] = 1
		var qi := 0
		while qi < q.size():
			var v := q[qi]
			qi += 1
			var vx := v % W
			for u in [v - 1, v + 1, v - W, v + W]:
				if u < 0 or u >= W * H or seen[u] == 1 or free[u] == 0:
					continue
				if (u == v - 1 and vx == 0) or (u == v + 1 and vx == W - 1):
					continue
				seen[u] = 1
				q.append(u)
		var lost := 0
		for v in W * H:
			if free[v] == 1 and seen[v] == 0:
				lost += 1
		check(lost == 0, "карта %d: недостижимых квадратов %d" % [i, lost])
		check(int(g.goal) < q.size(), "карта %d: цель %d больше числа квадратов %d" % [i, g.goal, q.size()])
	# зеркальная картина на втором круге
	var n: int = Maps.THEMES.size()
	var a: Dictionary = Maps.get_map(7)
	var b: Dictionary = Maps.get_map(7 + n)
	check(a["pic"] == b["pic"] and not a.get("flip", false) and b.get("flip", false), "второй круг не зеркальный")
	var g1 = await new_game(7, func(): GameData.maps_unlocked = 8)
	var w1: Array = []
	for x in g1.W:
		w1.append(g1._kind_at(x, g1.H / 2))
	var g2 = await new_game(7 + n, func(): GameData.maps_unlocked = 8 + n)
	var mismatch := 0
	for x in g2.W:
		if g2._kind_at(x, g2.H / 2) != w1[g2.W - 1 - x] and not (g2.start_cell.distance_to(Vector2i(x, g2.H / 2)) < 8):
			mismatch += 1
	check(mismatch == 0, "зеркальная картина не совпадает с исходной: %d клеток" % mismatch)



## Заливка перезарядки «Вернуть шар» видна сразу и растёт от самого левого края.
func test_recall_fill() -> void:
	var g = await new_game(2)
	g.coins = 100000
	g._fire(g.start_pos)
	g._refresh_ui()
	await get_tree().process_frame
	var w: float = g.btn_reset.size.x
	g.reset_cd["basic"] = g.RESET_CD - 0.5   # прошло полсекунды
	g._refresh_ui()
	check(g.reset_fill.visible and g.reset_fill.position.x == 0.0, "заливка не видна с первых секунд или не от края")
	check(g.reset_fill.size.x > 0.0 and g.reset_fill.size.x < w * 0.05, "ширина заливки через 0.5 с: %.1f из %.0f" % [g.reset_fill.size.x, w])
	check(is_equal_approx(g.reset_fill_panel.size.x, w), "плашка внутри не размером с кнопку")
	g.reset_cd["basic"] = g.RESET_CD * 0.5
	g._refresh_ui()
	check(absf(g.reset_fill.size.x - w * 0.5) < 1.0, "на середине перезарядки заливка %.0f из %.0f" % [g.reset_fill.size.x, w])
	g.reset_cd["basic"] = 0.0
	g._refresh_ui()
	check(not g.reset_fill.visible, "после перезарядки заливка не скрылась")



## Большая карта (картина): число квадратов известно; цель — подсказка про полную расчистку; финал на последнем 1%
## (досоздаёт все куски, поле расстояний считается порциями); полная расчистка — ★ и «Победа».
func test_big_map_full_clear() -> void:
	var g = await new_game(4, func(): GameData.maps_unlocked = 5)
	check(g.full_tracked and not g.track_all and g.total > 100000 and g.alive == g.total, "большая карта не знает число квадратов: %d" % g.total)
	# сверка с настоящим числом квадратов (досоздаём все куски)
	var real := 0
	for ck in g.chunks.size():
		var c = g._get_chunk(ck)
		for li in 1024:
			if c.kind[li] == 1:
				real += 1
	check(real == g.total, "число квадратов картины %d, а на деле %d" % [g.total, real])
	# цель: подсказка про полную расчистку
	g.destroyed = g.goal
	g._check_goal()
	check(g.goal_done and "Расчистите карту целиком" in g.toast_label.text, "нет подсказки про полную расчистку: %s" % g.toast_label.text)
	# финал: на последнем 1%
	g.alive = 500
	g._check_goal()
	check(g.finale and g.finale_pass.size() == g.W * g.H, "финал большой карты не начался")
	var frames := 0
	while g.bfs_busy and frames < 200:
		g._sim(0.016)
		frames += 1
	check(not g.bfs_busy and g.finale_dist.size() == g.W * g.H, "поле расстояний не досчиталось за %d кадров" % frames)
	check(frames > 1, "поле расстояний посчиталось за один кадр — на большой карте была бы пауза")
	# полная расчистка
	var s0: int = GameData.stars
	g.alive = 0
	g._check_goal()
	check(g.completed and GameData.maps_full.has("mountains"), "полная расчистка не засчитана")
	check(GameData.stars - s0 == GameData.stars_for(4, true), "за полную расчистку %d ★, а не %d" % [GameData.stars - s0, GameData.stars_for(4, true)])
	for n in g.ui_root.get_children():
		if n is AcceptDialog:
			n.queue_free()



## Прокачка: вкладки шаров, видна одна карточка, зелёный счётчик доступных покупок, компактные строки.
func test_upgrade_tabs() -> void:
	var g = await new_game(2)
	g.coins = 0
	g.run_u = 0
	g._show_upgrades(true)
	g._refresh_ui()
	check(g.upg_type == g.selected, "прокачка открылась не на выбранном в игре шаре")
	var shown := 0
	for t in g.shop_refs:
		if g.shop_refs[t]["card"].visible:
			shown += 1
	check(shown == 1, "видно карточек: %d" % shown)
	check(not g.upg_tabs_btn["basic"]["badge"].visible, "счётчик при нуле денег")
	g.coins = 100000
	g.run_u = 6
	g._refresh_ui()
	check(g.upg_tabs_btn["basic"]["badge"].visible and int(g.upg_tabs_btn["basic"]["badge_label"].text) == g._affordable("basic"),
		"счётчик доступных покупок: %s" % g.upg_tabs_btn["basic"]["badge_label"].text)
	check(g._affordable("basic") == 2 + 2, "у Пронизывающего доступно %d (2 ветки за монеты + 2 эволюции)" % g._affordable("basic"))
	g._open_upg_tab("splash")
	check(g.shop_refs["splash"]["card"].visible and not g.shop_refs["basic"]["card"].visible, "вкладка не переключила карточку")
	# вкладки шаров — внизу (над «Вернуться к игре»), каждая эволюция — на своей подложке
	await get_tree().process_frame
	await get_tree().process_frame
	check(g.upg_tab_box.get_global_rect().position.y > g.upg_scroll.get_global_rect().position.y, "вкладки шаров не внизу")
	var row: VBoxContainer = g.upg_tab_box.get_parent()
	var last: Control = row.get_child(row.get_child_count() - 1)
	check(last is Button and g.upg_tab_box.get_index() == last.get_index() - 1, "вкладки шаров не прямо над «Вернуться к игре»")
	var eb: Button = g.evo_refs["basic"]["stitch"]["buy"]
	var pan := eb.get_parent()
	while pan != null and not (pan is PanelContainer):
		pan = pan.get_parent()
	check(pan != null and String(pan.name).begins_with("Evo_"), "эволюция не на своей подложке")
	check(g._arrow("8.3 кл/с", "9.9 кл/с") == "8.3 → 9.9 кл/с" and g._arrow("10%", "20%") == "10 → 20%" and g._arrow("×3", "×4") == "×3 → ×4" \
		and g._arrow("−10%", "−8%") == "−10 → −8%", "_arrow: %s | %s" % [g._arrow("8.3 кл/с", "9.9 кл/с"), g._arrow("×3", "×4")])
	# строка ветки — значение без названия и без повторов единиц
	var lb: Label = g.shop_refs["basic"]["tracks"]["speed"]["label"]
	check(lb.text.count("кл/с") == 1 and "→" in lb.text and not ("Скорость" in lb.text), "строка скорости: %s" % lb.text)
	# эволюции — кнопки ◆ у некупленных и у веток купленных
	check(g.evo_refs["basic"]["scout"]["buy"].icon == g.ic_gem, "у некупленной эволюции нет кнопки ◆")
	g._buy_evo("basic", "scout")
	g._refresh_ui()
	# описания: у шара — всегда целиком, у эволюции — и после покупки
	var sd: Label = g.shop_refs["basic"]["card"].find_child("Desc", true, false)
	check(sd != null and sd.autowrap_mode != TextServer.AUTOWRAP_OFF and not sd.clip_text and sd.text == tr(GameData.TYPES["basic"]["desc"]),
		"описание шара не видно целиком")
	var epan: Node = g.shop_refs["basic"]["card"].find_child("Evo_scout", true, false)
	var ed: Label = epan.find_child("EvoDesc", true, false) if epan else null
	check(ed != null and ed.text == tr(GameData.evo_def("basic", "scout")["desc"]), "у купленной эволюции нет описания")
	var lr: Dictionary = g.evo_refs["basic"]["scout"]["ladders"]["scout_radius"]
	check(lr["button"].icon == g.ic_gem and lr["button"].text == "1" and lr["label"].text == "2 → 3 кл", "строка ветки эволюции: «%s» [%s]" % [lr["label"].text, lr["button"].text])

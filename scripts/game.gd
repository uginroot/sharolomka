extends Node2D
## Игровая карта: сетка квадратов и белых стен, шарики, камера с масштабом,
## нижняя панель (выбор шара и сброс) и полупрозрачное окно прокачки.

const Maps = preload("res://scripts/maps.gd")
const BallScript = preload("res://scripts/ball.gd")

const CELL := 40.0               # размер клетки в мировых единицах
const CHUNK := 8                 # поле перерисовывается кусками CHUNK×CHUNK
const RESET_CD := 30.0
const SPD_MAX := 10
const TEXT_MIN_PX := 24.0        # меньше этого размера клетки на экране цифры скрываются
const MAX_OFFLINE := 86400.0     # прогресс в свёрнутом виде — не больше суток
const WALL_COLOR := Color(0.93, 0.94, 0.97)

# ---- карта
var map: Dictionary
var map_index := 0
var cols := 0
var rows := 0
var world_size := Vector2.ZERO
var hp := PackedInt32Array()
var wall := PackedByteArray()
var outside := PackedByteArray()
var ucell := PackedByteArray()
var order := PackedInt32Array()   # квадраты по удалённости от старта (для офлайн-прогресса)
var alive := 0
var total := 0
var start_pos := Vector2.ZERO

# ---- шарики и эффекты
var balls: Array = []
var poisons := {}
var popups: Array = []
var colors := {}
var t_idx := {}
var st_dmg := PackedInt32Array()
var st_speed := PackedFloat32Array()
var st_lvl := PackedInt32Array()
var st_sup := PackedByteArray()

# ---- экономика карты
var rubles := 0
var counts := {}
var dmg_lvl := {}
var spd_lvl := {}
var reset_cd := {}

# ---- скорость урона (для офлайн-прогресса)
var live_dmg := 0
var rate_buf := PackedFloat32Array()
var rate_idx := 0
var rate_filled := 0
var rate_t := 0.0
var dmg_rate := 0.0
var offline_mode := false
var paused_at := 0.0

# ---- состояние
var aim_angle := -90.0
var snap_mode := 0
var selected := "basic"
var time_acc := 0.0
var save_t := 0.0
var redraw_t := 0.0
var ui_t := 0.0
var overlay_dirty := true
var completed := false

# ---- отрисовка
var bg_node: Node2D
var wall_node: Node2D
var overlay: Node2D
var chunks: Array = []
var chunk_dirty := PackedByteArray()
var dirty_count := 0
var ccols := 0
var crows := 0
var lod_text := true
var mm: MultiMesh
var mm_buf := PackedFloat32Array()
var mm_cap := 0
var mm_count := -1
var dot_tex: ImageTexture

# ---- камера и ввод
var cam: Camera2D
var zoom := 1.0
var zoom_min := 0.2
var zoom_max := 2.5
var cam_ready := false
var top_h := 80.0
var bottom_h := 160.0
var touches := {}
var pinch := false
var pinch_dist := 0.0
var pinch_mid := Vector2.ZERO
var mouse_pan := false

# ---- интерфейс
var ui_root: Control
var top_bar: PanelContainer
var top_margin: MarginContainer
var bottom_bar: PanelContainer
var bottom_margin: MarginContainer
var lbl_rub: Label
var lbl_u: Label
var lbl_prog: Label
var btn_snap: Button
var chips_box: HBoxContainer
var chip_group := ButtonGroup.new()
var chips := {}
var btn_reset: Button
var upg: Control
var upg_margin: MarginContainer
var upg_rub: Label
var upg_u: Label
var shop_box: VBoxContainer
var perk_box: VBoxContainer
var shop_refs := {}
var perk_refs := {}
var toast: PanelContainer
var toast_label: Label
var toast_t := 0.0


# ================================================================ запуск

func _ready() -> void:
	var maps := Maps.get_maps()
	map_index = clampi(GameData.current_map, 0, maps.size() - 1)
	map = maps[map_index]
	aim_angle = float(map["aim"])
	for ti in GameData.TYPE_ORDER.size():
		var t: String = GameData.TYPE_ORDER[ti]
		t_idx[t] = ti
		counts[t] = 0
		dmg_lvl[t] = 0
		spd_lvl[t] = 0
		reset_cd[t] = 0.0
		colors[t] = GameData.TYPES[t]["color"]
	var nt := GameData.TYPE_ORDER.size()
	st_dmg.resize(nt)
	st_speed.resize(nt)
	st_lvl.resize(nt)
	st_sup.resize(nt)
	rate_buf.resize(30)
	rate_buf.fill(0.0)
	dot_tex = _circle_texture(32, Color.WHITE)

	_build_level()
	var saved_at := 0.0
	if _load_state():
		saved_at = float(GameData.map_states[String(map["id"])].get("saved_at", 0.0))
	else:
		counts["basic"] = 1
	_recalc_stats()
	_build_nodes()
	for t in GameData.TYPE_ORDER:
		for k in int(counts[t]):
			_spawn_ball(t, aim_angle + (randf_range(-30.0, 30.0) if saved_at > 0.0 else 0.0))

	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()
	if saved_at > 0.0:
		_apply_offline(Time.get_unix_time_from_system() - saved_at)


func _center(i: int) -> Vector2:
	@warning_ignore("integer_division")
	return Vector2((i % cols + 0.5) * CELL, (i / cols + 0.5) * CELL)


func _scale_poly(p: PackedVector2Array, k: Vector2) -> PackedVector2Array:
	var q := PackedVector2Array()
	for v in p:
		q.append(v * k)
	return q


func _build_level() -> void:
	cols = int(map["cols"])
	rows = int(round(cols * 1.2))
	world_size = Vector2(cols, rows) * CELL
	var k := Vector2(world_size.x / 700.0, world_size.y / 840.0)
	start_pos = map["start"] * k
	var n := cols * rows
	hp.resize(n)
	hp.fill(0)
	wall.resize(n)
	wall.fill(0)
	outside.resize(n)
	outside.fill(0)
	ucell.resize(n)
	ucell.fill(0)

	var border := _scale_poly(map["border"], k)
	var obstacles: Array = []
	for o in map["obstacles"]:
		obstacles.append(_scale_poly(o, k))

	# 1. внешняя граница: всё снаружи — пустота, контур — стена
	var border_wall := PackedByteArray()
	border_wall.resize(n)
	border_wall.fill(0)
	if border.size() > 2:
		for i in n:
			if not Geometry2D.is_point_in_polygon(_center(i), border):
				outside[i] = 1
		for i in _raster(border):
			wall[i] = 1
			border_wall[i] = 1
			outside[i] = 0

	# 2. контуры картинок — белые кубики
	var ob_cells: Array = []
	for o in obstacles:
		var cells := _raster(o)
		for i in cells:
			if outside[i] == 0:
				wall[i] = 1
		ob_cells.append(cells)

	# 3. полости и входы
	var cavity := PackedByteArray()
	cavity.resize(n)
	cavity.fill(0)
	for oi in obstacles.size():
		var poly: PackedVector2Array = obstacles[oi]
		var cav := PackedInt32Array()
		for i in n:
			if wall[i] == 0 and outside[i] == 0 and Geometry2D.is_point_in_polygon(_center(i), poly):
				cav.append(i)
				cavity[i] = 1
		_make_entrance(poly, ob_cells[oi], cav, border_wall)

	# 4. всё, до чего шарик не может долететь от старта, становится стеной
	var reach := PackedByteArray()
	reach.resize(n)
	reach.fill(0)
	var sc := clampi(int(start_pos.y / CELL), 0, rows - 1) * cols + clampi(int(start_pos.x / CELL), 0, cols - 1)
	var stack := PackedInt32Array([sc])
	reach[sc] = 1
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var cx := i % cols
		@warning_ignore("integer_division")
		var cy := i / cols
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx: int = cx + o.x
			var yy: int = cy + o.y
			if xx < 0 or yy < 0 or xx >= cols or yy >= rows:
				continue
			var j: int = yy * cols + xx
			if reach[j] == 0 and wall[j] == 0 and outside[j] == 0:
				reach[j] = 1
				stack.append(j)
	for i in n:
		if reach[i] == 0 and wall[i] == 0 and outside[i] == 0:
			wall[i] = 1

	# 5. квадраты: жизни растут с расстоянием от старта
	var hb := float(map["hp_base"])
	var hg := float(map["hp_growth"])
	var cand: Array = []
	var by_dist: Array = []
	total = 0
	for i in n:
		if wall[i] == 1 or outside[i] == 1:
			continue
		var d := _center(i).distance_to(start_pos) / CELL
		if d < 2.2:
			continue
		hp[i] = int(ceil(hb * pow(1.0 + d * hg, 1.6)))
		total += 1
		by_dist.append(Vector2(d, i))
		if d > 3.0:
			cand.append(i)
			if cavity[i] == 1:   # в полостях U-баллы встречаются чаще
				cand.append(i)
				cand.append(i)
	alive = total
	by_dist.sort_custom(func(a, b): return a.x < b.x)
	order.resize(by_dist.size())
	for j in by_dist.size():
		order[j] = int(by_dist[j].y)

	# 6. U-баллы спрятаны в квадратах (одинаково при каждом запуске карты)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(map["id"]))
	var nu := maxi(4, int(total * 0.025))
	var placed := 0
	var guard := 0
	while placed < nu and not cand.is_empty() and guard < nu * 20:
		guard += 1
		var i: int = cand[rng.randi_range(0, cand.size() - 1)]
		if ucell[i] == 0:
			ucell[i] = 1
			placed += 1


## Клетки, через которые проходит контур (без диагональных щелей).
func _raster(poly: PackedVector2Array) -> PackedInt32Array:
	var mark := {}
	for e in poly.size():
		var a := poly[e]
		var b := poly[(e + 1) % poly.size()]
		var steps := int(ceil(a.distance_to(b) / (CELL * 0.2))) + 1
		var px := -1
		var py := -1
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			var cx := clampi(int(p.x / CELL), 0, cols - 1)
			var cy := clampi(int(p.y / CELL), 0, rows - 1)
			if cx == px and cy == py:
				continue
			if px >= 0 and cx != px and cy != py:
				mark[py * cols + cx] = true
			mark[cy * cols + cx] = true
			px = cx
			py = cy
	return PackedInt32Array(mark.keys())


## Прорубает вход шириной 3 клетки со стороны старта.
func _make_entrance(poly: PackedVector2Array, cells: PackedInt32Array, cav: PackedInt32Array,
		border_wall: PackedByteArray) -> void:
	if cav.is_empty():
		return
	var best := -1
	var bd := INF
	for i in cells:
		if wall[i] == 0 or border_wall[i] == 1:
			continue
		var d := _center(i).distance_squared_to(start_pos)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return
	# основная полость — самая большая связная область внутри фигуры
	var in_cav := {}
	for i in cav:
		in_cav[i] = true
	var main := {}
	var seen := {}
	for i0 in cav:
		if seen.has(i0):
			continue
		var comp := {}
		var stack := [i0]
		seen[i0] = true
		while not stack.is_empty():
			var i: int = stack.pop_back()
			comp[i] = true
			var cx := i % cols
			@warning_ignore("integer_division")
			var cy := i / cols
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var xx: int = cx + o.x
				var yy: int = cy + o.y
				if xx < 0 or yy < 0 or xx >= cols or yy >= rows:
					continue
				var j: int = yy * cols + xx
				if in_cav.has(j) and not seen.has(j):
					seen[j] = true
					stack.append(j)
		if comp.size() > main.size():
			main = comp
	var p := _center(best)
	var target := p
	bd = INF
	for i in main:
		var d := _center(i).distance_squared_to(p)
		if d < bd:
			bd = d
			target = _center(i)
	var dir := (target - p).normalized()
	var dist := p.distance_to(target)
	var s := 0.0
	while s <= dist + CELL:
		var q := p + dir * s
		s += CELL * 0.5
		var cx := int(q.x / CELL)
		var cy := int(q.y / CELL)
		if q.x < 0.0 or q.y < 0.0 or cx >= cols or cy >= rows:
			break
		if main.has(cy * cols + cx):
			break
		for yy in range(maxi(0, cy - 1), mini(rows - 1, cy + 1) + 1):
			for xx in range(maxi(0, cx - 1), mini(cols - 1, cx + 1) + 1):
				var j := yy * cols + xx
				if wall[j] == 1 and border_wall[j] == 0:
					wall[j] = 0


# ================================================================ сохранение

func _load_state() -> bool:
	var id := String(map["id"])
	if not GameData.map_states.has(id):
		return false
	var s: Dictionary = GameData.map_states[id]
	if int(s.get("cols", 0)) != cols or int(s.get("rows", 0)) != rows or int(s.get("ver", 0)) != 2:
		return false
	var h: Array = s.get("hp", [])
	if h.size() != hp.size():
		return false
	alive = 0
	for i in h.size():
		hp[i] = int(h[i])
		if hp[i] > 0:
			alive += 1
		else:
			ucell[i] = 0
	rubles = int(s.get("rubles", 0))
	dmg_rate = float(s.get("rate", 0.0))
	var c: Dictionary = s.get("counts", {})
	var dl: Dictionary = s.get("dmg", {})
	var sl: Dictionary = s.get("spd", {})
	for t in GameData.TYPE_ORDER:
		counts[t] = int(c.get(t, 0))
		dmg_lvl[t] = int(dl.get(t, 0))
		spd_lvl[t] = int(sl.get(t, 0))
	if int(counts["basic"]) == 0:
		counts["basic"] = 1
	return true


func _save_state() -> void:
	if completed:
		return
	GameData.map_states[String(map["id"])] = {
		"ver": 2, "cols": cols, "rows": rows, "hp": Array(hp),
		"rubles": rubles, "rate": dmg_rate, "counts": counts.duplicate(),
		"dmg": dmg_lvl.duplicate(), "spd": spd_lvl.duplicate(),
		"saved_at": Time.get_unix_time_from_system(),
	}
	GameData.save_game()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			paused_at = Time.get_unix_time_from_system()
			_save_state()
		NOTIFICATION_APPLICATION_RESUMED:
			if paused_at > 0.0:
				_apply_offline(Time.get_unix_time_from_system() - paused_at)
				paused_at = 0.0
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_save_state()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if upg != null and upg.visible:
				_show_upgrades(false)
			else:
				_to_menu()


## Пока игра была свёрнута или закрыта, шарики продолжали бить со средней скоростью.
func _apply_offline(sec: float) -> void:
	if sec < 3.0 or dmg_rate <= 0.0 or completed:
		return
	sec = minf(sec, MAX_OFFLINE)
	var budget := int(dmg_rate * sec)
	var r0 := rubles
	var u0 := GameData.u
	offline_mode = true
	for i in order:
		if budget <= 0:
			break
		if hp[i] <= 0:
			continue
		var take := mini(hp[i], budget)
		budget -= take
		_damage(i, take, null)
	offline_mode = false
	GameData.save_game()
	var mins := int(sec / 60.0)
	var when := "%d ч %d мин" % [mins / 60, mins % 60] if mins >= 60 else "%d мин" % maxi(1, mins)
	var txt := "Пока вас не было (%s):\n+%s р" % [when, GameData.fmt(rubles - r0)]
	if GameData.u > u0:
		txt += ", +%d U" % (GameData.u - u0)
	_show_toast(txt)


# ================================================================ характеристики

func _speed(t: String) -> float:
	return float(GameData.TYPES[t]["speed"]) * (1.0 + 0.08 * int(spd_lvl[t]))


func _damage_of(t: String) -> int:
	var d := float(GameData.TYPES[t]["damage"]) * (1 + int(dmg_lvl[t]))
	if t == "pierce":
		d *= 1.0 + 0.2 * int(GameData.perks[t])
	return maxi(1, int(round(d)))


func _damage_of_next(t: String) -> int:
	dmg_lvl[t] += 1
	var d := _damage_of(t)
	dmg_lvl[t] -= 1
	return d


func _recalc_stats() -> void:
	for ti in GameData.TYPE_ORDER.size():
		var t: String = GameData.TYPE_ORDER[ti]
		st_dmg[ti] = _damage_of(t)
		st_speed[ti] = _speed(t)
		st_lvl[ti] = int(GameData.perks[t])
		st_sup[ti] = 1 if GameData.supers[t] else 0


func _ball_cost(t: String) -> int:
	return int(round(float(GameData.TYPES[t]["ball_cost"]) * pow(1.35, int(counts[t]))))


func _dmg_cost(t: String) -> int:
	return int(round(float(GameData.TYPES[t]["dmg_cost"]) * pow(1.55, int(dmg_lvl[t]))))


func _spd_cost(t: String) -> int:
	return int(round(float(GameData.TYPES[t]["spd_cost"]) * pow(1.6, int(spd_lvl[t]))))


# ================================================================ шарики

func _spawn_ball(t: String, ang: float) -> void:
	var b = BallScript.new()
	b.type = t
	b.ti = t_idx[t]
	b.radius = float(GameData.TYPES[t]["radius"])
	b.pos = start_pos
	b.vel = Vector2.from_angle(deg_to_rad(ang)) * _speed(t)
	b.check_t = randf()
	balls.append(b)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	time_acc += delta
	for b in balls:
		_move_ball(b, delta)
	if not poisons.is_empty():
		_tick_poison(delta)
	for t in reset_cd:
		if reset_cd[t] > 0.0:
			reset_cd[t] = maxf(0.0, reset_cd[t] - delta)
	if not popups.is_empty():
		for p in popups:
			p["t"] -= delta
			p["pos"].y -= 30.0 * delta
		popups = popups.filter(func(p): return p["t"] > 0.0)
		overlay_dirty = true

	# средняя скорость урона за последние 30 с
	rate_t += delta
	if rate_t >= 1.0:
		rate_t -= 1.0
		rate_buf[rate_idx] = live_dmg
		live_dmg = 0
		rate_idx = (rate_idx + 1) % rate_buf.size()
		rate_filled = mini(rate_filled + 1, rate_buf.size())
		if rate_filled >= 10:
			var sum := 0.0
			for v in rate_buf:
				sum += v
			dmg_rate = sum / rate_filled

	# поле: только изменившиеся и видимые куски, не чаще 10 раз в секунду
	redraw_t -= delta
	if dirty_count > 0 and redraw_t <= 0.0:
		redraw_t = 0.1
		var view := _view_rect().grow(CELL * 2.0)
		for ci in chunk_dirty.size():
			if chunk_dirty[ci] == 1 and _chunk_rect(ci).intersects(view):
				chunk_dirty[ci] = 0
				dirty_count -= 1
				chunks[ci].queue_redraw()
	if overlay_dirty:
		overlay_dirty = false
		overlay.queue_redraw()
	_update_balls_mesh()

	if toast_t > 0.0:
		toast_t -= delta
		toast.modulate.a = clampf(toast_t, 0.0, 1.0)
		if toast_t <= 0.0:
			toast.visible = false

	ui_t -= delta
	if ui_t <= 0.0:
		ui_t = 0.25
		_refresh_ui()
	save_t += delta
	if save_t > 15.0:
		save_t = 0.0
		_save_state()
	_check_complete()


func _move_ball(b, delta: float) -> void:
	# Горячий цикл: работаем с локальными переменными, в объект пишем только при ударе.
	var pos: Vector2 = b.pos
	var vel: Vector2 = b.vel
	var r: float = b.radius
	var r2 := r * r
	var steps := maxi(1, int(ceil(vel.length() * delta / (r * 0.8))))
	var sd := delta / steps
	var inv := 1.0 / CELL
	var cs := Vector2(CELL, CELL)
	var sniper: bool = b.ti == 2
	var wx := world_size.x - r
	var wy := world_size.y - r
	for s in steps:
		pos += vel * sd
		var x0 := maxi(0, int((pos.x - r) * inv))
		var x1 := mini(cols - 1, int((pos.x + r) * inv))
		var y0 := maxi(0, int((pos.y - r) * inv))
		var y1 := mini(rows - 1, int((pos.y + r) * inv))
		for y in range(y0, y1 + 1):
			var row := y * cols
			for x in range(x0, x1 + 1):
				var i := row + x
				var is_wall := wall[i] == 1
				if not is_wall and hp[i] <= 0:
					continue
				var mn := Vector2(x * CELL, y * CELL)
				var mx := mn + cs
				var c := pos.clamp(mn, mx)
				var d := pos - c
				var l2 := d.length_squared()
				if l2 >= r2:
					continue
				var n: Vector2
				if l2 < 0.000001:
					var dl := pos.x - mn.x
					var dr := mx.x - pos.x
					var dt := pos.y - mn.y
					var db := mx.y - pos.y
					var m := minf(minf(dl, dr), minf(dt, db))
					if m == dl:
						n = Vector2.LEFT
						c = Vector2(mn.x, pos.y)
					elif m == dr:
						n = Vector2.RIGHT
						c = Vector2(mx.x, pos.y)
					elif m == dt:
						n = Vector2.UP
						c = Vector2(pos.x, mn.y)
					else:
						n = Vector2.DOWN
						c = Vector2(pos.x, mx.y)
				else:
					n = d / sqrt(l2)
				if not is_wall:
					b.pos = pos
					b.vel = vel
					if _hit_cell(b, i):
						continue   # пролетел насквозь
				pos = c + n * (r + 0.05)
				var vn := vel.dot(n)
				if vn < 0.0:
					vel -= 2.0 * vn * n
					if sniper and (not is_wall or st_sup[2] == 1):
						b.pos = pos
						b.vel = vel
						_try_seek(b, n, -1 if is_wall else i)
						vel = b.vel
		# края мира
		if pos.x < r:
			pos.x = r
			vel.x = absf(vel.x)
		elif pos.x > wx:
			pos.x = wx
			vel.x = -absf(vel.x)
		if pos.y < r:
			pos.y = r
			vel.y = absf(vel.y)
		elif pos.y > wy:
			pos.y = wy
			vel.y = -absf(vel.y)
	b.pos = pos
	b.vel = vel
	b.check_t -= delta
	if b.check_t <= 0.0:
		b.check_t = 1.0
		var ci := clampi(int(pos.y * inv), 0, rows - 1) * cols + clampi(int(pos.x * inv), 0, cols - 1)
		if outside[ci] == 1:   # оказался за внешней стеной — вернуть на старт
			b.pos = start_pos
			b.vel = Vector2.from_angle(deg_to_rad(aim_angle)) * vel.length()
		if b.recent.size() > 30:
			b.recent.clear()


## Возвращает true, если шарик пролетает сквозь квадрат.
func _hit_cell(b, i: int) -> bool:
	var ti: int = b.ti
	var dmg := st_dmg[ti]
	var lvl := st_lvl[ti]
	var sup := st_sup[ti] == 1
	match ti:
		0:  # обычный
			if randf() < 0.06 * lvl:
				dmg *= 5 if sup else 2
			_damage(i, dmg, b)
		1:  # бомба
			_damage(i, dmg, b)
			var sd := maxi(1, int(round(dmg * (0.3 + 0.14 * lvl))))
			var rad := 2 if sup else 1
			var cx := i % cols
			@warning_ignore("integer_division")
			var cy := i / cols
			for yy in range(maxi(0, cy - rad), mini(rows - 1, cy + rad) + 1):
				for xx in range(maxi(0, cx - rad), mini(cols - 1, cx + rad) + 1):
					var j := yy * cols + xx
					if j != i and hp[j] > 0:
						_damage(j, sd, b)
		3:  # пробойник
			if b.recent.has(i) and time_acc - float(b.recent[i]) < 0.3:
				return true
			var before := hp[i]
			_damage(i, dmg, b)
			if sup or dmg >= before:
				b.recent[i] = time_acc
				return true
		4:  # отравитель
			_damage(i, dmg, b)
			if hp[i] > 0:
				_apply_poison(i, dmg * 0.6, 3.0 + lvl, b)
		_:
			_damage(i, dmg, b)
	return false


func _try_seek(b, n: Vector2, exclude: int) -> void:
	if randf() >= 0.4 + 0.12 * st_lvl[2]:
		return
	var cx := clampi(int(b.pos.x / CELL), 0, cols - 1)
	var cy := clampi(int(b.pos.y / CELL), 0, rows - 1)
	for r in range(1, 16):
		var best := -1
		var bd := INF
		for yy in range(cy - r, cy + r + 1):
			if yy < 0 or yy >= rows:
				continue
			var edge_row := (yy == cy - r or yy == cy + r)
			var xs: Array = range(cx - r, cx + r + 1) if edge_row else [cx - r, cx + r]
			for xx in xs:
				if xx < 0 or xx >= cols:
					continue
				var j: int = yy * cols + xx
				if j == exclude or hp[j] <= 0:
					continue
				var dir: Vector2 = _center(j) - b.pos
				if dir.dot(n) <= 0.0:   # цель только с той стороны, куда отскочили
					continue
				var dd := dir.length_squared()
				if dd < bd:
					bd = dd
					best = j
		if best >= 0:
			b.vel = (_center(best) - b.pos).normalized() * b.vel.length()
			return


# ================================================================ квадраты

func _damage(i: int, amount: int, b) -> void:
	if hp[i] <= 0:
		return
	var dealt := mini(amount, hp[i])
	hp[i] -= dealt
	rubles += dealt
	if not offline_mode:
		live_dmg += dealt
	if b != null:
		b.earned += dealt
	_mark(i)
	if hp[i] <= 0:
		_destroy(i)


func _destroy(i: int) -> void:
	alive -= 1
	if ucell[i] == 1:
		ucell[i] = 0
		GameData.u += 1
		if not offline_mode:
			GameData.save_game()
			popups.append({"pos": _center(i), "text": "+1 U", "t": 1.5})
			overlay_dirty = true
	if poisons.has(i):
		var p: Dictionary = poisons[i]
		poisons.erase(i)
		if st_sup[4] == 1:
			var cx := i % cols
			@warning_ignore("integer_division")
			var cy := i / cols
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var xx: int = cx + o.x
				var yy: int = cy + o.y
				if xx >= 0 and xx < cols and yy >= 0 and yy < rows and hp[yy * cols + xx] > 0:
					_apply_poison(yy * cols + xx, p["dps"], p["dur"], p["ball"])


func _apply_poison(i: int, dps: float, dur: float, b) -> void:
	var old_dps := 0.0
	if poisons.has(i):
		old_dps = poisons[i]["dps"]
	else:
		_mark(i)
	poisons[i] = {"dps": maxf(dps, old_dps), "t": dur, "dur": dur, "acc": 0.0, "ball": b}


func _tick_poison(delta: float) -> void:
	for i in poisons.keys():
		if not poisons.has(i):
			continue
		var p: Dictionary = poisons[i]
		p["t"] -= delta
		p["acc"] += p["dps"] * delta
		if p["acc"] >= 1.0:
			var d := int(p["acc"])
			p["acc"] -= d
			_damage(i, d, p["ball"])
		if poisons.has(i) and (p["t"] <= 0.0 or hp[i] <= 0):
			poisons.erase(i)
			_mark(i)


func _check_complete() -> void:
	if completed or alive > 0:
		return
	completed = true
	var id := String(map["id"])
	var reward := 2 if GameData.maps_done.has(id) else 5
	GameData.u += reward
	GameData.maps_done[id] = true
	GameData.maps_unlocked = maxi(GameData.maps_unlocked, map_index + 2)
	GameData.map_states.erase(id)
	GameData.save_game()
	var d := AcceptDialog.new()
	d.title = "Победа!"
	d.dialog_text = "Карта «%s» пройдена!\nНаграда: +%d U" % [map["name"], reward]
	d.ok_button_text = "В меню"
	ui_root.add_child(d)
	d.confirmed.connect(_to_menu)
	d.canceled.connect(_to_menu)
	d.popup_centered()


# ================================================================ отрисовка

func _build_nodes() -> void:
	bg_node = Node2D.new()
	add_child(bg_node)
	bg_node.draw.connect(_draw_bg)
	ccols = int(ceil(float(cols) / CHUNK))
	crows = int(ceil(float(rows) / CHUNK))
	chunk_dirty.resize(ccols * crows)
	chunk_dirty.fill(0)
	for ci in ccols * crows:
		var ch := Node2D.new()
		add_child(ch)
		ch.draw.connect(_draw_chunk.bind(ci))
		chunks.append(ch)
	wall_node = Node2D.new()
	add_child(wall_node)
	wall_node.draw.connect(_draw_walls)

	# все шарики — одна MultiMesh: один вызов отрисовки на кадр
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture = dot_tex
	add_child(mmi)

	overlay = Node2D.new()
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)


func _circle_texture(sz: int, col: Color) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var h := sz * 0.5
	for y in sz:
		for x in sz:
			var d := Vector2(x + 0.5 - h, y + 0.5 - h).length()
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(h - 0.5 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _mark(i: int) -> void:
	@warning_ignore("integer_division")
	var ci := (i / cols / CHUNK) * ccols + (i % cols) / CHUNK
	if chunk_dirty[ci] == 0:
		chunk_dirty[ci] = 1
		dirty_count += 1


func _mark_all() -> void:
	for ci in chunk_dirty.size():
		if chunk_dirty[ci] == 0:
			chunk_dirty[ci] = 1
			dirty_count += 1
	redraw_t = 0.0


func _chunk_rect(ci: int) -> Rect2:
	@warning_ignore("integer_division")
	return Rect2((ci % ccols) * CHUNK * CELL, (ci / ccols) * CHUNK * CELL, CHUNK * CELL, CHUNK * CELL)


func _update_balls_mesh() -> void:
	var n := balls.size()
	if n != mm_count:
		if n > mm_cap:
			mm_cap = maxi(32, mm_cap * 2)
			while mm_cap < n:
				mm_cap *= 2
			mm.instance_count = mm_cap
			mm_buf.resize(mm_cap * 12)
			mm_buf.fill(0.0)
		var min_d := 7.0 / zoom   # при сильном отдалении шарик не меньше ~7 пикселей
		for k in n:
			var b = balls[k]
			var o: int = k * 12
			var dd: float = maxf(b.radius * 2.0, min_d)
			var col: Color = colors[b.type]
			mm_buf[o] = dd
			mm_buf[o + 1] = 0.0
			mm_buf[o + 4] = 0.0
			mm_buf[o + 5] = dd
			mm_buf[o + 8] = col.r
			mm_buf[o + 9] = col.g
			mm_buf[o + 10] = col.b
			mm_buf[o + 11] = 1.0
		mm.visible_instance_count = n
		mm_count = n
	for k in n:
		var p: Vector2 = balls[k].pos
		mm_buf[k * 12 + 3] = p.x
		mm_buf[k * 12 + 7] = p.y
	mm.buffer = mm_buf


func _hp_color(h: int) -> Color:
	var lg := log(float(h)) / log(10.0)
	return Color.from_hsv(fposmod(0.33 - lg * 0.11, 1.0), 0.6, 0.92)


func _draw_bg() -> void:
	bg_node.draw_rect(Rect2(Vector2.ZERO, world_size), Color(0.12, 0.14, 0.19))
	var void_col := Color(0.05, 0.06, 0.08)
	for i in outside.size():
		if outside[i] == 1:
			var c := _center(i)
			bg_node.draw_rect(Rect2(c.x - CELL * 0.5, c.y - CELL * 0.5, CELL, CELL), void_col)
	bg_node.draw_rect(Rect2(Vector2.ZERO, world_size), Color(0.55, 0.6, 0.75), false, 4.0)


func _draw_walls() -> void:
	var shade := Color(0.72, 0.74, 0.8)
	for i in wall.size():
		if wall[i] == 1:
			var c := _center(i)
			var r := Rect2(c.x - CELL * 0.5 + 1.0, c.y - CELL * 0.5 + 1.0, CELL - 2.0, CELL - 2.0)
			wall_node.draw_rect(r, shade)
			wall_node.draw_rect(r.grow(-3.0), WALL_COLOR)


func _draw_chunk(ci: int) -> void:
	var ch: Node2D = chunks[ci]
	@warning_ignore("integer_division")
	var cy0 := (ci / ccols) * CHUNK
	var cx0 := (ci % ccols) * CHUNK
	var y_end := mini(rows, cy0 + CHUNK)
	var x_end := mini(cols, cx0 + CHUNK)
	# при отдалении — только «свет»: квадраты без зазоров и цифр
	var gap := 1.0 if lod_text else 0.0
	for y in range(cy0, y_end):
		for x in range(cx0, x_end):
			var i := y * cols + x
			if hp[i] <= 0:
				continue
			var r := Rect2(x * CELL + gap, y * CELL + gap, CELL - gap * 2.0, CELL - gap * 2.0)
			ch.draw_rect(r, _hp_color(hp[i]))
			if poisons.has(i):
				ch.draw_rect(r.grow(-2.0), Color(0.2, 0.9, 0.2), false, 3.0)
	if not lod_text:
		return
	# цифры рисуем вдвое крупным шрифтом в масштабе 0.5 — так они чётче при приближении
	var font := ThemeDB.fallback_font
	ch.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.5, 0.5))
	for y in range(cy0, y_end):
		for x in range(cx0, x_end):
			var i := y * cols + x
			if hp[i] <= 0:
				continue
			ch.draw_string(font, Vector2(x * CELL * 2.0, (y * CELL + CELL * 0.5) * 2.0 + 11.0),
				GameData.fmt(hp[i]), HORIZONTAL_ALIGNMENT_CENTER, CELL * 2.0, 30, Color(0, 0, 0, 0.85))
	ch.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_overlay() -> void:
	var dir := Vector2.from_angle(deg_to_rad(aim_angle))
	var k := 0.0
	var w := 3.0 / zoom
	var len := 170.0 / zoom
	while k < len:
		overlay.draw_line(start_pos + dir * k, start_pos + dir * minf(k + len * 0.06, len), Color(1, 1, 1, 0.7), w)
		k += len * 0.12
	overlay.draw_circle(start_pos, maxf(9.0, 6.0 / zoom), Color(1.0, 0.85, 0.2))
	var font := ThemeDB.fallback_font
	var fs := int(clampf(26.0 / zoom, 26.0, 200.0))
	for p in popups:
		overlay.draw_string(font, p["pos"] - Vector2(fs * 2, 0), p["text"], HORIZONTAL_ALIGNMENT_CENTER, fs * 4, fs,
			Color(1.0, 0.85, 0.2, clampf(p["t"], 0.0, 1.0)))


# ================================================================ камера

func _screen_to_world(sp: Vector2) -> Vector2:
	return cam.position + (sp - get_viewport_rect().size * 0.5) / zoom


func _view_rect() -> Rect2:
	var vs := get_viewport_rect().size / zoom
	return Rect2(cam.position - vs * 0.5, vs)


func _update_zoom_limits() -> void:
	var vs := get_viewport_rect().size
	var avail := Vector2(vs.x - 16.0, vs.y - top_h - bottom_h - 16.0)
	zoom_min = minf(avail.x / world_size.x, avail.y / world_size.y)
	zoom_max = maxf(zoom_min, 2.5)


func _set_zoom(z: float, anchor: Vector2) -> void:
	var before := _screen_to_world(anchor)
	zoom = clampf(z, zoom_min, zoom_max)
	cam.zoom = Vector2(zoom, zoom)
	cam.position = before - (anchor - get_viewport_rect().size * 0.5) / zoom
	_clamp_cam()
	var lod := CELL * zoom >= TEXT_MIN_PX
	if lod != lod_text:
		lod_text = lod
		_mark_all()
	mm_count = -1
	overlay_dirty = true


## Карту можно двигать, пока её край не дойдёт до панелей; маленькая карта — по центру.
func _clamp_cam() -> void:
	var vs := get_viewport_rect().size
	var lo_x := (vs.x * 0.5 - 8.0) / zoom
	var hi_x := world_size.x - (vs.x * 0.5 - 8.0) / zoom
	var lo_y := (vs.y * 0.5 - top_h - 8.0) / zoom
	var hi_y := world_size.y - (vs.y * 0.5 - bottom_h - 8.0) / zoom
	var p := cam.position
	p.x = (lo_x + hi_x) * 0.5 if lo_x > hi_x else clampf(p.x, lo_x, hi_x)
	p.y = (lo_y + hi_y) * 0.5 if lo_y > hi_y else clampf(p.y, lo_y, hi_y)
	cam.position = p


# ================================================================ ввод

func _over_ui(p: Vector2) -> bool:
	if upg.visible:
		return true
	return top_bar.get_global_rect().has_point(p) or bottom_bar.get_global_rect().has_point(p)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			if touches.is_empty() and _over_ui(e.position):
				return
			touches[e.index] = e.position
			if touches.size() == 1 and not pinch:
				_aim_at(e.position)
			elif touches.size() >= 2:
				pinch = true
				_pinch_reset()
		else:
			touches.erase(e.index)
			if touches.size() >= 2:
				_pinch_reset()
			if touches.is_empty():
				pinch = false
	elif e is InputEventScreenDrag:
		if not touches.has(e.index):
			return
		touches[e.index] = e.position
		if pinch and touches.size() >= 2:
			_pinch_update()
		elif not pinch:
			_aim_at(e.position)
	elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION:
		if _over_ui(e.position):
			return
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom * 1.15, e.position)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom / 1.15, e.position)
		elif e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			_aim_at(e.position)
		elif e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			mouse_pan = e.pressed
	elif e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION:
		if mouse_pan:
			cam.position -= e.relative / zoom
			_clamp_cam()
		elif e.button_mask & MOUSE_BUTTON_MASK_LEFT and not _over_ui(e.position):
			_aim_at(e.position)


func _pinch_points() -> Array:
	var k := touches.keys()
	return [touches[k[0]], touches[k[1]]]


func _pinch_reset() -> void:
	var pts := _pinch_points()
	pinch_dist = maxf(1.0, pts[0].distance_to(pts[1]))
	pinch_mid = (pts[0] + pts[1]) * 0.5


func _pinch_update() -> void:
	var pts := _pinch_points()
	var dist := maxf(1.0, pts[0].distance_to(pts[1]))
	var mid: Vector2 = (pts[0] + pts[1]) * 0.5
	_set_zoom(zoom * dist / pinch_dist, mid)
	cam.position -= (mid - pinch_mid) / zoom
	_clamp_cam()
	pinch_dist = dist
	pinch_mid = mid


func _aim_at(sp: Vector2) -> void:
	var p := _screen_to_world(sp)
	if not Rect2(Vector2.ZERO, world_size).has_point(p):
		return
	var d := p - start_pos
	if d.length() < 12.0:
		return
	aim_angle = _snap(rad_to_deg(d.angle()))
	overlay_dirty = true


func _snap(a: float) -> float:
	match snap_mode:
		1:
			return round(a / 45.0) * 45.0
		2:
			return round(a / 90.0) * 90.0
	return a


func _cycle_snap() -> void:
	snap_mode = (snap_mode + 1) % 3
	aim_angle = _snap(aim_angle)
	overlay_dirty = true
	_refresh_ui()


# ================================================================ действия

func _buy_ball(t: String) -> void:
	var c := _ball_cost(t)
	if rubles < c:
		return
	rubles -= c
	counts[t] += 1
	_spawn_ball(t, aim_angle)
	_refresh_ui()


func _buy_dmg(t: String) -> void:
	var c := _dmg_cost(t)
	if rubles < c:
		return
	rubles -= c
	dmg_lvl[t] += 1
	_recalc_stats()
	_refresh_ui()


func _buy_spd(t: String) -> void:
	var c := _spd_cost(t)
	if rubles < c or int(spd_lvl[t]) >= SPD_MAX:
		return
	rubles -= c
	spd_lvl[t] += 1
	_recalc_stats()
	var sp := _speed(t)
	for b in balls:
		if b.type == t:
			b.vel = b.vel.normalized() * sp
	_refresh_ui()


## Раз в 30 с: шарик выбранного типа, заработавший меньше всех, возвращается на старт по прицелу.
func _reset_stuck() -> void:
	var t := selected
	if reset_cd[t] > 0.0:
		return
	var worst = null
	for b in balls:
		if b.type == t and (worst == null or b.earned < worst.earned):
			worst = b
	if worst == null:
		return
	worst.pos = start_pos
	worst.vel = Vector2.from_angle(deg_to_rad(aim_angle)) * _speed(t)
	for b in balls:
		if b.type == t:
			b.earned = 0
	reset_cd[t] = RESET_CD
	_refresh_ui()


func _unlock(t: String) -> void:
	var c := int(GameData.TYPES[t]["unlock_u"])
	if GameData.u < c or GameData.unlocked[t]:
		return
	GameData.u -= c
	GameData.unlocked[t] = true
	GameData.save_game()
	_rebuild_rows()


func _perk_up(t: String) -> void:
	var lvl := int(GameData.perks[t])
	if lvl >= GameData.PERK_MAX or GameData.u < lvl + 1:
		return
	GameData.u -= lvl + 1
	GameData.perks[t] = lvl + 1
	GameData.save_game()
	_recalc_stats()
	_refresh_ui()


func _super_up(t: String) -> void:
	if GameData.supers[t] or GameData.u < GameData.SUPER_COST:
		return
	GameData.u -= GameData.SUPER_COST
	GameData.supers[t] = true
	GameData.save_game()
	_recalc_stats()
	_refresh_ui()


func _select(t: String) -> void:
	selected = t
	_refresh_ui()


func _to_menu() -> void:
	_save_state()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ================================================================ интерфейс

func _safe_margins() -> Array:
	# отступы от вырезов, скруглений и системных полос + запас, чтобы кнопки не прижимались к краю
	var l := 0.0
	var t := 0.0
	var r := 0.0
	var b := 0.0
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var win := Vector2(DisplayServer.window_get_size())
		if win.x > 0.0 and win.y > 0.0:
			var k := get_viewport_rect().size / win
			l = safe.position.x * k.x
			t = safe.position.y * k.y
			r = maxf(0.0, (win.x - safe.end.x) * k.x)
			b = maxf(0.0, (win.y - safe.end.y) * k.y)
	return [l + 22.0, t + 12.0, r + 22.0, b + 22.0]


func _panel_style(alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, alpha)
	return sb


func _button(text: String, h: float = 56.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = h
	return b


func _small_label(text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _margin(m: MarginContainer, v: Array) -> void:
	m.add_theme_constant_override("margin_left", int(v[0]))
	m.add_theme_constant_override("margin_top", int(v[1]))
	m.add_theme_constant_override("margin_right", int(v[2]))
	m.add_theme_constant_override("margin_bottom", int(v[3]))


func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = GameData.make_theme()
	cl.add_child(ui_root)

	# --- верхняя полоса: меню, деньги, прогресс, режим угла
	top_bar = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", _panel_style(0.75))
	top_bar.anchor_right = 1.0
	ui_root.add_child(top_bar)
	top_margin = MarginContainer.new()
	top_bar.add_child(top_margin)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 10)
	top_margin.add_child(tr)
	var bmenu := _button("Меню", 52)
	bmenu.pressed.connect(_to_menu)
	tr.add_child(bmenu)
	lbl_rub = Label.new()
	lbl_u = Label.new()
	lbl_prog = Label.new()
	for l in [lbl_rub, lbl_u, lbl_prog]:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tr.add_child(l)
	btn_snap = _button("", 52)
	btn_snap.pressed.connect(_cycle_snap)
	tr.add_child(btn_snap)
	top_bar.resized.connect(_on_bars_resized)

	# --- нижняя панель: выбор шара, сброс, прокачка
	bottom_bar = PanelContainer.new()
	bottom_bar.add_theme_stylebox_override("panel", _panel_style(0.75))
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.anchor_right = 1.0
	bottom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui_root.add_child(bottom_bar)
	bottom_margin = MarginContainer.new()
	bottom_bar.add_child(bottom_margin)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	bottom_margin.add_child(bv)
	chips_box = HBoxContainer.new()
	chips_box.add_theme_constant_override("separation", 8)
	bv.add_child(chips_box)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 10)
	bv.add_child(br)
	btn_reset = _button("Сброс")
	btn_reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_reset.pressed.connect(_reset_stuck)
	br.add_child(btn_reset)
	var bup := _button("Прокачка")
	bup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bup.pressed.connect(_show_upgrades.bind(true))
	br.add_child(bup)
	bottom_bar.resized.connect(_on_bars_resized)

	# --- окно прокачки: полупрозрачное, игра под ним продолжается
	upg = Control.new()
	upg.set_anchors_preset(Control.PRESET_FULL_RECT)
	upg.visible = false
	ui_root.add_child(upg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	upg.add_child(dim)
	upg_margin = MarginContainer.new()
	upg_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	upg.add_child(upg_margin)
	var up := PanelContainer.new()
	var ups := _panel_style(0.82)
	ups.set_corner_radius_all(16)
	ups.content_margin_left = 14
	ups.content_margin_right = 14
	ups.content_margin_top = 12
	ups.content_margin_bottom = 12
	up.add_theme_stylebox_override("panel", ups)
	upg_margin.add_child(up)
	var uv := VBoxContainer.new()
	uv.add_theme_constant_override("separation", 10)
	up.add_child(uv)
	var uh := HBoxContainer.new()
	uv.add_child(uh)
	upg_rub = Label.new()
	upg_u = Label.new()
	for l in [upg_rub, upg_u]:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		uh.add_child(l)
	var bclose := _button("Закрыть", 52)
	bclose.pressed.connect(_show_upgrades.bind(false))
	uh.add_child(bclose)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	uv.add_child(tabs)
	var sc1 := ScrollContainer.new()
	sc1.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc1)
	shop_box = VBoxContainer.new()
	shop_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc1.add_child(shop_box)
	var sc2 := ScrollContainer.new()
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc2)
	perk_box = VBoxContainer.new()
	perk_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(perk_box)
	tabs.set_tab_title(0, "Шарики (рубли)")
	tabs.set_tab_title(1, "Перки (U)")

	# --- всплывающее сообщение
	toast = PanelContainer.new()
	var ts := _panel_style(0.9)
	ts.set_corner_radius_all(14)
	ts.content_margin_left = 18
	ts.content_margin_right = 18
	ts.content_margin_top = 12
	ts.content_margin_bottom = 12
	toast.add_theme_stylebox_override("panel", ts)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 0.3
	toast.anchor_bottom = 0.3
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.visible = false
	ui_root.add_child(toast)
	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(toast_label)

	_rebuild_rows()


func _layout() -> void:
	var m := _safe_margins()
	_margin(top_margin, [m[0], m[1], m[2], 8])
	_margin(bottom_margin, [m[0], 12, m[2], m[3]])
	_margin(upg_margin, [m[0], m[1] + 8.0, m[2], m[3]])
	_on_bars_resized()


func _on_bars_resized() -> void:
	if top_bar == null or bottom_bar == null:
		return
	top_h = top_bar.size.y
	bottom_h = bottom_bar.size.y
	_update_zoom_limits()
	if not cam_ready and top_h > 0.0 and bottom_h > 0.0:
		cam_ready = true
		# стартовый масштаб: клетка ~36 px, но не меньше «вся карта на экране»
		cam.position = start_pos
		_set_zoom(maxf(zoom_min, 36.0 / CELL), get_viewport_rect().size * 0.5)
	else:
		_set_zoom(zoom, get_viewport_rect().size * 0.5)


func _show_upgrades(show: bool) -> void:
	upg.visible = show
	touches.clear()
	pinch = false
	_refresh_ui()


func _show_toast(text: String) -> void:
	toast_label.text = text
	toast.visible = true
	toast.modulate.a = 1.0
	toast_t = 5.0


func _col(parent: HBoxContainer, caption: String, cb: Callable) -> Dictionary:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(v)
	var l := _small_label(caption)
	v.add_child(l)
	var b := _button("")
	b.pressed.connect(cb)
	v.add_child(b)
	return {"label": l, "button": b}


func _rebuild_rows() -> void:
	for box in [shop_box, perk_box, chips_box]:
		for c in box.get_children():
			c.queue_free()
	shop_refs.clear()
	perk_refs.clear()
	chips.clear()
	chip_group = ButtonGroup.new()
	if not GameData.unlocked[selected]:
		selected = "basic"

	for t in GameData.TYPE_ORDER:
		var def: Dictionary = GameData.TYPES[t]

		# --- фишка выбора шара на главном экране
		if GameData.unlocked[t]:
			var chip := _button("", 56)
			chip.toggle_mode = true
			chip.button_group = chip_group
			chip.icon = _circle_texture(26, def["color"])
			chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			chip.button_pressed = (t == selected)
			chip.pressed.connect(_select.bind(t))
			chips_box.add_child(chip)
			chips[t] = chip

		# --- магазин за рубли
		var box := VBoxContainer.new()
		shop_box.add_child(box)
		var head := HBoxContainer.new()
		box.add_child(head)
		var sw := TextureRect.new()
		sw.texture = _circle_texture(22, def["color"])
		sw.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		head.add_child(sw)
		var name_l := Label.new()
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(name_l)
		if GameData.unlocked[t]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			box.add_child(row)
			shop_refs[t] = {
				"name": name_l,
				"buy": _col(row, "Купить шар", _buy_ball.bind(t)),
				"dmg": _col(row, "Урон", _buy_dmg.bind(t)),
				"spd": _col(row, "Скорость", _buy_spd.bind(t)),
			}
		else:
			name_l.text = "%s — закрыт (вкладка «Перки»)" % def["name"]
			name_l.modulate = Color(1, 1, 1, 0.5)
		shop_box.add_child(HSeparator.new())

		# --- прокачка за U
		var pb := VBoxContainer.new()
		perk_box.add_child(pb)
		var pl := Label.new()
		pl.text = def["name"]
		pl.add_theme_color_override("font_color", def["color"])
		pb.add_child(pl)
		var desc := Label.new()
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 17)
		desc.text = "Перк «%s»: %s\nСупер «%s»: %s" % [def["perk"], def["perk_desc"], def["super"], def["super_desc"]]
		pb.add_child(desc)
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		pb.add_child(prow)
		if GameData.unlocked[t]:
			var perk_btn := _button("")
			perk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			perk_btn.pressed.connect(_perk_up.bind(t))
			prow.add_child(perk_btn)
			var sup_btn := _button("")
			sup_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sup_btn.pressed.connect(_super_up.bind(t))
			prow.add_child(sup_btn)
			perk_refs[t] = {"perk": perk_btn, "super": sup_btn}
		else:
			var ub := _button("")
			ub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ub.pressed.connect(_unlock.bind(t))
			prow.add_child(ub)
			perk_refs[t] = {"unlock": ub}
		perk_box.add_child(HSeparator.new())
	_refresh_ui()


func _refresh_ui() -> void:
	if lbl_rub == null:
		return
	lbl_rub.text = "%s р" % GameData.fmt(rubles)
	lbl_u.text = "U %d" % GameData.u
	lbl_prog.text = "%d%%" % int(100.0 * (total - alive) / maxi(1, total))
	btn_snap.text = ["Угол: любой", "Угол: 45°", "Угол: 90°"][snap_mode]

	for t in chips:
		chips[t].text = "×%d" % counts[t]
	var cd: float = reset_cd[selected]
	var tname: String = GameData.TYPES[selected]["name"]
	btn_reset.text = "Сброс: %s" % tname if cd <= 0.0 else "%s: %d с" % [tname, int(ceil(cd))]
	btn_reset.disabled = cd > 0.0 or int(counts[selected]) == 0

	if not upg.visible:
		return
	upg_rub.text = "%s р" % GameData.fmt(rubles)
	upg_u.text = "U: %d" % GameData.u
	for t in shop_refs:
		var r: Dictionary = shop_refs[t]
		r["name"].text = "%s ×%d" % [GameData.TYPES[t]["name"], counts[t]]
		var bc := _ball_cost(t)
		r["buy"]["button"].text = "%s р" % GameData.fmt(bc)
		r["buy"]["button"].disabled = rubles < bc
		var dc := _dmg_cost(t)
		r["dmg"]["label"].text = "Урон %d → %d" % [_damage_of(t), _damage_of_next(t)]
		r["dmg"]["button"].text = "%s р" % GameData.fmt(dc)
		r["dmg"]["button"].disabled = rubles < dc
		var sl := int(spd_lvl[t])
		r["spd"]["label"].text = "Скорость %d/%d" % [sl, SPD_MAX]
		if sl >= SPD_MAX:
			r["spd"]["button"].text = "макс."
			r["spd"]["button"].disabled = true
		else:
			var scost := _spd_cost(t)
			r["spd"]["button"].text = "%s р" % GameData.fmt(scost)
			r["spd"]["button"].disabled = rubles < scost

	for t in perk_refs:
		var r: Dictionary = perk_refs[t]
		if r.has("unlock"):
			var uc := int(GameData.TYPES[t]["unlock_u"])
			r["unlock"].text = "Открыть за %d U" % uc
			r["unlock"].disabled = GameData.u < uc
			continue
		var lvl := int(GameData.perks[t])
		if lvl >= GameData.PERK_MAX:
			r["perk"].text = "Перк: макс."
			r["perk"].disabled = true
		else:
			r["perk"].text = "Перк %d/%d · %d U" % [lvl, GameData.PERK_MAX, lvl + 1]
			r["perk"].disabled = GameData.u < lvl + 1
		if GameData.supers[t]:
			r["super"].text = "Супер активен"
			r["super"].disabled = true
		else:
			r["super"].text = "Супер · %d U" % GameData.SUPER_COST
			r["super"].disabled = GameData.u < GameData.SUPER_COST

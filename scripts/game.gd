extends Node2D
## Игровая карта: сетка квадратов, препятствия, шарики, магазин.

const Maps = preload("res://scripts/maps.gd")
const BallScript = preload("res://scripts/ball.gd")

const WORLD := Vector2(700, 840)
const TOP_H := 100.0
const BOTTOM_H := 440.0
const BUCKET := 40.0
const RESET_CD := 30.0
const SPD_MAX := 10

var map: Dictionary
var map_index := 0
var cols := 0
var rows := 0
var cell := 1.0
var hp := PackedInt32Array()
var vis := PackedByteArray()
var ucell := PackedByteArray()
var alive := 0
var total := 0

var seg_a := PackedVector2Array()
var seg_b := PackedVector2Array()
var buckets: Array = []
var bw := 0
var bh := 0

var balls: Array = []
var poisons := {}
var t_idx := {}
var st_dmg := PackedInt32Array()
var st_speed := PackedFloat32Array()
var st_lvl := PackedInt32Array()
var st_sup := PackedByteArray()
var popups: Array = []
var colors := {}

var rubles := 0
var counts := {}
var dmg_lvl := {}
var spd_lvl := {}
var reset_cd := {}

var start_pos := Vector2.ZERO
var aim_angle := -90.0
var snap_mode := 0
var time_acc := 0.0
var save_t := 0.0
var redraw_t := 0.0
var ui_t := 0.0
var field_dirty := true
var overlay_dirty := true
var completed := false

const CHUNK := 6
var world: Node2D
var bg_node: Node2D
var obst_node: Node2D
var overlay: Node2D
var chunks: Array = []
var chunk_dirty := PackedByteArray()
var ccols := 0
var crows := 0
var mm: MultiMesh
var mm_buf := PackedFloat32Array()
var mm_cap := 0
var mm_count := -1

var ui_root: Control
var lbl_map: Label
var lbl_rub: Label
var lbl_u: Label
var lbl_prog: Label
var btn_snap: Button
var shop_box: VBoxContainer
var perk_box: VBoxContainer
var shop_refs := {}
var perk_refs := {}


# ---------------------------------------------------------------- setup

func _ready() -> void:
	var maps := Maps.get_maps()
	map_index = clampi(GameData.current_map, 0, maps.size() - 1)
	map = maps[map_index]
	aim_angle = float(map["aim"])
	for t in GameData.TYPE_ORDER:
		counts[t] = 0
		dmg_lvl[t] = 0
		spd_lvl[t] = 0
		reset_cd[t] = 0.0
		colors[t] = GameData.TYPES[t]["color"]

	for ti in GameData.TYPE_ORDER.size():
		t_idx[GameData.TYPE_ORDER[ti]] = ti
	st_dmg.resize(GameData.TYPE_ORDER.size())
	st_speed.resize(GameData.TYPE_ORDER.size())
	st_lvl.resize(GameData.TYPE_ORDER.size())
	st_sup.resize(GameData.TYPE_ORDER.size())

	_build_level()
	var loaded := _load_state()
	if not loaded:
		counts["basic"] = 1
	_recalc_stats()
	_build_nodes()
	for t in GameData.TYPE_ORDER:
		for k in int(counts[t]):
			var spread := randf_range(-30.0, 30.0) if loaded else 0.0
			_spawn_ball(t, aim_angle + spread)

	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_ui()


func _build_level() -> void:
	cols = int(map["cols"])
	cell = WORLD.x / cols
	rows = int(floor(WORLD.y / cell))
	var n := cols * rows
	hp.resize(n)
	vis.resize(n)
	ucell.resize(n)
	hp.fill(0)
	vis.fill(0)
	ucell.fill(0)
	start_pos = map["start"]

	var border: PackedVector2Array = map["border"]
	var obstacles: Array = map["obstacles"]
	_add_poly(border)
	for o in obstacles:
		_add_poly(o)
	_build_buckets()

	# Клетки, через которые проходит контур, недоступны.
	var blocked := PackedByteArray()
	blocked.resize(n)
	blocked.fill(0)
	for s in seg_a.size():
		var a := seg_a[s]
		var b := seg_b[s]
		var steps := int(ceil(a.distance_to(b) / (cell * 0.25))) + 1
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			var x0 := maxi(0, int((p.x - 1.5) / cell))
			var x1 := mini(cols - 1, int((p.x + 1.5) / cell))
			var y0 := maxi(0, int((p.y - 1.5) / cell))
			var y1 := mini(rows - 1, int((p.y + 1.5) / cell))
			for yy in range(y0, y1 + 1):
				for xx in range(x0, x1 + 1):
					blocked[yy * cols + xx] = 1

	var cand: Array = []
	total = 0
	var hb := float(map["hp_base"])
	var hg := float(map["hp_growth"])
	for y in rows:
		for x in cols:
			var i := y * cols + x
			if blocked[i] == 1:
				continue
			var c := Vector2((x + 0.5) * cell, (y + 0.5) * cell)
			if not _point_ok(c):
				continue
			var d := c.distance_to(start_pos) / cell
			if d < 1.8:
				continue
			hp[i] = int(ceil(hb * pow(1.0 + d * hg, 1.6)))
			total += 1
			if d <= 4.5:
				vis[i] = 1
			if d > 3.0:
				cand.append(i)
	alive = total

	# U-баллы прячутся в случайных квадратах (одинаково при каждом запуске карты).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(map["id"]))
	var nu := maxi(4, int(total * 0.03))
	for k in nu:
		if cand.is_empty():
			break
		var j := rng.randi_range(0, cand.size() - 1)
		ucell[cand[j]] = 1
		cand.remove_at(j)


func _add_poly(p: PackedVector2Array) -> void:
	for k in p.size():
		seg_a.append(p[k])
		seg_b.append(p[(k + 1) % p.size()])


func _build_buckets() -> void:
	bw = int(ceil(WORLD.x / BUCKET))
	bh = int(ceil(WORLD.y / BUCKET))
	buckets = []
	buckets.resize(bw * bh)
	for k in buckets.size():
		buckets[k] = PackedInt32Array()
	for s in seg_a.size():
		var r := Rect2(seg_a[s], Vector2.ZERO).expand(seg_b[s]).grow(12.0)
		var x0 := clampi(int(r.position.x / BUCKET), 0, bw - 1)
		var x1 := clampi(int(r.end.x / BUCKET), 0, bw - 1)
		var y0 := clampi(int(r.position.y / BUCKET), 0, bh - 1)
		var y1 := clampi(int(r.end.y / BUCKET), 0, bh - 1)
		for by in range(y0, y1 + 1):
			for bx in range(x0, x1 + 1):
				var arr: PackedInt32Array = buckets[by * bw + bx]
				arr.append(s)
				buckets[by * bw + bx] = arr


func _point_ok(p: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(p, map["border"]):
		return false
	for o in map["obstacles"]:
		if Geometry2D.is_point_in_polygon(p, o):
			return false
	return true


func _layout() -> void:
	var vs := get_viewport_rect().size
	var avail := Rect2(8, TOP_H + 6, vs.x - 16, vs.y - TOP_H - BOTTOM_H - 12)
	var s := minf(avail.size.x / WORLD.x, avail.size.y / WORLD.y)
	world.scale = Vector2(s, s)
	world.position = avail.position + (avail.size - WORLD * s) * 0.5


# ---------------------------------------------------------------- save

func _load_state() -> bool:
	var id := String(map["id"])
	if not GameData.map_states.has(id):
		return false
	var s: Dictionary = GameData.map_states[id]
	if int(s.get("cols", 0)) != cols or int(s.get("rows", 0)) != rows:
		return false
	var h: Array = s.get("hp", [])
	var v: Array = s.get("vis", [])
	if h.size() != hp.size() or v.size() != vis.size():
		return false
	alive = 0
	for i in h.size():
		hp[i] = int(h[i])
		vis[i] = int(v[i])
		if hp[i] > 0:
			alive += 1
	rubles = int(s.get("rubles", 0))
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
		"cols": cols, "rows": rows, "hp": Array(hp), "vis": Array(vis),
		"rubles": rubles, "counts": counts.duplicate(),
		"dmg": dmg_lvl.duplicate(), "spd": spd_lvl.duplicate(),
	}
	GameData.save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_save_state()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_to_menu()


# ---------------------------------------------------------------- stats

func _speed(t: String) -> float:
	return float(GameData.TYPES[t]["speed"]) * (1.0 + 0.08 * int(spd_lvl[t]))


func _damage_of(t: String) -> int:
	var d := float(GameData.TYPES[t]["damage"]) * (1 + int(dmg_lvl[t]))
	if t == "pierce":
		d *= 1.0 + 0.2 * int(GameData.perks[t])
	return maxi(1, int(round(d)))


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


# ---------------------------------------------------------------- balls

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

	# Поле перерисовывается кусками и не чаще 10 раз в секунду.
	redraw_t -= delta
	if field_dirty and redraw_t <= 0.0:
		for ci in chunk_dirty.size():
			if chunk_dirty[ci] == 1:
				chunk_dirty[ci] = 0
				chunks[ci].queue_redraw()
		field_dirty = false
		redraw_t = 0.1
	if overlay_dirty:
		overlay_dirty = false
		overlay.queue_redraw()
	_update_balls_mesh()

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
	var inv := 1.0 / cell
	var cs := Vector2(cell, cell)
	var sniper: bool = b.type == "sniper"
	for s in steps:
		pos += vel * sd
		# --- квадраты
		var x0 := maxi(0, int((pos.x - r) * inv))
		var x1 := mini(cols - 1, int((pos.x + r) * inv))
		var y0 := maxi(0, int((pos.y - r) * inv))
		var y1 := mini(rows - 1, int((pos.y + r) * inv))
		for y in range(y0, y1 + 1):
			var row := y * cols
			for x in range(x0, x1 + 1):
				var i := row + x
				if hp[i] <= 0:
					continue
				var mn := Vector2(x * cell, y * cell)
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
				b.pos = pos
				b.vel = vel
				if _hit_cell(b, i):
					continue   # пролетел насквозь
				pos = c + n * (r + 0.05)
				var vn := vel.dot(n)
				if vn < 0.0:
					vel -= 2.0 * vn * n
					if sniper:
						b.pos = pos
						b.vel = vel
						_try_seek(b, n, i)
						vel = b.vel
		# --- стены и препятствия
		var bk: PackedInt32Array = buckets[clampi(int(pos.y / BUCKET), 0, bh - 1) * bw + clampi(int(pos.x / BUCKET), 0, bw - 1)]
		for si in bk:
			var c := Geometry2D.get_closest_point_to_segment(pos, seg_a[si], seg_b[si])
			var d := pos - c
			var l2 := d.length_squared()
			if l2 >= r2:
				continue
			var n: Vector2
			if l2 < 0.000001:
				n = -vel.normalized()
			else:
				n = d / sqrt(l2)
			pos = c + n * (r + 0.05)
			var vn := vel.dot(n)
			if vn < 0.0:
				vel -= 2.0 * vn * n
				if sniper and st_sup[2] == 1:
					b.pos = pos
					b.vel = vel
					_try_seek(b, n, -1)
					vel = b.vel
	b.pos = pos
	b.vel = vel
	b.check_t -= delta
	if b.check_t <= 0.0:
		b.check_t = 1.0
		if not _point_ok(pos):   # вылетел за стену — вернуть на старт
			b.pos = start_pos
			b.vel = Vector2.from_angle(deg_to_rad(aim_angle)) * vel.length()
		if b.recent.size() > 30:
			b.recent.clear()


## Возвращает true, если шарик пролетает сквозь квадрат.
func _hit_cell(b, i: int) -> bool:
	var t: String = b.type
	var ti: int = b.ti
	var dmg := st_dmg[ti]
	var lvl := st_lvl[ti]
	var sup := st_sup[ti] == 1
	match t:
		"basic":
			if randf() < 0.06 * lvl:
				dmg *= 5 if sup else 2
			_damage(i, dmg, b)
		"splash":
			_damage(i, dmg, b)
			var sd := maxi(1, int(round(dmg * (0.3 + 0.14 * lvl))))
			var rad := 2 if sup else 1
			var cx := i % cols
			var cy := i / cols
			for yy in range(maxi(0, cy - rad), mini(rows - 1, cy + rad) + 1):
				for xx in range(maxi(0, cx - rad), mini(cols - 1, cx + rad) + 1):
					var j := yy * cols + xx
					if j != i and hp[j] > 0:
						_damage(j, sd, b)
		"pierce":
			if b.recent.has(i) and time_acc - float(b.recent[i]) < 0.3:
				return true
			var before := hp[i]
			_damage(i, dmg, b)
			if sup or dmg >= before:
				b.recent[i] = time_acc
				return true
		"poison":
			_damage(i, dmg, b)
			if hp[i] > 0:
				_apply_poison(i, dmg * 0.6, 3.0 + lvl, b)
		_:
			_damage(i, dmg, b)
	return false


func _try_seek(b, n: Vector2, exclude: int) -> void:
	var chance := 0.4 + 0.12 * st_lvl[2]
	if randf() >= chance:
		return
	var cx := clampi(int(b.pos.x / cell), 0, cols - 1)
	var cy := clampi(int(b.pos.y / cell), 0, rows - 1)
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
				if j == exclude or hp[j] <= 0 or vis[j] == 0:
					continue
				var c := Vector2((xx + 0.5) * cell, (yy + 0.5) * cell)
				var dir: Vector2 = c - b.pos
				if dir.dot(n) <= 0.0:   # цель только с той стороны, куда отскочили
					continue
				var dd := dir.length_squared()
				if dd < bd:
					bd = dd
					best = j
		if best >= 0:
			var tc := Vector2((best % cols + 0.5) * cell, (best / cols + 0.5) * cell)
			b.vel = (tc - b.pos).normalized() * b.vel.length()
			return


# ---------------------------------------------------------------- cells

func _damage(i: int, amount: int, b) -> void:
	if hp[i] <= 0:
		return
	var dealt := mini(amount, hp[i])
	hp[i] -= dealt
	rubles += dealt
	if b != null:
		b.earned += dealt
	_mark(i)
	if hp[i] <= 0:
		_destroy(i)


func _destroy(i: int) -> void:
	alive -= 1
	var cx := i % cols
	var cy := i / cols
	if ucell[i] == 1:
		ucell[i] = 0
		GameData.u += 1
		GameData.save_game()
		popups.append({"pos": Vector2((cx + 0.5) * cell, (cy + 0.5) * cell), "text": "+1 U", "t": 1.5})
		overlay_dirty = true
	for yy in range(maxi(0, cy - 2), mini(rows - 1, cy + 2) + 1):
		for xx in range(maxi(0, cx - 2), mini(cols - 1, cx + 2) + 1):
			var j := yy * cols + xx
			if vis[j] == 0:
				vis[j] = 1
				_mark(j)
	if poisons.has(i):
		var p: Dictionary = poisons[i]
		poisons.erase(i)
		_mark(i)
		if st_sup[4] == 1:
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


# ---------------------------------------------------------------- drawing

func _hp_color(h: int) -> Color:
	var lg := log(float(h)) / log(10.0)
	return Color.from_hsv(fposmod(0.33 - lg * 0.11, 1.0), 0.6, 0.92)


func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	q.append(p[0])
	return q


func _build_nodes() -> void:
	world = Node2D.new()
	add_child(world)
	bg_node = Node2D.new()
	world.add_child(bg_node)
	bg_node.draw.connect(_draw_bg)
	ccols = int(ceil(float(cols) / CHUNK))
	crows = int(ceil(float(rows) / CHUNK))
	chunk_dirty.resize(ccols * crows)
	chunk_dirty.fill(0)
	for ci in ccols * crows:
		var ch := Node2D.new()
		world.add_child(ch)
		ch.draw.connect(_draw_chunk.bind(ci))
		chunks.append(ch)
	obst_node = Node2D.new()
	world.add_child(obst_node)
	obst_node.draw.connect(_draw_obstacles)

	# Все шарики — одна MultiMesh: один вызов отрисовки на кадр.
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x + 0.5 - 16.0, y + 0.5 - 16.0).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(15.5 - d, 0.0, 1.0)))
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture = ImageTexture.create_from_image(img)
	world.add_child(mmi)

	overlay = Node2D.new()
	world.add_child(overlay)
	overlay.draw.connect(_draw_overlay)


func _mark(i: int) -> void:
	@warning_ignore("integer_division")
	var ci := (i / cols / CHUNK) * ccols + (i % cols) / CHUNK
	chunk_dirty[ci] = 1
	field_dirty = true


func _update_balls_mesh() -> void:
	var n := balls.size()
	if n != mm_count:
		# состав шариков изменился — пересобираем буфер целиком
		if n > mm_cap:
			mm_cap = maxi(32, mm_cap * 2)
			while mm_cap < n:
				mm_cap *= 2
			mm.instance_count = mm_cap
			mm_buf.resize(mm_cap * 12)
			mm_buf.fill(0.0)
		for k in n:
			var b = balls[k]
			var o: int = k * 12
			var dd: float = b.radius * 2.0
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
	# каждый кадр меняются только координаты
	for k in n:
		var b = balls[k]
		var p: Vector2 = b.pos
		mm_buf[k * 12 + 3] = p.x
		mm_buf[k * 12 + 7] = p.y
	mm.buffer = mm_buf


func _draw_bg() -> void:
	bg_node.draw_colored_polygon(map["border"], Color(0.12, 0.14, 0.19))


func _draw_obstacles() -> void:
	for o in map["obstacles"]:
		obst_node.draw_colored_polygon(o, Color(0.3, 0.33, 0.42))
		obst_node.draw_polyline(_closed(o), Color(0.62, 0.68, 0.85), 3.0)
	obst_node.draw_polyline(_closed(map["border"]), Color(0.62, 0.68, 0.85), 4.0)


func _draw_chunk(ci: int) -> void:
	var ch: Node2D = chunks[ci]
	var font := ThemeDB.fallback_font
	var fs := int(clampf(cell * 0.4, 10.0, 20.0))
	@warning_ignore("integer_division")
	var cy0 := (ci / ccols) * CHUNK
	var cx0 := (ci % ccols) * CHUNK
	for y in range(cy0, mini(rows, cy0 + CHUNK)):
		for x in range(cx0, mini(cols, cx0 + CHUNK)):
			var i := y * cols + x
			if hp[i] <= 0:
				continue
			var r := Rect2(x * cell + 1.0, y * cell + 1.0, cell - 2.0, cell - 2.0)
			if vis[i] == 0:
				ch.draw_rect(r, Color(0.2, 0.21, 0.25))
				continue
			ch.draw_rect(r, _hp_color(hp[i]))
			if poisons.has(i):
				ch.draw_rect(r.grow(-1.0), Color(0.2, 0.9, 0.2), false, 2.5)
			ch.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.35),
				GameData.fmt(hp[i]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(0, 0, 0, 0.85))


func _draw_overlay() -> void:
	var dir := Vector2.from_angle(deg_to_rad(aim_angle))
	var k := 0.0
	while k < 170.0:
		overlay.draw_line(start_pos + dir * k, start_pos + dir * minf(k + 10.0, 170.0), Color(1, 1, 1, 0.6), 3.0)
		k += 20.0
	overlay.draw_circle(start_pos, 9.0, Color(1.0, 0.85, 0.2))
	var font := ThemeDB.fallback_font
	for p in popups:
		overlay.draw_string(font, p["pos"] - Vector2(40, 0), p["text"], HORIZONTAL_ALIGNMENT_CENTER, 80, 26,
			Color(1.0, 0.85, 0.2, clampf(p["t"], 0.0, 1.0)))


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_aim_at(event.position)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_aim_at(event.position)


func _aim_at(screen_pos: Vector2) -> void:
	var p := world.to_local(screen_pos)
	if not Rect2(Vector2.ZERO, WORLD).has_point(p):
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


# ---------------------------------------------------------------- actions

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


## Раз в 30 с: шарик этого типа, заработавший меньше всех, возвращается на старт по прицелу.
func _reset_stuck(t: String) -> void:
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


func _to_menu() -> void:
	_save_state()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ---------------------------------------------------------------- UI

func _button(text: String, h: float = 52.0) -> Button:
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


func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = GameData.make_theme()
	cl.add_child(ui_root)

	# Верхняя панель
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	top.offset_bottom = TOP_H
	ui_root.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	var r1 := HBoxContainer.new()
	tv.add_child(r1)
	var bmenu := _button("Меню", 48)
	bmenu.pressed.connect(_to_menu)
	r1.add_child(bmenu)
	lbl_map = Label.new()
	lbl_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_map.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_map.text = map["name"]
	r1.add_child(lbl_map)
	btn_snap = _button("", 48)
	btn_snap.pressed.connect(_cycle_snap)
	r1.add_child(btn_snap)
	var r2 := HBoxContainer.new()
	tv.add_child(r2)
	lbl_rub = Label.new()
	lbl_u = Label.new()
	lbl_prog = Label.new()
	for l in [lbl_rub, lbl_u, lbl_prog]:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r2.add_child(l)

	# Нижняя панель: магазин и прокачка
	var bottom := PanelContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_top = -BOTTOM_H
	ui_root.add_child(bottom)
	var tabs := TabContainer.new()
	bottom.add_child(tabs)
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
	tabs.set_tab_title(1, "Прокачка (U)")

	_rebuild_rows()


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
	for c in shop_box.get_children():
		c.queue_free()
	for c in perk_box.get_children():
		c.queue_free()
	shop_refs.clear()
	perk_refs.clear()

	for t in GameData.TYPE_ORDER:
		var def: Dictionary = GameData.TYPES[t]

		# --- магазин за рубли
		var box := VBoxContainer.new()
		shop_box.add_child(box)
		var head := HBoxContainer.new()
		box.add_child(head)
		var sw := ColorRect.new()
		sw.color = def["color"]
		sw.custom_minimum_size = Vector2(22, 22)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(sw)
		var name_l := Label.new()
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(name_l)
		if GameData.unlocked[t]:
			var reset := _button("Сброс", 44)
			reset.pressed.connect(_reset_stuck.bind(t))
			head.add_child(reset)
			var row := HBoxContainer.new()
			box.add_child(row)
			shop_refs[t] = {
				"name": name_l, "reset": reset,
				"buy": _col(row, "Купить шар", _buy_ball.bind(t)),
				"dmg": _col(row, "Урон", _buy_dmg.bind(t)),
				"spd": _col(row, "Скорость", _buy_spd.bind(t)),
			}
		else:
			name_l.text = "%s — закрыт (вкладка «Прокачка»)" % def["name"]
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
	lbl_u.text = "U: %d" % GameData.u
	lbl_prog.text = "Разбито %d%%" % int(100.0 * (total - alive) / maxi(1, total))
	btn_snap.text = ["Угол: любой", "Угол: 45°", "Угол: 90°"][snap_mode]

	for t in shop_refs:
		var r: Dictionary = shop_refs[t]
		r["name"].text = "%s ×%d" % [GameData.TYPES[t]["name"], counts[t]]
		var cd: float = reset_cd[t]
		r["reset"].text = "Сброс" if cd <= 0.0 else "%d с" % int(ceil(cd))
		r["reset"].disabled = cd > 0.0 or int(counts[t]) == 0
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


func _damage_of_next(t: String) -> int:
	dmg_lvl[t] += 1
	var d := _damage_of(t)
	dmg_lvl[t] -= 1
	return d

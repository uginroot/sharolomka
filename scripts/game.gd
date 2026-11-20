extends Node2D
## Игровая карта. Мир хранится кусками 32×32 клетки и создаётся по мере открытия,
## поэтому карта может быть размером хоть 10000×10000.

const Maps = preload("res://scripts/maps.gd")
const BallScript = preload("res://scripts/ball.gd")
const ChunkScript = preload("res://scripts/chunk.gd")

const CELL := 40.0               # клетка в мировых единицах
const INV := 1.0 / 40.0
const CS := 32                   # клеток в куске по стороне
const CPX := 1280.0              # CS * CELL
const START_CLEAR := 2.3         # радиус пустой площадки у старта, клеток
const RESET_CD := 30.0
const SPD_MAX := 10
const MAX_OFFLINE := 86400.0     # перематываем не больше суток
const WARP_BUDGET_US := 9000     # сколько микросекунд за кадр можно тратить на перемотку
const PREGEN_LIMIT := 60000      # карты меньше этого генерируем целиком (можно пройти на 100%)
const FOG := Color(0.07, 0.08, 0.11)
const FLOOR := Color(0.13, 0.15, 0.2)
const WALL_FACE := Color(0.9, 0.92, 0.96)
const WALL_LIGHT := Color(1, 1, 1)
const WALL_DARK := Color(0.6, 0.64, 0.74)
const WALL_SEAM := Color(0.8, 0.83, 0.9)

# ---- карта
var map: Dictionary
var map_index := 0
var W := 0
var H := 0
var cw := 0
var chh := 0
var wpx := 0.0
var hpx := 0.0
var chunks: Array = []
var region_cache := {}
var region_size := 64
var templates := {}
var seed_i := 0
var start_cell := Vector2i.ZERO
var start_pos := Vector2.ZERO
var hb := 1.0
var hg := 0.1
var track_all := false
var alive := 0
var total := 0
var destroyed := 0
var goal := 0
var goal_done := false
var ex0 := 0
var ey0 := 0
var ex1 := 0
var ey1 := 0

# ---- шарики и эффекты
var balls: Array = []
var poisons := {}
var popups: Array = []
var colors := {}
var t_idx := {}
var st_dmg := PackedInt32Array()
var st_lvl := PackedInt32Array()
var st_sup := PackedByteArray()

# ---- экономика карты
var rubles := 0
var counts := {}
var dmg_lvl := {}
var spd_lvl := {}
var reset_cd := {}

# ---- время
var catchup := 0.0
var warping := false
var paused_at := 0.0
var time_acc := 0.0
var save_t := 0.0
var ui_t := 0.0
var limits_t := 0.0

# ---- состояние
var aim_angle := -90.0
var snap_mode := 0
var selected := "basic"
var overlay_dirty := true
var completed := false

# ---- отрисовка
var field_root: Node2D
var overlay: Node2D
var dirty := {}
var lod := 0                     # 0 — с цифрами, 1 — «свет», 2 — грубо, по текстуре на кусок
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
var warp_label: Label
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
	templates = Maps.templates()
	aim_angle = float(map["aim"])
	for ti in GameData.TYPE_ORDER.size():
		var t: String = GameData.TYPE_ORDER[ti]
		t_idx[t] = ti
		counts[t] = 0
		dmg_lvl[t] = 0
		spd_lvl[t] = 0
		reset_cd[t] = 0.0
		colors[t] = GameData.TYPES[t]["color"]
	st_dmg.resize(GameData.TYPE_ORDER.size())
	st_lvl.resize(GameData.TYPE_ORDER.size())
	st_sup.resize(GameData.TYPE_ORDER.size())
	dot_tex = _circle_texture(32, Color.WHITE)

	W = int(map["w"])
	H = int(map["h"])
	cw = (W + CS - 1) / CS
	chh = (H + CS - 1) / CS
	wpx = W * CELL
	hpx = H * CELL
	chunks.resize(cw * chh)
	seed_i = hash(String(map["id"]))
	start_cell = map["start"]
	start_pos = (Vector2(start_cell) + Vector2(0.5, 0.5)) * CELL
	hb = float(map["hp_base"])
	hg = float(map["hp_growth"])
	region_size = int(map.get("region", maxi(W, H)))
	track_all = W * H <= PREGEN_LIMIT
	ex0 = start_cell.x
	ex1 = start_cell.x
	ey0 = start_cell.y
	ey1 = start_cell.y

	field_root = Node2D.new()
	add_child(field_root)
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

	var saved_at := _load_state()
	if saved_at <= 0.0:
		counts["basic"] = 1
	if track_all:
		alive = 0
		total = 0
		for ck in chunks.size():
			var c = _get_chunk(ck)
			for li in CS * CS:
				if c.kind[li] == 1:
					alive += 1
		total = alive + destroyed
	goal = total if int(map["goal"]) == 0 else int(map["goal"])
	# площадка у старта открыта
	for y in range(start_cell.y - 3, start_cell.y + 4):
		for x in range(start_cell.x - 3, start_cell.x + 4):
			if _kind_at(x, y) == 0:
				_reveal(x, y)

	_recalc_stats()
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
		_start_catchup(Time.get_unix_time_from_system() - saved_at)


# ================================================================ генерация мира

func _hash3(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


func _get_chunk(ck: int):
	var c = chunks[ck]
	if c == null:
		c = _gen_chunk(ck, [])
		chunks[ck] = c
	return c


func _gen_chunk(ck: int, blob: Array):
	var c = ChunkScript.new()
	c.hp.resize(CS * CS)
	c.kind.resize(CS * CS)
	c.vis.resize(CS * CS)
	c.hp.fill(0)
	c.kind.fill(0)
	c.vis.fill(0)
	var cx0 := (ck % cw) * CS
	@warning_ignore("integer_division")
	var cy0 := (ck / cw) * CS
	var sc2 := START_CLEAR * START_CLEAR
	var solid := 0
	for ly in CS:
		var y := cy0 + ly
		for lx in CS:
			var x := cx0 + lx
			var li := (ly << 5) | lx
			if x >= W or y >= H:
				c.kind[li] = 3
				continue
			var m := _mask_at(x, y)
			if m == 2:
				c.kind[li] = 2
				solid += 1
				continue
			var dx := float(x - start_cell.x)
			var dy := float(y - start_cell.y)
			var d2 := dx * dx + dy * dy
			if d2 < sc2:
				continue
			c.kind[li] = 1
			c.hp[li] = int(ceil(hb * pow(1.0 + sqrt(d2) * hg, 1.6)))
			solid += 1
	if not blob.is_empty():
		var raw: PackedByteArray = (blob[0] as PackedByteArray).decompress(int(blob[1]), FileAccess.COMPRESSION_ZSTD)
		c.hp = raw.slice(0, CS * CS * 4).to_int32_array()
		c.vis = raw.slice(CS * CS * 4, CS * CS * 5)
		for li in CS * CS:
			if c.kind[li] == 1 and c.hp[li] <= 0:
				c.kind[li] = 0
				solid -= 1
		c.changed = true
		c.blob = blob
		c.blob_dirty = false
	c.solid = solid
	return c


## 0 — ничего, 2 — стена, 4 — полость внутри картинки.
func _mask_at(x: int, y: int) -> int:
	@warning_ignore("integer_division")
	var reg = _region(x / region_size, y / region_size)
	if reg == null:
		return 0
	var lx: int = x - reg["x0"]
	var ly: int = y - reg["y0"]
	if lx < 0 or ly < 0 or lx >= reg["w"] or ly >= reg["h"]:
		return 0
	return reg["mask"][ly * reg["w"] + lx]


func _region(rx: int, ry: int):
	var key := ry * 1000003 + rx
	if region_cache.has(key):
		return region_cache[key]
	var res = null
	if map.has("fixed"):
		if rx == 0 and ry == 0:
			res = _build_picture(map["fixed"], Rect2i(0, 0, W, H))
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = _hash3(rx, ry, seed_i)
		var x0 := rx * region_size
		var y0 := ry * region_size
		var has_start := Rect2i(x0 - 3, y0 - 3, region_size + 6, region_size + 6).has_point(start_cell)
		if rng.randf() < float(map["density"]) and not has_start:
			var tl: Array = map["templates"]
			var tpl: String = tl[rng.randi() % tl.size()]
			var span := region_size - 6
			var size := maxi(12, int(span * rng.randf_range(0.5, 1.0)))
			var px := x0 + 3 + rng.randi_range(0, span - size)
			var py := y0 + 3 + rng.randi_range(0, span - size)
			res = _build_picture([[tpl, Rect2i(px, py, size, size)]], Rect2i(px - 1, py - 1, size + 2, size + 2))
	region_cache[key] = res
	return res


## Растеризует картинки в маску: контур — стена, внутри — полость, со стороны старта — вход.
## Закутки, куда шарик не долетит, заливаются стеной.
func _build_picture(items: Array, box: Rect2i) -> Dictionary:
	var bw := box.size.x
	var bh := box.size.y
	var mask := PackedByteArray()
	mask.resize(bw * bh)
	mask.fill(0)
	var polys: Array = []
	for it in items:
		var r: Rect2i = it[1]
		for p in templates[it[0]]:
			var q := PackedVector2Array()
			for v in p:
				q.append(Vector2(r.position - box.position) + v * Vector2(r.size))
			polys.append(q)
	var outlines: Array = []
	for q in polys:
		var cells := _raster_local(q, bw, bh)
		for i in cells:
			mask[i] = 2
		outlines.append(cells)
	var st := Vector2(start_cell - box.position) + Vector2(0.5, 0.5)
	for pi in polys.size():
		var q: PackedVector2Array = polys[pi]
		var cav := PackedInt32Array()
		for i in bw * bh:
			@warning_ignore("integer_division")
			if mask[i] != 2 and Geometry2D.is_point_in_polygon(Vector2(i % bw + 0.5, i / bw + 0.5), q):
				cav.append(i)
				mask[i] = 4
		_entrance_local(mask, bw, bh, outlines[pi], cav, st)
	# заливка от краёв: всё недостижимое — стена
	var reach := PackedByteArray()
	reach.resize(bw * bh)
	reach.fill(0)
	var stack := PackedInt32Array()
	for x in bw:
		for y in [0, bh - 1]:
			var i: int = y * bw + x
			if mask[i] != 2 and reach[i] == 0:
				reach[i] = 1
				stack.append(i)
	for y in bh:
		for x in [0, bw - 1]:
			var i: int = y * bw + x
			if mask[i] != 2 and reach[i] == 0:
				reach[i] = 1
				stack.append(i)
	if box.has_point(start_cell):
		var si := (start_cell.y - box.position.y) * bw + start_cell.x - box.position.x
		if mask[si] != 2 and reach[si] == 0:
			reach[si] = 1
			stack.append(si)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var cx := i % bw
		@warning_ignore("integer_division")
		var cy := i / bw
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx: int = cx + o.x
			var yy: int = cy + o.y
			if xx < 0 or yy < 0 or xx >= bw or yy >= bh:
				continue
			var j: int = yy * bw + xx
			if reach[j] == 0 and mask[j] != 2:
				reach[j] = 1
				stack.append(j)
	for i in bw * bh:
		if reach[i] == 0 and mask[i] != 2:
			mask[i] = 2
	return {"x0": box.position.x, "y0": box.position.y, "w": bw, "h": bh, "mask": mask}


func _raster_local(poly: PackedVector2Array, bw: int, bh: int) -> PackedInt32Array:
	var mark := {}
	for e in poly.size():
		var a := poly[e]
		var b := poly[(e + 1) % poly.size()]
		var steps := int(ceil(a.distance_to(b) / 0.2)) + 1
		var px := -1
		var py := -1
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			var cx := clampi(int(p.x), 0, bw - 1)
			var cy := clampi(int(p.y), 0, bh - 1)
			if cx == px and cy == py:
				continue
			if px >= 0 and cx != px and cy != py:
				mark[py * bw + cx] = true
			mark[cy * bw + cx] = true
			px = cx
			py = cy
	return PackedInt32Array(mark.keys())


func _entrance_local(mask: PackedByteArray, bw: int, bh: int, outline: PackedInt32Array,
		cav: PackedInt32Array, st: Vector2) -> void:
	if cav.is_empty():
		return
	# основная полость — самая большая связная часть
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
			var cx := i % bw
			@warning_ignore("integer_division")
			var cy := i / bw
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var xx: int = cx + o.x
				var yy: int = cy + o.y
				if xx < 0 or yy < 0 or xx >= bw or yy >= bh:
					continue
				var j: int = yy * bw + xx
				if in_cav.has(j) and not seen.has(j):
					seen[j] = true
					stack.append(j)
		if comp.size() > main.size():
			main = comp
	if main.size() < 2:
		return
	# стена, ближайшая к старту
	var best := -1
	var bd := INF
	for i in outline:
		if mask[i] != 2:
			continue
		@warning_ignore("integer_division")
		var d := Vector2(i % bw + 0.5, i / bw + 0.5).distance_squared_to(st)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return
	@warning_ignore("integer_division")
	var p := Vector2(best % bw + 0.5, best / bw + 0.5)
	var target := p
	bd = INF
	for i in main:
		@warning_ignore("integer_division")
		var c := Vector2(i % bw + 0.5, i / bw + 0.5)
		var d := c.distance_squared_to(p)
		if d < bd:
			bd = d
			target = c
	var dir := (target - p).normalized()
	var dist := p.distance_to(target)
	var s := 0.0
	while s <= dist + 1.0:
		var q := p + dir * s
		s += 0.5
		var cx := int(q.x)
		var cy := int(q.y)
		if cx < 0 or cy < 0 or cx >= bw or cy >= bh or main.has(cy * bw + cx):
			break
		for yy in range(maxi(0, cy - 1), mini(bh - 1, cy + 1) + 1):
			for xx in range(maxi(0, cx - 1), mini(bw - 1, cx + 1) + 1):
				if mask[yy * bw + xx] == 2:
					mask[yy * bw + xx] = 4


func _kind_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return 3
	var c = chunks[(x >> 5) + (y >> 5) * cw]
	if c == null:
		c = _get_chunk((x >> 5) + (y >> 5) * cw)
	return c.kind[((y & 31) << 5) | (x & 31)]


func _vis_at(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= W or y >= H:
		return false
	var c = chunks[(x >> 5) + (y >> 5) * cw]
	return c != null and c.vis[((y & 31) << 5) | (x & 31)] == 1


## Открывает клетку и её соседей (туман: виден только первый слой у пустоты).
func _reveal(x: int, y: int) -> void:
	for yy in range(y - 1, y + 2):
		if yy < 0 or yy >= H:
			continue
		for xx in range(x - 1, x + 2):
			if xx < 0 or xx >= W:
				continue
			var ck := (xx >> 5) + (yy >> 5) * cw
			var c = _get_chunk(ck)
			var li := ((yy & 31) << 5) | (xx & 31)
			if c.vis[li] == 0:
				c.vis[li] = 1
				c.changed = true
				c.blob_dirty = true
				_ensure_node(ck)
				_mark(ck)
				ex0 = mini(ex0, xx)
				ex1 = maxi(ex1, xx)
				ey0 = mini(ey0, yy)
				ey1 = maxi(ey1, yy)


# ================================================================ сохранение

func _save_path() -> String:
	return "user://map_%s.bin" % String(map["id"])


func _load_state() -> float:
	var id := String(map["id"])
	if not GameData.map_states.has(id) or not FileAccess.file_exists(_save_path()):
		return 0.0
	var f := FileAccess.open(_save_path(), FileAccess.READ)
	if f == null:
		return 0.0
	var s = f.get_var()
	if typeof(s) != TYPE_DICTIONARY or int(s.get("ver", 0)) != 3 or int(s.get("w", 0)) != W:
		return 0.0
	rubles = int(s.get("rubles", 0))
	destroyed = int(s.get("destroyed", 0))
	goal_done = bool(s.get("goal_done", false))
	var c: Dictionary = s.get("counts", {})
	var dl: Dictionary = s.get("dmg", {})
	var sl: Dictionary = s.get("spd", {})
	for t in GameData.TYPE_ORDER:
		counts[t] = int(c.get(t, 0))
		dmg_lvl[t] = int(dl.get(t, 0))
		spd_lvl[t] = int(sl.get(t, 0))
	if int(counts["basic"]) == 0:
		counts["basic"] = 1
	var ch: Dictionary = s.get("chunks", {})
	for ck in ch:
		var cc = _gen_chunk(int(ck), ch[ck])
		chunks[int(ck)] = cc
		for li in CS * CS:
			if cc.vis[li] == 1:
				var x := (int(ck) % cw) * CS + (li & 31)
				@warning_ignore("integer_division")
				var y := (int(ck) / cw) * CS + (li >> 5)
				ex0 = mini(ex0, x)
				ex1 = maxi(ex1, x)
				ey0 = mini(ey0, y)
				ey1 = maxi(ey1, y)
	return float(s.get("saved_at", 0.0))


func _save_state() -> void:
	if completed:
		return
	var out := {}
	for ck in chunks.size():
		var c = chunks[ck]
		if c == null or not c.changed:
			continue
		if c.blob_dirty:
			var raw: PackedByteArray = c.hp.to_byte_array()
			raw.append_array(c.vis)
			c.blob = [raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size()]
			c.blob_dirty = false
		out[ck] = c.blob
	var s := {
		"ver": 3, "w": W, "rubles": rubles, "destroyed": destroyed, "goal_done": goal_done,
		"counts": counts.duplicate(), "dmg": dmg_lvl.duplicate(), "spd": spd_lvl.duplicate(),
		"saved_at": Time.get_unix_time_from_system(), "chunks": out,
	}
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_var(s)
		f.close()
	GameData.map_states[String(map["id"])] = {"saved": true}
	GameData.save_game()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			paused_at = Time.get_unix_time_from_system()
			_save_state()
		NOTIFICATION_APPLICATION_RESUMED:
			if paused_at > 0.0:
				_start_catchup(Time.get_unix_time_from_system() - paused_at)
				paused_at = 0.0
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_save_state()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if upg != null and upg.visible:
				_show_upgrades(false)
			else:
				_to_menu()


## Пропущенное время проигрывается настоящей физикой в ускоренной перемотке.
func _start_catchup(sec: float) -> void:
	if sec < 2.0 or completed:
		return
	catchup = minf(catchup + sec, MAX_OFFLINE)


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
		st_lvl[ti] = int(GameData.perks[t])
		st_sup[ti] = 1 if GameData.supers[t] else 0


func _ball_cost(t: String) -> int:
	return int(round(float(GameData.TYPES[t]["ball_cost"]) * pow(1.35, int(counts[t]))))


func _dmg_cost(t: String) -> int:
	return int(round(float(GameData.TYPES[t]["dmg_cost"]) * pow(1.55, int(dmg_lvl[t]))))


func _spd_cost(t: String) -> int:
	return int(round(float(GameData.TYPES[t]["spd_cost"]) * pow(1.6, int(spd_lvl[t]))))


# ================================================================ симуляция

func _spawn_ball(t: String, ang: float) -> void:
	var b = BallScript.new()
	b.type = t
	b.ti = t_idx[t]
	b.radius = float(GameData.TYPES[t]["radius"])
	b.pos = start_pos
	b.vel = Vector2.from_angle(deg_to_rad(ang)) * _speed(t)
	balls.append(b)


func _sim(dt: float) -> void:
	time_acc += dt
	for b in balls:
		_move_ball(b, dt)
	if not poisons.is_empty():
		_tick_poison(dt)
	for t in reset_cd:
		if reset_cd[t] > 0.0:
			reset_cd[t] = maxf(0.0, reset_cd[t] - dt)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_sim(delta)

	# перемотка пропущенного времени — в пределах бюджета на кадр
	if catchup > 0.0:
		warping = true
		var t0 := Time.get_ticks_usec()
		while catchup > 0.0 and Time.get_ticks_usec() - t0 < WARP_BUDGET_US:
			var s := minf(1.0 / 30.0, catchup)
			_sim(s)
			catchup -= s
		if catchup <= 0.0:
			catchup = 0.0
			warping = false
			GameData.save_game()

	if not popups.is_empty():
		for p in popups:
			p["t"] -= delta
			p["pos"].y -= 30.0 * delta / zoom
		popups = popups.filter(func(p): return p["t"] > 0.0)
		overlay_dirty = true

	_redraw_dirty()
	if overlay_dirty:
		overlay_dirty = false
		overlay.queue_redraw()
	_update_balls_mesh()

	if toast_t > 0.0:
		toast_t -= delta
		toast.modulate.a = clampf(toast_t, 0.0, 1.0)
		if toast_t <= 0.0:
			toast.visible = false
	limits_t -= delta
	if limits_t <= 0.0 and cam_ready:
		limits_t = 1.0
		_update_zoom_limits()
		_clamp_cam()
	ui_t -= delta
	if ui_t <= 0.0:
		ui_t = 0.25
		_refresh_ui()
	save_t += delta
	if save_t > 20.0 and not warping:
		save_t = 0.0
		_save_state()
	_check_goal()


## Непрерывные столкновения: шарик летит сразу до ближайшего препятствия,
## а внутри пустого куска — до его края за один шаг.
func _move_ball(b, delta: float) -> void:
	var p: Vector2 = b.pos
	var speed: float = b.vel.length()
	if speed <= 0.0:
		return
	var d: Vector2 = b.vel / speed
	var dist := speed * delta
	var r: float = b.radius
	var wx0 := r
	var wy0 := r
	var wx1 := wpx - r
	var wy1 := hpx - r
	var sniper: bool = b.ti == 2
	var pierce: bool = b.ti == 3
	var iter := 0
	var stalls := 0
	while dist > 0.0001 and iter < 24:
		iter += 1
		var step := minf(dist, CELL)
		var gx := int(p.x * INV)
		var gy := int(p.y * INV)
		var c0 = chunks[(gx >> 5) + (gy >> 5) * cw]
		var skip := false
		if c0 != null and c0.solid == 0:
			var bx0 := float((gx >> 5) << 5) * CELL + r
			var by0 := float((gy >> 5) << 5) * CELL + r
			var bx1 := bx0 + CPX - 2.0 * r
			var by1 := by0 + CPX - 2.0 * r
			var te := INF
			if d.x > 0.0:
				te = (bx1 - p.x) / d.x
			elif d.x < 0.0:
				te = (bx0 - p.x) / d.x
			if d.y > 0.0:
				te = minf(te, (by1 - p.y) / d.y)
			elif d.y < 0.0:
				te = minf(te, (by0 - p.y) / d.y)
			if te > 1.0:
				step = minf(dist, te)
				skip = true
		var best := step
		var bnx := 0.0
		var bny := 0.0
		var hit := -1
		if not skip:
			var ex := p.x + d.x * step
			var ey := p.y + d.y * step
			var x0 := maxi(0, int((minf(p.x, ex) - r) * INV))
			var x1 := mini(W - 1, int((maxf(p.x, ex) + r) * INV))
			var y0 := maxi(0, int((minf(p.y, ey) - r) * INV))
			var y1 := mini(H - 1, int((maxf(p.y, ey) + r) * INV))
			for cy in range(y0, y1 + 1):
				for cx in range(x0, x1 + 1):
					var cc = chunks[(cx >> 5) + (cy >> 5) * cw]
					if cc == null:
						cc = _get_chunk((cx >> 5) + (cy >> 5) * cw)
					var k: int = cc.kind[((cy & 31) << 5) | (cx & 31)]
					if k == 0 or k == 3:
						continue
					var id := cy * W + cx
					if pierce and b.recent.has(id) and time_acc - float(b.recent[id]) < 0.3:
						continue
					# пересечение луча с клеткой, расширенной на радиус шарика
					var lx := cx * CELL - r
					var hx := lx + CELL + 2.0 * r
					var ly := cy * CELL - r
					var hy := ly + CELL + 2.0 * r
					var tx0: float
					var tx1: float
					var ty0: float
					var ty1: float
					if d.x != 0.0:
						tx0 = (lx - p.x) / d.x
						tx1 = (hx - p.x) / d.x
						if tx0 > tx1:
							var tmp := tx0
							tx0 = tx1
							tx1 = tmp
					elif p.x <= lx or p.x >= hx:
						continue
					else:
						tx0 = -INF
						tx1 = INF
					if d.y != 0.0:
						ty0 = (ly - p.y) / d.y
						ty1 = (hy - p.y) / d.y
						if ty0 > ty1:
							var tmp := ty0
							ty0 = ty1
							ty1 = tmp
					elif p.y <= ly or p.y >= hy:
						continue
					else:
						ty0 = -INF
						ty1 = INF
					var tn := maxf(tx0, ty0)
					var tf := minf(tx1, ty1)
					if tn > tf or tf <= 0.0 or tn >= best:
						continue
					var nx := 0.0
					var ny := 0.0
					if tx0 > ty0 + 0.001:
						nx = -signf(d.x)
					elif ty0 > tx0 + 0.001:
						ny = -signf(d.y)
					else:
						nx = -signf(d.x)
						ny = -signf(d.y)
					if tn < 0.0:
						# уже внутри — сталкиваемся, только если движемся внутрь
						if d.x * nx + d.y * ny >= 0.0:
							continue
						tn = 0.0
					best = tn
					bnx = nx
					bny = ny
					hit = id if k == 1 else -3
		# края мира
		if d.x < 0.0 and (wx0 - p.x) / d.x < best:
			best = maxf(0.0, (wx0 - p.x) / d.x)
			bnx = 1.0
			bny = 0.0
			hit = -2
		elif d.x > 0.0 and (wx1 - p.x) / d.x < best:
			best = maxf(0.0, (wx1 - p.x) / d.x)
			bnx = -1.0
			bny = 0.0
			hit = -2
		if d.y < 0.0 and (wy0 - p.y) / d.y < best:
			best = maxf(0.0, (wy0 - p.y) / d.y)
			bnx = 0.0
			bny = 1.0
			hit = -2
		elif d.y > 0.0 and (wy1 - p.y) / d.y < best:
			best = maxf(0.0, (wy1 - p.y) / d.y)
			bnx = 0.0
			bny = -1.0
			hit = -2
		p += d * best
		dist -= best
		if hit == -1:
			continue
		# защита от зацикливания в одной точке (угол, зажатый шарик)
		if best < 0.001:
			stalls += 1
			if stalls > 3:
				break
		else:
			stalls = 0
		if hit >= 0:
			b.pos = p
			b.vel = d * speed
			if _hit_cell(b, hit):
				continue   # пробойник пролетел насквозь
		if bnx != 0.0:
			d.x = -d.x
		if bny != 0.0:
			d.y = -d.y
		p += Vector2(bnx, bny) * 0.02
		if sniper and (hit >= 0 or st_sup[2] == 1) and time_acc - b.seek_t > 0.15:
			b.seek_t = time_acc
			b.pos = p
			b.vel = d * speed
			_try_seek(b, Vector2(bnx, bny), hit)
			d = b.vel.normalized()
	b.pos = p
	b.vel = d * speed
	if b.recent.size() > 40:
		b.recent.clear()


## Возвращает true, если шарик пролетает сквозь квадрат.
func _hit_cell(b, id: int) -> bool:
	var ti: int = b.ti
	var dmg := st_dmg[ti]
	var lvl := st_lvl[ti]
	var sup := st_sup[ti] == 1
	match ti:
		0:
			if randf() < 0.06 * lvl:
				dmg *= 5 if sup else 2
			_damage(id, dmg, b)
		1:
			_damage(id, dmg, b)
			var sd := maxi(1, int(round(dmg * (0.3 + 0.14 * lvl))))
			var rad := 2 if sup else 1
			var cx := id % W
			@warning_ignore("integer_division")
			var cy := id / W
			for yy in range(maxi(0, cy - rad), mini(H - 1, cy + rad) + 1):
				for xx in range(maxi(0, cx - rad), mini(W - 1, cx + rad) + 1):
					if xx != cx or yy != cy:
						_damage(yy * W + xx, sd, b)
		3:
			var before := _hp_of(id)
			_damage(id, dmg, b)
			if sup or dmg >= before:
				b.recent[id] = time_acc
				return true
		4:
			_damage(id, dmg, b)
			if _hp_of(id) > 0:
				_apply_poison(id, dmg * 0.6, 3.0 + lvl, b)
		_:
			_damage(id, dmg, b)
	return false


func _hp_of(id: int) -> int:
	var x := id % W
	@warning_ignore("integer_division")
	var y := id / W
	var c = chunks[(x >> 5) + (y >> 5) * cw]
	if c == null:
		return 0
	var li := ((y & 31) << 5) | (x & 31)
	return c.hp[li] if c.kind[li] == 1 else 0


func _try_seek(b, n: Vector2, exclude: int) -> void:
	if randf() >= 0.4 + 0.12 * st_lvl[2]:
		return
	var cx := int(b.pos.x * INV)
	var cy := int(b.pos.y * INV)
	for r in range(1, 12):
		var best := -1
		var bd := INF
		for yy in range(cy - r, cy + r + 1):
			var edge_row := (yy == cy - r or yy == cy + r)
			var xs: Array = range(cx - r, cx + r + 1) if edge_row else [cx - r, cx + r]
			for xx in xs:
				if not _vis_at(xx, yy) or _kind_at(xx, yy) != 1:
					continue
				var j: int = yy * W + xx
				if j == exclude:
					continue
				var dir: Vector2 = (Vector2(xx, yy) + Vector2(0.5, 0.5)) * CELL - b.pos
				if dir.dot(n) <= 0.0:
					continue
				var dd := dir.length_squared()
				if dd < bd:
					bd = dd
					best = j
		if best >= 0:
			@warning_ignore("integer_division")
			var tc := (Vector2(best % W, best / W) + Vector2(0.5, 0.5)) * CELL
			b.vel = (tc - b.pos).normalized() * b.vel.length()
			return


func _damage(id: int, amount: int, b) -> void:
	var x := id % W
	@warning_ignore("integer_division")
	var y := id / W
	var ck := (x >> 5) + (y >> 5) * cw
	var c = chunks[ck]
	if c == null:
		return
	var li := ((y & 31) << 5) | (x & 31)
	if c.kind[li] != 1:
		return
	var h: int = c.hp[li]
	var dealt := mini(amount, h)
	c.hp[li] = h - dealt
	c.changed = true
	c.blob_dirty = true
	rubles += dealt
	if b != null:
		b.earned += dealt
	_mark(ck)
	if h - dealt <= 0:
		c.kind[li] = 0
		c.solid -= 1
		destroyed += 1
		alive -= 1
		_on_destroyed(x, y, id)


func _on_destroyed(x: int, y: int, id: int) -> void:
	_reveal(x, y)
	# U-баллы спрятаны в части квадратов (в полостях картинок — чаще)
	var rate := 250 * (3 if _mask_at(x, y) == 4 else 1)
	if _hash3(x, y, seed_i + 7) % 10000 < rate:
		GameData.u += 1
		if not warping:
			GameData.save_game()
			popups.append({"pos": (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL, "text": "+1 U", "t": 1.5})
			overlay_dirty = true
	if poisons.has(id):
		var p: Dictionary = poisons[id]
		poisons.erase(id)
		if st_sup[4] == 1:
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var j: int = (y + o.y) * W + x + o.x
				if x + o.x >= 0 and x + o.x < W and y + o.y >= 0 and y + o.y < H and _hp_of(j) > 0:
					_apply_poison(j, p["dps"], p["dur"], p["ball"])


func _apply_poison(id: int, dps: float, dur: float, b) -> void:
	var old := 0.0
	if poisons.has(id):
		old = poisons[id]["dps"]
	poisons[id] = {"dps": maxf(dps, old), "t": dur, "dur": dur, "acc": 0.0, "ball": b}
	_mark_cell(id)


func _tick_poison(dt: float) -> void:
	for id in poisons.keys():
		if not poisons.has(id):
			continue
		var p: Dictionary = poisons[id]
		p["t"] -= dt
		p["acc"] += p["dps"] * dt
		if p["acc"] >= 1.0:
			var d := int(p["acc"])
			p["acc"] -= d
			_damage(id, d, p["ball"])
		if poisons.has(id) and (p["t"] <= 0.0 or _hp_of(id) <= 0):
			poisons.erase(id)
			_mark_cell(id)


func _check_goal() -> void:
	if not goal_done and destroyed >= goal:
		goal_done = true
		var id := String(map["id"])
		var reward := 2 if GameData.maps_done.has(id) else 5
		GameData.u += reward
		GameData.maps_done[id] = true
		GameData.maps_unlocked = maxi(GameData.maps_unlocked, map_index + 2)
		GameData.save_game()
		if not (track_all and alive <= 0):
			_show_toast("Цель карты выполнена!\n+%d U, открыта следующая карта" % reward)
	if track_all and alive <= 0 and not completed:
		completed = true
		GameData.map_states.erase(String(map["id"]))
		DirAccess.remove_absolute(_save_path())
		GameData.save_game()
		var d := AcceptDialog.new()
		d.title = "Победа!"
		d.dialog_text = "Карта «%s» разбита полностью!" % map["name"]
		d.ok_button_text = "В меню"
		ui_root.add_child(d)
		d.confirmed.connect(_to_menu)
		d.canceled.connect(_to_menu)
		d.popup_centered()


# ================================================================ отрисовка

func _ensure_node(ck: int) -> void:
	var c = chunks[ck]
	if c.node != null:
		return
	var n := Node2D.new()
	@warning_ignore("integer_division")
	n.position = Vector2((ck % cw) * CPX, (ck / cw) * CPX)
	n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	field_root.add_child(n)
	n.draw.connect(_draw_chunk.bind(ck))
	c.node = n


func _mark(ck: int) -> void:
	if chunks[ck].node != null:
		dirty[ck] = true
		chunks[ck].tex_dirty = true


func _mark_cell(id: int) -> void:
	var x := id % W
	@warning_ignore("integer_division")
	var y := id / W
	_mark((x >> 5) + (y >> 5) * cw)


func _mark_all() -> void:
	for ck in chunks.size():
		if chunks[ck] != null and chunks[ck].node != null:
			dirty[ck] = true


## Перерисовываем только изменившиеся куски, которые видны на экране, и не больше 12 за кадр.
func _redraw_dirty() -> void:
	if dirty.is_empty():
		return
	var view := _view_rect().grow(CPX * 0.5)
	var done := 0
	for ck in dirty.keys():
		@warning_ignore("integer_division")
		var r := Rect2((ck % cw) * CPX, (ck / cw) * CPX, CPX, CPX)
		if r.intersects(view):
			dirty.erase(ck)
			chunks[ck].node.queue_redraw()
			done += 1
			if done >= 12:
				break


func _circle_texture(sz: int, col: Color) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var h := sz * 0.5
	for y in sz:
		for x in sz:
			var d := Vector2(x + 0.5 - h, y + 0.5 - h).length()
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(h - 0.5 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


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
		var min_d := 7.0 / zoom
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
	var lg := log(float(maxi(h, 1))) / log(10.0)
	return Color.from_hsv(fposmod(0.33 - lg * 0.11, 1.0), 0.6, 0.92)


func _draw_chunk(ck: int) -> void:
	var c = chunks[ck]
	var n: Node2D = c.node
	var x0 := (ck % cw) * CS
	@warning_ignore("integer_division")
	var y0 := (ck / cw) * CS
	if lod == 2:
		if c.tex == null or c.tex_dirty:
			_build_chunk_tex(c)
		n.draw_texture_rect(c.tex, Rect2(0, 0, CPX, CPX), false)
		return
	var kind: PackedByteArray = c.kind
	var vis: PackedByteArray = c.vis
	var hp: PackedInt32Array = c.hp
	# пол и туман (туман рисуется полосами)
	n.draw_rect(Rect2(0, 0, CPX, CPX), FLOOR)
	for ly in CS:
		var run := -1
		for lx in CS + 1:
			var fog := lx < CS and (vis[(ly << 5) | lx] == 0 or kind[(ly << 5) | lx] == 3)
			if fog and run < 0:
				run = lx
			elif not fog and run >= 0:
				n.draw_rect(Rect2(run * CELL, ly * CELL, (lx - run) * CELL, CELL), FOG)
				run = -1
	var detail := lod == 0
	var gap := 1.0 if detail else 0.0
	# квадраты
	for li in CS * CS:
		if kind[li] != 1 or vis[li] == 0:
			continue
		var r := Rect2((li & 31) * CELL + gap, (li >> 5) * CELL + gap, CELL - 2.0 * gap, CELL - 2.0 * gap)
		var col := _hp_color(hp[li])
		n.draw_rect(r, col)
		if detail:
			n.draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), col.lerp(Color.WHITE, 0.3))
			n.draw_rect(Rect2(r.position.x, r.end.y - 4.0, r.size.x, 4.0), col.darkened(0.22))
			if poisons.has((y0 + (li >> 5)) * W + x0 + (li & 31)):
				n.draw_rect(r.grow(-2.0), Color(0.2, 0.9, 0.2), false, 3.0)
	# стены: цельная белая фигура с фасками, тенью и швами между кубиками
	for li in CS * CS:
		if kind[li] != 2 or vis[li] == 0:
			continue
		var lx := li & 31
		var ly := li >> 5
		var gx := x0 + lx
		var gy := y0 + ly
		var px := lx * CELL
		var py := ly * CELL
		if not detail:
			n.draw_rect(Rect2(px, py, CELL, CELL), WALL_FACE)
			continue
		var up := _kind_at(gx, gy - 1) == 2
		var dn := _kind_at(gx, gy + 1) == 2
		var lf := _kind_at(gx - 1, gy) == 2
		var rt := _kind_at(gx + 1, gy) == 2
		if not dn and gy + 1 < H:
			n.draw_rect(Rect2(px + 4.0, py + CELL, CELL, 9.0), Color(0, 0, 0, 0.3))
		if not rt and gx + 1 < W:
			n.draw_rect(Rect2(px + CELL, py + 6.0, 7.0, CELL), Color(0, 0, 0, 0.22))
		n.draw_rect(Rect2(px, py, CELL, CELL), WALL_FACE)
		if not up:
			n.draw_rect(Rect2(px, py, CELL, 5.0), WALL_LIGHT)
		if not lf:
			n.draw_rect(Rect2(px, py, 4.0, CELL), WALL_LIGHT)
		if not dn:
			n.draw_rect(Rect2(px, py + CELL - 6.0, CELL, 6.0), WALL_DARK)
		if not rt:
			n.draw_rect(Rect2(px + CELL - 5.0, py, 5.0, CELL), WALL_DARK)
		if rt:
			n.draw_rect(Rect2(px + CELL - 1.0, py + 6.0, 1.5, CELL - 12.0), WALL_SEAM)
		if dn:
			n.draw_rect(Rect2(px + 6.0, py + CELL - 1.0, CELL - 12.0, 1.5), WALL_SEAM)
	if not detail:
		return
	# цифры — вдвое крупным шрифтом в масштабе 0.5, чтобы были чёткими при приближении
	var font := ThemeDB.fallback_font
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.5, 0.5))
	for li in CS * CS:
		if kind[li] != 1 or vis[li] == 0:
			continue
		n.draw_string(font, Vector2((li & 31) * CELL * 2.0, ((li >> 5) * CELL + CELL * 0.5) * 2.0 + 11.0),
			GameData.fmt(hp[li]), HORIZONTAL_ALIGNMENT_CENTER, CELL * 2.0, 30, Color(0, 0, 0, 0.85))
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _build_chunk_tex(c) -> void:
	var img := Image.create(CS, CS, false, Image.FORMAT_RGBA8)
	for li in CS * CS:
		var col := Color(0, 0, 0, 0)
		if c.vis[li] == 1:
			match c.kind[li]:
				0:
					col = FLOOR
				1:
					col = _hp_color(c.hp[li])
				2:
					col = WALL_FACE
		img.set_pixel(li & 31, li >> 5, col)
	if c.tex == null:
		c.tex = ImageTexture.create_from_image(img)
	else:
		c.tex.update(img)
	c.tex_dirty = false


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
	var fs := int(clampf(26.0 / zoom, 26.0, 4000.0))
	for p in popups:
		overlay.draw_string(font, p["pos"] - Vector2(fs * 2, 0), p["text"], HORIZONTAL_ALIGNMENT_CENTER, fs * 4, fs,
			Color(1.0, 0.85, 0.2, clampf(p["t"], 0.0, 1.0)))


# ================================================================ камера

func _screen_to_world(sp: Vector2) -> Vector2:
	return cam.position + (sp - get_viewport_rect().size * 0.5) / zoom


func _view_rect() -> Rect2:
	var vs := get_viewport_rect().size / zoom
	return Rect2(cam.position - vs * 0.5, vs)


func _explored_rect() -> Rect2:
	var m := 6
	var a := Vector2(maxi(0, ex0 - m), maxi(0, ey0 - m)) * CELL
	var b := Vector2(mini(W, ex1 + 1 + m), mini(H, ey1 + 1 + m)) * CELL
	return Rect2(a, b - a)


func _update_zoom_limits() -> void:
	var vs := get_viewport_rect().size
	var avail := Vector2(vs.x - 16.0, vs.y - top_h - bottom_h - 16.0)
	var er := _explored_rect()
	zoom_min = minf(minf(avail.x / er.size.x, avail.y / er.size.y), 36.0 / CELL)
	zoom_max = 2.5
	if zoom < zoom_min:
		_set_zoom(zoom_min, vs * 0.5)


func _set_zoom(z: float, anchor: Vector2) -> void:
	var before := _screen_to_world(anchor)
	zoom = clampf(z, zoom_min, zoom_max)
	cam.zoom = Vector2(zoom, zoom)
	cam.position = before - (anchor - get_viewport_rect().size * 0.5) / zoom
	_clamp_cam()
	var px := CELL * zoom
	var nl := 0 if px >= 24.0 else (1 if px >= 4.0 else 2)
	if nl != lod:
		lod = nl
		_mark_all()
	mm_count = -1
	overlay_dirty = true


## Камера ходит в пределах открытой части карты.
func _clamp_cam() -> void:
	var vs := get_viewport_rect().size
	var er := _explored_rect()
	var lo_x := er.position.x + (vs.x * 0.5 - 8.0) / zoom
	var hi_x := er.end.x - (vs.x * 0.5 - 8.0) / zoom
	var lo_y := er.position.y + (vs.y * 0.5 - top_h - 8.0) / zoom
	var hi_y := er.end.y - (vs.y * 0.5 - bottom_h - 8.0) / zoom
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
	var d := _screen_to_world(sp) - start_pos
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
	warp_label = Label.new()
	warp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warp_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	warp_label.visible = false
	var tv := VBoxContainer.new()
	top_margin.remove_child(tr)
	top_margin.add_child(tv)
	tv.add_child(tr)
	tv.add_child(warp_label)

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
	if track_all:
		lbl_prog.text = "%d%%" % int(100.0 * destroyed / maxi(1, total))
	elif goal_done:
		lbl_prog.text = GameData.fmt(destroyed)
	else:
		lbl_prog.text = "%s/%s" % [GameData.fmt(destroyed), GameData.fmt(goal)]
	if catchup > 0.0:
		var sec := int(catchup)
		warp_label.text = "Перемотка пропущенного времени: %d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]
		warp_label.visible = true
	elif warp_label.visible:
		warp_label.visible = false
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

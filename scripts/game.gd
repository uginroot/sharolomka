extends Node2D
## Игровая карта. Мир хранится кусками 32×32 клетки и создаётся по мере открытия,
## поэтому карта может быть размером хоть 10000×10000.

const Maps = preload("res://scripts/maps.gd")
const BallScript = preload("res://scripts/ball.gd")
const ChunkScript = preload("res://scripts/chunk.gd")
const Icons = preload("res://scripts/icons.gd")
const TouchScroll = preload("res://scripts/touch_scroll.gd")

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
const GOLD_RATE := 30            # золотой квадрат: шанс на 10 000
const FRENZY_TIME := 15.0        # «золотая лихорадка»: урон ×2, секунд
const FINALE_SHARE := 0.08       # финал маленькой карты, когда осталось ≤ 8% квадратов
const FOG := Color(0.07, 0.08, 0.11)
const FLOOR := Color(0.13, 0.15, 0.2)
const WALL_FACE := Color(0.9, 0.92, 0.96)
const WALL_LIGHT := Color(1, 1, 1)
const WALL_DARK := Color(0.6, 0.64, 0.74)
const WALL_SEAM := Color(0.8, 0.83, 0.9)
const GRID := Color(1, 1, 1, 0.055)
const FOG_GRID := Color(1, 1, 1, 0.03)       # сетка в тумане — ещё прозрачнее
const OUTSIDE := Color(0.03, 0.035, 0.05)     # за пределами карты — темнее тумана
const BORDER := Color(0.55, 0.68, 1.0, 0.85)  # граница карты
const SLING_R := 230.0          # радиус области наведения рогатки, px экрана
const SLING_MIN := 28.0         # меньше — это касание, а не оттягивание
const HOLD_TIME := 0.22         # удержание пальца на месте до начала прицеливания, с
const PAN_SLOP := 12.0          # сдвиг пальца раньше удержания — это перемещение карты, px

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
var coin_acc := 0.0              # дробная часть монет при бонусе
var coin_mult := 1.0
var frenzy_t := 0.0              # осталось «золотой лихорадки»
var finale := false              # финал: шары летят к последним квадратам
var finale_ids := PackedInt32Array()
var finale_dist := PackedInt32Array()
var finale_t := 0.0
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
var coins := 0
var counts := {}
var dmg_lvl := {}
var spd_lvl := {}
var reset_cd := {}
var reset_armed := false        # «Сброс» включён: следующий выстрел перезапускает бездельника

# ---- время
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
var frame_node: Node2D           # сетка в тумане и затемнение за картой (под кусками)
var border_node: Node2D          # граница карты (над кусками)
var _frame_key := Vector3.ZERO
var floor_col := FLOOR           # цвет пола — у бесконечных уровней свой по теме
var hue_shift := 0.0             # сдвиг оттенка квадратов по теме
var overlay: Node2D
var dirty := {}
var redraw_t := 0.0
var lod := 0                     # 0 — с цифрами, 1 — «свет», 2 — грубо, по текстуре на кусок
var ball_layer: Node2D
var ball_tex: ImageTexture

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
var aim_before := 0.0
var sling := false              # идёт оттягивание рогатки
var sling_start := Vector2.ZERO # где нажали (экран)
var sling_pos := Vector2.ZERO   # где палец сейчас (экран)
var sling_cancel := false       # палец вытянут за область наведения
var sling_view: Control
var press_pending := false      # палец нажат, ещё не ясно: прицел или перемещение
var press_t := 0.0
var press_pos := Vector2.ZERO
var panning := false
var saved_balls: Array = []
var last_launch := Vector2.ZERO  # откуда был последний выстрел — для кнопки «Выстрел» и «Сброса»
var sling_from = null           # точка вылета для текущей рогатки (мир) или null — нажали не туда

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
var upg_tabs: TabContainer
var toast: PanelContainer
var toast_label: Label
var toast_t := 0.0


# ================================================================ запуск

func _ready() -> void:
	map_index = maxi(0, GameData.current_map)
	map = Maps.get_map(map_index)
	floor_col = map.get("floor", FLOOR)
	hue_shift = float(map.get("hue", 0.0))
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
	ball_tex = Icons.ball(64)

	W = int(map["w"])
	H = int(map["h"])
	cw = (W + CS - 1) / CS
	chh = (H + CS - 1) / CS
	wpx = W * CELL
	hpx = H * CELL
	chunks.resize(cw * chh)
	seed_i = _seed_of(String(map["id"]))
	@warning_ignore("integer_division")
	start_cell = Vector2i(W / 2, H / 2)   # прохождение начинается из центра карты
	start_pos = (Vector2(start_cell) + Vector2(0.5, 0.5)) * CELL
	last_launch = start_pos
	hb = float(map["hp_base"])
	hg = float(map["hp_growth"])
	region_size = int(map.get("region", maxi(W, H)))
	track_all = W * H <= PREGEN_LIMIT
	ex0 = start_cell.x
	ex1 = start_cell.x
	ey0 = start_cell.y
	ey1 = start_cell.y

	frame_node = Node2D.new()
	add_child(frame_node)
	frame_node.draw.connect(_draw_frame)
	field_root = Node2D.new()
	add_child(field_root)
	border_node = Node2D.new()
	add_child(border_node)
	border_node.draw.connect(_draw_border)
	# шарики: одна текстура на всех — Godot склеивает их в один вызов отрисовки
	ball_layer = Node2D.new()
	add_child(ball_layer)
	ball_layer.draw.connect(_draw_balls)
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

	coin_mult = GameData.coin_mult()
	_recalc_stats()
	# шары продолжают движение с тех мест, где были при выходе
	var placed := {}
	for sb in saved_balls:
		var t: String = sb[0]
		if not t_idx.has(t) or int(placed.get(t, 0)) >= int(counts[t]):
			continue
		_spawn_ball(t, 0.0, Vector2(sb[1], sb[2]))
		var v := Vector2(sb[3], sb[4])
		balls[-1].vel = (v.normalized() if v.length() > 0.0 else Vector2.UP) * _speed(t)
		placed[t] = int(placed.get(t, 0)) + 1
	for t in GameData.TYPE_ORDER:
		for k in int(counts[t]) - int(placed.get(t, 0)):
			_spawn_ball(t, aim_angle + (randf_range(-30.0, 30.0) if saved_at > 0.0 else 0.0))

	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()


# ================================================================ генерация мира

## Сид карты: djb2 по символам id — те же значения, что даёт hash() в Godot 4.3, но без зависимости
## от движка (если в новой версии hash() изменится, карты не «переедут» относительно сохранений).
static func _seed_of(s: String) -> int:
	var h := 5381
	for i in s.length():
		h = ((h << 5) + h + s.unicode_at(i)) & 0xffffffff
	return h


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
	c.gold.resize(CS * CS)
	c.hp.fill(0)
	c.kind.fill(0)
	c.vis.fill(0)
	c.gold.fill(0)
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
			c.hp[li] = int(minf(ceil(hb * pow(1.0 + sqrt(d2) * hg, 1.6)), 2.0e9))   # жизни хранятся в int32
			if _hash3(x, y, seed_i + 13) % 10000 < GOLD_RATE:
				c.gold[li] = 1
			solid += 1
	if not blob.is_empty():
		var raw: PackedByteArray = (blob[0] as PackedByteArray).decompress(int(blob[1]), FileAccess.COMPRESSION_ZSTD)
		c.hp = raw.slice(0, CS * CS * 4).to_int32_array()
		c.vis = raw.slice(CS * CS * 4, CS * CS * 5)
		if raw.size() >= CS * CS * 6:
			# с v0.15 в сохранении есть и типы клеток — открытая часть не зависит от генератора
			c.kind = raw.slice(CS * CS * 5, CS * CS * 6)
			solid = 0
			for li in CS * CS:
				var k: int = c.kind[li]
				if k == 1 or k == 2:
					solid += 1
		else:
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
	if has_meta("test_no_pictures"):   # только для теста «стены из сохранения не зависят от генератора»
		return null
	var res = null
	if map.has("fixed"):
		if rx == 0 and ry == 0:
			res = _build_picture(map["fixed"], Rect2i(0, 0, W, H))
	else:
		var x0 := rx * region_size
		var y0 := ry * region_size
		var has_start := Rect2i(x0 - 3, y0 - 3, region_size + 6, region_size + 6).has_point(start_cell)
		# картинка целиком помещается и в регион, и в карту (у края карты регион обрезан)
		var span_x := mini(region_size, W - x0) - 6
		var span_y := mini(region_size, H - y0) - 6
		var span := mini(span_x, span_y)
		var slot := [] if has_start or span < 12 else _layout_slot(rx, ry)
		if not slot.is_empty():
			var size := maxi(12, int(span * float(slot[1])))
			# по центру региона — раскладка читается как задуманный рисунок
			@warning_ignore("integer_division")
			var px := x0 + 3 + (span_x - size) / 2
			@warning_ignore("integer_division")
			var py := y0 + 3 + (span_y - size) / 2
			res = _build_picture([[slot[0], Rect2i(px, py, size, size), slot[2]]], Rect2i(px - 1, py - 1, size + 2, size + 2))
	region_cache[key] = res
	return res


## Раскладка картинок по регионам — узор вокруг старта, а не случайная россыпь:
##   rings  — концентрические кольца, в каждом свой мотив;  rays   — 8 лучей от центра;
##   spiral — три рукава спирали;  checker — шахматка;  mosaic — сетка с чередованием мотивов.
## Размер растёт от центра к краю; на левой половине картинки зеркальные — карта симметрична.
## Возвращает [шаблон, доля размера региона, зеркально] или [] — регион пустой.
func _layout_slot(rx: int, ry: int) -> Array:
	var R := float(region_size)
	var c := (Vector2(rx, ry) + Vector2(0.5, 0.5)) * R
	var d := c - (Vector2(start_cell) + Vector2(0.5, 0.5))
	var dist := d.length() / R
	if dist < 1.2:
		return []
	var ring := int(round(dist))
	var tl: Array = map["templates"]
	var n := tl.size()
	var ang := atan2(d.y, d.x)
	@warning_ignore("integer_division")
	var srx: int = start_cell.x / region_size
	@warning_ignore("integer_division")
	var sry: int = start_cell.y / region_size
	var ax := absi(rx - srx)
	var ay := absi(ry - sry)
	var occ := true
	var tpl: String = tl[ring % n]
	match String(map.get("layout", "rings")):
		"rings":
			occ = ring % 3 != 0
		"rays":
			var step := TAU / 8.0
			var a2 := fposmod(ang + step * 0.5, step) - step * 0.5
			occ = absf(a2) * dist < 0.75 or ring % 4 == 0
		"spiral":
			var arm := fposmod(ang / TAU * 3.0 - dist * 0.16, 1.0)
			occ = arm < 0.62
			tpl = tl[int(fposmod(ang / TAU * 3.0 - dist * 0.16, 3.0)) % n]
		"checker":
			occ = (ax + ay) % 2 == 0
			@warning_ignore("integer_division")
			tpl = tl[((ax + ay) / 2) % n]
		"mosaic":
			occ = ax % 2 == 0 or ay % 2 == 0
			tpl = tl[(ax + 2 * ay) % n]
	if not occ:
		return []
	var frac := 0.7 + 0.25 * clampf((dist - 1.0) / 5.0, 0.0, 1.0)
	return [tpl, frac, d.x < 0.0]


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
		var flip: bool = it.size() > 2 and it[2]
		for p in templates[it[0]]:
			var q := PackedVector2Array()
			for v in p:
				var u: Vector2 = Vector2(1.0 - v.x, v.y) if flip else v   # зеркало для левой половины
				q.append(Vector2(r.position - box.position) + u * Vector2(r.size))
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
	# клетки за краем карты — не проход
	for i in bw * bh:
		@warning_ignore("integer_division")
		var gx := box.position.x + i % bw
		@warning_ignore("integer_division")
		var gy := box.position.y + i / bw
		if gx >= W or gy >= H:
			mask[i] = 2
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
	if typeof(s) != TYPE_DICTIONARY or int(s.get("ver", 0)) != 5 or int(s.get("w", 0)) != W:
		return 0.0
	coins = int(s.get("coins", s.get("rubles", 0)))   # до v0.14 ключ назывался "rubles"
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
	saved_balls = s.get("balls", [])
	var ll: Array = s.get("last_launch", [])
	if ll.size() == 2:
		last_launch = Vector2(ll[0], ll[1])
	aim_angle = float(s.get("aim", aim_angle))
	if GameData.unlocked.get(String(s.get("selected", "basic")), false):
		selected = String(s.get("selected", "basic"))
	var ch: Dictionary = s.get("chunks", {})
	for ck in ch:
		var cc = _gen_chunk(int(ck), ch[ck])
		chunks[int(ck)] = cc
		if cc.vis.count(1) > 0:
			_ensure_node(int(ck))
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
			raw.append_array(c.kind)
			c.blob = [raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size()]
			c.blob_dirty = false
		out[ck] = c.blob
	var s := {
		"ver": 5, "w": W, "coins": coins, "destroyed": destroyed, "goal_done": goal_done,
		"counts": counts.duplicate(), "dmg": dmg_lvl.duplicate(), "spd": spd_lvl.duplicate(),
		"saved_at": Time.get_unix_time_from_system(), "chunks": out,
		"balls": balls.map(func(b): return [b.type, b.pos.x, b.pos.y, b.vel.x, b.vel.y]),
		"last_launch": [last_launch.x, last_launch.y], "aim": aim_angle, "selected": selected,
	}
	# пишем во временный файл и переименовываем: если телефон выключится посреди записи,
	# останется прежнее целое сохранение, а не обрезанный файл
	var tmp := _save_path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_var(s)
	f.close()
	DirAccess.rename_absolute(tmp, _save_path())
	GameData.map_states[String(map["id"])] = {"saved": true}
	GameData.save_game()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_save_state()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if upg != null and upg.visible:
				_show_upgrades(false)
			else:
				_to_menu()


# ================================================================ характеристики

func _speed(t: String) -> float:
	return float(GameData.TYPES[t]["speed"]) * (1.0 + 0.08 * int(spd_lvl[t]))


## Урон: base·(1 + ур.) и ×2 на каждом 10-м уровне — вехи держат рост экспоненциальным
## (без них доход глохнет против экспоненциальных цен — симулятор баланса v0.16).
func _damage_of(t: String) -> int:
	var lv := int(dmg_lvl[t])
	var d := float(GameData.TYPES[t]["damage"]) * (1 + lv) * pow(2.0, floori(lv / 10.0)) * GameData.mastery_mult()
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


## Цена base·growth^n с потолком: без него на больших n float выходит за int64 и цена
## становится отрицательной (шар покупался бесплатно — найдено ревью v0.15).
const PRICE_CAP := 4.0e18


static func _price(base: float, growth: float, n: int) -> int:
	return int(minf(round(base * pow(growth, n)), PRICE_CAP))


func _ball_cost(t: String) -> int:
	return _price(float(GameData.TYPES[t]["ball_cost"]), 1.35, int(counts[t]))


func _dmg_cost(t: String) -> int:
	return _price(float(GameData.TYPES[t]["dmg_cost"]), 1.55, int(dmg_lvl[t]))


func _spd_cost(t: String) -> int:
	return _price(float(GameData.TYPES[t]["spd_cost"]), 1.6, int(spd_lvl[t]))


# ================================================================ симуляция

func _spawn_ball(t: String, ang: float, at = null) -> void:
	var b = BallScript.new()
	b.type = t
	b.ti = t_idx[t]
	b.radius = float(GameData.TYPES[t]["radius"])
	b.pos = start_pos if at == null else at
	b.vel = Vector2.from_angle(deg_to_rad(ang)) * _speed(t)
	balls.append(b)


func _sim(dt: float) -> void:
	time_acc += dt
	if finale:
		finale_t -= dt
		if finale_t <= 0.0:
			finale_t = 1.0
			_finale_field()
		for b in balls:
			if time_acc - b.seek_t > 0.25:
				b.seek_t = time_acc + randf() * 0.05
				_finale_steer(b)
	if frenzy_t > 0.0:
		frenzy_t = maxf(0.0, frenzy_t - dt)
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

	if not popups.is_empty():
		for p in popups:
			p["t"] -= delta
			p["pos"].y -= 30.0 * delta / zoom
		popups = popups.filter(func(p): return p["t"] > 0.0)
		overlay_dirty = true

	_redraw_dirty()
	# сетка в тумане и граница зависят от камеры — перерисовываем, только когда она сдвинулась
	var key := Vector3(cam.position.x, cam.position.y, zoom) if cam != null else Vector3.ZERO
	if key != _frame_key:
		_frame_key = key
		frame_node.queue_redraw()
		border_node.queue_redraw()
	_hold_tick(delta)
	# прицел и подсказки перерисовываем, только пока они на экране (и один раз после — чтобы стереть)
	var active := sling or press_pending or not popups.is_empty()
	if active or overlay_dirty or sling_view.get_meta("was", false):
		overlay.queue_redraw()
		sling_view.queue_redraw()
		sling_view.set_meta("was", active)
		overlay_dirty = false
	ball_layer.queue_redraw()

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
		ui_t = 0.1
		_refresh_ui()
	save_t += delta
	if save_t > 20.0:
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
		if finale:
			pass   # в финале шары ведёт поле расстояний (см. _sim)
		elif sniper and (hit >= 0 or st_sup[2] == 1) and time_acc - b.seek_t > 0.15:
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
	Sfx.play("hit", 0.15)
	var ti: int = b.ti
	var dmg := st_dmg[ti] * (2 if frenzy_t > 0.0 else 1)
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
			# пролетает сквозь добитый квадрат; с «Призраком» — сквозь любой видимый,
			# но в туман не уходит: от скрытых квадратов отскакивает
			var before := _hp_of(id)
			var visible := _vis_id(id)
			_damage(id, dmg, b)
			if dmg >= before or (sup and visible):
				b.recent[id] = time_acc
				return true
		4:
			_damage(id, dmg, b)
			if _hp_of(id) > 0:
				_apply_poison(id, dmg * 0.6, 3.0 + lvl, b)
		_:
			_damage(id, dmg, b)
	return false


func _vis_id(id: int) -> bool:
	@warning_ignore("integer_division")
	return _vis_at(id % W, id / W)


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
	# монеты = снятые жизни × постоянный бонус за пройденные карты
	coin_acc += dealt * coin_mult
	var add := int(coin_acc)
	coin_acc -= add
	coins += add
	if b != null:
		b.earned += dealt
	_mark(ck)
	if h - dealt <= 0:
		Sfx.play("break", 0.12)
		c.kind[li] = 0
		c.solid -= 1
		destroyed += 1
		alive -= 1
		_on_destroyed(x, y, id)


func _on_destroyed(x: int, y: int, id: int) -> void:
	_reveal(x, y)
	# U-баллы спрятаны в части квадратов (в полостях картинок — чаще)
	var rate := int(map.get("u_rate", 10)) * (2 if _mask_at(x, y) == 4 else 1)
	if _hash3(x, y, seed_i + 7) % 10000 < rate:
		GameData.u += 1
		GameData.request_save()   # отложенно: при частых находках не дёргаем флеш-память
		Sfx.play("u", 0.03)
		popups.append({"pos": (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL, "text": "+1 U", "t": 1.5})
		overlay_dirty = true
	var c = chunks[(x >> 5) + (y >> 5) * cw]
	var li := ((y & 31) << 5) | (x & 31)
	if c.gold[li] == 1:
		c.gold[li] = 0
		frenzy_t = minf(maxf(frenzy_t, 0.0) + FRENZY_TIME, FRENZY_TIME * 2.0)   # копится, но не больше 30 с
		popups.append({"pos": (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL, "text": "×2!", "t": 1.5})
		_show_toast(tr("Золотой квадрат! Урон ×2 на %d с") % int(FRENZY_TIME))
		Sfx.play("gold", 0.0)
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


## Финал маленькой карты: последние ≤8% квадратов подсвечиваются, шары летят к ним сами —
## без этого последние минуты уходили на поиск разрозненных квадратов (симулятор баланса v0.16).
func _start_finale() -> void:
	finale = true
	finale_ids = PackedInt32Array()
	for ck in chunks.size():
		var c = chunks[ck]
		if c == null or c.solid == 0:
			continue
		for li in CS * CS:
			if c.kind[li] == 1:
				var x := (ck % cw) * CS + (li & 31)
				@warning_ignore("integer_division")
				var y := (ck / cw) * CS + (li >> 5)
				finale_ids.append(y * W + x)
				if c.vis[li] == 0:
					c.vis[li] = 1
					c.changed = true
					c.blob_dirty = true
					_ensure_node(ck)
				_mark(ck)
	_finale_field()
	Sfx.play("finale", 0.0)
	_show_toast(tr("Финал: осталось %d — шары летят к последним квадратам") % finale_ids.size())


## Поле расстояний финала: обход в ширину от оставшихся квадратов по свободным клеткам.
## Шар поворачивает к соседней клетке, которая ближе к цели, — так он обходит стены
## (наведение «по прямой» не находило квадраты в выемках картинок).
func _finale_field() -> void:
	finale_dist.resize(W * H)
	finale_dist.fill(1 << 30)
	var q := PackedInt32Array()
	var live := PackedInt32Array()
	for id in finale_ids:
		if _hp_of(id) > 0:
			live.append(id)
			finale_dist[id] = 0
			q.append(id)
	finale_ids = live
	var head := 0
	while head < q.size():
		var id := q[head]
		head += 1
		var x := id % W
		@warning_ignore("integer_division")
		var y := id / W
		var nd := finale_dist[id] + 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx: int = x + o.x
			var yy: int = y + o.y
			if xx < 0 or yy < 0 or xx >= W or yy >= H:
				continue
			var j: int = yy * W + xx
			if finale_dist[j] <= nd or _kind_at(xx, yy) != 0:
				continue
			finale_dist[j] = nd
			q.append(j)


func _finale_steer(b) -> void:
	var cx := int(b.pos.x * INV)
	var cy := int(b.pos.y * INV)
	if cx < 0 or cy < 0 or cx >= W or cy >= H:
		return
	var best := finale_dist[cy * W + cx]
	var to := Vector2i(-1, -1)
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var xx: int = cx + o.x
		var yy: int = cy + o.y
		if xx < 0 or yy < 0 or xx >= W or yy >= H:
			continue
		# по диагонали — только если не срезаем угол стены
		if o.x != 0 and o.y != 0 and (_kind_at(cx + o.x, cy) == 2 or _kind_at(cx, cy + o.y) == 2):
			continue
		var dv: int = finale_dist[yy * W + xx]
		if dv < best:
			best = dv
			to = Vector2i(xx, yy)
	if to.x >= 0:
		var tc := (Vector2(to) + Vector2(0.5, 0.5)) * CELL
		b.vel = (tc - b.pos).normalized() * b.vel.length()


func _check_goal() -> void:
	if track_all and not finale and alive > 0 and alive <= maxi(12, int(total * FINALE_SHARE)):
		_start_finale()

	if not goal_done and destroyed >= goal:
		goal_done = true
		var id := String(map["id"])
		var reward := 2 if GameData.maps_done.has(id) else 5
		GameData.u += reward
		GameData.maps_done[id] = true
		coin_mult = GameData.coin_mult()
		GameData.maps_unlocked = maxi(GameData.maps_unlocked, map_index + 2)
		GameData.save_game()
		if not (track_all and alive <= 0):
			Sfx.play("goal", 0.0)
			_show_toast(tr("Цель карты выполнена!\n+%d U, +%d%% монет навсегда, открыта следующая карта") % [reward, int(GameData.MAP_BONUS * 100)])
	if track_all and alive <= 0 and not completed:
		completed = true
		GameData.map_states.erase(String(map["id"]))
		DirAccess.remove_absolute(_save_path())
		GameData.save_game()
		var d := AcceptDialog.new()
		d.title = tr("Победа!")
		d.dialog_text = tr("Карта «%s» разбита полностью!") % Maps.title(map, tr)
		d.ok_button_text = tr("В меню")
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


## Перерисовываем только изменившиеся куски, которые видны на экране: не чаще 10 раз в секунду и не больше 12 за раз.
func _redraw_dirty() -> void:
	if dirty.is_empty():
		return
	redraw_t -= get_process_delta_time()
	if redraw_t > 0.0:
		return
	redraw_t = 0.1   # не чаще 10 раз в секунду — для батареи
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


func _draw_balls() -> void:
	# на экране шарик не меньше 11 пикселей, иначе его не видно при отдалении
	var min_d := 11.0 / zoom
	for b in balls:
		var dd: float = maxf(b.radius * 2.6, min_d)
		ball_layer.draw_texture_rect(ball_tex, Rect2(b.pos.x - dd * 0.5, b.pos.y - dd * 0.5, dd, dd), false, colors[b.type])


func _hp_color(h: int) -> Color:
	var lg := log(float(maxi(h, 1))) / log(10.0)
	return Color.from_hsv(fposmod(0.33 - lg * 0.11 + hue_shift, 1.0), 0.6, 0.92)


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
	# пол — полосами только под видимыми клетками; туман — это просто фон сцены
	var gw := mini(CS, W - x0)
	var gh := mini(CS, H - y0)
	for ly in gh:
		var run := -1
		for lx in gw + 1:
			var seen := lx < gw and vis[(ly << 5) | lx] == 1
			if seen and run < 0:
				run = lx
			elif not seen and run >= 0:
				n.draw_rect(Rect2(run * CELL, ly * CELL, (lx - run) * CELL, CELL), floor_col)
				if lod == 0:
					# еле видная сетка — только вблизи и только на открытом полу
					var gl := PackedVector2Array()
					for k in range(run, lx + 1):
						gl.append(Vector2(k * CELL, ly * CELL))
						gl.append(Vector2(k * CELL, ly * CELL + CELL))
					gl.append(Vector2(run * CELL, ly * CELL))
					gl.append(Vector2(lx * CELL, ly * CELL))
					n.draw_multiline(gl, GRID)
				run = -1
	var detail := lod == 0
	var gap := 1.0 if detail else 0.0
	# квадраты
	for li in CS * CS:
		if kind[li] != 1 or vis[li] == 0:
			continue
		var r := Rect2((li & 31) * CELL + gap, (li >> 5) * CELL + gap, CELL - 2.0 * gap, CELL - 2.0 * gap)
		var golden: bool = c.gold[li] == 1
		var col := Color(1.0, 0.8, 0.2) if golden else _hp_color(hp[li])
		n.draw_rect(r, col)
		if golden and detail:
			n.draw_rect(r.grow(-2.0), Color(1, 1, 1, 0.9), false, 2.0)
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
	var font: Font = GameData.font
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
					col = floor_col
				1:
					col = Color(1.0, 0.8, 0.2) if c.gold[li] == 1 else _hp_color(c.hp[li])
				2:
					col = WALL_FACE
		img.set_pixel(li & 31, li >> 5, col)
	if c.tex == null:
		c.tex = ImageTexture.create_from_image(img)
	else:
		c.tex.update(img)
	c.tex_dirty = false


## Центр игрового поля на экране (между верхней и нижней панелями) в мировых координатах.
func _screen_center_world() -> Vector2:
	var vs := get_viewport_rect().size
	return _screen_to_world(Vector2(vs.x * 0.5, (top_h + vs.y - bottom_h) * 0.5))


## Точка вылета — ровно точка нажатия, если она в пустой открытой клетке; иначе null (нажали не туда).
## Сдвиг только на несколько пикселей от соседних квадратов/стен, чтобы шар не появился внутри них.
func _launch_from(w: Vector2):
	var cx := int(floor(w.x * INV))
	var cy := int(floor(w.y * INV))
	if not _vis_at(cx, cy) or _kind_at(cx, cy) != 0:
		return null
	var r := 8.5
	var lo := Vector2(cx, cy) * CELL
	var hi := lo + Vector2(CELL, CELL)
	var p := w
	if _kind_at(cx - 1, cy) != 0:
		p.x = maxf(p.x, lo.x + r)
	if _kind_at(cx + 1, cy) != 0:
		p.x = minf(p.x, hi.x - r)
	if _kind_at(cx, cy - 1) != 0:
		p.y = maxf(p.y, lo.y + r)
	if _kind_at(cx, cy + 1) != 0:
		p.y = minf(p.y, hi.y - r)
	return p


## Сетка в тумане (только вблизи) и затемнение за пределами карты — в пределах экрана.
func _draw_frame() -> void:
	var v := _view_rect().grow(CELL)
	var world := Rect2(0, 0, wpx, hpx)
	# за картой — темнее тумана, чтобы край читался даже без рамки
	if v.position.x < 0.0:
		frame_node.draw_rect(Rect2(v.position.x, v.position.y, -v.position.x, v.size.y), OUTSIDE)
	if v.end.x > wpx:
		frame_node.draw_rect(Rect2(wpx, v.position.y, v.end.x - wpx, v.size.y), OUTSIDE)
	if v.position.y < 0.0:
		frame_node.draw_rect(Rect2(maxf(v.position.x, 0.0), v.position.y, minf(v.end.x, wpx) - maxf(v.position.x, 0.0), -v.position.y), OUTSIDE)
	if v.end.y > hpx:
		frame_node.draw_rect(Rect2(maxf(v.position.x, 0.0), hpx, minf(v.end.x, wpx) - maxf(v.position.x, 0.0), v.end.y - hpx), OUTSIDE)
	if lod != 0:
		return
	var r := v.intersection(world)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var x0 := floorf(r.position.x / CELL) * CELL
	var y0 := floorf(r.position.y / CELL) * CELL
	var gl := PackedVector2Array()
	var x := x0
	while x <= r.end.x:
		gl.append(Vector2(x, r.position.y))
		gl.append(Vector2(x, r.end.y))
		x += CELL
	var y := y0
	while y <= r.end.y:
		gl.append(Vector2(r.position.x, y))
		gl.append(Vector2(r.end.x, y))
		y += CELL
	frame_node.draw_multiline(gl, FOG_GRID)


## Граница карты: яркая рамка поверх кусков (видна, когда край карты на экране).
func _draw_border() -> void:
	var w := maxf(3.0, 4.0 / zoom)
	var r := Rect2(0, 0, wpx, hpx)
	border_node.draw_rect(r.grow(w * 1.5), Color(BORDER.r, BORDER.g, BORDER.b, 0.18), false, w * 3.0)
	border_node.draw_rect(r.grow(w * 0.5), BORDER, false, w)


func _draw_overlay() -> void:
	var w := 3.0 / zoom
	var dir := Vector2.from_angle(deg_to_rad(aim_angle))
	var col: Color = colors[selected]
	var pull := (sling_start - sling_pos).length()
	if sling and sling_from != null:
		var lp: Vector2 = sling_from
		overlay.draw_arc(lp, 13.0 / zoom, 0.0, TAU, 32, Color(0, 0, 0, 0.6), 6.0 / zoom)
		overlay.draw_arc(lp, 13.0 / zoom, 0.0, TAU, 32, col, 3.0 / zoom)
		overlay.draw_circle(lp, 4.0 / zoom, col)
		if pull >= SLING_MIN:
			# стрелка направления: длина растёт с оттягиванием, при отмене — красная
			var acol := Color(1.0, 0.85, 0.3, 0.95)
			if reset_armed:
				acol = Color(0.45, 0.85, 1.0, 0.95)
			if sling_cancel:
				acol = Color(1, 0.4, 0.4, 0.9)
			var alen := (90.0 + 180.0 * minf(pull, SLING_R) / SLING_R) / zoom
			var tip: Vector2 = lp + dir * alen
			var side := dir.orthogonal() * (14.0 / zoom)
			overlay.draw_line(lp, tip - dir * (18.0 / zoom), Color(0, 0, 0, 0.5), 9.0 / zoom)
			overlay.draw_line(lp, tip - dir * (18.0 / zoom), acol, 5.0 / zoom)
			overlay.draw_colored_polygon(PackedVector2Array([tip, tip - dir * (26.0 / zoom) + side,
				tip - dir * (26.0 / zoom) - side]), acol)
	var font: Font = GameData.font_bold
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
	# отдалиться можно до всей карты целиком — видны её границы и размер (даже 10000×10000)
	var whole := minf(avail.x / wpx, avail.y / hpx)
	zoom_min = minf(minf(minf(avail.x / er.size.x, avail.y / er.size.y), whole), 30.0 / CELL)
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
	overlay_dirty = true


## Центр поля (точка выстрела) может дойти до любого края открытой части карты при любом масштабе.
func _clamp_cam() -> void:
	var vs := get_viewport_rect().size
	var off_y := ((top_h + vs.y - bottom_h) * 0.5 - vs.y * 0.5) / zoom
	var a := Vector2(maxi(0, ex0 - 1), maxi(0, ey0 - 1)) * CELL
	var b := Vector2(mini(W, ex1 + 2), mini(H, ey1 + 2)) * CELL
	var c := cam.position + Vector2(0, off_y)
	c = c.clamp(a, b)
	cam.position = c - Vector2(0, off_y)


# ================================================================ ввод

func _over_ui(p: Vector2) -> bool:
	if upg.visible:
		return true
	return top_bar.get_global_rect().has_point(p) or bottom_bar.get_global_rect().has_point(p)


## Один палец: сразу повёл — перемещение карты; нажал и подержал HOLD_TIME — прицел-рогатка
## (оттянуть назад, отпустить — выстрел; за областью наведения — отмена). Два пальца — масштаб и сдвиг.
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			if touches.is_empty() and _over_ui(e.position):
				return
			touches[e.index] = e.position
			if touches.size() == 1 and not pinch:
				_press_down(e.position)
			elif touches.size() >= 2:
				_press_cancel()
				pinch = true
				_pinch_reset()
		else:
			if touches.has(e.index) and touches.size() == 1:
				_press_up()
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
			_press_drag(e.position, e.relative)
	elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION:
		if e.pressed and _over_ui(e.position):
			return
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom * 1.15, e.position)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom / 1.15, e.position)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_down(e.position)
			else:
				_press_up()
		elif e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			mouse_pan = e.pressed
	elif e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION:
		if mouse_pan:
			cam.position -= e.relative / zoom
			_clamp_cam()
		elif e.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_press_drag(e.position, e.relative)


func _press_down(p: Vector2) -> void:
	press_pending = true
	press_t = 0.0
	press_pos = p
	panning = false


func _press_drag(p: Vector2, rel: Vector2) -> void:
	if sling:
		_sling_move(p)
	elif panning:
		cam.position -= rel / zoom
		_clamp_cam()
	elif press_pending and p.distance_to(press_pos) > PAN_SLOP:
		# повёл сразу — это перемещение карты
		press_pending = false
		panning = true
		cam.position -= (p - press_pos) / zoom
		_clamp_cam()


func _press_up() -> void:
	if sling:
		_sling_release()
	press_pending = false
	panning = false


func _press_cancel() -> void:
	press_pending = false
	panning = false
	_sling_abort()


## Палец держат на месте — после HOLD_TIME начинается прицеливание.
func _hold_tick(delta: float) -> void:
	if not press_pending:
		return
	press_t += delta
	if press_t >= HOLD_TIME:
		press_pending = false
		_sling_begin(press_pos)
		GameData.vibrate(40)   # 15 мс на многих телефонах не ощущались
		Sfx.play("aim", 0.0)


func _sling_begin(p: Vector2) -> void:
	sling = true
	sling_start = p
	sling_pos = p
	sling_cancel = false
	aim_before = aim_angle
	sling_from = _launch_from(_screen_to_world(p))


## Можно ли сейчас выстрелить: включён сброс или хватает денег на новый шар.
func _can_shoot() -> bool:
	return reset_armed or coins >= _ball_cost(selected)


func _sling_move(p: Vector2) -> void:
	sling_pos = p
	var pull := sling_start - p
	sling_cancel = pull.length() > SLING_R or sling_from == null or not _can_shoot()
	if pull.length() >= SLING_MIN and not sling_cancel:
		aim_angle = _snap(rad_to_deg(pull.angle()))


func _sling_release() -> void:
	var pull := sling_start - sling_pos
	var ok := not sling_cancel and sling_from != null and pull.length() >= SLING_MIN and _can_shoot()
	sling = false
	if ok:
		if reset_armed:
			_relaunch_idler(sling_from)
		else:
			_fire(sling_from)
	else:
		aim_angle = aim_before


func _sling_abort() -> void:
	if sling:
		sling = false
		aim_angle = aim_before


func _draw_sling() -> void:
	if press_pending and press_t > 0.06:
		# колечко дорисовывается, пока палец держат: заполнилось — начинается прицел
		var f := clampf(press_t / HOLD_TIME, 0.0, 1.0)
		sling_view.draw_arc(press_pos, 30.0, -PI / 2.0, -PI / 2.0 + TAU * f, 40, Color(1, 1, 1, 0.75), 4.0, true)
	if not sling:
		return
	var pull := sling_start - sling_pos
	var bad := sling_cancel or sling_from == null or not _can_shoot()
	var col := Color(1, 0.4, 0.4, 0.9) if bad else Color(1, 1, 1, 0.85)
	# область наведения вокруг точки нажатия
	sling_view.draw_circle(sling_start, SLING_R, Color(col.r, col.g, col.b, 0.06))
	sling_view.draw_arc(sling_start, SLING_R, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.35), 2.0, true)
	sling_view.draw_line(sling_start, sling_pos, Color(col.r, col.g, col.b, 0.6), 3.0, true)
	sling_view.draw_circle(sling_start, 6.0, col)
	sling_view.draw_circle(sling_pos, 10.0, Color(col.r, col.g, col.b, 0.5))
	if pull.length() < SLING_MIN and not bad:
		return
	var font: Font = GameData.font_bold
	var txt := tr("Отпустите — отмена") if sling_cancel else tr("Отпустите — выстрел")
	if not sling_cancel and reset_armed:
		txt = tr("Отпустите — перезапуск бездельника")
	if sling_from == null:
		txt = tr("Нажмите на открытую клетку")
	elif not _can_shoot():
		txt = tr("Не хватает монет")
	var tw := minf(640.0, sling_view.size.x - 20.0)
	var tp := Vector2(clampf(sling_start.x - tw * 0.5, 10.0, sling_view.size.x - tw - 10.0), sling_start.y - SLING_R - 16)
	sling_view.draw_string(font, tp + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_CENTER, tw, 20, Color(0, 0, 0, 0.6))
	sling_view.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, tw, 20, col)


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

## Выстрел новым шаром выбранного типа (рогаткой). Без точки — из места последнего выстрела (для тестов).
func _fire(from = null) -> void:
	var t := selected
	var c := _ball_cost(t)
	var lp: Vector2 = last_launch if from == null else from
	if coins < c:
		return
	coins -= c
	counts[t] += 1
	last_launch = lp
	_spawn_ball(t, aim_angle, lp)
	Sfx.play("launch")
	_refresh_ui()


func _buy_dmg(t: String) -> void:
	var c := _dmg_cost(t)
	if coins < c:
		return
	coins -= c
	dmg_lvl[t] += 1
	Sfx.play("buy", 0.04)
	_recalc_stats()
	_refresh_ui()


func _buy_spd(t: String) -> void:
	var c := _spd_cost(t)
	if coins < c or int(spd_lvl[t]) >= SPD_MAX:
		return
	coins -= c
	spd_lvl[t] += 1
	Sfx.play("buy", 0.04)
	_recalc_stats()
	var sp := _speed(t)
	for b in balls:
		if b.type == t:
			b.vel = b.vel.normalized() * sp
	_refresh_ui()


## «Сброс» — переключатель: следующий выстрел рогаткой бесплатно перезапускает шар выбранного типа,
## заработавший меньше всех (бездельника). Кулдаун 30 с на тип начинается с этого выстрела.
func _reset_stuck() -> void:
	if reset_armed:
		reset_armed = false
	elif reset_cd[selected] <= 0.0 and int(counts[selected]) > 0:
		reset_armed = true
	_refresh_ui()


func _idler(t: String):
	var worst = null
	for b in balls:
		if b.type == t and (worst == null or b.earned < worst.earned):
			worst = b
	return worst


func _relaunch_idler(p: Vector2) -> void:
	var t := selected
	var worst = _idler(t)
	reset_armed = false
	if worst == null:
		return
	worst.pos = p
	worst.vel = Vector2.from_angle(deg_to_rad(aim_angle)) * _speed(t)
	worst.recent.clear()
	for b in balls:
		if b.type == t:
			b.earned = 0
	reset_cd[t] = RESET_CD
	last_launch = p
	_refresh_ui()


func _unlock(t: String) -> void:
	var c := int(GameData.TYPES[t]["unlock_u"])
	if GameData.u < c or GameData.unlocked[t]:
		return
	GameData.u -= c
	GameData.unlocked[t] = true
	Sfx.play("gold", 0.0)
	GameData.save_game()
	_rebuild_rows()


func _perk_up(t: String) -> void:
	var lvl := int(GameData.perks[t])
	if lvl >= GameData.PERK_MAX or GameData.u < lvl + 1:
		return
	GameData.u -= lvl + 1
	GameData.perks[t] = lvl + 1
	Sfx.play("buy", 0.04)
	GameData.save_game()
	_recalc_stats()
	_refresh_ui()


func _super_up(t: String) -> void:
	if GameData.supers[t] or GameData.u < GameData.SUPER_COST:
		return
	GameData.u -= GameData.SUPER_COST
	GameData.supers[t] = true
	Sfx.play("gold", 0.0)
	GameData.save_game()
	_recalc_stats()
	_refresh_ui()


func _mastery_up() -> void:
	var c := GameData.mastery_cost()
	if GameData.u < c:
		return
	GameData.u -= c
	GameData.mastery += 1
	Sfx.play("buy", 0.04)
	GameData.save_game()
	_recalc_stats()
	_refresh_ui()


func _select(t: String) -> void:
	selected = t
	if reset_armed and (reset_cd[t] > 0.0 or int(counts[t]) == 0):
		reset_armed = false
	_refresh_ui()


func _to_menu() -> void:
	_save_state()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ================================================================ интерфейс

var ic_coin: ImageTexture
var ic_gem: ImageTexture
var prog_bar: ProgressBar
var mastery_btn: Button
var frenzy_label: Label


func _safe_margins() -> Array:
	# отступы от выреза камеры, скруглений и системных полос + запас от края
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
	return [l + 20.0, t + 12.0, r + 20.0, b + 20.0]


func _margin(m: MarginContainer, v: Array) -> void:
	m.add_theme_constant_override("margin_left", int(v[0]))
	m.add_theme_constant_override("margin_top", int(v[1]))
	m.add_theme_constant_override("margin_right", int(v[2]))
	m.add_theme_constant_override("margin_bottom", int(v[3]))


func _button(text: String, variation: String = "", h: float = 58.0, icon: Texture2D = null) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = h
	if variation != "":
		b.theme_type_variation = variation
	if icon != null:
		b.icon = icon
		b.expand_icon = false
	return b


func _label(text: String = "", variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	return l


func _icon_rect(tex: Texture2D, sz: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(sz, sz)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## «Пилюля» со значком и числом — для монет и U.
func _pill(tex: Texture2D, color: Color) -> Label:
	var p := PanelContainer.new()
	p.theme_type_variation = "Pill"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	h.add_child(_icon_rect(tex, 26))
	var l := Label.new()
	l.add_theme_font_override("font", GameData.font_bold)
	l.add_theme_color_override("font_color", color)
	h.add_child(l)
	return l


func _build_ui() -> void:
	ic_coin = Icons.coin(40)
	ic_gem = Icons.gem(40)
	var cl := CanvasLayer.new()
	add_child(cl)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = GameData.make_theme()   # CanvasLayer не передаёт тему от окна — задаём явно
	cl.add_child(ui_root)
	sling_view = Control.new()
	sling_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	sling_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sling_view.draw.connect(_draw_sling)
	ui_root.add_child(sling_view)

	# --- верхняя полоса
	top_bar = PanelContainer.new()
	top_bar.anchor_right = 1.0
	ui_root.add_child(top_bar)
	top_margin = MarginContainer.new()
	top_bar.add_child(top_margin)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	top_margin.add_child(tv)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 8)
	tv.add_child(tr)
	var bmenu := _button("", "", 52, Icons.menu(40))
	bmenu.custom_minimum_size.x = 56
	bmenu.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bmenu.pressed.connect(_to_menu)
	tr.add_child(bmenu)
	lbl_rub = _pill(ic_coin, GameData.C_GOLD)
	tr.add_child(lbl_rub.get_parent().get_parent())
	lbl_u = _pill(ic_gem, GameData.C_GEM)
	tr.add_child(lbl_u.get_parent().get_parent())
	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 2)
	tr.add_child(pv)
	lbl_prog = _label("", "Muted")
	lbl_prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(lbl_prog)
	prog_bar = ProgressBar.new()
	prog_bar.show_percentage = false
	prog_bar.custom_minimum_size.y = 10
	prog_bar.max_value = 1.0
	pv.add_child(prog_bar)
	btn_snap = _button("", "", 52, Icons.angle(40))
	btn_snap.pressed.connect(_cycle_snap)
	tr.add_child(btn_snap)
	frenzy_label = _label("")
	frenzy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frenzy_label.add_theme_color_override("font_color", GameData.C_GOLD)
	frenzy_label.add_theme_font_override("font", GameData.font_bold)
	frenzy_label.visible = false
	tv.add_child(frenzy_label)
	top_bar.resized.connect(_on_bars_resized)

	# --- нижняя панель: выбор шара, сброс, прокачка
	bottom_bar = PanelContainer.new()
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
	btn_reset = _button("", "ChipButton", 64, Icons.refresh(40))
	btn_reset.toggle_mode = true
	btn_reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_reset.pressed.connect(_reset_stuck)
	br.add_child(btn_reset)
	var bup := _button(tr("Прокачка"), "AccentButton", 64, Icons.arrow_up(40))
	bup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bup.pressed.connect(_show_upgrades.bind(true))
	br.add_child(bup)
	bottom_bar.resized.connect(_on_bars_resized)

	# --- окно прокачки: полупрозрачное, игра под ним идёт
	upg = Control.new()
	upg.set_anchors_preset(Control.PRESET_FULL_RECT)
	upg.visible = false
	ui_root.add_child(upg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.3)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	upg.add_child(dim)
	upg_margin = MarginContainer.new()
	upg_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	upg.add_child(upg_margin)
	var up := PanelContainer.new()
	var ups := StyleBoxFlat.new()
	ups.bg_color = Color(0.08, 0.09, 0.14, 0.86)
	ups.set_corner_radius_all(22)
	ups.border_color = Color(1, 1, 1, 0.08)
	ups.set_border_width_all(1)
	ups.content_margin_left = 14
	ups.content_margin_right = 14
	ups.content_margin_top = 14
	ups.content_margin_bottom = 14
	up.add_theme_stylebox_override("panel", ups)
	upg_margin.add_child(up)
	var uv := VBoxContainer.new()
	uv.add_theme_constant_override("separation", 12)
	up.add_child(uv)
	var uh := HBoxContainer.new()
	uh.add_theme_constant_override("separation", 8)
	uv.add_child(uh)
	var ut := _label(tr("Прокачка"), "Title")
	ut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uh.add_child(ut)
	upg_rub = _pill(ic_coin, GameData.C_GOLD)
	uh.add_child(upg_rub.get_parent().get_parent())
	upg_u = _pill(ic_gem, GameData.C_GEM)
	uh.add_child(upg_u.get_parent().get_parent())
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	uv.add_child(tabs)
	upg_tabs = tabs
	for k in 2:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(sc)
		var m := MarginContainer.new()
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.add_theme_constant_override("margin_top", 10)
		m.add_theme_constant_override("margin_right", 6)
		sc.add_child(m)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 12)
		m.add_child(vb)
		if k == 0:
			shop_box = vb
		else:
			perk_box = vb
		var ts = TouchScroll.new()   # прокрутка пальцем, даже если палец лёг на кнопку
		ts.target = sc
		upg.add_child(ts)
	tabs.set_tab_title(0, tr("  Шарики  "))
	tabs.set_tab_title(1, tr("  Перки  "))
	var bclose := _button(tr("Вернуться к игре"), "AccentButton", 60)
	bclose.pressed.connect(_show_upgrades.bind(false))
	uv.add_child(bclose)

	# --- всплывающее сообщение
	toast = PanelContainer.new()
	toast.theme_type_variation = "Card"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 0.28
	toast.anchor_bottom = 0.28
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.visible = false
	ui_root.add_child(toast)
	toast_label = _label("")
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(toast_label)

	_rebuild_rows()


func _layout() -> void:
	var m := _safe_margins()
	_margin(top_margin, [m[0], m[1], m[2], 10])
	_margin(bottom_margin, [m[0], 12, m[2], m[3]])
	_margin(upg_margin, [m[0] - 8.0, m[1] + 6.0, m[2] - 8.0, m[3]])
	_on_bars_resized()


func _on_bars_resized() -> void:
	if top_bar == null or bottom_bar == null:
		return
	top_h = top_bar.size.y
	bottom_h = bottom_bar.size.y
	_update_zoom_limits()
	if not cam_ready and top_h > 0.0 and bottom_h > 0.0:
		cam_ready = true
		cam.position = start_pos + Vector2(0, -CELL * 3.0)
		_set_zoom(52.0 / CELL, get_viewport_rect().size * 0.5)
	else:
		_set_zoom(zoom, get_viewport_rect().size * 0.5)


func _show_upgrades(show: bool) -> void:
	upg.visible = show
	touches.clear()
	pinch = false
	_press_cancel()
	_refresh_ui()


func _show_toast(text: String) -> void:
	toast_label.text = text
	toast.visible = true
	toast.modulate.a = 1.0
	toast_t = 5.0


## Кнопка с ценой: подпись сверху, цена со значком монеты/камня.
func _price_btn(parent: HBoxContainer, caption: String, icon: Texture2D, cb: Callable) -> Dictionary:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	parent.add_child(v)
	var l := _label(caption, "Muted")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var b := _button("", "", 54, icon)
	b.pressed.connect(cb)
	v.add_child(b)
	return {"label": l, "button": b}


func _card_head(parent: VBoxContainer, t: String, locked: bool) -> Label:
	var def: Dictionary = GameData.TYPES[t]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	h.add_child(_icon_rect(Icons.dot(def["color"], 44) if not locked else Icons.lock(40), 32))
	var n := _label(tr(def["name"]), "Title")
	h.add_child(n)
	var extra := _label("", "Muted")
	extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(extra)
	return extra


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

	# «Мастерство» — вечная трата U, первая карточка вкладки перков
	var mc := PanelContainer.new()
	mc.theme_type_variation = "Card"
	perk_box.add_child(mc)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mc.add_child(mv)
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 10)
	mv.add_child(mh)
	mh.add_child(_icon_rect(ic_gem, 32))
	mh.add_child(_label(tr("Мастерство"), "Title"))
	var md := _label(tr("+10% урона всех шаров за уровень, без предела"), "Muted")
	md.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mv.add_child(md)
	mastery_btn = _button("", "AccentButton", 54, ic_gem)
	mastery_btn.pressed.connect(_mastery_up)
	mv.add_child(mastery_btn)

	for t in GameData.TYPE_ORDER:
		var def: Dictionary = GameData.TYPES[t]
		var unlocked: bool = GameData.unlocked[t]

		# --- фишка выбора шара: значок и число шаров сверху, цена снизу (влезают все 5 типов)
		if unlocked:
			var chip := _button("", "ChipButton", 62)
			chip.toggle_mode = true
			chip.button_group = chip_group
			chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			chip.custom_minimum_size.x = 0
			chip.button_pressed = (t == selected)
			chip.pressed.connect(_select.bind(t))
			chips_box.add_child(chip)
			var cv := VBoxContainer.new()
			cv.set_anchors_preset(Control.PRESET_FULL_RECT)
			cv.alignment = BoxContainer.ALIGNMENT_CENTER
			cv.add_theme_constant_override("separation", 0)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(cv)
			var top := HBoxContainer.new()
			top.alignment = BoxContainer.ALIGNMENT_CENTER
			top.add_theme_constant_override("separation", 4)
			top.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(top)
			var ic := _icon_rect(Icons.dot(def["color"], 44), 20)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top.add_child(ic)
			var cnt := Label.new()
			cnt.add_theme_font_override("font", GameData.font_bold)
			cnt.add_theme_font_size_override("font_size", 19)
			cnt.text_direction = Control.TEXT_DIRECTION_LTR
			top.add_child(cnt)
			var price := Label.new()
			price.add_theme_font_size_override("font_size", 15)
			price.add_theme_color_override("font_color", GameData.C_GOLD)
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			price.text_direction = Control.TEXT_DIRECTION_LTR
			cv.add_child(price)
			chips[t] = chip
			chip.set_meta("cnt", cnt)
			chip.set_meta("price", price)

		# --- карточка магазина
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		shop_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 10)
		card.add_child(cv)
		var extra := _card_head(cv, t, not unlocked)
		var sd := _label(tr(def["desc"]), "Muted")
		sd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(sd)
		if unlocked:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			cv.add_child(row)
			shop_refs[t] = {
				"extra": extra,
				"dmg": _price_btn(row, tr("Урон"), ic_coin, _buy_dmg.bind(t)),
				"spd": _price_btn(row, tr("Скорость"), ic_coin, _buy_spd.bind(t)),
			}
		else:
			card.modulate = Color(1, 1, 1, 0.6)
			extra.text = tr("открывается во вкладке «Перки»")

		# --- карточка перков
		var pc := PanelContainer.new()
		pc.theme_type_variation = "Card"
		perk_box.add_child(pc)
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 8)
		pc.add_child(pv)
		_card_head(pv, t, not unlocked)
		var d0 := _label(tr(def["desc"]), "Muted")
		d0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pv.add_child(d0)
		var d1 := _label(tr("«%s» — %s") % [tr(def["perk"]), tr(def["perk_desc"])], "Muted")
		d1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pv.add_child(d1)
		var d2 := _label(tr("Супер «%s» — %s") % [tr(def["super"]), tr(def["super_desc"])], "Muted")
		d2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pv.add_child(d2)
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		pv.add_child(prow)
		if unlocked:
			var perk_btn := _button("", "", 54, ic_gem)
			perk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			perk_btn.pressed.connect(_perk_up.bind(t))
			prow.add_child(perk_btn)
			var sup_btn := _button("", "", 54, ic_gem)
			sup_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sup_btn.pressed.connect(_super_up.bind(t))
			prow.add_child(sup_btn)
			perk_refs[t] = {"perk": perk_btn, "super": sup_btn}
		else:
			var ub := _button("", "AccentButton", 54, ic_gem)
			ub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ub.pressed.connect(_unlock.bind(t))
			prow.add_child(ub)
			perk_refs[t] = {"unlock": ub}
	_refresh_ui()


func _refresh_ui() -> void:
	if lbl_rub == null:
		return
	lbl_rub.text = GameData.fmt(coins)
	lbl_u.text = str(GameData.u)
	var frac := float(destroyed) / maxf(1.0, float(goal))
	prog_bar.value = minf(1.0, frac)
	if track_all:
		lbl_prog.text = tr("Разбито %d%%") % int(100.0 * frac)
	elif goal_done:
		lbl_prog.text = tr("Разбито %s") % GameData.fmt(destroyed)
	else:
		lbl_prog.text = tr("%s из %s") % [GameData.fmt(destroyed), GameData.fmt(goal)]
	btn_snap.text = [tr("любой"), tr("45°"), tr("90°")][snap_mode]
	if frenzy_t > 0.0:
		frenzy_label.text = tr("Урон ×2 · %d с") % int(ceil(frenzy_t))
		frenzy_label.visible = true
	elif frenzy_label.visible:
		frenzy_label.visible = false
	for t in chips:
		# цена следующего шара прямо на фишке; не хватает денег — фишка тусклее
		var price := _ball_cost(t)
		chips[t].get_meta("cnt").text = "×%d" % counts[t]
		chips[t].get_meta("price").text = GameData.fmt(price)
		chips[t].modulate = Color(1, 1, 1, 1.0 if coins >= price else 0.6)
	var cd: float = reset_cd[selected]
	if reset_armed:
		btn_reset.text = tr("Сброс: прицельтесь")
	elif cd > 0.0:
		btn_reset.text = tr("Сброс · %d с") % int(ceil(cd))
	else:
		btn_reset.text = tr("Сброс")
	btn_reset.set_pressed_no_signal(reset_armed)
	btn_reset.disabled = not reset_armed and (cd > 0.0 or int(counts[selected]) == 0)

	if not upg.visible:
		return
	upg_rub.text = GameData.fmt(coins)
	upg_u.text = str(GameData.u)
	for t in shop_refs:
		var r: Dictionary = shop_refs[t]
		r["extra"].text = tr("шаров на карте: %d") % counts[t]
		var dc := _dmg_cost(t)
		r["dmg"]["label"].text = tr("Урон %d → %d") % [_damage_of(t), _damage_of_next(t)]
		r["dmg"]["button"].text = GameData.fmt(dc)
		r["dmg"]["button"].disabled = coins < dc
		var sl := int(spd_lvl[t])
		var cps := _speed(t) / CELL
		if sl >= SPD_MAX:
			r["spd"]["label"].text = tr("Скорость %.1f кл/с") % cps
		else:
			spd_lvl[t] += 1
			var nxt := _speed(t) / CELL
			spd_lvl[t] -= 1
			r["spd"]["label"].text = tr("Скорость %.1f → %.1f кл/с") % [cps, nxt]
		if sl >= SPD_MAX:
			r["spd"]["button"].text = tr("макс.")
			r["spd"]["button"].disabled = true
		else:
			var scost := _spd_cost(t)
			r["spd"]["button"].text = GameData.fmt(scost)
			r["spd"]["button"].disabled = coins < scost

	var mcost := GameData.mastery_cost()
	mastery_btn.text = tr("Уровень %d → %d · %d") % [GameData.mastery, GameData.mastery + 1, mcost]
	mastery_btn.disabled = GameData.u < mcost
	for t in perk_refs:
		var r: Dictionary = perk_refs[t]
		if r.has("unlock"):
			var uc := int(GameData.TYPES[t]["unlock_u"])
			r["unlock"].text = tr("Открыть · %d") % uc
			r["unlock"].disabled = GameData.u < uc
			continue
		var lvl := int(GameData.perks[t])
		if lvl >= GameData.PERK_MAX:
			r["perk"].text = tr("Перк %d/%d") % [lvl, GameData.PERK_MAX]
			r["perk"].disabled = true
		else:
			r["perk"].text = tr("Перк %d/%d · %d") % [lvl, GameData.PERK_MAX, lvl + 1]
			r["perk"].disabled = GameData.u < lvl + 1
		if GameData.supers[t]:
			r["super"].text = tr("Супер есть")
			r["super"].disabled = true
		else:
			r["super"].text = tr("Супер · %d") % GameData.SUPER_COST
			r["super"].disabled = GameData.u < GameData.SUPER_COST

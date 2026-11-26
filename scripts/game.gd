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
const SHAKE_CD := 300.0          # «Встряска»: раз в 5 минут
const SHAKE_MIN := 10.0          # поворот направления каждого шара, градусов (случайно, в случайную сторону)
const SHAKE_MAX := 20.0
const MAX_OFFLINE := 86400.0     # перематываем не больше суток
const WARP_BUDGET_US := 9000     # сколько микросекунд за кадр можно тратить на перемотку
const PREGEN_LIMIT := 60000      # карты меньше этого генерируем целиком (можно пройти на 100%)
const GOLD_RATE := 30            # золотой квадрат: шанс на 10 000
const FRENZY_TIME := 15.0        # «золотая лихорадка»: урон ×2, секунд
const U_PER_LEVEL := 25.0        # сколько U-баллов в среднем находится до цели уровня
const FINALE_SHARE := 0.08       # финал маленькой карты, когда осталось ≤ 8% квадратов
const FOG := Color(0.07, 0.08, 0.11)
const FLOOR := Color(0.13, 0.15, 0.2)
const WALL_FACE := Color(0.9, 0.92, 0.96)
const WALL_LIGHT := Color(1, 1, 1)
const WALL_DARK := Color(0.6, 0.64, 0.74)
const WALL_SEAM := Color(0.8, 0.83, 0.9)
const GRID := Color(1, 1, 1, 0.055)
const FOG_GRID := Color(1, 1, 1, 0.03)       # сетка в тумане — ещё прозрачнее
const FOG_EDGE := 0.55                        # яркость мягкого края тумана у открытых клеток
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
var run_u := 0                   # U-баллы этого уровня — тратятся на деревья умений шаров
var u_ppm := 0                   # шанс U-балла в квадрате на миллион
var gold_rate := GOLD_RATE       # шанс золотого квадрата на 10 000 (+ «Наследие»)
var frenzy_time := FRENZY_TIME
var dmg_total := {}              # статистика шаров уровня: тип → весь нанесённый урон
var dmg_win := {}                # тип → урон по секундам за последние 10 с (кольцо из 10 корзин)
var dmg_sec := 0                 # секунда игрового времени, до которой корзины актуальны
const DPS_WINDOW := 60            # окно среднего урона в секунду, с (было 10 — значение сильно прыгало)
var play_time := 0.0             # сколько игрок играет этот уровень (только пока игра открыта), с
var coin_acc := 0.0              # дробная часть монет при бонусе
var coin_mult := 1.0
var frenzy_t := 0.0              # осталось «золотой лихорадки»
var frenzy_max := 15.0           # длина полоски лихорадки
var finale := false              # финал: шары летят к последним квадратам
var finale_ids := PackedInt32Array()
var finale_dist := PackedInt32Array()
var finale_t := 0.0
var full_tracked := false        # знаем число всех квадратов (маленькие карты и карты-картины) — есть полная расчистка
var finale_pass := PackedByteArray()   # финал: 1 — свободная клетка (по ней идёт поле расстояний)
var bfs_q := PackedInt32Array()        # поле расстояний считается порциями (на больших картах — полмиллиона клеток)
var bfs_head := 0
var bfs_dist := PackedInt32Array()
var bfs_busy := false
const BFS_BUDGET := 40000              # клеток поля за кадр
const FINALE_BIG_SHARE := 0.01         # финал большой карты — последний 1% квадратов, но не больше FINALE_BIG_MAX
const FINALE_BIG_MAX := 2000
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
var st_share := PackedFloat32Array()   # доля удара по соседям (Никитиевый + бонус стаи)

# ---- экономика карты
var coins := 0
var counts := {}
var tlvl := {}                   # ветки за монеты: тип → {id ветки: уровень} (сбрасывается каждый уровень)
var unl := {}                    # открытые типы на этом уровне (за 1 U)
var evo := {}                    # эволюции на этом уровне: тип → {id: true}
var elvl := {}                   # ветки эволюций: тип → {id ветки: уровень}
var extra := {}                  # шары сверх оплаченных пусков (залпы Дробовика): тип → число
var poison_hops := {}            # Инфекция: клетка → сколько переходов яд уже сделал
var corr_until := {}             # Разъедание: клетка → до какого времени ещё уязвима
var zaps := []                   # вспышки молний для отрисовки
var evo_refs := {}               # вкладка «Эволюции»: тип → {эволюция: кнопки}
var aura_r_now := 0.0            # текущий радиус ауры (с боевым кличем) — для отрисовки
var fleet := {}                  # бонусы стаи: вид → число ступеней
var aura_t := 0.0
var reset_cd := {}
var shake_cd := 0.0              # перезарядка «Встряски», с (сохраняется с уровнем)
var btn_shake: Button
var shake_fill: Control
var shake_fill_panel: Panel
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
var fog_builds := 0              # сколько раз пересчитывался край тумана — для тестов
var frame_node: Node2D           # сетка в тумане и затемнение за картой (под кусками)
var border_node: Node2D          # граница карты (над кусками)
var _frame_key := Vector3.ZERO
var has_shape := false          # карта-сцена с формой (овал, круг, скруглённый прямоугольник)
var shape_pts := PackedVector2Array()
var floor_col := FLOOR           # цвет пола — у бесконечных уровней свой по теме
var hue_shift := 0.0             # сдвиг оттенка квадратов по теме
var overlay: Node2D
var dirty := {}
var redraw_t := 0.0
var lod := 0                     # 0 — с цифрами, 1 — «свет», 2 — грубо, по текстуре на кусок
var ball_layer: Node2D
var ball_tex: ImageTexture
var ball_icons := {}             # силуэт шара по типу на поле
var ui_icons := {}               # значок типа для фишек и карточек (у Гесиевого шлейф нарисован в значке)
var highlight_type := ""         # подсветка шаров выбранного типа (на фишке нажали) …
var highlight_t := 0.0           # … и сколько ей ещё гореть
const HIGHLIGHT_TIME := 1.2

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
var reset_fill: Control
var reset_fill_panel: Panel
const ROW_FONT := 23
var upg: Control
var upg_margin: MarginContainer
var upg_rub: Label
var upg_u: Label
var shop_box: VBoxContainer
var upg_tab_box: HBoxContainer
var upg_tabs_btn := {}           # тип → {button, count, badge}
var upg_type := "basic"          # чья карточка открыта в прокачке
var upg_tab_group := ButtonGroup.new()
var upg_scroll: ScrollContainer
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
	gold_rate = int(GOLD_RATE * (1.0 + 0.2 * GameData.meta_level("gold")))
	frenzy_time = FRENZY_TIME + 3.0 * GameData.meta_level("frenzy")
	map = Maps.get_map(map_index)
	floor_col = map.get("floor", FLOOR)
	hue_shift = float(map.get("hue", 0.0))
	templates = Maps.templates()
	aim_angle = float(map["aim"])
	for ti in GameData.TYPE_ORDER.size():
		var t: String = GameData.TYPE_ORDER[ti]
		t_idx[t] = ti
		counts[t] = 0
		tlvl[t] = {}
		dmg_total[t] = 0
		var wb := PackedFloat32Array()
		wb.resize(DPS_WINDOW)
		dmg_win[t] = wb
		evo[t] = {}
		elvl[t] = {}
		extra[t] = 0
		unl[t] = bool(GameData.unlocked.get(t, t == "basic"))
		reset_cd[t] = 0.0
		colors[t] = GameData.TYPES[t]["color"]
	st_dmg.resize(GameData.TYPE_ORDER.size())
	st_share.resize(GameData.TYPE_ORDER.size())
	ball_tex = Icons.ball(64)
	for t in GameData.TYPE_ORDER:
		ball_icons[t] = Icons.ball_type(t, GameData.TYPES[t]["color"])
		ui_icons[t] = Icons.ball_type(t, GameData.TYPES[t]["color"], 96, true)

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
	if map.has("start"):   # у сцен старт на переднем плане — главный рисунок в центре не стирается
		start_cell = Vector2i(int(float(map["start"][0]) * W), int(float(map["start"][1]) * H))
	start_pos = (Vector2(start_cell) + Vector2(0.5, 0.5)) * CELL
	last_launch = start_pos
	hb = float(map["hp_base"])
	hg = float(map["hp_growth"])
	region_size = int(map.get("region", maxi(W, H)))
	has_shape = map.has("shape")
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
		# новый уровень: всё с нуля, кроме «Наследия»
		counts["basic"] = 1 + GameData.meta_level("start_balls")
		coins = GameData.start_coins()
		run_u = GameData.meta_level("start_u")
	if track_all:
		alive = 0
		total = 0
		for ck in chunks.size():
			var c = _get_chunk(ck)
			for li in CS * CS:
				if c.kind[li] == 1:
					alive += 1
		total = alive + destroyed
	elif map.has("pic"):
		# число квадратов картины известно из маски: все свободные клетки минус пустая площадка у старта
		var reg = _region(0, 0)
		var m: PackedByteArray = reg["mask"]
		var n := 0
		for v in m:
			if v == 0:
				n += 1
		var sc2 := START_CLEAR * START_CLEAR
		var r := int(ceil(START_CLEAR))
		for yy in range(start_cell.y - r, start_cell.y + r + 1):
			for xx in range(start_cell.x - r, start_cell.x + r + 1):
				if xx >= 0 and yy >= 0 and xx < W and yy < H and m[yy * W + xx] == 0 \
						and (Vector2(xx + 0.5, yy + 0.5) - start_pos * INV).length_squared() <= sc2:
					n -= 1
		total = n
		alive = total - destroyed
	full_tracked = track_all or map.has("pic")
	goal = total if int(map["goal"]) == 0 else int(map["goal"])
	# U-баллы: в среднем U_PER_LEVEL до цели уровня (+20% за уровень «Поиска U»)
	u_ppm = int(minf(U_PER_LEVEL / maxf(1.0, float(goal)) * 1.0e6 * (1.0 + 0.2 * GameData.meta_level("u_find")), 200000.0))
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
	c.ox = cx0
	c.oy = cy0
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
			if _hash3(x, y, seed_i + 13) % 10000 < gold_rate:
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


# ---------------------------------------------------------------- карты-сцены (с v0.29)
# Сцена — рисунок тонкими белыми линиями (как в pixel-rikoshet, но свои сюжеты): список штрихов в долях карты
# (0..1 по ширине и высоте). Форма карты (овал, круг, скруглённый прямоугольник): снаружи — сплошная стена,
# которая рисуется цветом фона за картой. Закрытые контуры получают проходы автоматически.

## Внутри ли формы карты точка (в клетках). Без формы — вся карта.
func _in_shape(px: float, py: float) -> bool:
	var cx := W * 0.5
	var cy := H * 0.5
	match String(map.get("shape", "")):
		"oval", "circle":
			var rx := W * 0.5 - 0.5
			var ry := H * 0.5 - 0.5
			var dx := (px - cx) / rx
			var dy := (py - cy) / ry
			return dx * dx + dy * dy <= 1.0
		"round":
			var r := minf(W, H) * 0.16
			var qx := absf(px - cx) - (W * 0.5 - r)
			var qy := absf(py - cy) - (H * 0.5 - r)
			if qx <= 0.0 or qy <= 0.0:
				return absf(px - cx) <= W * 0.5 and absf(py - cy) <= H * 0.5
			return qx * qx + qy * qy <= r * r
	return true


## Клетка за пределами формы карты (физически — стена, рисуется как фон за картой).
func _void_at(x: int, y: int) -> bool:
	return has_shape and not _in_shape(x + 0.5, y + 0.5)


## Углы лучей: равномерные плюс направления на углы карты (чтобы затемнение снаружи закрывало и уголки).
func _shape_angles(n: int) -> Array:
	var angs := []
	for k in n:
		angs.append(TAU * k / n)
	for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		angs.append(fposmod((Vector2(W, H) * 0.5 * corner).angle(), TAU))
	angs.sort()
	return angs


## Затемнение снаружи формы: полосы между контуром и краем карты (одна команда отрисовки).
var _ext_pts := PackedVector2Array()
var _ext_idx := PackedInt32Array()


func _build_exterior() -> void:
	var inner := _shape_points()
	var c := Vector2(W, H) * 0.5 * CELL
	var half := Vector2(W, H) * 0.5 * CELL
	var outer := PackedVector2Array()
	for p in inner:
		var d := (p - c).normalized()
		var t := minf(half.x / maxf(absf(d.x), 1e-6), half.y / maxf(absf(d.y), 1e-6))
		outer.append(c + d * t)
	_ext_pts = PackedVector2Array()
	_ext_idx = PackedInt32Array()
	var n := inner.size()
	for k in n:
		var k2 := (k + 1) % n
		var base := _ext_pts.size()
		_ext_pts.append_array([inner[k], outer[k], outer[k2], inner[k2]])
		_ext_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## Контур формы в мировых координатах (для границы и затемнения снаружи).
func _shape_points(n: int = 120) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := Vector2(W, H) * 0.5
	for a in _shape_angles(n):
		var d := Vector2.from_angle(a)
		var lo := 0.0
		var hi := float(maxi(W, H))
		for it in 18:
			var mid := (lo + hi) * 0.5
			var p := c + d * mid
			if _in_shape(p.x, p.y):
				lo = mid
			else:
				hi = mid
		pts.append((c + d * lo) * CELL)
	return pts


## Карта-картина: готовая маска maps/pic/<id>.png (0 — квадрат, 128 — стена рисунка, 255 — за формой карты),
## собранная заранее tools/gen_picture_maps.py; на втором круге бесконечных уровней — зеркально.
func _build_pic() -> Dictionary:
	var tex: Texture2D = load("res://maps/pic/%s.png" % String(map["pic"]))
	var img := tex.get_image()
	img.convert(Image.FORMAT_L8)
	var src := img.get_data()
	var m := PackedByteArray()
	m.resize(W * H)
	var flip: bool = map.get("flip", false)
	for y in H:
		var row := y * W
		for x in W:
			var v: int = src[row + (W - 1 - x if flip else x)]
			m[row + x] = 2 if v >= 64 else 0
	return {"x0": 0, "y0": 0, "w": W, "h": H, "mask": m}


func _build_scene() -> Dictionary:
	var n := W * H
	var m := PackedByteArray()
	m.resize(n)
	m.fill(0)
	var vm := PackedByteArray()
	vm.resize(n)
	vm.fill(0)
	for y in H:
		for x in W:
			if _void_at(x, y):
				vm[y * W + x] = 1
				m[y * W + x] = 2
	for st in map["scene"]:
		_stroke(m, st)
	# площадка у старта всегда свободна
	var r := int(ceil(START_CLEAR)) + 2
	for y in range(start_cell.y - r, start_cell.y + r + 1):
		for x in range(start_cell.x - r, start_cell.x + r + 1):
			if x >= 0 and y >= 0 and x < W and y < H and vm[y * W + x] == 0:
				m[y * W + x] = 0
	_open_enclosed(m, vm)
	return {"x0": 0, "y0": 0, "w": W, "h": H, "mask": m}


func _cellp(p) -> Vector2i:
	return Vector2i(int(round(float(p[0]) * (W - 1))), int(round(float(p[1]) * (H - 1))))


func _plot(m: PackedByteArray, x: int, y: int) -> void:
	if x >= 0 and y >= 0 and x < W and y < H:
		m[y * W + x] = 2


func _line_cells(m: PackedByteArray, a: Vector2i, b: Vector2i) -> void:
	# 4-связный Брезенхэм: за шаг — одна ось, поэтому у линии нет диагональных щелей и шар сквозь неё не проскочит
	var x := a.x
	var y := a.y
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx - dy
	_plot(m, x, y)
	while x != b.x or y != b.y:
		if 2 * err > -dy and x != b.x:
			err -= dy
			x += sx
		else:
			err += dx
			y += sy
		_plot(m, x, y)


func _poly_cells(m: PackedByteArray, pts: Array, closed: bool) -> void:
	for k in pts.size() - 1:
		_line_cells(m, pts[k], pts[k + 1])
	if closed and pts.size() > 2:
		_line_cells(m, pts[-1], pts[0])


## Штрихи сцены (координаты — доли карты; радиусы — доли меньшей стороны):
##   ["line", [[x,y],…], closed]    ["circle", [cx,cy], r]    ["arc", [cx,cy], r, от°, до°]
##   ["dots", [x0,y0], [x1,y1], шаг_клеток]    ["stars", [x,y,w,h], сколько, сид]
##   ["tpl", имя_шаблона, [x,y,w,h], зеркально]    ["wave", [x0,y], x1, амплитуда, период]
func _stroke(m: PackedByteArray, st: Array) -> void:
	var mn := float(mini(W, H))
	match String(st[0]):
		"line":
			var pts := []
			for p in st[1]:
				pts.append(_cellp(p))
			_poly_cells(m, pts, st.size() > 2 and bool(st[2]))
		"circle", "arc":
			var c := Vector2(float(st[1][0]) * (W - 1), float(st[1][1]) * (H - 1))
			var rr := float(st[2]) * mn
			var a0 := 0.0 if st[0] == "circle" else deg_to_rad(float(st[3]))
			var a1 := TAU if st[0] == "circle" else deg_to_rad(float(st[4]))
			var segs := maxi(12, int(rr * absf(a1 - a0)))
			var pts := []
			for k in segs + 1:
				var a := lerpf(a0, a1, float(k) / segs)
				var p := c + Vector2(cos(a), sin(a)) * rr
				pts.append(Vector2i(int(round(p.x)), int(round(p.y))))
			_poly_cells(m, pts, false)
		"dots":
			var a := _cellp(st[1])
			var b := _cellp(st[2])
			var step := maxi(2, int(st[3]))
			var len := Vector2(b - a).length()
			var k := 0.0
			while k <= len:
				var p := Vector2(a).lerp(Vector2(b), k / maxf(1.0, len))
				_plot(m, int(round(p.x)), int(round(p.y)))
				k += step
		"stars":
			var rng := RandomNumberGenerator.new()
			rng.seed = int(st[3])
			var rc: Array = st[1]
			for k in int(st[2]):
				var x := int((float(rc[0]) + rng.randf() * float(rc[2])) * (W - 1))
				var y := int((float(rc[1]) + rng.randf() * float(rc[3])) * (H - 1))
				_plot(m, x, y)
				if rng.randf() < 0.4:   # часть звёзд — крестиком
					_plot(m, x - 1, y)
					_plot(m, x + 1, y)
					_plot(m, x, y - 1)
					_plot(m, x, y + 1)
		"tpl":
			var rc: Array = st[2]
			var flip: bool = st.size() > 3 and bool(st[3])
			var ox := float(rc[0]) * (W - 1)
			var oy := float(rc[1]) * (H - 1)
			var sw := float(rc[2]) * (W - 1)
			var sh := float(rc[3]) * (H - 1)
			for poly in templates[String(st[1])]:
				var pts := []
				for v in poly:
					var u: Vector2 = Vector2(1.0 - v.x, v.y) if flip else v
					pts.append(Vector2i(int(round(ox + u.x * sw)), int(round(oy + u.y * sh))))
				_poly_cells(m, pts, true)
		"wave":
			var x0 := float(st[1][0])
			var y0 := float(st[1][1])
			var x1 := float(st[2])
			var amp := float(st[3])
			var per := float(st[4])
			var pts := []
			var steps := maxi(8, int((x1 - x0) * W))
			for k in steps + 1:
				var xf := lerpf(x0, x1, float(k) / steps)
				pts.append(_cellp([xf, y0 + amp * sin(TAU * (xf - x0) / per)]))
			_poly_cells(m, pts, false)


## Проходы в закрытых контурах: поиск в ширину, где пересечь стену стоит 1, пройти по свободной клетке — 0.
## Для каждой недостижимой области вскрывается кратчайший путь сквозь стены — минимум разрывов в линиях.
func _open_enclosed(m: PackedByteArray, vm: PackedByteArray) -> void:
	var n := W * H
	var s := start_cell.y * W + start_cell.x
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 30)
	var par := PackedInt32Array()
	par.resize(n)
	par.fill(-1)
	var buckets := [PackedInt32Array([s])]
	dist[s] = 0
	var d := 0
	while d < buckets.size():
		var b: PackedInt32Array = buckets[d]
		var i := 0
		while i < b.size():
			var v := b[i]
			i += 1
			if dist[v] != d:
				continue
			var vx := v % W
			for u in [v - 1, v + 1, v - W, v + W]:
				if u < 0 or u >= n or vm[u] == 1:
					continue
				if (u == v - 1 and vx == 0) or (u == v + 1 and vx == W - 1):
					continue
				var nd := d + (1 if m[u] == 2 else 0)
				if nd < dist[u]:
					dist[u] = nd
					par[u] = v
					if nd == d:
						b.append(u)
					else:
						while buckets.size() <= nd:
							buckets.append(PackedInt32Array())
						buckets[nd].append(u)
		d += 1
	var reach := PackedByteArray()
	reach.resize(n)
	reach.fill(0)
	_flood(m, vm, reach, s)
	for v in n:
		if m[v] != 0 or reach[v] == 1 or vm[v] == 1:
			continue
		var w := v
		while w >= 0 and reach[w] == 0:
			if m[w] == 2:
				# проход шириной 3 клетки: в щель в одну клетку шары попадали редко, отсеки расчищались долго
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var u := w + oy * W + ox
						if u >= 0 and u < W * H and vm[u] == 0 and absi((u % W) - (w % W)) <= 1:
							m[u] = 0 if m[u] == 2 else m[u]
			w = par[w]
		_flood(m, vm, reach, v)


func _flood(m: PackedByteArray, vm: PackedByteArray, reach: PackedByteArray, s: int) -> void:
	var n := W * H
	var q := PackedInt32Array([s])
	reach[s] = 1
	var i := 0
	while i < q.size():
		var v := q[i]
		i += 1
		var vx := v % W
		for u in [v - 1, v + 1, v - W, v + W]:
			if u < 0 or u >= n or reach[u] == 1 or m[u] != 0 or vm[u] == 1:
				continue
			if (u == v - 1 and vx == 0) or (u == v + 1 and vx == W - 1):
				continue
			reach[u] = 1
			q.append(u)


func _region(rx: int, ry: int):
	var key := ry * 1000003 + rx
	if region_cache.has(key):
		return region_cache[key]
	if has_meta("test_no_pictures"):   # только для теста «стены из сохранения не зависят от генератора»
		return null
	var res = null
	if map.has("pic"):
		if rx == 0 and ry == 0:
			res = _build_pic()
	elif map.has("scene"):
		if rx == 0 and ry == 0:
			res = _build_scene()
	elif map.has("fixed"):
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
				c.fog_dirty = true
				# клетка у края куска освещает туман соседнего куска — его тоже перерисовать
				if (xx & 31) <= 1 or (xx & 31) >= 30 or (yy & 31) <= 1 or (yy & 31) >= 30:
					for oy in range(-2, 3):
						for ox in range(-2, 3):
							var nx := xx + ox
							var ny := yy + oy
							if nx >= 0 and ny >= 0 and nx < W and ny < H:
								var ck2 := (nx >> 5) + (ny >> 5) * cw
								if ck2 != ck and chunks[ck2] != null and chunks[ck2].node != null:
									chunks[ck2].fog_dirty = true
									_mark(ck2)
				ex0 = mini(ex0, xx)
				ex1 = maxi(ex1, xx)
				ey0 = mini(ey0, yy)
				ey1 = maxi(ey1, yy)


# ================================================================ сохранение

func _save_path() -> String:
	return GameData.slot_dir() + "map_%s.bin" % String(map["id"])


func _load_state() -> float:
	var id := String(map["id"])
	if not GameData.map_states.has(id) or not FileAccess.file_exists(_save_path()):
		return 0.0
	var f := FileAccess.open(_save_path(), FileAccess.READ)
	if f == null:
		return 0.0
	var s = f.get_var()
	if typeof(s) != TYPE_DICTIONARY or int(s.get("ver", 0)) != 8 or int(s.get("w", 0)) != W:
		return 0.0
	coins = int(s.get("coins", s.get("rubles", 0)))   # до v0.14 ключ назывался "rubles"
	destroyed = int(s.get("destroyed", 0))
	goal_done = bool(s.get("goal_done", false))
	var c: Dictionary = s.get("counts", {})
	var tl: Dictionary = s.get("tracks", {})
	var ul: Dictionary = s.get("unl", {})
	for t in GameData.TYPE_ORDER:
		counts[t] = int(c.get(t, 0))
		var d: Dictionary = tl.get(t, {})
		for k in d:
			tlvl[t][String(k)] = int(d[k])
		unl[t] = t == "basic" or bool(ul.get(t, false))
		var ev: Dictionary = s.get("evo", {}).get(t, {})
		for k in ev:
			if not GameData.evo_def(t, String(k)).is_empty():
				evo[t][String(k)] = true
		var el: Dictionary = s.get("elvl", {}).get(t, {})
		for k in el:
			elvl[t][String(k)] = clampi(int(el[k]), 0, GameData.LADDER_MAX)
		extra[t] = maxi(0, int(s.get("extra", {}).get(t, 0)))
	if int(counts["basic"]) == 0:
		counts["basic"] = 1
	run_u = int(s.get("u", 0))
	play_time = maxf(0.0, float(s.get("time", 0.0)))
	shake_cd = clampf(float(s.get("shake_cd", 0.0)), 0.0, SHAKE_CD)
	var dt_saved: Dictionary = s.get("dmg_total", {})
	for t in GameData.TYPE_ORDER:
		dmg_total[t] = maxi(0, int(dt_saved.get(t, 0)))
	saved_balls = s.get("balls", [])
	var ll: Array = s.get("last_launch", [])
	if ll.size() == 2:
		last_launch = Vector2(ll[0], ll[1])
	aim_angle = float(s.get("aim", aim_angle))
	if unl.get(String(s.get("selected", "basic")), false):
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
		"ver": 8, "w": W, "coins": coins, "destroyed": destroyed, "goal_done": goal_done,
		"counts": counts.duplicate(), "tracks": tlvl.duplicate(true), "unl": unl.duplicate(),
		"evo": evo.duplicate(true), "elvl": elvl.duplicate(true), "extra": extra.duplicate(), "time": play_time, "shake_cd": shake_cd,
		"dmg_total": dmg_total.duplicate(),
		"saved_at": Time.get_unix_time_from_system(), "chunks": out,
		"balls": balls.map(func(b): return [b.type, b.pos.x, b.pos.y, b.vel.x, b.vel.y]),
		"last_launch": [last_launch.x, last_launch.y], "aim": aim_angle, "selected": selected,
		"u": run_u,
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
	GameData.map_states[String(map["id"])] = {"saved": true, "time": play_time}   # время — для меню
	GameData.save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and btn_reset != null:
		for bb in btn_reset.get_parent().get_children():
			if bb is Button:
				_fit_button_text.call_deferred(bb)   # язык сменился — подогнать надписи нижнего ряда заново
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_save_state()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if upg != null and upg.visible:
				_show_upgrades(false)
			else:
				_to_menu()


# ================================================================ характеристики

const MAX_SPEED := 50.0 * CELL      # предел скорости шара, px/с (у pixel-rikoshet — 300 кл/с; нам хватает 50)


func _tl(t: String, id: String) -> int:
	return int(tlvl[t].get(id, 0))


# ---------------------------------------------------------------- эволюции (за U уровня)

func _has_evo(t: String, id: String) -> bool:
	return evo[t].has(id)


func _el(t: String, track: String) -> int:
	return int(elvl[t].get(track, 0))


## Значение ветки эволюции: base + step·уровень (с нижним пределом min, если задан).
func _ev(t: String, track: String) -> float:
	var d := GameData.evo_track(t, track)
	var v := float(d["base"]) + float(d["step"]) * _el(t, track)
	if d.has("max"):
		v = minf(v, float(d["max"]))
	return maxf(v, float(d["min"])) if d.has("min") else v


## Первая эволюция стоит EVO_COST, вторая — вдвое дороже (как в pixel-rikoshet).
func _evo_cost(t: String) -> int:
	return GameData.EVO_COST * (GameData.EVO_LATER_MULT if evo[t].size() >= 1 else 1)


func _ladder_cost(t: String, track: String) -> int:
	return _el(t, track) + 1


func _ladder_maxed(t: String, track: String) -> bool:
	var lv := _el(t, track)
	if lv >= GameData.LADDER_MAX:
		return true
	var d := GameData.evo_track(t, track)
	var nxt := float(d["base"]) + float(d["step"]) * (lv + 1)
	if d.has("min") and nxt < float(d["min"]) - 0.001:
		return true
	if d.has("max") and float(d["base"]) + float(d["step"]) * lv >= float(d["max"]) - 0.001:
		return true
	if track == "sprint_cap" and _ev(t, track) >= MAX_SPEED / maxf(1.0, _speed("sniper")) - 1.0 - 0.001:
		return true   # разгон упирается в потолок скорости — больше предела толку нет
	# следующий уровень не меняет то, что видит игрок, — U не списываем
	return _ev_text(t, track, lv) == _ev_text(t, track, lv + 1)


func _buy_evo(t: String, id: String) -> void:
	if not unl[t] or _has_evo(t, id) or run_u < _evo_cost(t):
		return
	run_u -= _evo_cost(t)
	evo[t][id] = true
	Sfx.play("gold", 0.0)
	if id == "shotgun":
		_shotgun_split()   # каждый Гесиевый на поле сразу становится залпом
	_recalc_stats()
	_resync_speeds()
	_rebuild_rows()


func _buy_ladder(t: String, track: String) -> void:
	var eid := ""
	for e in GameData.EVOS[t]:
		for tr_ in e["tracks"]:
			if tr_["id"] == track:
				eid = e["id"]
	if eid == "" or not _has_evo(t, eid) or _ladder_maxed(t, track) or run_u < _ladder_cost(t, track):
		return
	run_u -= _ladder_cost(t, track)
	elvl[t][track] = _el(t, track) + 1
	Sfx.play("buy", 0.04)
	_recalc_stats()
	_resync_speeds()
	_refresh_ui()


## Залп Дробовика: 1 + целая часть «Шаров в залпе».
func _volley_size() -> int:
	return 1 + int(floor(_ev("sniper", "shotgun_balls"))) if _has_evo("sniper", "shotgun") else 1


func _shotgun_split() -> void:
	var add := _volley_size() - 1
	if add <= 0:
		return
	for b in balls.duplicate():
		if b.type == "sniper" and balls.size() < 3000:
			var base := rad_to_deg(b.vel.angle())
			for k in add:
				var off: float = (k + 1) * 9.0 * (1 if k % 2 == 0 else -1)
				_spawn_ball("sniper", base + off, b.pos)
				extra["sniper"] += 1


func _track_def(t: String, id: String) -> Dictionary:
	for tr_ in GameData.TYPES[t]["tracks"]:
		if tr_["id"] == id:
			return tr_
	return {}


## Цена уровня ветки: заданные цены, дальше каждая следующая ×1.7 (как в pixel-rikoshet), с потолком.
func _track_cost(t: String, id: String) -> int:
	var prices: Array = _track_def(t, id)["prices"]
	var lv := _tl(t, id)
	if lv < prices.size():
		return int(prices[lv])
	return _price(float(prices[-1]), 1.7, lv - prices.size() + 1)


func _track_value(t: String, id: String, lv := -1) -> float:
	var d := _track_def(t, id)
	return float(d["value"]) * (_tl(t, id) if lv < 0 else lv)


func _speed(t: String) -> float:
	var s := float(GameData.TYPES[t]["speed"]) * (1.0 + _track_value(t, "speed"))
	s *= 1.0 + 0.05 * int(fleet.get("speed", 0))
	return minf(s, MAX_SPEED)


## Прямой урон удара: база + «Сила удара», × «Наследие» × бонус стаи Знаменосца, + плоская прибавка Отбойника.
func _damage_of(t: String, lv := -1) -> int:
	var def: Dictionary = GameData.TYPES[t]
	if float(def["damage"]) <= 0.0:
		return 0   # Антониевый бьёт только ядом
	var d := float(def["damage"]) + (_track_value(t, "impact", lv) if not _track_def(t, "impact").is_empty() else 0.0)
	d *= GameData.dmg_mult() * (1.0 + 0.05 * int(fleet.get("damage", 0)))
	return maxi(1, int(round(d)) + int(fleet.get("flat", 0)))


func _poison_ticks(t := "poison") -> int:
	return int(GameData.TYPES["poison"]["poison_ticks"]) + int(_track_value("poison", "ticks"))


func _poison_rate() -> float:
	return float(GameData.TYPES["poison"]["poison_rate"]) + _track_value("poison", "cadence")


func _aura_radius() -> float:
	return (float(GameData.TYPES["banner"]["aura_radius"]) + _track_value("banner", "radius")) * CELL


func _aura_hold() -> float:
	return float(GameData.TYPES["banner"]["aura_hold"]) + _track_value("banner", "hold")


func _recalc_stats() -> void:
	for k in ["points", "speed", "splash", "poison", "damage", "flat"]:
		fleet[k] = 0
	for t in GameData.TYPE_ORDER:
		fleet[GameData.TYPES[t]["fleet"]] += GameData.fleet_steps(int(counts[t]))
	coin_mult = GameData.coin_mult() * (1.0 + 0.05 * int(fleet["points"]))
	for ti in GameData.TYPE_ORDER.size():
		var t: String = GameData.TYPE_ORDER[ti]
		st_dmg[ti] = _damage_of(t)
		st_share[ti] = float(GameData.TYPES[t].get("smash_share", 0.0)) + 0.05 * int(fleet["splash"])
		if t == "splash" and _has_evo(t, "area"):
			st_share[ti] += _ev(t, "area_share")


## Цена base·growth^n с потолком: без него на больших n float выходит за int64 и цена
## становится отрицательной (шар покупался бесплатно — найдено ревью v0.15).
const PRICE_CAP := 4.0e18


static func _price(base: float, growth: float, n: int) -> int:
	return int(minf(round(base * pow(growth, n)), PRICE_CAP))


## Цена пуска (как в pixel-rikoshet): (база + 5·n)·1.12ⁿ, n — сколько шаров типа уже куплено.
## Мягкий потолок около 60–70 шаров одного типа; основные монеты уходят в прокачку.
func _ball_cost(t: String) -> int:
	var n := int(counts[t])
	var p := minf(round((float(GameData.TYPES[t]["launch_base"]) + 5.0 * n) * pow(1.12, n)), PRICE_CAP)
	if t == "sniper" and _has_evo("sniper", "shotgun"):
		p *= 1.0 - minf(0.5, _ev("sniper", "shotgun_cheap"))   # «Массовое производство», не больше −50%
	return maxi(1, int(p))


# ================================================================ симуляция

func _spawn_ball(t: String, ang: float, at = null) -> void:
	var b = BallScript.new()
	b.type = t
	b.ti = t_idx[t]
	b.radius = float(GameData.TYPES[t]["radius"])
	b.pos = start_pos if at == null else at
	b.vel = Vector2.from_angle(deg_to_rad(ang)) * _speed(t)
	b.pos = _depenetrate(b, b.pos, false)   # пущен у самого угла стены — сразу наружу, иначе мог застрять
	balls.append(b)


func _sim(dt: float) -> void:
	time_acc += dt
	if finale:
		if bfs_busy:
			_finale_field_step()
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
	if highlight_t > 0.0:
		highlight_t = maxf(0.0, highlight_t - dt)
	aura_t -= dt
	if aura_t <= 0.0:
		aura_t = 0.1
		_update_aura()
	var sprint_on := _has_evo("sniper", "sprint")
	var zap_on := _has_evo("splash", "lightning")
	var grav_on := _has_evo("pierce", "gravity")
	var drill_on := _has_evo("pierce", "kleshch")
	for b in balls:
		if b.buff_t > 0.0:
			b.buff_t -= dt
		if sprint_on and b.type == "sniper":
			b.sprint = minf(_ev("sniper", "sprint_cap"), b.sprint + _ev("sniper", "sprint_rate") * dt)
		if zap_on and b.type == "splash":
			b.zap_t -= dt
			if b.zap_t <= 0.0:
				b.zap_t += 1.0 / maxf(0.05, _ev("splash", "lightning_rate"))
				_lightning(b)
		if b.type == "pierce":
			if drill_on and b.drill_id >= 0:
				_drill(b, dt)
			elif grav_on:
				b.gt_t -= dt
				if b.gt_t <= 0.0:
					b.gt_t = 0.5 + randf() * 0.1
					b.gtarget = _gravity_target(b)
		_move_ball(b, dt)
	if not zaps.is_empty():
		for z in zaps:
			z["t"] -= dt
		zaps = zaps.filter(func(z): return z["t"] > 0.0)
		overlay_dirty = true
	if not poisons.is_empty():
		_tick_poison(dt)
	for t in reset_cd:
		if reset_cd[t] > 0.0:
			reset_cd[t] = maxf(0.0, reset_cd[t] - dt)
	if shake_cd > 0.0:
		shake_cd = maxf(0.0, shake_cd - dt)


## Выталкивание: если шар перекрывает стену или квадрат (пущен у самого угла, сдвинут «Встряской» и т. п.),
## сдвигаем центр наружу от ближайшей точки клетки. Клетки, сквозь которые Отбойник проходит намеренно, не трогаем.
func _depenetrate(b, p: Vector2, pierce: bool) -> Vector2:
	var r: float = b.radius
	# быстрый выход: шар в пустом куске и не задевает его границу — перекрывать нечего (так почти всегда)
	var gx := int(p.x * INV)
	var gy := int(p.y * INV)
	if gx < 0 or gy < 0 or gx >= W or gy >= H:
		return p
	var c0 = chunks[(gx >> 5) + (gy >> 5) * cw]
	if c0 != null and c0.solid == 0:
		var bx0 := float((gx >> 5) << 5) * CELL
		var by0 := float((gy >> 5) << 5) * CELL
		if p.x - r > bx0 and p.x + r < bx0 + CPX and p.y - r > by0 and p.y + r < by0 + CPX:
			return p
	# быстрый выход: шар целиком внутри своей свободной клетки
	var fx := p.x - gx * CELL
	var fy := p.y - gy * CELL
	if fx >= r and fx <= CELL - r and fy >= r and fy <= CELL - r and c0 != null \
			and c0.kind[((gy & 31) << 5) | (gx & 31)] == 0:
		return p
	for pass_i in 2:
		var moved := false
		var x0 := maxi(0, int((p.x - r) * INV))
		var x1 := mini(W - 1, int((p.x + r) * INV))
		var y0 := maxi(0, int((p.y - r) * INV))
		var y1 := mini(H - 1, int((p.y + r) * INV))
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				var k := _kind_at(cx, cy)
				if k != 1 and k != 2:
					continue
				var id := cy * W + cx
				if pierce and b.recent.has(id) and time_acc - float(b.recent[id]) < 0.3:
					continue
				var q := Vector2(clampf(p.x, cx * CELL, cx * CELL + CELL), clampf(p.y, cy * CELL, cy * CELL + CELL))
				var v := p - q
				var dl := v.length()
				if dl >= r:
					continue
				if dl > 1e-4:
					p += v / dl * (r - dl + 0.05)
				else:
					# центр внутри клетки — к ближайшей грани
					var c := (Vector2(cx, cy) + Vector2(0.5, 0.5)) * CELL
					var o := p - c
					if absf(o.x) >= absf(o.y):
						p.x = c.x + signf(o.x if o.x != 0.0 else 1.0) * (CELL * 0.5 + r + 0.05)
					else:
						p.y = c.y + signf(o.y if o.y != 0.0 else 1.0) * (CELL * 0.5 + r + 0.05)
				moved = true
		if not moved:
			break
	return p


## Клещ: бурит клетку со скоростью «Хватки» (ударов в секунду). Пробил — «Глубже» ведёт дальше по линии,
## иначе шар отскакивает обратно; клетки, разбитые с одного удара, в счёт «Глубже» не идут.
func _drill(b, dt: float) -> void:
	if _hp_of(b.drill_id) <= 0:
		_drill_done(b)
		return
	b.drill_acc += _ev("pierce", "kleshch_grip") * dt
	while b.drill_acc >= 1.0 and b.drill_id >= 0:
		b.drill_acc -= 1.0
		var mult: float = (2.0 if frenzy_t > 0.0 else 1.0) * ((1.0 + b.buff) if b.buff_t > 0.0 else 1.0)
		_damage(b.drill_id, maxi(1, int(round(st_dmg[b.ti] * mult))), b)
		if _hp_of(b.drill_id) <= 0:
			_drill_done(b)


func _drill_done(b) -> void:
	b.drill_id = -1
	if b.deeper_left > 0:
		b.deeper_left -= 1
		b.vel = b.drill_vel            # «Глубже»: дальше по той же линии
	else:
		b.deeper_left = int(_ev("pierce", "kleshch_deeper"))
		b.vel = -b.drill_vel           # обычный отскок назад из тоннеля


## Аура Знаменосца: шары в круге получают бафф урона и держат его _aura_hold() секунд.
## Поиск через сетку с шагом в радиус ауры — без перебора «каждый с каждым». Знаменосцы друг друга не усиливают.
func _update_aura() -> void:
	if int(counts.get("banner", 0)) == 0:
		return
	var r := _aura_radius()
	if _has_evo("banner", "war_banner"):
		var period := _ev("banner", "war_banner_cry")
		if fmod(time_acc, period) < 1.0:
			r *= 2.0   # боевой клич: на секунду круг вдвое шире (у всех Знаменосцев одновременно)
	aura_r_now = r
	var r2 := r * r
	var inv := 1.0 / r
	var grid := {}
	for bn in balls:
		if bn.type == "banner":
			var k := Vector2i(int(floor(bn.pos.x * inv)), int(floor(bn.pos.y * inv)))
			if not grid.has(k):
				grid[k] = []
			grid[k].append(bn)
	if grid.is_empty():
		return
	var hold := _aura_hold()
	var bonus := float(GameData.TYPES["banner"]["aura_bonus"])
	if _has_evo("banner", "war_banner"):
		bonus += _ev("banner", "war_banner_damage")
	var sbonus := _ev("banner", "tailwind_speed") if _has_evo("banner", "tailwind") else 0.0
	var self_share := _ev("banner", "tailwind_self") if _has_evo("banner", "tailwind") else 0.0
	for b in balls:
		if b.type == "banner":
			if self_share > 0.0:
				b.buff_t = hold
				b.buff = bonus * minf(1.0, self_share)
				b.spd_buff = sbonus * minf(1.0, self_share)
			continue
		var k := Vector2i(int(floor(b.pos.x * inv)), int(floor(b.pos.y * inv)))
		var hit := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for bn in grid.get(k + Vector2i(dx, dy), []):
					if bn.pos.distance_squared_to(b.pos) <= r2:
						hit = true
						break
				if hit:
					break
			if hit:
				break
		if hit:
			b.buff_t = hold
			b.buff = bonus
			b.spd_buff = sbonus


func _process(delta: float) -> void:
	if not completed:
		play_time += delta   # реальное время игры на уровне (в свёрнутом виде _process не идёт)
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
	var active := sling or press_pending or not popups.is_empty() or not zaps.is_empty()
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
	if b.drill_id >= 0:
		return   # Клещ бурит — стоит на месте (см. _sim)
	var p: Vector2 = b.pos
	var speed: float = b.vel.length()
	if speed <= 0.0:
		return
	var d: Vector2 = b.vel / speed
	# Гравитация: доворот к цели с ускорением «Тяги»
	if b.gtarget.x >= 0.0:
		var to: Vector2 = b.gtarget - p
		if to.length_squared() > 1.0:
			d = (d * speed + to.normalized() * _ev("pierce", "gravity_force") * delta).normalized()
	# Спринтер и Попутный ветер ускоряют полёт (без изменения базовой скорости шара)
	var mult: float = 1.0 + b.sprint + (b.spd_buff if b.buff_t > 0.0 else 0.0)
	var dist := minf(speed * mult, MAX_SPEED) * delta
	var r: float = b.radius
	var wx0 := r
	var wy0 := r
	var wx1 := wpx - r
	var wy1 := hpx - r
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
						# уже внутри — нормаль по геометрии (от ближайшей точки клетки к центру шара), а не по
						# направлению движения: иначе «движемся внутрь» выходило всегда, и шар у угла застревал
						var q := Vector2(clampf(p.x, lx + r, hx - r), clampf(p.y, ly + r, hy - r))
						var gn := p - q
						if gn.length_squared() < 1e-8:
							continue
						if d.dot(gn) >= 0.0:
							continue   # выходим из клетки — не мешаем
						if absf(gn.x) >= absf(gn.y):
							nx = signf(gn.x)
							ny = 0.0
						else:
							nx = 0.0
							ny = signf(gn.y)
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
				p = _depenetrate(b, p, pierce)   # топчется на месте — значит, перекрыл клетку: выталкиваем
				break
		else:
			stalls = 0
		if hit >= 0:
			b.pos = p
			b.vel = d * speed
			_hit_cell(b, hit)
			if b.drill_id >= 0:
				b.drill_vel = d * speed   # направление до отскока: после пробоя Клещ может идти «Глубже»
				b.vel = d * speed
				return
		if bnx != 0.0:
			d.x = -d.x
		if bny != 0.0:
			d.y = -d.y
		p += Vector2(bnx, bny) * 0.02
		if finale:
			pass   # в финале шары ведёт поле расстояний (см. _sim)
	b.pos = p
	b.vel = d * speed
	if b.recent.size() > 40:
		b.recent.clear()


## Удар шара по клетке. Антониевый не бьёт, только отравляет. Остальные: прямой урон (× лихорадка,
## × бафф Знаменосца), удар по открытым соседям (Никитиевый 25% + бонус стаи всем) и яд от бонуса стаи.
func _hit_cell(b, id: int) -> void:
	Sfx.play("hit", 0.15)
	b.sprint = 0.0   # Спринтер: удар по породе сбрасывает разгон
	if b.type == "poison":
		_apply_poison(id, _poison_ticks(), b)
		if _has_evo("poison", "infection"):
			_infect(id, int(poison_hops.get(id, 0)), b)   # при каждом ударе, даже если клетка выдержала
		return
	var ti: int = b.ti
	var mult: float = (2.0 if frenzy_t > 0.0 else 1.0) * ((1.0 + b.buff) if b.buff_t > 0.0 else 1.0)
	var dmg := maxi(1, int(round(st_dmg[ti] * mult)))
	_damage(id, dmg, b)
	var share: float = st_share[ti]
	if share > 0.0:
		var rad := int(GameData.TYPES[b.type].get("smash_radius", 1))
		if b.type == "splash" and _has_evo("splash", "area"):
			rad = int(_ev("splash", "area_radius"))
		_smash(id, dmg * share, rad, b)
	if b.type == "basic":
		if _has_evo("basic", "scout"):
			_scout(id)
		if _has_evo("basic", "stitch"):
			_stitch(id, dmg, b)
	if b.type == "pierce" and _has_evo("pierce", "kleshch") and _hp_of(id) > 0:
		b.drill_id = id   # Клещ: не разбил с удара — впивается и бурит (см. _move_ball и _sim)
		b.drill_acc = 0.0
	var ps := 0.05 * int(fleet.get("poison", 0))
	if ps > 0.0 and _hp_of(id) > 0:
		var ticks := _prob_round(dmg * ps)
		if ticks > 0:
			_apply_poison(id, ticks, b)


## Дробное число → целое со случайным округлением (в среднем точно): 0.3 → 1 с шансом 30%.
func _prob_round(x: float) -> int:
	var i := int(floor(x))
	return i + (1 if randf() < x - i else 0)


## Разведка: удар открывает туман вокруг клетки (радиус растёт с веткой).
func _scout(id: int) -> void:
	var r := int(_ev("basic", "scout_radius"))
	var cx := id % W
	@warning_ignore("integer_division")
	var cy := id / W
	for yy in range(maxi(0, cy - r), mini(H - 1, cy + r) + 1):
		for xx in range(maxi(0, cx - r), mini(W - 1, cx + r) + 1):
			if (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) <= r * r and not _vis_at(xx, yy):
				_reveal(xx, yy)


## Прошивка: клетки за целью по линии полёта получают долю силы; линию обрывают стена и край карты.
func _stitch(id: int, dmg: int, b) -> void:
	var d: Vector2 = b.vel.normalized()
	if d == Vector2.ZERO:
		return
	@warning_ignore("integer_division")
	var c := (Vector2(id % W, id / W) + Vector2(0.5, 0.5)) * CELL
	var depth := int(_ev("basic", "stitch_depth"))
	var amount := dmg * _ev("basic", "stitch_share")
	var last := id
	var k := 1
	var steps := 0
	while k <= depth and steps < depth * 3:
		steps += 1
		var p := c + d * CELL * 0.75 * steps
		var x := int(p.x * INV)
		var y := int(p.y * INV)
		if x < 0 or y < 0 or x >= W or y >= H:
			return
		var nid := y * W + x
		if nid == last:
			continue
		last = nid
		var kind := _kind_at(x, y)
		if kind == 2:
			return
		if kind == 1:
			var a := _prob_round(amount)
			if a > 0:
				if not _vis_at(x, y):
					_reveal(x, y)
				_damage(nid, a, b)
		k += 1


## Инфекция: яд переходит на соседей. Шанс падает за каждый переход («Затухание» уменьшает потерю);
## каждые полные 100% — один сосед наверняка, остаток — шанс ещё на одного. Только чистые клетки.
func _infect(id: int, hops: int, b) -> void:
	var loss := 0.10 * pow(0.8, _el("poison", "infection_fade"))
	var chance := _ev("poison", "infection_chance") - loss * hops
	if chance <= 0.0:
		return
	var n := _prob_round(chance)
	if n <= 0:
		return
	var cx := id % W
	@warning_ignore("integer_division")
	var cy := id / W
	var cand := []
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var x: int = cx + o.x
		var y: int = cy + o.y
		if x >= 0 and y >= 0 and x < W and y < H and _kind_at(x, y) == 1 and not poisons.has(y * W + x):
			cand.append(y * W + x)
	cand.shuffle()
	for k in mini(n, cand.size()):
		poison_hops[cand[k]] = hops + 1
		_apply_poison(cand[k], _poison_ticks(), b)


## Молния: разряд бьёт всю открытую породу в радиусе (стены заслоняют) на четверть базовой силы удара.
func _lightning(b) -> void:
	var r := int(_ev("splash", "lightning_range"))
	var base := float(GameData.TYPES["splash"]["damage"]) + _track_value("splash", "impact")
	var amount := 0.25 * base
	var cx := int(b.pos.x * INV)
	var cy := int(b.pos.y * INV)
	var targets := PackedVector2Array()
	for yy in range(maxi(0, cy - r), mini(H - 1, cy + r) + 1):
		for xx in range(maxi(0, cx - r), mini(W - 1, cx + r) + 1):
			if (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) > r * r:
				continue
			if _kind_at(xx, yy) != 1 or not _vis_at(xx, yy):
				continue
			var tc := (Vector2(xx, yy) + Vector2(0.5, 0.5)) * CELL
			if not _clear_line(b.pos, tc):
				continue
			var a := _prob_round(amount)
			if a > 0:
				_damage(yy * W + xx, a, b)
				targets.append(tc)
	if not targets.is_empty() and zaps.size() < 24:
		zaps.append(_make_zap(b.pos, targets))
		overlay_dirty = true


## Анимация разряда: ломаные молнии от шара к поражённым клеткам (до ZAP_BOLTS, остальным — искры).
## Изломы считаются один раз — пока разряд гаснет, молния не «дрожит».
const ZAP_TIME := 0.28
const ZAP_BOLTS := 12


func _make_zap(from: Vector2, targets: PackedVector2Array) -> Dictionary:
	var order := range(targets.size())
	order.shuffle()
	var bolts := []
	var sparks := PackedVector2Array()
	for k in order.size():
		var tgt: Vector2 = targets[order[k]]
		if k < ZAP_BOLTS:
			var pts := PackedVector2Array([from])
			var d := tgt - from
			var n := clampi(int(d.length() / (CELL * 0.8)), 3, 10)
			var side := d.orthogonal().normalized()
			for i in range(1, n):
				var f := float(i) / n
				pts.append(from + d * f + side * randf_range(-0.35, 0.35) * CELL)
			pts.append(tgt)
			bolts.append(pts)
		sparks.append(tgt)
	return {"bolts": bolts, "sparks": sparks, "t": ZAP_TIME}


## Нет ли стены между двумя точками (проверка по клеткам с шагом в полклетки).
func _clear_line(a: Vector2, c: Vector2) -> bool:
	var n := int(a.distance_to(c) / (CELL * 0.5)) + 1
	for k in range(1, n):
		var p := a.lerp(c, float(k) / n)
		if _kind_at(int(p.x * INV), int(p.y * INV)) == 2:
			return false
	return true


## Гравитация: цель — самая крепкая видимая клетка породы в радиусе (при равенстве — ближняя), не за стеной.
func _gravity_target(b) -> Vector2:
	var r := int(_ev("pierce", "gravity_range"))
	var cx := int(b.pos.x * INV)
	var cy := int(b.pos.y * INV)
	var best := -1
	var best_hp := 0
	var best_d := 1 << 30
	for yy in range(maxi(0, cy - r), mini(H - 1, cy + r) + 1):
		for xx in range(maxi(0, cx - r), mini(W - 1, cx + r) + 1):
			var d2 := (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy)
			if d2 > r * r or _kind_at(xx, yy) != 1 or not _vis_at(xx, yy):
				continue
			var h := _hp_of(yy * W + xx)
			if h > best_hp or (h == best_hp and d2 < best_d):
				best = yy * W + xx
				best_hp = h
				best_d = d2
	if best < 0:
		return Vector2(-1, -1)
	@warning_ignore("integer_division")
	var tc := (Vector2(best % W, best / W) + Vector2(0.5, 0.5)) * CELL
	return tc if _clear_line(b.pos, tc) else Vector2(-1, -1)


## Статистика шаров: весь урон типа за уровень и урон по секундам за последние DPS_WINDOW секунд.
func _count_damage(t: String, dealt: int) -> void:
	_advance_dps()
	dmg_total[t] = int(dmg_total[t]) + dealt
	var wb: PackedFloat32Array = dmg_win[t]
	wb[dmg_sec % DPS_WINDOW] += dealt
	dmg_win[t] = wb


## Сдвигает кольцо корзин до текущей секунды: устаревшие секунды обнуляются.
func _advance_dps() -> void:
	var cur := int(time_acc)
	if cur - dmg_sec >= DPS_WINDOW:
		for t in dmg_win:
			var z := PackedFloat32Array()
			z.resize(DPS_WINDOW)
			dmg_win[t] = z
		dmg_sec = cur
		return
	while dmg_sec < cur:
		dmg_sec += 1
		for t in dmg_win:
			var wb: PackedFloat32Array = dmg_win[t]
			wb[dmg_sec % DPS_WINDOW] = 0.0
			dmg_win[t] = wb


## Средний урон в секунду за последние DPS_WINDOW секунд (в начале уровня — за прошедшее время).
func _dps(t: String) -> float:
	_advance_dps()
	var sum := 0.0
	for v in dmg_win[t]:
		sum += v
	return sum / clampf(time_acc, 1.0, float(DPS_WINDOW))


## Удар по открытым разрушаемым клеткам вокруг (радиус по Чебышёву), каждой — доля силы.
func _smash(id: int, amount: float, rad: int, b) -> void:
	var cx := id % W
	@warning_ignore("integer_division")
	var cy := id / W
	for yy in range(maxi(0, cy - rad), mini(H - 1, cy + rad) + 1):
		for xx in range(maxi(0, cx - rad), mini(W - 1, cx + rad) + 1):
			if (xx != cx or yy != cy) and _vis_at(xx, yy):
				var a := _prob_round(amount)
				if a > 0:
					_damage(yy * W + xx, a, b)


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
	if _has_evo("poison", "corrosion") and (poisons.has(id) or float(corr_until.get(id, -1.0)) > time_acc):
		amount = _prob_round(amount * (1.0 + _ev("poison", "corrosion_bonus")))   # Разъедание
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
		_count_damage(b.type, dealt)
	_mark(ck)
	if h - dealt <= 0:
		Sfx.play("break", 0.12)
		c.kind[li] = 0
		c.solid -= 1
		destroyed += 1
		alive -= 1
		if finale and finale_pass.size() == W * H:
			finale_pass[id] = 1   # разбитая клетка стала проходом для поля расстояний
		_on_destroyed(x, y, id)


func _on_destroyed(x: int, y: int, id: int) -> void:
	_reveal(x, y)
	# U-баллы спрятаны в части квадратов (в полостях картинок — чаще)
	var ppm := u_ppm * (2 if _mask_at(x, y) == 4 else 1)   # в полостях картинок — вдвое чаще
	if _hash3(x, y, seed_i + 7) % 1000000 < ppm:
		run_u += 1
		if _has_evo("basic", "scout"):
			run_u += _prob_round(_ev("basic", "scout_find"))   # Находка: каждые 100% — ещё U наверняка
		Sfx.play("u", 0.03)
		popups.append({"pos": (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL, "text": "+1 U", "t": 1.5})
		overlay_dirty = true
	var c = chunks[(x >> 5) + (y >> 5) * cw]
	var li := ((y & 31) << 5) | (x & 31)
	if c.gold[li] == 1:
		c.gold[li] = 0
		frenzy_t = minf(maxf(frenzy_t, 0.0) + frenzy_time, frenzy_time * 2.0)   # копится, но не больше двух
		frenzy_max = maxf(frenzy_t, frenzy_time)
		popups.append({"pos": (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL, "text": "×2!", "t": 1.5})
		Sfx.play("gold", 0.0)
	if poisons.has(id):
		if _has_evo("poison", "infection"):
			_infect(id, int(poison_hops.get(id, 0)), poisons[id]["ball"])   # кем бы ни была добита
		poisons.erase(id)
	poison_hops.erase(id)
	corr_until.erase(id)


## Яд (как в pixel-rikoshet): клетка считает оставшиеся тики; каждый удар прибавляет тики,
## урон и частоту тика задаёт первый отравивший. Тик снимает 1 HP (× «Наследие», × лихорадка).
func _apply_poison(id: int, ticks: int, b) -> void:
	if poisons.has(id):
		poisons[id]["left"] += ticks
	else:
		poisons[id] = {"left": ticks, "acc": 0.0, "rate": _poison_rate(), "ball": b,
			"dmg": maxi(1, int(round(GameData.dmg_mult())))}
		_mark_cell(id)


func _tick_poison(dt: float) -> void:
	for id in poisons.keys():
		if not poisons.has(id):
			continue
		var p: Dictionary = poisons[id]
		p["acc"] += p["rate"] * dt
		while p["acc"] >= 1.0 and p["left"] > 0 and poisons.has(id):
			p["acc"] -= 1.0
			p["left"] -= 1
			_damage(id, int(p["dmg"]) * (2 if frenzy_t > 0.0 else 1), p["ball"])
		if poisons.has(id) and (p["left"] <= 0 or _hp_of(id) <= 0):
			poisons.erase(id)
			if _has_evo("poison", "corrosion") and _el("poison", "corrosion_linger") > 0:
				corr_until[id] = time_acc + _ev("poison", "corrosion_linger")
			_mark_cell(id)


## Финал маленькой карты: последние ≤8% квадратов подсвечиваются, шары летят к ним сами —
## без этого последние минуты уходили на поиск разрозненных квадратов (симулятор баланса v0.16).
func _start_finale() -> void:
	finale = true
	finale_ids = PackedInt32Array()
	finale_pass.resize(W * H)
	finale_pass.fill(0)
	for ck in chunks.size():
		var c = chunks[ck]
		if c == null:
			c = _get_chunk(ck)   # большая карта: досоздаём ещё не открытые куски — там тоже остались квадраты
		var ox: int = (ck % cw) * CS
		@warning_ignore("integer_division")
		var oy: int = (ck / cw) * CS
		for li in CS * CS:
			if c.kind[li] == 0:
				var px := ox + (li & 31)
				var py := oy + (li >> 5)
				if px < W and py < H:
					finale_pass[py * W + px] = 1
		if c.solid == 0:
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
## (наведение «по прямой» не находило квадраты в выемках картинок). Считается порциями по BFS_BUDGET клеток
## за кадр; готовое поле подменяет старое — на большой карте нет паузы на полный обход.
func _finale_field() -> void:
	if bfs_busy:
		return
	bfs_dist.resize(W * H)
	bfs_dist.fill(1 << 30)
	bfs_q = PackedInt32Array()
	var live := PackedInt32Array()
	for id in finale_ids:
		if _hp_of(id) > 0:
			live.append(id)
			bfs_dist[id] = 0
			bfs_q.append(id)
	finale_ids = live
	bfs_head = 0
	bfs_busy = true
	_finale_field_step()


func _finale_field_step() -> void:
	var budget := BFS_BUDGET
	var n := W * H
	while bfs_head < bfs_q.size() and budget > 0:
		budget -= 1
		var id := bfs_q[bfs_head]
		bfs_head += 1
		var x := id % W
		var nd := bfs_dist[id] + 1
		for j in [id - 1 if x > 0 else -1, id + 1 if x < W - 1 else -1, id - W, id + W]:
			if j < 0 or j >= n or bfs_dist[j] <= nd or finale_pass[j] == 0:
				continue
			bfs_dist[j] = nd
			bfs_q.append(j)
	if bfs_head >= bfs_q.size():
		finale_dist = bfs_dist.duplicate()
		bfs_busy = false


func _finale_steer(b) -> void:
	var cx := int(b.pos.x * INV)
	var cy := int(b.pos.y * INV)
	if cx < 0 or cy < 0 or cx >= W or cy >= H or finale_dist.size() != W * H:
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
	if full_tracked and not finale and alive > 0:
		var lim := maxi(12, int(total * FINALE_SHARE)) if track_all \
			else maxi(12, mini(FINALE_BIG_MAX, int(total * FINALE_BIG_SHARE)))
		if alive <= lim:
			_start_finale()

	if not goal_done and destroyed >= goal:
		goal_done = true
		var id := String(map["id"])
		var gained := GameData.stars_for(map_index, not GameData.maps_done.has(id))
		GameData.stars += gained
		GameData.maps_done[id] = true
		GameData.record_completion(id, play_time)
		GameData.maps_unlocked = maxi(GameData.maps_unlocked, map_index + 2)
		GameData.save_game()
		if not (track_all and alive <= 0):
			Sfx.play("goal", 0.0)
			var msg: String = tr("Цель уровня выполнена!\n+%d ★, открыт следующий уровень") % gained + "\n" + \
				tr("Время: %s") % GameData.fmt_time(play_time)
			if full_tracked and not track_all:
				# на большой карте можно идти дальше — за полную расчистку ещё ★
				msg += "\n" + tr("Расчистите карту целиком — ещё +%d ★") % GameData.stars_for(map_index, not GameData.maps_full.has(id))
			_show_toast(msg)
	if full_tracked and alive <= 0 and not completed:
		completed = true
		var bonus := ""
		if not track_all:
			# большая карта расчищена целиком — награда ★ (первый раз как за цель, потом +1)
			var fid := String(map["id"])
			var fg := GameData.stars_for(map_index, not GameData.maps_full.has(fid))
			GameData.stars += fg
			GameData.maps_full[fid] = true
			bonus = "\n+%d ★" % fg
			Sfx.play("goal", 0.0)
		GameData.map_states.erase(String(map["id"]))
		DirAccess.remove_absolute(_save_path())
		GameData.save_game()
		var d := AcceptDialog.new()
		d.title = tr("Победа!")
		d.dialog_text = tr("Карта «%s» разбита полностью!") % Maps.title(map, tr) + bonus
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
	var ar := aura_r_now if aura_r_now > 0.0 else _aura_radius()   # с боевым кличем круг шире
	var hl := highlight_t > 0.0
	# «Вернуть шар» включён — пульсирует шар, который вернётся (бездельник выбранного типа)
	var idle_b = _idler(selected) if reset_armed else null
	var pulse := 0.5 + 0.5 * sin(time_acc * 7.0)
	var hcol := Color(1, 1, 1, clampf(highlight_t / HIGHLIGHT_TIME, 0.0, 1.0))
	for b in balls:
		var dd: float = maxf(b.radius * 2.6, min_d)
		if b.type == "pierce":
			dd *= 1.25   # Отбойник крупнее — различим даже в точку
		if b.type == "sniper":
			# шлейф Гесиевого — против направления полёта, виден и при отдалении
			var back: Vector2 = -b.vel.normalized() if b.vel.length_squared() > 1.0 else Vector2.ZERO
			if back != Vector2.ZERO:
				var side := Vector2(-back.y, back.x) * dd * 0.18
				var c1: Color = colors["sniper"]
				c1.a = 0.55
				var c2: Color = colors["sniper"]
				c2.a = 0.3
				ball_layer.draw_line(b.pos + back * dd * 0.45 + side, b.pos + back * dd * 1.5 + side, c1, dd * 0.2)
				ball_layer.draw_line(b.pos + back * dd * 0.45 - side, b.pos + back * dd * 1.2 - side, c2, dd * 0.2)
		var big := dd * Icons.BALL_K
		if b.type == "poison" and b.vel.length_squared() > 1.0:
			# капля Антониевого — кончиком против полёта, как шлейф у Гесиевого
			ball_layer.draw_set_transform(b.pos, _drop_rot(b.vel), Vector2.ONE)
			ball_layer.draw_texture_rect(ball_icons[b.type], Rect2(-big * 0.5, -big * 0.5, big, big), false)
			ball_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			ball_layer.draw_texture_rect(ball_icons[b.type], Rect2(b.pos.x - big * 0.5, b.pos.y - big * 0.5, big, big), false)
		if b == idle_b:
			ball_layer.draw_arc(b.pos, dd * (0.9 + 0.35 * pulse), 0.0, TAU, 28, Color(0.45, 0.85, 1.0, 0.95 - 0.5 * pulse), maxf(2.0, 3.5 / zoom))
		if hl and b.type == highlight_type:
			ball_layer.draw_arc(b.pos, dd * 0.85, 0.0, TAU, 24, hcol, maxf(2.0, 3.0 / zoom))
		if b.type == "banner":
			# круг ауры виден при любом масштабе: лёгкая заливка и чёткий контур; при боевом кличе — ярче
			var cry: bool = ar > _aura_radius() * 1.5
			var fill: Color = colors["banner"]
			fill.a = 0.12 if cry else 0.07
			var ring: Color = colors["banner"]
			ring.a = 0.85 if cry else 0.55
			ball_layer.draw_circle(b.pos, ar, fill)
			ball_layer.draw_arc(b.pos, ar, 0.0, TAU, 48, ring, maxf(1.5, 2.5 / zoom))


## Поворот текстуры капли: её кончик (вверх, −Y) должен смотреть против полёта.
static func _drop_rot(vel: Vector2) -> float:
	return (-vel).angle() + PI * 0.5


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
	if lod <= 1:
		if c.fog_dirty:
			_build_fog_edge(c, vis, x0, y0, gw, gh)
		if not c.fog_idx.is_empty():
			RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), c.fog_idx, c.fog_pts, c.fog_cols)
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
		if kind[li] != 2:
			continue
		var lx := li & 31
		var ly := li >> 5
		var gx := x0 + lx
		var gy := y0 + ly
		var px := lx * CELL
		var py := ly * CELL
		if has_shape and _void_at(gx, gy):
			n.draw_rect(Rect2(px, py, CELL, CELL), OUTSIDE)   # за формой карты — фон, а не стена
			continue
		if vis[li] == 0:
			continue
		if not detail:
			n.draw_rect(Rect2(px, py, CELL, CELL), WALL_FACE)
			continue
		var up := _kind_at(gx, gy - 1) == 2 and not _void_at(gx, gy - 1)
		var dn := _kind_at(gx, gy + 1) == 2 and not _void_at(gx, gy + 1)
		var lf := _kind_at(gx - 1, gy) == 2 and not _void_at(gx - 1, gy)
		var rt := _kind_at(gx + 1, gy) == 2 and not _void_at(gx + 1, gy)
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


## Мягкий край тумана: скрытые клетки у границы освещены градиентом на 2 клетки — со стороны открытых
## клеток светлее, дальше плавно уходят в темноту (вместо резкой ступеньки). Что внутри — не видно.
## Свет считается в вершинах сетки по расстоянию до открытых клеток; весь край куска — один массив
## треугольников (одна команда отрисовки), без триангуляции на каждую клетку.
func _build_fog_edge(c, vis: PackedByteArray, x0: int, y0: int, gw: int, gh: int) -> void:
	c.fog_dirty = false
	fog_builds += 1
	# видимость клеток куска с полем в 2 клетки вокруг (соседние куски)
	var m := 2
	var ew := gw + 2 * m
	var eh := gh + 2 * m
	var ev := PackedByteArray()
	ev.resize(ew * eh)
	for ey in eh:
		for ex in ew:
			ev[ey * ew + ex] = 1 if _vis_local(vis, x0, y0, ex - m, ey - m) else 0
	# вершины (gw+1)×(gh+1): 0 — касается открытой клетки, 1 — рядом с такой вершиной, 2 — темно
	var vw := gw + 3
	var vh := gh + 3
	var vd := PackedByteArray()
	vd.resize(vw * vh)
	vd.fill(2)
	for vy in vh:
		for vx in vw:
			# вершина (vx-1, vy-1) в координатах куска; клетки вокруг неё в ev — со сдвигом m
			var cx := vx - 1 + m
			var cy := vy - 1 + m
			if ev[(cy - 1) * ew + cx - 1] == 1 or ev[(cy - 1) * ew + cx] == 1 or ev[cy * ew + cx - 1] == 1 or ev[cy * ew + cx] == 1:
				vd[vy * vw + vx] = 0
	for vy in range(1, vh - 1):
		for vx in range(1, vw - 1):
			if vd[vy * vw + vx] == 0:
				continue
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if vd[(vy + oy) * vw + vx + ox] == 0:
						vd[vy * vw + vx] = 1
	var lit := [FOG_EDGE, FOG_EDGE * 0.35, 0.0]
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for ly in gh:
		for lx in gw:
			if vis[(ly << 5) | lx] == 1 or (has_shape and _void_at(x0 + lx, y0 + ly)):
				continue
			var a0: int = vd[(ly + 1) * vw + lx + 1]
			var a1: int = vd[(ly + 1) * vw + lx + 2]
			var a2: int = vd[(ly + 2) * vw + lx + 2]
			var a3: int = vd[(ly + 2) * vw + lx + 1]
			if a0 == 2 and a1 == 2 and a2 == 2 and a3 == 2:
				continue
			var base := pts.size()
			var px := lx * CELL
			var py := ly * CELL
			pts.append_array([Vector2(px, py), Vector2(px + CELL, py), Vector2(px + CELL, py + CELL), Vector2(px, py + CELL)])
			cols.append_array([_fog_col(lit[a0]), _fog_col(lit[a1]), _fog_col(lit[a2]), _fog_col(lit[a3])])
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	c.fog_pts = pts
	c.fog_cols = cols
	c.fog_idx = idx


func _fog_col(a: float) -> Color:
	return Color(floor_col.r, floor_col.g, floor_col.b, a)


## Видна ли клетка: внутри куска — по его массиву (быстро), за краем куска — через соседний кусок.
func _vis_local(vis: PackedByteArray, x0: int, y0: int, lx: int, ly: int) -> bool:
	if lx >= 0 and ly >= 0 and lx < CS and ly < CS:
		return vis[(ly << 5) | lx] == 1
	return _vis_at(x0 + lx, y0 + ly)


func _build_chunk_tex(c) -> void:
	var img := Image.create(CS, CS, false, Image.FORMAT_RGBA8)
	for li in CS * CS:
		var col := Color(0, 0, 0, 0)
		if has_shape and c.kind[li] == 2 and _void_at(c.ox + (li & 31), c.oy + (li >> 5)):
			col = OUTSIDE
		elif c.vis[li] == 1:
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
	if has_shape:
		if _ext_idx.is_empty():
			_build_exterior()
		var cols := PackedColorArray()
		cols.resize(_ext_pts.size())
		cols.fill(OUTSIDE)
		RenderingServer.canvas_item_add_triangle_array(frame_node.get_canvas_item(), _ext_idx, _ext_pts, cols)
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
	if has_shape:
		if shape_pts.is_empty():
			shape_pts = _shape_points()
			shape_pts.append(shape_pts[0])
		border_node.draw_polyline(shape_pts, Color(BORDER.r, BORDER.g, BORDER.b, 0.18), w * 3.0)
		border_node.draw_polyline(shape_pts, BORDER, w)
		return
	var r := Rect2(0, 0, wpx, hpx)
	border_node.draw_rect(r.grow(w * 1.5), Color(BORDER.r, BORDER.g, BORDER.b, 0.18), false, w * 3.0)
	border_node.draw_rect(r.grow(w * 0.5), BORDER, false, w)


func _draw_overlay() -> void:
	# вспышки молний: тонкий круг радиуса разряда, быстро гаснет
	for z in zaps:
		var k: float = z["t"] / ZAP_TIME
		var glow := Color(0.55, 0.75, 1.0, 0.35 * k)
		var core := Color(0.92, 0.97, 1.0, 0.95 * k)
		for pts in z["bolts"]:
			overlay.draw_polyline(pts, glow, 6.0 / zoom)    # свечение
			overlay.draw_polyline(pts, core, 2.0 / zoom)    # яркая сердцевина
		for p in z["sparks"]:
			overlay.draw_circle(p, (6.0 + 10.0 * (1.0 - k)) / zoom, Color(0.75, 0.88, 1.0, 0.55 * k))   # вспышка на клетке
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
			if _sling_blocked():
				acol = Color(1, 0.4, 0.4, 0.9)
			var alen := (90.0 + 180.0 * minf(pull, SLING_R) / SLING_R) / zoom
			var tip: Vector2 = lp + dir * alen
			var side := dir.orthogonal() * (14.0 / zoom)
			overlay.draw_line(lp, tip - dir * (18.0 / zoom), Color(0, 0, 0, 0.5), 9.0 / zoom)
			overlay.draw_line(lp, tip - dir * (18.0 / zoom), acol, 5.0 / zoom)
			overlay.draw_colored_polygon(PackedVector2Array([tip, tip - dir * (26.0 / zoom) + side,
				tip - dir * (26.0 / zoom) - side]), acol)
			# угол у кончика стрелки; на ключевом угле (кратном 45°) — золотой
			var deg := _angle_deg(aim_angle)
			var on_key := deg % 45 == 0
			var fsz := int(26.0 / zoom)
			var lp2: Vector2 = tip + dir * (34.0 / zoom) - Vector2(fsz * 1.5, -fsz * 0.35)
			var font2: Font = GameData.font_bold
			var txt := "%d°" % deg
			overlay.draw_string_outline(font2, lp2, txt, HORIZONTAL_ALIGNMENT_CENTER, fsz * 3.0, fsz, int(6.0 / zoom), Color(0, 0, 0, 0.85))
			overlay.draw_string(font2, lp2, txt, HORIZONTAL_ALIGNMENT_CENTER, fsz * 3.0, fsz,
				Color(1.0, 0.82, 0.3) if on_key else Color.WHITE)
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
func _sling_blocked() -> bool:
	return sling_cancel or sling_from == null or not _can_shoot()


func _can_shoot() -> bool:
	return reset_armed or coins >= _ball_cost(selected)


func _sling_move(p: Vector2) -> void:
	sling_pos = p
	var pull := sling_start - p
	# отмена — только вытягивание за область наведения; деньги и точку вылета проверяем каждый кадр
	# (_sling_blocked), иначе после появления денег стрелка оставалась красной до движения пальца
	sling_cancel = pull.length() > SLING_R
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
	var bad := _sling_blocked()
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


## Режимы угла: 0 — любой; 1 — кратно 45°; 2 — «ключевые»: к углам, кратным 45°, прицел притягивается
## только вблизи (± GameData.magnet_deg градусов, настраивается 1–5°), остальные углы — свободно.
func _snap(a: float) -> float:
	match snap_mode:
		1:
			return round(a / 45.0) * 45.0
		2:
			var key: float = round(a / 45.0) * 45.0
			return key if absf(a - key) <= float(GameData.magnet_deg) + 0.001 else a
	return a


## Угол для подписи: как на транспортире — 0° вправо, 90° вверх, 0…359.
func _angle_deg(a: float) -> int:
	return int(round(fposmod(-a, 360.0))) % 360


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
	_recalc_stats()   # бонусы стаи считаются по числу купленных
	last_launch = lp
	var n := _volley_size() if t == "sniper" else 1
	for k in n:
		# залп Дробовика — симметричный веер, считается одним пуском
		var off: float = 0.0 if k == 0 else ceil(k / 2.0) * 9.0 * (1 if k % 2 == 1 else -1)
		_spawn_ball(t, aim_angle + off, lp)
	extra[t] += n - 1
	Sfx.play("launch")
	_refresh_ui()


## Купить уровень ветки за монеты. Скорость сразу меняется у летящих шаров.
func _buy_track(t: String, id: String) -> void:
	var c := _track_cost(t, id)
	if coins < c or not unl[t] or _track_maxed(t, id):
		return
	coins -= c
	tlvl[t][id] = _tl(t, id) + 1
	Sfx.play("buy", 0.04)
	_recalc_stats()
	_resync_speeds()
	_refresh_ui()


func _resync_speeds() -> void:
	for b in balls:
		b.vel = b.vel.normalized() * _speed(b.type)


## Открыть тип шара за 1 U на этом уровне.
func _unlock_type(t: String) -> void:
	if unl[t] or run_u < 1:
		return
	run_u -= 1
	unl[t] = true
	Sfx.play("gold", 0.0)
	_rebuild_rows()


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


func _select(t: String) -> void:
	highlight_type = t
	highlight_t = HIGHLIGHT_TIME   # шары этого типа на поле на секунду получают яркий обод
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
var frenzy_label: Label
var ic_refresh: Texture2D
var frenzy_bar: Control
var frenzy_prog: ProgressBar


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
## Плашка счётчика фиксированной ширины: место под самую длинную запись числа (sample), цифры табличные —
## при смене числа блок не меняет ни ширину, ни положение, и соседи не сдвигаются.
const PILL_FONT := 26


func _pill(tex: Texture2D, color: Color, sample: String = "") -> Label:
	var p := PanelContainer.new()
	p.theme_type_variation = "Pill"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	h.add_child(_icon_rect(tex, 30))
	var l := Label.new()
	l.add_theme_font_override("font", GameData.tnum_font())
	l.add_theme_font_size_override("font_size", PILL_FONT)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if sample != "":
		l.custom_minimum_size.x = ceilf(GameData.tnum_font().get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, PILL_FONT).x) + 2.0
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
	lbl_rub = _pill(ic_coin, GameData.C_GOLD, "888.8Qa")   # самая длинная запись GameData.fmt
	tr.add_child(lbl_rub.get_parent().get_parent())
	lbl_u = _pill(ic_gem, GameData.C_GEM, "8888")
	tr.add_child(lbl_u.get_parent().get_parent())
	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 2)
	tr.add_child(pv)
	lbl_prog = _label("", "Muted")
	lbl_prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_prog.clip_text = true   # подпись не раздвигает верхнюю панель (тест проверяет, что помещается целиком)
	lbl_prog.custom_minimum_size.x = 0
	pv.add_child(lbl_prog)
	prog_bar = ProgressBar.new()
	prog_bar.show_percentage = false
	prog_bar.custom_minimum_size.y = 10
	prog_bar.max_value = 1.0
	pv.add_child(prog_bar)
	# кнопка меню — справа (выбор угла переехал вниз)
	var bmenu := _button("", "", 52, Icons.menu(40))
	bmenu.custom_minimum_size.x = 56
	bmenu.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bmenu.pressed.connect(_to_menu)
	tr.add_child(bmenu)
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
	# нижний ряд: прокачка, угол, «Вернуть шар». Надписи всегда в одну строку (шрифт ужимается под ширину),
	# высота ряда постоянна — интерфейс не прыгает при смене состояний
	btn_shake = _button(tr("Встряска"), "ChipButton", 64, Icons.shake(40))
	btn_shake.pressed.connect(_shake)
	var sf := _make_cd_fill(btn_shake)
	shake_fill = sf[0]
	shake_fill_panel = sf[1]
	var bup := _button(tr("Прокачка"), "AccentButton", 64, Icons.arrow_up(40))
	bup.pressed.connect(_show_upgrades.bind(true))
	btn_snap = _button("", "", 64, Icons.angle(40))
	btn_snap.pressed.connect(_cycle_snap)
	ic_refresh = Icons.refresh(40)
	btn_reset = _button(tr("Вернуть шар"), "ChipButton", 64, ic_refresh)
	btn_reset.toggle_mode = true
	btn_reset.pressed.connect(_reset_stuck)
	# перезарядка «Вернуть шар»: фон кнопки заполняется слева направо
	# «окно» растущей ширины (обрезает содержимое) с плашкой во весь размер кнопки внутри: заливка видна сразу,
	# от самого левого края, со скруглением как у кнопки (раньше появлялась лишь через ~5 с и с отступа)
	reset_fill = Control.new()
	reset_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reset_fill.clip_contents = true   # без растяжения по краям: размер задаётся явно в _layout_reset_fill
	btn_reset.add_child(reset_fill)
	reset_fill_panel = Panel.new()
	reset_fill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reset_fill.add_child(reset_fill_panel)
	btn_reset.resized.connect(_layout_reset_fill)
	for bb in [bup, btn_snap, btn_shake, btn_reset]:   # «Встряска» — рядом с «Вернуть шар»
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bb.custom_minimum_size.x = 0
		bb.autowrap_mode = TextServer.AUTOWRAP_OFF
		bb.clip_text = true
		bb.set_meta("icon0", bb.icon)
		br.add_child(bb)
		bb.resized.connect(_fit_button_text.bind(bb))
	bottom_bar.resized.connect(_on_bars_resized)

	# --- полоска «золотой лихорадки» под верхней панелью: убывает, поверх — надпись с таймером.
	# Не влияет на раскладку (камера не прыгает) и лежит ПОД окном прокачки.
	frenzy_bar = Control.new()
	frenzy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frenzy_bar.anchor_right = 1.0
	frenzy_bar.custom_minimum_size.y = 30
	frenzy_bar.visible = false
	ui_root.add_child(frenzy_bar)
	frenzy_prog = ProgressBar.new()
	frenzy_prog.show_percentage = false
	frenzy_prog.max_value = 1.0
	frenzy_prog.set_anchors_preset(Control.PRESET_FULL_RECT)
	frenzy_prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.78, 0.2, 0.9)
	fill.set_corner_radius_all(8)
	frenzy_prog.add_theme_stylebox_override("fill", fill)
	var bgb := StyleBoxFlat.new()
	bgb.bg_color = Color(0, 0, 0, 0.45)
	bgb.set_corner_radius_all(8)
	frenzy_prog.add_theme_stylebox_override("background", bgb)
	frenzy_bar.add_child(frenzy_prog)
	frenzy_label = _label("")
	frenzy_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	frenzy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frenzy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frenzy_label.add_theme_font_override("font", GameData.font_bold)
	frenzy_label.add_theme_font_size_override("font_size", 21)
	frenzy_label.add_theme_color_override("font_color", Color.WHITE)   # белый с обводкой — читается и на золоте, и на тёмном
	frenzy_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	frenzy_label.add_theme_constant_override("outline_size", 6)
	frenzy_bar.add_child(frenzy_label)

	# --- всплывающее сообщение — тоже под окном прокачки
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

	# --- окно прокачки: полупрозрачное, игра под ним идёт
	upg = Control.new()
	upg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# в окне прокачки места много — шрифт крупнее, чем в остальном интерфейсе
	var big: Theme = GameData.make_theme().duplicate()
	big.default_font_size = 28
	big.set_font_size("font_size", "Muted", 23)
	big.set_font_size("font_size", "Title", 32)
	upg.theme = big
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
	ups.bg_color = Color(0.08, 0.09, 0.14, 0.98)   # плотный фон: карточка одна, под ней не должно просвечивать поле
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
	# вкладки шаров: значок, число шаров, зелёный счётчик того, что можно купить (закрытый — замок и «1 U»)
	upg_tab_box = HBoxContainer.new()
	upg_tab_box.add_theme_constant_override("separation", 6)
	uv.add_child(upg_tab_box)
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
			upg_scroll = sc
		else:
			perk_box = vb
		var ts = TouchScroll.new()   # прокрутка пальцем, даже если палец лёг на кнопку
		ts.target = sc
		upg.add_child(ts)
	tabs.set_tab_title(0, tr("  Шарики  "))
	tabs.set_tab_hidden(1, true)
	tabs.tabs_visible = false   # прокачка на одной странице: карточка шара содержит и монеты, и эволюции
	var bclose := _button(tr("Вернуться к игре"), "AccentButton", 60)
	bclose.pressed.connect(_show_upgrades.bind(false))
	uv.add_child(bclose)
	uv.move_child(upg_tab_box, bclose.get_index() - 1)   # вкладки шаров — внизу, под большим пальцем, над «Вернуться к игре»

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
	if frenzy_bar != null:
		var m := _safe_margins()
		frenzy_bar.offset_left = m[0]
		frenzy_bar.offset_right = -m[2]
		frenzy_bar.offset_top = top_h + 6.0
		frenzy_bar.offset_bottom = top_h + 42.0
	_update_zoom_limits()
	if not cam_ready and top_h > 0.0 and bottom_h > 0.0:
		cam_ready = true
		cam.position = start_pos + Vector2(0, -CELL * 3.0)
		_set_zoom(52.0 / CELL, get_viewport_rect().size * 0.5)
	else:
		_set_zoom(zoom, get_viewport_rect().size * 0.5)


func _show_upgrades(show: bool) -> void:
	if show and not upg.visible:
		_open_upg_tab(selected if unl[selected] else "basic")   # открывается шар, выбранный в игре
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
	var b := _button("", "", 62, icon)
	b.pressed.connect(cb)
	v.add_child(b)
	return {"label": l, "button": b}


func _card_head(parent: VBoxContainer, t: String, locked: bool) -> Label:
	var def: Dictionary = GameData.TYPES[t]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	h.add_child(_icon_rect(ui_icons[t] if not locked else Icons.lock(40), 40 if not locked else 32))
	var n := _label(tr(def["name"]), "Title")
	h.add_child(n)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	return null


func _rebuild_rows() -> void:
	for box in [shop_box, perk_box, chips_box, upg_tab_box]:
		for c in box.get_children():
			c.queue_free()
	upg_tabs_btn.clear()
	upg_tab_group = ButtonGroup.new()
	shop_refs.clear()
	perk_refs.clear()
	evo_refs.clear()
	chips.clear()
	chip_group = ButtonGroup.new()
	if not unl[selected]:
		selected = "basic"

	for t in GameData.TYPE_ORDER:
		var def: Dictionary = GameData.TYPES[t]
		var unlocked: bool = unl[t]

		# --- фишка выбора шара: значок и число шаров сверху, цена снизу (влезают все 5 типов)
		if unlocked:
			var chip := _button("", "ChipButton", 86)
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
			var ic := _icon_rect(ui_icons[t], 34)   # тот же силуэт, что на поле (у Гесиевого — со шлейфом)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top.add_child(ic)
			var cnt := Label.new()
			cnt.add_theme_font_override("font", GameData.font_bold)
			cnt.add_theme_font_size_override("font_size", 23)
			cnt.text_direction = Control.TEXT_DIRECTION_LTR
			top.add_child(cnt)
			var price := Label.new()
			price.add_theme_font_size_override("font_size", 18)
			price.add_theme_color_override("font_color", GameData.C_GOLD)
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			price.text_direction = Control.TEXT_DIRECTION_LTR
			cv.add_child(price)
			# средний урон в секунду на один шар этого типа (за 60 с) — какой тип выгоднее докупать
			var cdps := Label.new()
			cdps.add_theme_font_size_override("font_size", 15)
			cdps.add_theme_color_override("font_color", C_DPS)
			cdps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cdps.text_direction = Control.TEXT_DIRECTION_LTR
			cv.add_child(cdps)
			chips[t] = chip
			chip.set_meta("cnt", cnt)
			chip.set_meta("price", price)
			chip.set_meta("dps", cdps)

		# --- вкладка шара в прокачке
		var tb := _button("", "ChipButton", 78)
		tb.toggle_mode = true
		tb.button_group = upg_tab_group
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size.x = 0
		tb.pressed.connect(_open_upg_tab.bind(t))
		upg_tab_box.add_child(tb)
		var tv := VBoxContainer.new()
		tv.set_anchors_preset(Control.PRESET_FULL_RECT)
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.add_theme_constant_override("separation", 0)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tb.add_child(tv)
		var tic := _icon_rect(ui_icons[t] if unlocked else Icons.lock(40), 30 if unlocked else 24)
		tic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tv.add_child(tic)
		var tcnt := Label.new()
		tcnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tcnt.add_theme_font_size_override("font_size", 17)
		tcnt.text_direction = Control.TEXT_DIRECTION_LTR
		tcnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(tcnt)
		var tdps := Label.new()
		tdps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tdps.add_theme_font_size_override("font_size", 14)
		tdps.add_theme_color_override("font_color", C_DPS)
		tdps.text_direction = Control.TEXT_DIRECTION_LTR
		tdps.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(tdps)
		var badge := PanelContainer.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.36, 0.84, 0.54)
		bsb.set_corner_radius_all(10)
		bsb.content_margin_left = 6
		bsb.content_margin_right = 6
		badge.add_theme_stylebox_override("panel", bsb)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -26
		badge.offset_top = -6
		badge.offset_right = 4
		var bl := Label.new()
		bl.add_theme_font_override("font", GameData.font_bold)
		bl.add_theme_font_size_override("font_size", 15)
		bl.add_theme_color_override("font_color", Color(0.05, 0.23, 0.12))
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_child(bl)
		tb.add_child(badge)
		upg_tabs_btn[t] = {"button": tb, "count": tcnt, "dps": tdps, "badge": badge, "badge_label": bl}

		# --- карточка шара (видна только у открытой вкладки)
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		card.visible = t == upg_type
		shop_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		_card_head(cv, t, not unlocked)
		# описание шара — всегда целиком
		var sd := _label(tr(def["desc"]), "Muted")
		sd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sd.name = "Desc"
		cv.add_child(sd)
		if unlocked:
			# бонус стаи — полоской: ступень, прогресс до следующей, что даёт сейчас
			var fr := HBoxContainer.new()
			fr.add_theme_constant_override("separation", 8)
			cv.add_child(fr)
			var fcol: Color = def["color"].lerp(Color.WHITE, 0.35)
			var fl := _label("", "Muted")
			fl.add_theme_color_override("font_color", fcol)
			fr.add_child(fl)
			var fb := ProgressBar.new()
			fb.show_percentage = false
			fb.max_value = 1.0
			fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			fb.custom_minimum_size.y = 10
			var fbg := StyleBoxFlat.new()
			fbg.bg_color = Color(0, 0, 0, 0.35)
			fbg.set_corner_radius_all(5)
			var ffg := StyleBoxFlat.new()
			ffg.bg_color = fcol
			ffg.set_corner_radius_all(5)
			fb.add_theme_stylebox_override("background", fbg)
			fb.add_theme_stylebox_override("fill", ffg)
			fr.add_child(fb)
			var fe := _label("", "Muted")
			fr.add_child(fe)
			var st := _stats_panel(cv)
			var trs := {}
			for tr_ in def["tracks"]:
				trs[tr_["id"]] = _upg_row(cv, tr(TRACK_NAMES.get(tr_["id"], tr_["id"])), ic_coin, _buy_track.bind(t, tr_["id"]))
			shop_refs[t] = {"card": card, "fleet": fl, "fleet_bar": fb, "fleet_eff": fe, "tracks": trs,
				"stat": st["total"], "stat_dps": st["dps"], "stat_ball": st["ball"]}
			_build_evo_section(cv, t)
		else:
			var ub := _button(tr("Открыть · 1 U"), "AccentButton", 62, ic_gem)
			ub.pressed.connect(_unlock_type.bind(t))
			cv.add_child(ub)
			shop_refs[t] = {"card": card, "unlock": ub}
	_refresh_ui()


## «8.3 кл/с → 9.9 кл/с» → «8.3 → 9.9 кл/с»: одинаковая единица — только в конце.
static func _arrow(a: String, b: String) -> String:
	var i := a.length()
	while i > 0 and not a[i - 1].is_valid_int():
		i -= 1
	var unit := a.substr(i)
	if unit.strip_edges() != "" and b.ends_with(unit) and i > 0:
		return "%s → %s" % [a.substr(0, i), b]
	return "%s → %s" % [a, b]


## Статистика шара на своей подложке: урон за уровень, урон в секунду (за 60 с), на один шар.
func _stats_panel(cv: VBoxContainer) -> Dictionary:
	var pan := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.45, 0.6, 1.0, 0.07)
	psb.set_corner_radius_all(12)
	psb.content_margin_left = 12
	psb.content_margin_right = 12
	psb.content_margin_top = 6
	psb.content_margin_bottom = 6
	pan.add_theme_stylebox_override("panel", psb)
	pan.name = "Stats"
	cv.add_child(pan)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pan.add_child(v)
	var out := {}
	for k in [["total", tr("Урон за уровень")], ["dps", tr("Урон в секунду (за 60 с)")], ["ball", tr("На один шар")]]:
		var row := HBoxContainer.new()
		v.add_child(row)
		var nl := _label(k[1], "Muted")
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		var vl := _label("", "")
		vl.add_theme_font_override("font", GameData.font_bold)
		vl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
		vl.text_direction = Control.TEXT_DIRECTION_LTR
		row.add_child(vl)
		out[k[0]] = vl
	return out


const C_DPS := Color(0.62, 0.75, 1.0)   # цвет строки урона на фишках и вкладках


## Средний урон в секунду на один шар типа (за 60 с) — для фишек и вкладок; у закрытого — пусто, без шаров — «—».
func _ball_dps_text(t: String) -> String:
	if not unl[t]:
		return ""
	var nb := int(counts[t]) + int(extra[t])
	if nb <= 0:
		return "—"
	return _rate_text(_dps(t) / nb)


## Число в секунду для статистики: до 100 — с одним знаком, дальше — коротко (12.3K).
func _rate_text(v: float) -> String:
	return _u_rate(_num(snappedf(v, 0.1)) if v < 100.0 else GameData.fmt(int(v)))


## Строка улучшения: название, значение «сейчас → после» и кнопка цены (монеты или U) — одна строка.
func _upg_row(parent: VBoxContainer, name: String, icon: Texture2D, cb: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var nl := _label(name, "")
	row.add_child(nl)
	var vl := _label("", "Muted")
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(vl)
	var bt := _button("", "", 56, icon)
	bt.custom_minimum_size.x = 132
	bt.pressed.connect(cb)
	row.add_child(bt)
	return {"label": vl, "button": bt, "name": nl}


## Эволюции шара — в его же карточке, под прокачкой за монеты. Купленная: заголовок с ✓ и строки веток
## (значение и кнопка ◆), некупленная: название, короткое описание и кнопка ◆ цены.
func _build_evo_section(cv: VBoxContainer, t: String) -> void:
	var hd := _label(tr("  Эволюции  ").strip_edges(), "Muted")
	hd.add_theme_font_override("font", GameData.font_bold)
	cv.add_child(hd)
	var refs := {}
	for e in GameData.EVOS[t]:
		var eid: String = e["id"]
		# каждая эволюция — на своей подложке: отделена от соседней и от улучшений за монеты
		var pan := PanelContainer.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(1, 1, 1, 0.05)
		psb.border_color = Color(1, 1, 1, 0.08)
		psb.set_border_width_all(1)
		psb.set_corner_radius_all(12)
		psb.content_margin_left = 12
		psb.content_margin_right = 10
		psb.content_margin_top = 8
		psb.content_margin_bottom = 8
		pan.add_theme_stylebox_override("panel", psb)
		pan.name = "Evo_" + eid
		cv.add_child(pan)
		var ev := VBoxContainer.new()
		ev.add_theme_constant_override("separation", 6)
		pan.add_child(ev)
		if not _has_evo(t, eid):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			ev.add_child(row)
			var tv := VBoxContainer.new()
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tv.add_theme_constant_override("separation", 2)
			row.add_child(tv)
			var nm := _label(tr(e["name"]), "")
			nm.add_theme_font_override("font", GameData.font_bold)
			tv.add_child(nm)
			var ds := _label(tr(e["desc"]), "Muted")
			ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tv.add_child(ds)
			var bb := _button("", "", 56, ic_gem)
			bb.custom_minimum_size.x = 132
			bb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bb.pressed.connect(_buy_evo.bind(t, eid))
			row.add_child(bb)
			refs[eid] = {"buy": bb}
			continue
		psb.border_color = Color(0.55, 0.9, 0.65, 0.35)   # купленная — с зеленоватой рамкой
		var nm2 := _label(tr(e["name"]) + "  ✓", "")
		nm2.add_theme_font_override("font", GameData.font_bold)
		nm2.add_theme_color_override("font_color", Color(0.55, 0.9, 0.65))
		ev.add_child(nm2)
		var ds2 := _label(tr(e["desc"]), "Muted")   # описание остаётся и после покупки
		ds2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds2.name = "EvoDesc"
		ev.add_child(ds2)
		var ladders := {}
		for tr_ in e["tracks"]:
			ladders[tr_["id"]] = _upg_row(ev, tr(tr_["name"]), ic_gem, _buy_ladder.bind(t, tr_["id"]))
		refs[eid] = {"ladders": ladders}
	evo_refs[t] = refs


## Открыть вкладку шара в прокачке: видна только его карточка, прокрутка — к началу.
func _open_upg_tab(t: String) -> void:
	upg_type = t
	for tp in shop_refs:
		shop_refs[tp]["card"].visible = tp == t
	for tp in upg_tabs_btn:
		upg_tabs_btn[tp]["button"].set_pressed_no_signal(tp == t)   # программно группа не снимает прежнюю
	if upg_scroll != null:
		upg_scroll.scroll_vertical = 0


## Сколько улучшений шара можно купить прямо сейчас (для зелёного счётчика на вкладке).
func _affordable(t: String) -> int:
	if not unl[t]:
		return 1 if run_u >= 1 else 0
	var n := 0
	for d in GameData.TYPES[t]["tracks"]:
		if not _track_maxed(t, d["id"]) and coins >= _track_cost(t, d["id"]):
			n += 1
	for e in GameData.EVOS[t]:
		if not _has_evo(t, e["id"]):
			if run_u >= _evo_cost(t):
				n += 1
		else:
			for trk in e["tracks"]:
				if not _ladder_maxed(t, trk["id"]) and run_u >= _ladder_cost(t, trk["id"]):
					n += 1
	return n


## Бонус стаи: ступень k из 9, прогресс до следующей (0..1) и что даёт сейчас.
func _fleet_parts(t: String) -> Array:
	var f: String = GameData.TYPES[t]["fleet"]
	var n := int(counts[t])
	var k := GameData.fleet_steps(n)
	var val := k if f == "flat" else 5 * k
	var prev: int = 0 if k == 0 else int(GameData.FLEET_STEPS[k - 1])
	var frac := 1.0
	if k < GameData.FLEET_STEPS.size():
		frac = clampf(float(n - prev) / float(int(GameData.FLEET_STEPS[k]) - prev), 0.0, 1.0)
	return [k, frac, tr(GameData.FLEET_DESC[f]) % val]


# ---------------------------------------------------------------- значения с единицами

## Число без лишних нулей: 2 → «2», 0.25 → «0.25», 1.5 → «1.5».
static func _num(v: float) -> String:
	if absf(v - round(v)) < 0.001:
		return str(int(round(v)))
	return ("%.2f" % v).rstrip("0").rstrip(".")


func _u_cells(v: float) -> String:
	return tr("%s кл") % _num(v)


func _u_rate(v: String) -> String:
	return tr("%s/с") % v


func _u_sec(v: float) -> String:
	return tr("%s с") % _num(v)


static func _pct(v: float) -> String:
	return "%s%%" % _num(v * 100.0)


## Значение ветки эволюции на уровне lv — как его видит игрок (с единицами).
func _ev_text(t: String, track: String, lv: int) -> String:
	var d := GameData.evo_track(t, track)
	var v := float(d["base"]) + float(d["step"]) * lv
	if d.has("min"):
		v = maxf(v, float(d["min"]))
	match track:
		"scout_radius", "stitch_depth", "area_radius", "lightning_range", "gravity_range":
			return _u_cells(floorf(v))
		"kleshch_deeper":
			return _u_cells(v)
		"scout_find", "stitch_share", "sprint_cap", "infection_chance", "corrosion_bonus", "war_banner_damage", \
				"tailwind_speed", "tailwind_self":
			return _pct(v)
		"area_share":
			return ("+" if v > 0.0 else "") + _pct(v)
		"shotgun_cheap":
			return ("−" if v > 0.0 else "") + _pct(minf(0.5, v))
		"sprint_rate":
			return _u_rate(_pct(v))
		"lightning_rate", "kleshch_grip":
			return _u_rate(_num(v))
		"shotgun_balls":
			return "×%d" % (1 + int(floor(v)))
		"infection_fade":
			return "−" + _pct(0.10 * pow(0.8, lv))   # потеря шанса за переход
		"corrosion_linger", "war_banner_cry":
			return _u_sec(v)
	return _num(v)


## «Радиус разведки: 2 кл → 3 кл»; на пределе — «…: 3 с (макс.)».
func _ev_caption(t: String, track: String) -> String:
	var name := tr(GameData.evo_track(t, track)["name"])
	var lv := _el(t, track)
	if _ladder_maxed(t, track):
		return "%s: %s (%s)" % [name, _ev_text(t, track, lv), tr("макс.")]
	return "%s: %s → %s" % [name, _ev_text(t, track, lv), _ev_text(t, track, lv + 1)]


## Процент прогресса: вниз (100% — только при полной расчистке), до 10% — с одним знаком.
static func _pct_text(frac: float) -> String:
	var p := frac * 100.0
	if p < 10.0:
		return "%.1f%%" % (floorf(p * 10.0) / 10.0)
	return "%d%%" % int(floorf(p))


## Надпись кнопки нижнего ряда — всегда в одну строку: если не помещается, шрифт уменьшается (до 15).
func _fit_button_text(bb: Button) -> void:
	if bb.size.x <= 0.0:
		return
	var font: Font = bb.get_theme_font("font")
	var sb: StyleBox = bb.get_theme_stylebox("normal")
	var icon0: Texture2D = bb.get_meta("icon0", bb.icon)
	var base_room := bb.size.x - sb.get_content_margin(SIDE_LEFT) - sb.get_content_margin(SIDE_RIGHT)
	var with_icon := base_room - (float(bb.get_theme_constant("icon_max_width")) + float(bb.get_theme_constant("h_separation")) if icon0 != null else 0.0)
	var fs := ROW_FONT
	var shown := bb.atr(bb.text)   # кнопка переводится движком: мерить надо показанный текст, а не ключ
	while fs > 15 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > with_icon:
		fs -= 1
	var use_icon := icon0 != null and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= with_icon
	if icon0 != null and not use_icon:
		# не влезает и мелким шрифтом — убираем значок, текст важнее
		fs = ROW_FONT
		while fs > 15 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > base_room:
			fs -= 1
	if bb.icon != (icon0 if use_icon else null):
		bb.icon = icon0 if use_icon else null
	if bb.get_theme_font_size("font_size") != fs:
		bb.add_theme_font_size_override("font_size", fs)


## «Встряска»: направление каждого шара поворачивается на SHAKE_MIN…SHAKE_MAX градусов в случайную сторону —
## застрявшие на одной траектории шары сбиваются с неё. Скорость не меняется; бурящие (Клещ) не трогаются.
func _shake() -> void:
	if shake_cd > 0.0 or balls.is_empty():
		return
	for b in balls:
		if b.drill_id >= 0 or b.vel.length_squared() <= 1.0:
			continue
		var a := deg_to_rad(randf_range(SHAKE_MIN, SHAKE_MAX)) * (1.0 if randf() < 0.5 else -1.0)
		b.vel = b.vel.rotated(a)
	shake_cd = SHAKE_CD
	Sfx.play("launch", 0.0)
	GameData.vibrate(30)
	_refresh_ui()


## Заливка перезарядки на кнопке: «окно» растущей ширины с плашкой размером с кнопку внутри.
func _make_cd_fill(btn: Button) -> Array:
	var clip := Control.new()
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	btn.add_child(clip)
	var pnl := Panel.new()
	pnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(pnl)
	return [clip, pnl]


func _layout_cd_fill(btn: Button, clip: Control, pnl: Panel, done: float) -> void:
	var sz := btn.size
	pnl.size = sz
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.85, 1.0, 0.3)
	var base := btn.get_theme_stylebox("disabled")
	sb.set_corner_radius_all(base.corner_radius_top_left if base is StyleBoxFlat else 12)
	pnl.add_theme_stylebox_override("panel", sb)
	clip.position = Vector2.ZERO
	clip.size = Vector2(sz.x * done, sz.y)
	clip.visible = done > 0.0


## Перезарядка «Вернуть шар»: доля прошедшего времени — полупрозрачная заливка слева направо.
## Плашка внутри всегда размером с кнопку (скругление как у кнопки), а «окно» обрезает её по доле.
func _layout_reset_fill() -> void:
	if reset_fill == null:
		return
	var sz := btn_reset.size
	reset_fill_panel.size = sz
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.85, 1.0, 0.3)
	var base := btn_reset.get_theme_stylebox("disabled")
	sb.set_corner_radius_all(base.corner_radius_top_left if base is StyleBoxFlat else 12)
	reset_fill_panel.add_theme_stylebox_override("panel", sb)
	var cd: float = reset_cd.get(selected, 0.0)
	var done := 0.0 if (cd <= 0.0 or reset_armed) else clampf(1.0 - cd / RESET_CD, 0.0, 1.0)
	reset_fill.position = Vector2.ZERO
	reset_fill.size = Vector2(sz.x * done, sz.y)
	reset_fill.visible = done > 0.0


func _refresh_ui() -> void:
	if lbl_rub == null:
		return
	lbl_rub.text = GameData.fmt(coins)
	lbl_u.text = str(run_u)
	var frac := float(destroyed) / maxf(1.0, float(goal))
	prog_bar.value = minf(1.0, frac)
	# числа и проценты: «1.2K из 18.2K · 7%»; после цели на больших картах — «Разбито 350K · 117%» (от цели)
	if goal_done and not track_all:
		lbl_prog.text = tr("Разбито %s") % GameData.fmt(destroyed) + " · " + _pct_text(frac)
	else:
		lbl_prog.text = tr("%s из %s") % [GameData.fmt(destroyed), GameData.fmt(goal)] + " · " + _pct_text(frac)
	var snap_txt: String = [tr("любой"), tr("45°"), tr("ключевые")][snap_mode]
	if btn_snap.text != snap_txt:
		btn_snap.text = snap_txt
		_fit_button_text(btn_snap)
	if frenzy_t > 0.0:
		frenzy_label.text = tr("Урон ×2 · %d с") % int(ceil(frenzy_t))
		frenzy_prog.max_value = frenzy_max
		frenzy_prog.value = frenzy_t
		frenzy_bar.visible = true
	elif frenzy_bar.visible:
		frenzy_bar.visible = false
	for t in chips:
		# цена следующего шара прямо на фишке; не хватает денег — фишка тусклее
		var price := _ball_cost(t)
		chips[t].get_meta("cnt").text = "×%d" % counts[t]
		chips[t].get_meta("price").text = GameData.fmt(price)
		chips[t].get_meta("dps").text = _ball_dps_text(t)
		chips[t].modulate = Color(1, 1, 1, 1.0 if coins >= price else 0.6)
	var cd: float = reset_cd[selected]
	# надпись не меняется — состояние показывает оформление: включено — акцентная заливка,
	# перезарядка — фон заполняется слева направо (_layout_reset_fill)
	btn_reset.theme_type_variation = "AccentButton" if reset_armed else "ChipButton"
	btn_reset.set_pressed_no_signal(reset_armed)
	btn_reset.disabled = not reset_armed and (cd > 0.0 or int(counts[selected]) == 0)
	_layout_reset_fill()
	if btn_shake != null:
		btn_shake.disabled = shake_cd > 0.0 or balls.is_empty()
		_layout_cd_fill(btn_shake, shake_fill, shake_fill_panel, 0.0 if shake_cd <= 0.0 else clampf(1.0 - shake_cd / SHAKE_CD, 0.0, 1.0))

	if not upg.visible:
		return
	upg_rub.text = GameData.fmt(coins)
	upg_u.text = str(run_u)
	for t in shop_refs:
		var r: Dictionary = shop_refs[t]
		if upg_tabs_btn.has(t):
			var tbr: Dictionary = upg_tabs_btn[t]
			tbr["count"].text = ("×%d" % (int(counts[t]) + int(extra[t]))) if unl[t] else "1 U"
			tbr["dps"].text = _ball_dps_text(t)
			var af := _affordable(t)
			tbr["badge"].visible = af > 0
			tbr["badge_label"].text = str(af)
		if r.has("unlock"):
			r["unlock"].disabled = run_u < 1
			continue
		var dps := _dps(t)
		var nb := maxi(1, int(counts[t]) + int(extra[t]))
		r["stat"].text = GameData.fmt(dmg_total[t])
		r["stat_dps"].text = _rate_text(dps)
		r["stat_ball"].text = _rate_text(dps / nb)
		var fp := _fleet_parts(t)
		r["fleet"].text = tr("Стая %d/9") % fp[0]
		r["fleet_bar"].value = fp[1]
		r["fleet_eff"].text = fp[2]
		for id in r["tracks"]:
			var cost := _track_cost(t, id)
			var lv := _tl(t, id)
			if _track_maxed(t, id):
				r["tracks"][id]["label"].text = "%s (%s)" % [_track_text(t, id, lv), tr("макс.")]
				r["tracks"][id]["button"].text = tr("макс.")
				r["tracks"][id]["button"].disabled = true
			else:
				r["tracks"][id]["label"].text = _arrow(_track_text(t, id, lv), _track_text(t, id, lv + 1))
				r["tracks"][id]["button"].text = GameData.fmt(cost)
				r["tracks"][id]["button"].disabled = coins < cost
	for t in evo_refs:
		for eid in evo_refs[t]:
			var er: Dictionary = evo_refs[t][eid]
			if er.has("buy"):
				var ec := _evo_cost(t)
				er["buy"].text = str(ec)
				er["buy"].disabled = run_u < ec
				continue
			for trk in er["ladders"]:
				var lr: Dictionary = er["ladders"][trk]
				var elv := _el(t, trk)
				lr["label"].text = ("%s (%s)" % [_ev_text(t, trk, elv), tr("макс.")]) if _ladder_maxed(t, trk) \
					else _arrow(_ev_text(t, trk, elv), _ev_text(t, trk, elv + 1))
				if _ladder_maxed(t, trk):
					lr["button"].text = tr("макс.")
					lr["button"].disabled = true
				else:
					lr["button"].text = str(_ladder_cost(t, trk))
					lr["button"].disabled = run_u < _ladder_cost(t, trk)


## Подпись ветки: «Скорость 8.2 → 9.9 кл/с», «Сила удара 1 → 2», …
## Значение ветки за монеты на уровне lv — как его видит игрок (с единицами).
## Значение считается по-настоящему (с потолком скорости и округлением урона), а не по формуле ветки.
func _track_text(t: String, id: String, lv: int) -> String:
	var keep := _tl(t, id)
	tlvl[t][id] = lv
	var txt := id
	match id:
		"speed":
			txt = _u_rate(_u_cells(snappedf(_speed(t) / CELL, 0.1)))
		"impact":
			txt = str(_damage_of(t))
		"ticks":
			txt = str(_poison_ticks())
		"cadence":
			txt = _u_rate(_num(_poison_rate()))
		"radius":
			txt = _u_cells(int(_aura_radius() / CELL))
		"hold":
			txt = _u_sec(_aura_hold())
	tlvl[t][id] = keep
	return txt


const TRACK_NAMES := {"speed": "Скорость", "impact": "Сила удара", "ticks": "Количество тиков",
	"cadence": "Частота тиков яда", "radius": "Радиус ауры", "hold": "Длительность бафа"}


## Ветка на пределе: следующий уровень не меняет то, что видит игрок (например, скорость упёрлась в потолок
## 50 кл/с) — тогда покупка недоступна и ничего не списывает (раньше деньги уходили впустую).
func _track_maxed(t: String, id: String) -> bool:
	var lv := _tl(t, id)
	return _track_text(t, id, lv) == _track_text(t, id, lv + 1)


func _track_caption(t: String, id: String) -> String:
	var lv := _tl(t, id)
	var name := tr(TRACK_NAMES.get(id, id))
	if _track_maxed(t, id):
		return "%s: %s (%s)" % [name, _track_text(t, id, lv), tr("макс.")]
	return "%s: %s → %s" % [name, _track_text(t, id, lv), _track_text(t, id, lv + 1)]

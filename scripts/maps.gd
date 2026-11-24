extends RefCounted
const PictureMaps = preload("res://scripts/picture_maps.gd")
## Карты и картинки-шаблоны.

const W := 700.0
const H := 840.0


## Картинки-шаблоны: многоугольники в квадрате 0..1. Из них строятся стены из белых кубиков.
static func templates() -> Dictionary:
	var cat := ellipse_poly(Vector2(350, 390), 170, 170)
	cat = union(cat, PackedVector2Array([Vector2(200, 335), Vector2(215, 165), Vector2(310, 235)]))
	cat = union(cat, PackedVector2Array([Vector2(500, 335), Vector2(485, 165), Vector2(390, 235)]))
	var fish := union(ellipse_poly(Vector2(320, 420), 280, 190, 64),
		PackedVector2Array([Vector2(520, 420), Vector2(694, 250), Vector2(694, 590)]))
	var cap := PackedVector2Array()
	for k in 25:
		var a := PI + PI * k / 24.0
		cap.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.45))
	var mushroom := union(cap, rect_poly(0.34, 0.4, 0.32, 0.6))
	var cactus := union(rect_poly(0.4, 0.08, 0.2, 0.92), rect_poly(0.14, 0.46, 0.3, 0.14))
	cactus = union(cactus, rect_poly(0.14, 0.24, 0.14, 0.34))
	cactus = union(cactus, rect_poly(0.56, 0.36, 0.3, 0.14))
	cactus = union(cactus, rect_poly(0.72, 0.14, 0.14, 0.36))
	var flower := ellipse_poly(Vector2(0.5, 0.5), 0.2, 0.2, 24)
	for k in 5:
		var a := -PI / 2.0 + TAU * k / 5.0
		flower = union(flower, ellipse_poly(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.3, 0.2, 0.2, 24))
	var drop := union(ellipse_poly(Vector2(0.5, 0.66), 0.34, 0.34, 32),
		PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.8, 0.5), Vector2(0.2, 0.5)]))
	return {
		"house": norm([PackedVector2Array([Vector2(0.1, 0.45), Vector2(0.5, 0.05), Vector2(0.9, 0.45),
			Vector2(0.9, 0.95), Vector2(0.1, 0.95)])]),
		"heart": norm([heart_poly(Vector2.ZERO, 17.0)]),
		"star": norm([star_poly(Vector2.ZERO, 1.0, 0.5, 5)]),
		"moon": norm([subtract(ellipse_poly(Vector2.ZERO, 1, 1), ellipse_poly(Vector2(0.5, -0.3), 0.78, 0.78))]),
		"tree": norm([tree_poly(), star_poly(Vector2(350, 100), 55, 26, 5)]),
		"cat": norm([cat]),
		"fish": norm([fish]),
		"yarn": norm([ellipse_poly(Vector2.ZERO, 1, 1)]),
		"mushroom": norm([mushroom]),
		"mountain": norm([PackedVector2Array([Vector2(0, 1), Vector2(0.18, 0.55), Vector2(0.3, 0.68),
			Vector2(0.5, 0.08), Vector2(0.68, 0.5), Vector2(0.8, 0.38), Vector2(1, 1)])]),
		"cactus": norm([cactus]),
		"snowflake": norm([star_poly(Vector2.ZERO, 1.0, 0.5, 6)]),
		"rocket": norm([PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.66, 0.2), Vector2(0.66, 0.68),
			Vector2(0.86, 0.9), Vector2(0.86, 1.0), Vector2(0.62, 0.86), Vector2(0.38, 0.86),
			Vector2(0.14, 1.0), Vector2(0.14, 0.9), Vector2(0.34, 0.68), Vector2(0.34, 0.2)])]),
		"crown": norm([PackedVector2Array([Vector2(0, 1), Vector2(0, 0.3), Vector2(0.25, 0.6), Vector2(0.5, 0.12),
			Vector2(0.75, 0.6), Vector2(1, 0.3), Vector2(1, 1)])]),
		"castle": norm([PackedVector2Array([Vector2(0, 1), Vector2(0, 0.25), Vector2(0.14, 0.25), Vector2(0.14, 0.36),
			Vector2(0.28, 0.36), Vector2(0.28, 0.25), Vector2(0.42, 0.25), Vector2(0.42, 0.36),
			Vector2(0.58, 0.36), Vector2(0.58, 0.25), Vector2(0.72, 0.25), Vector2(0.72, 0.36),
			Vector2(0.86, 0.36), Vector2(0.86, 0.25), Vector2(1, 0.25), Vector2(1, 1)])]),
		"gem": norm([PackedVector2Array([Vector2(0.2, 0.1), Vector2(0.8, 0.1), Vector2(1, 0.38), Vector2(0.5, 1),
			Vector2(0, 0.38)])]),
		"flower": norm([flower]),
		"drop": norm([drop]),
		"bolt": norm([PackedVector2Array([Vector2(0.55, 0), Vector2(0.15, 0.55), Vector2(0.45, 0.55),
			Vector2(0.3, 1), Vector2(0.85, 0.4), Vector2(0.55, 0.4), Vector2(0.75, 0)])]),
	}


## Нарисованные вручную карты; дальше уровни генерируются бесконечно (get_map).
const HANDMADE := 7

## Темы бесконечных уровней: название (переводится), картинки, цвет пола, сдвиг оттенка квадратов.
const THEMES := [
	{"pic": "t_robot", "floor": Color(0.13, 0.13, 0.17), "hue": 0.1},
	{"pic": "t_railway", "floor": Color(0.15, 0.12, 0.1), "hue": 0.05},
	{"pic": "t_workshop", "floor": Color(0.14, 0.13, 0.12), "hue": 0.12},
	{"pic": "t_lab", "floor": Color(0.09, 0.14, 0.13), "hue": -0.05},
	{"pic": "t_airfield", "floor": Color(0.1, 0.13, 0.18), "hue": -0.18},
	{"pic": "t_electric", "floor": Color(0.15, 0.14, 0.08), "hue": 0.08},
	{"pic": "t_orbit", "floor": Color(0.07, 0.07, 0.14), "hue": 0.35},
	{"pic": "t_plant", "floor": Color(0.13, 0.12, 0.12), "hue": 0.0},
	{"pic": "t_computers", "floor": Color(0.1, 0.12, 0.16), "hue": -0.3},
	{"pic": "t_space", "floor": Color(0.08, 0.08, 0.13), "hue": 0.28},
	{"pic": "t_fleet", "floor": Color(0.06, 0.13, 0.17), "hue": -0.22},
	{"pic": "t_field", "floor": Color(0.1, 0.15, 0.1), "hue": -0.05},
]


## Карта по номеру (0, 1, 2, …): первые HANDMADE — нарисованные, дальше — бесконечные уровни.
## Один и тот же номер всегда даёт одну и ту же карту (у всех игроков одинаковую).
static func get_map(i: int) -> Dictionary:
	if i < HANDMADE:
		return get_maps()[i]
	var lv := i - HANDMADE + 1               # 1, 2, 3, … среди бесконечных
	var k := (lv - 1) % THEMES.size()
	var theme: Dictionary = THEMES[k]
	@warning_ignore("integer_division")
	var flip: bool = ((lv - 1) / THEMES.size()) % 2 == 1   # на втором круге картины зеркальные
	var mp := _pic(theme["pic"], {"u_rate": 2, "hp_base": HP_BASE + HP_STEP * lv, "hp_growth": 0.015,
		"goal": int(minf(GOAL_BASE * (1.0 + GOAL_STEP * (lv - 1)), 1.0e15))})
	mp["id"] = "lv%d" % (i + 1)
	mp["number"] = i + 1
	mp["floor"] = theme["floor"]
	mp["hue"] = theme["hue"]
	if flip:
		mp["flip"] = true
		mp["start"] = [1.0 - float(mp["start"][0]), mp["start"][1]]
	return mp


## Карта-картина: размер, старт и название — из сгенерированного PictureMaps.PICS.
static func _pic(id: String, extra: Dictionary) -> Dictionary:
	var p: Dictionary = PictureMaps.PICS[id]
	var mp := {"id": id, "pic": id, "name": p["name"], "w": p["w"], "h": p["h"], "start": p["start"],
		"aim": -90.0, "shape": "round", "templates": []}
	mp.merge(extra, true)
	return mp


## Бесконечные уровни растут линейно — в том же темпе, что и бонус монет (+25% за карту).
## Экспоненциальный рост делал далёкие уровни непроходимыми на старте (каждая карта начинается
## с одного шара) и переполнял числа (тест test_endless_levels). Подобрано симулятором баланса.
## Узоры раскладки картинок (см. game.gd → _layout_slot).
const LAYOUTS := ["rings", "rays", "spiral", "checker", "mosaic"]

const HP_BASE := 4.0
const HP_STEP := 0.35
const GOAL_BASE := 200000
const GOAL_STEP := 0.05


## Название карты для показа: нарисованные — по имени, бесконечные — «Тема 12».
static func title(mp: Dictionary, translate: Callable) -> String:
	var n: String = translate.call(mp["name"])
	return n if not mp.has("number") else "%s %d" % [n, mp["number"]]


## Карты растут от 20×24 до 10000×10000 клеток. Прохождение начинается из центра карты.
## fixed — картинки в заданных местах; иначе картинки разбросаны по регионам region×region.
## goal — сколько квадратов разбить, чтобы открыть следующую карту (0 — все).
## u_rate — шанс U-балла в квадрате на 10 000 (в полостях картинок ×3); убывает от карты к карте.
static func get_maps() -> Array:
	var all := ["house", "heart", "star", "moon", "tree", "cat", "fish", "yarn", "mushroom", "mountain"]
	return [
		{"id": "meadow", "u_rate": 70, "name": "Лужайка", "w": 20, "h": 24, "aim": -70.0,
			"hp_base": 1.0, "hp_growth": 0.30, "goal": 0, "fixed": [["house", Rect2i(5, 0, 10, 9)], ["heart", Rect2i(6, 16, 8, 8)]]},
		{"id": "heart", "u_rate": 40, "name": "Сердце", "w": 40, "h": 48, "aim": -70.0,
			"hp_base": 1.5, "hp_growth": 0.25, "goal": 0, "fixed": [["heart", Rect2i(9, 1, 22, 19)], ["heart", Rect2i(14, 30, 13, 13)]]},
		{"id": "garden", "u_rate": 12, "name": "Сад", "w": 120, "h": 150, "aim": -90.0,
			"hp_base": 2.0, "hp_growth": 0.06, "goal": 0, "shape": "oval", "templates": ["tree"], "start": [0.7, 0.18],
			# «Ночной сад» — цельная картина: дом с трубой и дымом, большое дерево, месяц и звёзды над холмами,
			# забор с цветами и котом на переднем плане, тропинка от двери к зрителю
			"scene": [
				# небо: месяц и звёзды
				["circle", [0.26, 0.13], 0.075], ["arc", [0.3, 0.115], 0.065, 120, 300],
				["stars", [0.08, 0.05, 0.84, 0.17], 34, 11],
				# холмы — линия горизонта через всю картину
				["line", [[0.0, 0.6], [0.06, 0.56], [0.12, 0.55], [0.2, 0.57]]],
				["line", [[0.62, 0.58], [0.68, 0.56], [0.74, 0.57], [0.78, 0.59]]],
				["line", [[0.84, 0.59], [0.9, 0.56], [0.96, 0.56], [1.0, 0.58]]],
				# дом: стены, крыша, труба с дымом, дверь, окна с переплётом
				["line", [[0.2, 0.42], [0.62, 0.42], [0.62, 0.64], [0.2, 0.64]], true],
				["line", [[0.15, 0.43], [0.41, 0.26], [0.67, 0.43]]],
				["line", [[0.53, 0.33], [0.53, 0.25], [0.59, 0.25], [0.59, 0.37]]],
				["dots", [0.56, 0.23], [0.6, 0.17], 3], ["dots", [0.6, 0.17], [0.57, 0.11], 3],
				["line", [[0.36, 0.64], [0.36, 0.52], [0.46, 0.52], [0.46, 0.64]]],
				["line", [[0.24, 0.47], [0.32, 0.47], [0.32, 0.55], [0.24, 0.55]], true],
				["line", [[0.28, 0.47], [0.28, 0.55]]], ["line", [[0.24, 0.51], [0.32, 0.51]]],
				["line", [[0.5, 0.47], [0.58, 0.47], [0.58, 0.55], [0.5, 0.55]], true],
				["line", [[0.54, 0.47], [0.54, 0.55]]], ["line", [[0.5, 0.51], [0.58, 0.51]]],
				# большое дерево справа: ствол и пышная крона
				["line", [[0.78, 0.63], [0.79, 0.45]]], ["line", [[0.84, 0.63], [0.83, 0.45]]],
				["circle", [0.81, 0.36], 0.11], ["arc", [0.72, 0.42], 0.06, 90, 250], ["arc", [0.9, 0.42], 0.06, 290, 450],
				# тропинка от двери к зрителю — расходится в перспективе
				["line", [[0.39, 0.64], [0.33, 0.8], [0.26, 0.98]]], ["line", [[0.43, 0.64], [0.5, 0.8], [0.57, 0.98]]],
				# забор на переднем плане (с калиткой у тропинки), цветы и кот на заборе
				["line", [[0.04, 0.78], [0.31, 0.78]]], ["line", [[0.52, 0.78], [0.96, 0.78]]],
				["line", [[0.07, 0.75], [0.07, 0.83]]], ["line", [[0.15, 0.75], [0.15, 0.83]]],
				["line", [[0.23, 0.75], [0.23, 0.83]]], ["line", [[0.31, 0.75], [0.31, 0.83]]],
				["line", [[0.52, 0.75], [0.52, 0.83]]], ["line", [[0.6, 0.75], [0.6, 0.83]]],
				["line", [[0.68, 0.75], [0.68, 0.83]]], ["line", [[0.84, 0.75], [0.84, 0.83]]],
				["line", [[0.92, 0.75], [0.92, 0.83]]],
				["tpl", "cat", [0.74, 0.69, 0.09, 0.09]],
				["tpl", "flower", [0.1, 0.84, 0.07, 0.05]], ["tpl", "flower", [0.19, 0.85, 0.06, 0.05]],
				["tpl", "mushroom", [0.84, 0.86, 0.06, 0.06], true],
			]},

		{"id": "yard", "u_rate": 5, "name": "Кошачий двор", "w": 200, "h": 200, "aim": -90.0,
			"hp_base": 2.5, "hp_growth": 0.03, "goal": 0, "shape": "round", "templates": ["cat"], "start": [0.68, 0.86],
			# «Кошачий двор» — цельная картина: большой дом слева, забор справа с котом, дерево за забором,
			# верёвка с бельём между домом и деревом, солнце и облака; к коту катится клубок
			"scene": [
				# небо: солнце с лучами и облака
				["circle", [0.6, 0.11], 0.05],
				["line", [[0.6, 0.03], [0.6, 0.045]]], ["line", [[0.6, 0.175], [0.6, 0.19]]],
				["line", [[0.52, 0.11], [0.535, 0.11]]], ["line", [[0.665, 0.11], [0.68, 0.11]]],
				["line", [[0.545, 0.055], [0.555, 0.065]]], ["line", [[0.645, 0.155], [0.655, 0.165]]],
				["line", [[0.655, 0.055], [0.645, 0.065]]], ["line", [[0.555, 0.155], [0.545, 0.165]]],
				["arc", [0.24, 0.1], 0.04, 180, 360], ["arc", [0.3, 0.09], 0.05, 180, 360], ["arc", [0.36, 0.1], 0.035, 180, 360],
				["line", [[0.2, 0.1], [0.395, 0.1]]],
				# земля
				["line", [[0.02, 0.72], [0.98, 0.72]]],
				# большой дом: стены, крыша, труба, окна с переплётом, арочная дверь
				["line", [[0.08, 0.4], [0.5, 0.4], [0.5, 0.72], [0.08, 0.72]], true],
				["line", [[0.04, 0.41], [0.29, 0.19], [0.54, 0.41]]],
				["line", [[0.38, 0.3], [0.38, 0.21], [0.44, 0.21], [0.44, 0.35]]],
				["line", [[0.12, 0.46], [0.22, 0.46], [0.22, 0.56], [0.12, 0.56]], true],
				["line", [[0.17, 0.46], [0.17, 0.56]]], ["line", [[0.12, 0.51], [0.22, 0.51]]],
				["line", [[0.36, 0.46], [0.46, 0.46], [0.46, 0.56], [0.36, 0.56]], true],
				["line", [[0.41, 0.46], [0.41, 0.56]]], ["line", [[0.36, 0.51], [0.46, 0.51]]],
				["line", [[0.25, 0.72], [0.25, 0.6]]], ["line", [[0.33, 0.72], [0.33, 0.6]]], ["arc", [0.29, 0.6], 0.04, 180, 360],
				# верёвка с бельём от дома к дереву
				["arc", [0.66, 0.2], 0.18, 40, 140],
				["line", [[0.6, 0.37], [0.6, 0.42], [0.63, 0.42], [0.63, 0.375]]],
				["line", [[0.68, 0.375], [0.68, 0.43], [0.71, 0.43], [0.71, 0.37]]],
				# дерево за забором
				["line", [[0.85, 0.72], [0.86, 0.42]]], ["line", [[0.9, 0.72], [0.89, 0.42]]],
				["circle", [0.87, 0.3], 0.1],
				# забор справа и кот на нём
				["line", [[0.56, 0.6], [0.97, 0.6]]], ["line", [[0.56, 0.67], [0.97, 0.67]]],
				["line", [[0.58, 0.57], [0.58, 0.72]]], ["line", [[0.66, 0.57], [0.66, 0.72]]],
				["line", [[0.74, 0.57], [0.74, 0.72]]], ["line", [[0.82, 0.57], [0.82, 0.72]]],
				["line", [[0.94, 0.57], [0.94, 0.72]]],
				["tpl", "cat", [0.69, 0.43, 0.13, 0.14]],
				# передний план: клубок с ниткой, миска, рыбья косточка, дорожка из плиток к двери
				["tpl", "yarn", [0.4, 0.83, 0.08, 0.08]], ["wave", [0.48, 0.87], 0.6, 0.015, 0.06],
				["arc", [0.15, 0.84], 0.04, 0, 180], ["line", [[0.11, 0.84], [0.19, 0.84]]],
				["tpl", "fish", [0.82, 0.8, 0.1, 0.05], true],
				["line", [[0.26, 0.76], [0.32, 0.76], [0.32, 0.79], [0.26, 0.79]], true],
				["line", [[0.25, 0.83], [0.31, 0.83], [0.31, 0.86], [0.25, 0.86]], true],
				["line", [[0.24, 0.9], [0.3, 0.9], [0.3, 0.93], [0.24, 0.93]], true],
			]},

		# большие карты — картины из иллюстраций Fluent Emoji (MIT): маска maps/pic/<id>.png, см. tools/gen_picture_maps.py
		_pic("mountains", {"u_rate": 3, "hp_base": 3.0, "hp_growth": 0.03, "goal": 180000}),
		_pic("ocean", {"u_rate": 2, "hp_base": 3.5, "hp_growth": 0.02, "goal": 230000}),
		_pic("night", {"u_rate": 2, "hp_base": 4.0, "hp_growth": 0.015, "goal": 280000}),
	]


## Вписывает набор многоугольников в квадрат 0..1 с сохранением пропорций.
static func norm(polys: Array) -> Array:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in polys:
		for v in p:
			mn = mn.min(v)
			mx = mx.max(v)
	var sz := mx - mn
	var s := 1.0 / maxf(sz.x, sz.y)
	var off := (Vector2.ONE - sz * s) * 0.5
	var out: Array = []
	for p in polys:
		var q := PackedVector2Array()
		for v in p:
			q.append((v - mn) * s + off)
		out.append(q)
	return out


static func rect_poly(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


static func ellipse_poly(c: Vector2, rx: float, ry: float, n: int = 48) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in n:
		var a := TAU * k / n
		p.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return p


static func star_poly(c: Vector2, ro: float, ri: float, pts: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in pts * 2:
		var a := -PI / 2.0 + PI * k / pts
		var r := ro if k % 2 == 0 else ri
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p


static func heart_poly(c: Vector2, size: float, n: int = 64) -> PackedVector2Array:
	var s := size / 17.0
	var p := PackedVector2Array()
	for k in n:
		var t := TAU * k / n
		var st := sin(t)
		var x := 16.0 * st * st * st
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		p.append(c + Vector2(x, y) * s)
	return p


static func tree_poly() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(350, 170), Vector2(450, 320), Vector2(400, 320), Vector2(510, 450),
		Vector2(440, 450), Vector2(570, 590), Vector2(385, 590), Vector2(385, 670),
		Vector2(315, 670), Vector2(315, 590), Vector2(130, 590), Vector2(260, 450),
		Vector2(190, 450), Vector2(300, 320), Vector2(250, 320)])


static func union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	return largest(Geometry2D.merge_polygons(a, b))


static func subtract(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	return largest(Geometry2D.clip_polygons(a, b))


static func largest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var ba := -1.0
	for p in polys:
		var a := absf(area(p))
		if a > ba:
			ba = a
			best = p
	return best


static func area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

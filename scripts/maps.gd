extends RefCounted
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
	{"name": "Пустыня", "templates": ["cactus", "mountain", "star", "drop"], "floor": Color(0.19, 0.16, 0.11), "hue": 0.05},
	{"name": "Ледник", "templates": ["snowflake", "mountain", "gem", "star"], "floor": Color(0.1, 0.15, 0.21), "hue": -0.18},
	{"name": "Космос", "templates": ["rocket", "star", "moon", "gem"], "floor": Color(0.07, 0.07, 0.14), "hue": 0.35},
	{"name": "Королевство", "templates": ["crown", "castle", "heart", "gem"], "floor": Color(0.15, 0.11, 0.18), "hue": 0.5},
	{"name": "Цветочный луг", "templates": ["flower", "tree", "mushroom", "heart"], "floor": Color(0.1, 0.17, 0.12), "hue": -0.05},
	{"name": "Гроза", "templates": ["bolt", "drop", "moon", "star"], "floor": Color(0.12, 0.13, 0.17), "hue": -0.3},
	{"name": "Глубины", "templates": ["fish", "drop", "star", "yarn"], "floor": Color(0.06, 0.13, 0.17), "hue": -0.22},
	{"name": "Кошачий город", "templates": ["cat", "house", "yarn", "fish"], "floor": Color(0.14, 0.14, 0.18), "hue": 0.1},
	{"name": "Лес", "templates": ["tree", "mushroom", "house", "flower"], "floor": Color(0.09, 0.14, 0.1), "hue": 0.0},
	{"name": "Вулкан", "templates": ["mountain", "drop", "gem", "bolt"], "floor": Color(0.18, 0.1, 0.09), "hue": 0.12},
	{"name": "Ночь", "templates": ["moon", "star", "cat", "house"], "floor": Color(0.08, 0.08, 0.13), "hue": 0.28},
	{"name": "Сокровища", "templates": ["gem", "crown", "heart", "star"], "floor": Color(0.16, 0.14, 0.09), "hue": 0.08},
]


## Карта по номеру (0, 1, 2, …): первые HANDMADE — нарисованные, дальше — бесконечные уровни.
## Один и тот же номер всегда даёт одну и ту же карту (у всех игроков одинаковую).
static func get_map(i: int) -> Dictionary:
	if i < HANDMADE:
		return get_maps()[i]
	var lv := i - HANDMADE + 1               # 1, 2, 3, … среди бесконечных
	var theme: Dictionary = THEMES[(lv - 1) % THEMES.size()]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000003 * i + 7
	var size: int = [4000, 6000, 8000, 10000][rng.randi() % 4]
	return {
		"id": "lv%d" % (i + 1), "name": theme["name"], "number": i + 1,
		"w": size, "h": int(size * rng.randf_range(1.0, 1.25)), "aim": -70.0,
		"u_rate": 2, "hp_base": HP_BASE + HP_STEP * lv, "hp_growth": 0.015,
		"goal": int(minf(GOAL_BASE * (1.0 + GOAL_STEP * (lv - 1)), 1.0e15)),
		"region": rng.randi_range(44, 72), "density": rng.randf_range(0.6, 0.78),
		"templates": theme["templates"], "floor": theme["floor"], "hue": theme["hue"],
		"layout": LAYOUTS[(lv * 7 + rng.randi() % 3) % LAYOUTS.size()],
	}


## Бесконечные уровни растут линейно — в том же темпе, что и бонус монет (+25% за карту).
## Экспоненциальный рост делал далёкие уровни непроходимыми на старте (каждая карта начинается
## с одного шара) и переполнял числа (тест test_endless_levels). Подобрано симулятором баланса.
## Узоры раскладки картинок (см. game.gd → _layout_slot).
const LAYOUTS := ["rings", "rays", "spiral", "checker", "mosaic"]

const HP_BASE := 4.0
const HP_STEP := 0.35
const GOAL_BASE := 150000
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
		{"id": "garden", "layout": "mosaic", "u_rate": 12, "name": "Сад", "w": 100, "h": 120, "aim": -70.0,
			"hp_base": 2.0, "hp_growth": 0.12, "goal": 0, "region": 30, "density": 0.85,
			"templates": ["tree", "house", "heart", "mushroom"]},
		{"id": "yard", "layout": "rings", "u_rate": 5, "name": "Кошачий двор", "w": 300, "h": 360, "aim": -70.0,
			"hp_base": 2.5, "hp_growth": 0.06, "goal": 25000, "region": 40, "density": 0.75,
			"templates": ["cat", "yarn", "fish", "house", "heart"]},
		{"id": "mountains", "layout": "rays", "u_rate": 3, "name": "Горы", "w": 1000, "h": 1200, "aim": -70.0,
			"hp_base": 3.0, "hp_growth": 0.03, "goal": 80000, "region": 48, "density": 0.7,
			"templates": ["mountain", "moon", "star", "tree", "mushroom"]},
		{"id": "ocean", "layout": "spiral", "u_rate": 2, "name": "Океан", "w": 3000, "h": 3600, "aim": -70.0,
			"hp_base": 3.5, "hp_growth": 0.02, "goal": 150000, "region": 56, "density": 0.65,
			"templates": ["fish", "star", "moon", "heart", "yarn"]},
		{"id": "night", "layout": "rings", "u_rate": 2, "name": "Звёздная ночь", "w": 10000, "h": 10000, "aim": -70.0,
			"hp_base": 4.0, "hp_growth": 0.015, "goal": 200000, "region": 64, "density": 0.65,
			"templates": all},
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

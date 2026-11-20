extends RefCounted
## Карты. border — внешняя граница (пустая = прямоугольник), obstacles — фигуры-картинки.

const W := 700.0
const H := 840.0


static func get_maps() -> Array:
	# Координаты задаются в «дизайн-пространстве» 700×840 и растягиваются на сетку карты.
	# Препятствия превращаются в стенки из белых кубиков, внутри — полость с квадратами и вход.
	var none := PackedVector2Array()
	var house := PackedVector2Array([Vector2(230, 470), Vector2(350, 330), Vector2(470, 470),
		Vector2(470, 620), Vector2(230, 620)])

	var cat := ellipse_poly(Vector2(350, 390), 170, 170)
	cat = union(cat, PackedVector2Array([Vector2(200, 335), Vector2(215, 165), Vector2(310, 235)]))
	cat = union(cat, PackedVector2Array([Vector2(500, 335), Vector2(485, 165), Vector2(390, 235)]))

	var mountains := PackedVector2Array([
		Vector2(6, 834), Vector2(6, 640), Vector2(90, 560), Vector2(150, 610),
		Vector2(260, 450), Vector2(330, 540), Vector2(400, 480), Vector2(520, 600),
		Vector2(600, 520), Vector2(694, 610), Vector2(694, 834)])
	var moon := subtract(ellipse_poly(Vector2(560, 170), 70, 70), ellipse_poly(Vector2(595, 140), 62, 62))

	var fish := union(ellipse_poly(Vector2(320, 420), 280, 300, 72),
		PackedVector2Array([Vector2(520, 420), Vector2(694, 190), Vector2(694, 650)]))
	var gill := subtract(ellipse_poly(Vector2(250, 420), 165, 165), ellipse_poly(Vector2(212, 420), 157, 157))

	var sky_moon := subtract(ellipse_poly(Vector2(110, 110), 70, 70), ellipse_poly(Vector2(140, 85), 62, 62))

	return [
		{"id": "meadow", "name": "Лужайка", "cols": 16, "hp_base": 1.0, "hp_growth": 0.30,
			"start": Vector2(350, 800), "aim": -70.0, "border": none, "obstacles": [house]},
		{"id": "heart", "name": "Сердце", "cols": 22, "hp_base": 1.5, "hp_growth": 0.30,
			"start": Vector2(350, 800), "aim": -70.0, "border": none,
			"obstacles": [heart_poly(Vector2(350, 370), 190.0)]},
		{"id": "tree", "name": "Ёлка", "cols": 28, "hp_base": 2.0, "hp_growth": 0.28,
			"start": Vector2(350, 800), "aim": -70.0, "border": none,
			"obstacles": [tree_poly(), star_poly(Vector2(350, 95), 50, 22, 5)]},
		{"id": "cat", "name": "Кот", "cols": 34, "hp_base": 2.5, "hp_growth": 0.26,
			"start": Vector2(350, 800), "aim": -70.0, "border": none,
			"obstacles": [cat, ellipse_poly(Vector2(585, 690), 60, 60)]},
		{"id": "mountains", "name": "Горы и луна", "cols": 40, "hp_base": 3.0, "hp_growth": 0.25,
			"start": Vector2(350, 50), "aim": 110.0, "border": none, "obstacles": [mountains, moon]},
		{"id": "fish", "name": "Рыба", "cols": 48, "hp_base": 3.5, "hp_growth": 0.24,
			"start": Vector2(440, 640), "aim": -70.0, "border": fish,
			"obstacles": [ellipse_poly(Vector2(150, 330), 34, 34), gill]},
		{"id": "sky", "name": "Звёздная ночь", "cols": 56, "hp_base": 4.0, "hp_growth": 0.22,
			"start": Vector2(350, 800), "aim": -70.0, "border": none,
			"obstacles": [sky_moon,
				star_poly(Vector2(470, 150), 95, 42, 5), star_poly(Vector2(200, 330), 85, 38, 5),
				star_poly(Vector2(500, 420), 110, 48, 5), star_poly(Vector2(160, 600), 75, 34, 5),
				star_poly(Vector2(560, 650), 70, 32, 5)]},
	]


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

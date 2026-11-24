extends RefCounted
## Иконки рисуются кодом один раз при запуске — без файлов картинок.

static func _img(sz: int) -> Image:
	return Image.create(sz, sz, false, Image.FORMAT_RGBA8)


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _cov(d: float) -> float:
	# сглаживание края: d — расстояние до границы в пикселях (отрицательное внутри)
	return clampf(0.5 - d, 0.0, 1.0)


static func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if a <= 0.0:
		return
	var base := img.get_pixel(x, y)
	var na := a * c.a
	var out_a := na + base.a * (1.0 - na)
	if out_a <= 0.0:
		return
	var rgb := (Color(c.r, c.g, c.b) * na + Color(base.r, base.g, base.b) * base.a * (1.0 - na)) / out_a
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, out_a))


static func _disk(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	var sz := img.get_width()
	for y in sz:
		for x in sz:
			_blend(img, x, y, c, _cov(Vector2(x + 0.5 - cx, y + 0.5 - cy).length() - r))


## Шарик: белый с тёмной обводкой и бликом — цвет задаётся модуляцией.
static func ball(sz: int = 64) -> ImageTexture:
	var img := _img(sz)
	var h := sz * 0.5
	_disk(img, h, h, h - 1.0, Color(0.05, 0.06, 0.1, 0.85))
	_disk(img, h, h, h - sz * 0.12, Color(1, 1, 1))
	_disk(img, h - sz * 0.13, h - sz * 0.13, sz * 0.13, Color(1, 1, 1, 0.9))
	return _tex(img)


## Запас места вокруг шара в текстуре силуэта (под кольцо Никитиевого и флажок Знаменосца).
const BALL_K := 1.5


## Заливка со сглаживанием: покрытие пикселя по 3×3 подвыборкам; inside(x, y) — внутри ли фигуры.
static func _fill_ss(img: Image, c: Color, inside: Callable, box: Rect2) -> void:
	var sz := img.get_width()
	var x0 := maxi(0, int(box.position.x) - 1)
	var y0 := maxi(0, int(box.position.y) - 1)
	var x1 := mini(sz - 1, int(box.end.x) + 1)
	var y1 := mini(sz - 1, int(box.end.y) + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var n := 0
			for sy in 3:
				for sx in 3:
					if inside.call(x + (sx + 0.5) / 3.0, y + (sy + 0.5) / 3.0):
						n += 1
			if n > 0:
				_blend(img, x, y, c, n / 9.0)


static func _in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p - b).cross(a - b)
	var d2 := (p - c).cross(b - c)
	var d3 := (p - a).cross(c - a)
	var neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (neg and pos)


## Силуэт шара по типу (цветной, без модуляции): тип читается по форме, а не только по цвету.
##   basic — круг с бликом; sniper — круг (шлейф рисуется на лету по полёту); splash — пунктирное кольцо;
##   poison — белая капля; banner — флажок; pierce — толстый белый обод и тёмная сердцевина.
## ui = true — значок для фишек и карточек: у Гесиевого шлейф нарисован в самом значке (на поле шлейф живой,
## по направлению полёта, поэтому в текстуре поля его нет).
static func ball_type(t: String, col: Color, sz: int = 96, ui: bool = false) -> ImageTexture:
	var img := _img(sz)
	var h := sz * 0.5
	var r := h / BALL_K
	var trail := ui and t == "sniper"
	var c := Vector2(h + (r * 0.38 if trail else 0.0), h)
	if trail:
		# две полосы движения слева от шара
		for k in 2:
			var yy := c.y + (-r * 0.34 if k == 0 else r * 0.34)
			var x0 := sz * 0.04
			var x1 := c.x - r * 1.05
			var w := r * 0.16
			var a := 0.8 if k == 0 else 0.5
			_fill_ss(img, Color(col.r, col.g, col.b, a), func(x, y):
				var p := Vector2(x, y)
				var q := Vector2(clampf(p.x, x0, x1), yy)
				return p.distance_to(q) <= w, Rect2(x0 - w, yy - w, x1 - x0 + 2.0 * w, w * 2.0))
	if t == "splash":
		var rr := r * 1.4
		var w := r * 0.13
		_fill_ss(img, col, func(x, y):
			var v := Vector2(x, y) - c
			var d := v.length()
			if absf(d - rr) > w:
				return false
			return int(floor((v.angle() + PI) / TAU * 10.0)) % 2 == 0, Rect2(c - Vector2(rr + w, rr + w), Vector2(rr + w, rr + w) * 2.0))
	if t == "banner":
		# флажок крупный — читается и на фишке, и на поле в мелком масштабе
		var px := c.x - r * 0.25
		var top := Vector2(px, c.y - r * 1.46)
		var w := r * 0.13
		_fill_ss(img, Color(0.05, 0.06, 0.1, 0.9), func(x, y): return absf(x - px) <= w + 1.5 and y >= top.y - 1.5 and y <= c.y - r * 0.5,
			Rect2(px - w - 2, top.y - 2, w * 2.0 + 4, r))
		_fill_ss(img, Color(1, 1, 1), func(x, y): return absf(x - px) <= w and y >= top.y and y <= c.y - r * 0.55,
			Rect2(px - w, top.y, w * 2.0, r))
		var a := top
		var b := top + Vector2(r * 1.12, r * 0.3)
		var d := top + Vector2(0, r * 0.62)
		_fill_ss(img, Color(0.05, 0.06, 0.1, 0.9), func(x, y): return _in_tri(Vector2(x, y), a + Vector2(-2, -2.5), b + Vector2(3.5, 0), d + Vector2(-2, 2.5)),
			Rect2(a.x - 3, a.y - 3, r * 1.3, r * 0.8))
		_fill_ss(img, Color(1, 1, 1), func(x, y): return _in_tri(Vector2(x, y), a, b, d), Rect2(a.x, a.y, r * 1.2, r * 0.7))
	if t == "poison":
		# Антониевый — сам шар-капля: круглый низ и заострённый кончик вверх. Отличие — в контуре, поэтому
		# тип читается и в мелком масштабе (белая капля внутри круга на телефоне не различалась)
		var dc := c + Vector2(0, r * 0.22)
		var dr := r * 0.9
		var tip := c + Vector2(0, -r * 1.38)
		var bl := dc + Vector2(-dr * 0.78, -dr * 0.62)
		var br := dc + Vector2(dr * 0.78, -dr * 0.62)
		var inside := func(p: Vector2, grow: float) -> bool:
			return p.distance_to(dc) <= dr + grow or _in_tri(p, tip + Vector2(0, -grow * 1.6), bl + Vector2(-grow, 0), br + Vector2(grow, 0))
		var box := Rect2(c.x - r * 1.1, tip.y - 3.0, r * 2.2, dc.y + dr - tip.y + 6.0)
		_fill_ss(img, Color(0.05, 0.06, 0.1, 0.85), func(x, y): return inside.call(Vector2(x, y), 1.5), box)
		_fill_ss(img, col, func(x, y): return inside.call(Vector2(x, y), 0.0), box)
		_disk(img, dc.x - dr * 0.34, dc.y - dr * 0.2, dr * 0.24, Color(1, 1, 1, 0.85))
		return _tex(img)
	_disk(img, c.x, c.y, r + 1.5, Color(0.05, 0.06, 0.1, 0.85))
	_disk(img, c.x, c.y, r, col)
	match t:
		"pierce":
			_fill_ss(img, Color(1, 1, 1), func(x, y):
				var d := Vector2(x, y).distance_to(c)
				return d <= r and d >= r * 0.66, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
			_disk(img, c.x, c.y, r * 0.4, col.darkened(0.5))
		_:
			_disk(img, c.x - r * 0.32, c.y - r * 0.32, r * 0.26, Color(1, 1, 1, 0.85))
	return _tex(img)


## Круглый значок цвета шара для фишек и карточек.
static func dot(col: Color, sz: int = 44) -> ImageTexture:
	var img := _img(sz)
	var h := sz * 0.5
	_disk(img, h, h, h - 1.0, Color(0, 0, 0, 0.45))
	_disk(img, h, h, h - 4.0, col)
	_disk(img, h - sz * 0.12, h - sz * 0.12, sz * 0.12, Color(1, 1, 1, 0.55))
	return _tex(img)


static func coin(sz: int = 40) -> ImageTexture:
	var img := _img(sz)
	var h := sz * 0.5
	_disk(img, h, h + 1.5, h - 1.5, Color(0.55, 0.36, 0.05))
	_disk(img, h, h, h - 1.5, Color(1.0, 0.78, 0.2))
	_disk(img, h, h, h * 0.62, Color(0.95, 0.62, 0.1))
	_disk(img, h, h, h * 0.5, Color(1.0, 0.82, 0.3))
	_disk(img, h - h * 0.25, h - h * 0.3, h * 0.18, Color(1, 1, 1, 0.7))
	return _tex(img)


static func gem(sz: int = 40) -> ImageTexture:
	var img := _img(sz)
	var h := sz * 0.5
	for y in sz:
		for x in sz:
			var dx := absf(x + 0.5 - h)
			var dy := absf(y + 0.5 - h)
			var d := (dx * 0.85 + dy - h * 0.92) / 1.3
			var top := y + 0.5 < h
			var col := Color(0.78, 0.55, 1.0) if top else Color(0.55, 0.3, 0.92)
			if top and x + 0.5 < h:
				col = Color(0.9, 0.75, 1.0)
			_blend(img, x, y, col, _cov(d))
	return _tex(img)


static func menu(sz: int = 40) -> ImageTexture:
	var img := _img(sz)
	for i in 3:
		var cy := sz * (0.28 + 0.22 * i)
		for y in sz:
			for x in sz:
				var dx := maxf(0.0, absf(x + 0.5 - sz * 0.5) - sz * 0.3)
				var dy := absf(y + 0.5 - cy)
				_blend(img, x, y, Color.WHITE, _cov(Vector2(dx, dy).length() - sz * 0.06))
	return _tex(img)


static func arrow_up(sz: int = 40) -> ImageTexture:
	var img := _img(sz)
	var h := sz * 0.5
	for y in sz:
		for x in sz:
			var px := x + 0.5
			var py := y + 0.5
			# наконечник
			var tip := py >= sz * 0.15 and py <= sz * 0.55 and absf(px - h) <= (py - sz * 0.15) * 0.95
			# древко
			var stem := absf(px - h) <= sz * 0.1 and py >= sz * 0.45 and py <= sz * 0.85
			var a := 1.0 if tip or stem else 0.0
			_blend(img, x, y, Color.WHITE, a)
	return _tex(img)


static func refresh(sz: int = 40) -> ImageTexture:
	var img := _img(sz)
	var h := sz * 0.5
	var r := sz * 0.32
	var w := sz * 0.08
	for y in sz:
		for x in sz:
			var v := Vector2(x + 0.5 - h, y + 0.5 - h)
			var ang := fposmod(v.angle(), TAU)
			if ang > TAU * 0.80 or ang < TAU * 0.05:
				continue
			_blend(img, x, y, Color.WHITE, _cov(absf(v.length() - r) - w))
	# наконечник стрелки на конце дуги
	var end := Vector2(h, h) + Vector2.from_angle(TAU * 0.80) * r
	for y in sz:
		for x in sz:
			var p := Vector2(x + 0.5, y + 0.5) - end
			var q := p.rotated(-TAU * 0.80)
			if q.y <= 0.0 and q.y >= -sz * 0.2 and absf(q.x) <= (q.y + sz * 0.2) * 0.9:
				_blend(img, x, y, Color.WHITE, 1.0)
	return _tex(img)


static func angle(sz: int = 40) -> ImageTexture:
	var img := _img(sz)
	var o := Vector2(sz * 0.18, sz * 0.82)
	var a := o + Vector2(sz * 0.68, 0)
	var b := o + Vector2.from_angle(-PI / 4.0) * sz * 0.75
	for y in sz:
		for x in sz:
			var p := Vector2(x + 0.5, y + 0.5)
			var d1 := Geometry2D.get_closest_point_to_segment(p, o, a).distance_to(p)
			var d2 := Geometry2D.get_closest_point_to_segment(p, o, b).distance_to(p)
			var d := minf(d1, d2) - sz * 0.05
			var arc := absf(p.distance_to(o) - sz * 0.36) - sz * 0.035
			var pa := (p - o).angle()
			if pa < -PI / 4.0 or pa > 0.0:
				arc = 99.0
			_blend(img, x, y, Color.WHITE, maxf(_cov(d), _cov(arc)))
	return _tex(img)


static func lock(sz: int = 40) -> ImageTexture:
	var img := _img(sz)
	var h := sz * 0.5
	for y in sz:
		for x in sz:
			var p := Vector2(x + 0.5, y + 0.5)
			var body := Vector2(maxf(0.0, absf(p.x - h) - sz * 0.26), maxf(0.0, absf(p.y - sz * 0.66) - sz * 0.18)).length() - sz * 0.04
			var sh := absf(p.distance_to(Vector2(h, sz * 0.42)) - sz * 0.17) - sz * 0.05
			if p.y > sz * 0.45:
				sh = 99.0
			_blend(img, x, y, Color(1, 1, 1, 0.8), maxf(_cov(body), _cov(sh)))
	return _tex(img)

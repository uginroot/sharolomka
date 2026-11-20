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

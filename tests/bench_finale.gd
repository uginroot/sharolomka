extends Node
## Стенд производительности финала большой карты: «Обсерватория» (720×720), разбито всё, кроме 1500 квадратов,
## 200 шаров. Печатает время старта финала и кадра (среднее и худшее) по частям.
##   godot --headless --path . res://tests/bench_finale.tscn
func _ready():
	_run.call_deferred()


func _run():
	get_window().size = Vector2i(720, 1280)
	GameData.reset_all()
	GameData.maps_unlocked = 8
	GameData.current_map = 6
	var g = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	# досоздаём всё и «разбиваем» карту, кроме 1500 случайных квадратов
	var ids := PackedInt32Array()
	for ck in g.chunks.size():
		var c = g._get_chunk(ck)
		var ox: int = (ck % g.cw) * 32
		var oy: int = (ck / g.cw) * 32
		for li in 1024:
			if c.kind[li] == 1:
				ids.append((oy + (li >> 5)) * g.W + ox + (li & 31))
	var keep := {}
	seed(7)
	while keep.size() < 1500:
		keep[ids[randi() % ids.size()]] = true
	for id in ids:
		if keep.has(id):
			continue
		var x: int = id % g.W
		var y: int = id / g.W
		var c = g.chunks[(x >> 5) + (y >> 5) * g.cw]
		var li := ((y & 31) << 5) | (x & 31)
		c.kind[li] = 0
		c.solid -= 1
		c.vis[li] = 1
	g.destroyed = g.total - 1500
	g.alive = 1500
	g.goal_done = true
	print("подготовка стенда: %d мс" % ((Time.get_ticks_usec() - t0) / 1000))
	g.coins = 1e15
	for k in 200:
		g._spawn_ball(["basic", "sniper"][k % 2], randf() * 360.0, (Vector2(randi() % g.W, randi() % g.H) + Vector2(0.5, 0.5)) * 40.0)
	var t1 := Time.get_ticks_usec()
	g._check_goal()
	print("старт финала: %d мс (финал=%s)" % [(Time.get_ticks_usec() - t1) / 1000, g.finale])
	var tot := 0.0
	var worst := 0.0
	var frames := 240
	for f in frames:
		var a := Time.get_ticks_usec()
		g._sim(1.0 / 60.0)
		var dt := (Time.get_ticks_usec() - a) / 1000.0
		tot += dt
		worst = maxf(worst, dt)
	print("кадр в финале: среднее %.2f мс, худшее %.2f мс (осталось %d)" % [tot / frames, worst, g.alive])
	# по частям: только поле расстояний и только наведение
	var a2 := Time.get_ticks_usec()
	g._finale_field()
	while g.bfs_busy:
		g._finale_field_step()
	print("полный пересчёт поля: %d мс" % ((Time.get_ticks_usec() - a2) / 1000))
	var a3 := Time.get_ticks_usec()
	for b in g.balls:
		g._finale_steer(b)
	print("наведение 200 шаров: %.2f мс" % ((Time.get_ticks_usec() - a3) / 1000.0))
	get_tree().quit()

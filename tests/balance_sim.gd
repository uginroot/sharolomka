extends Node
## Симулятор баланса: бот проходит кампанию карта за картой и печатает темп игры.
##   godot --headless --path . res://tests/balance_sim.tscn -- <минут_на_карту> <последняя_карта>
## Бот: стреляет у фронта разрушения, покупает самое дешёвое полезное, тратит U на типы и перки,
## пользуется сбросом. Главная метрика скуки — самая длинная пауза без покупок («ожидание»).

const GAME := preload("res://scenes/game.tscn")
const DT := 1.0 / 20.0

var rng := RandomNumberGenerator.new()
var verbose := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	verbose = true
	var args := OS.get_cmdline_user_args()
	var minutes := float(args[0]) if args.size() > 0 else 20.0
	var last_map := int(args[1]) if args.size() > 1 else 3
	rng.seed = 42
	seed(42)
	GameData.reset_all()
	GameData.lang_choice = "ru"
	GameData.apply_settings()
	print("карта;мин;монет/с;разбито;шаров;урон(обыч);U;покупок/мин;макс.ожидание,с;событие")
	for m in range(0, last_map + 1):
		GameData.current_map = m
		var g = GAME.instantiate()
		add_child(g)
		await get_tree().process_frame
		var r := _play(g, minutes)
		print("ИТОГ %s: цель %s за %s мин, монет/с в конце %.0f, U всего %d, самое долгое ожидание %.0f с" % [
			g.map["id"], "достигнута" if g.goal_done else "НЕ достигнута", r["goal_min"], r["last_rate"],
			g.run_u + r["u_spent"], r["max_wait"]])
		g.queue_free()
		await get_tree().process_frame
		GameData.maps_unlocked = maxi(GameData.maps_unlocked, m + 2)
		spend_stars()
		print("  ★ после уровня: потрачено, «Наследие»: %s" % str(GameData.meta))
	get_tree().quit()


func _play(g, minutes: float) -> Dictionary:
	var t := 0.0
	var next_report := 0.0
	var last_buy := 0.0
	var max_wait := 0.0
	var buys_window := 0
	var coins_mark: int = g.coins
	var earned_mark := 0
	var total_earned := 0
	var prev_coins: int = g.coins
	var goal_min := "—"
	var u_spent := 0
	var last_rate := 0.0
	var think := 0.0
	var reset_t := 0.0
	while t < minutes * 60.0:
		g._sim(DT)
		t += DT
		total_earned += maxi(0, g.coins - prev_coins)
		prev_coins = g.coins
		think -= DT
		if think <= 0.0:
			think = 0.5
			var before: int = g.coins
			var n := _shop(g)
			u_spent += _spend_u(g)
			if n > 0:
				max_wait = maxf(max_wait, t - last_buy)
				last_buy = t
				buys_window += n
			prev_coins = g.coins
		reset_t += DT
		if reset_t > 31.0:
			reset_t = 0.0
			_relaunch_idler(g)
		if not g.goal_done:
			g._check_goal()
			if g.goal_done:
				goal_min = "%.1f" % (t / 60.0)
				if verbose:
					print("%s;%.1f;;;;;;;;ЦЕЛЬ" % [g.map["id"], t / 60.0])
		if t >= next_report:
			var rate := float(total_earned - earned_mark) / maxf(1.0, t - (next_report - 60.0)) if next_report > 0 else 0.0
			earned_mark = total_earned
			last_rate = rate
			if verbose:
				print("%s;%.0f;%.0f;%d;%d;%d;%d;%d;%.0f;" % [g.map["id"], t / 60.0, rate, g.destroyed, g.balls.size(),
					g._damage_of("basic"), g.run_u, buys_window, maxf(max_wait, t - last_buy)])
			buys_window = 0
			next_report += 60.0
		if g.track_all and g.alive <= 0:
			break
		if not verbose and g.goal_done:
			break
	max_wait = maxf(max_wait, t - last_buy)
	return {"goal_min": goal_min, "max_wait": max_wait, "u_spent": u_spent, "last_rate": last_rate}


## Пустая открытая клетка у фронта и направление на соседний квадрат.
func _frontier_shot(g) -> Array:
	for attempt in 40:
		var x := rng.randi_range(g.ex0, g.ex1)
		var y := rng.randi_range(g.ey0, g.ey1)
		if not g._vis_at(x, y) or g._kind_at(x, y) != 0:
			continue
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if g._kind_at(x + o.x, y + o.y) == 1:
				var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * 40.0
				var ang := rad_to_deg(Vector2(o).angle()) + rng.randf_range(-35.0, 35.0)
				return [p, ang]
	return [g.last_launch, rng.randf_range(-180.0, 180.0)]


## Покупает самое дешёвое из полезного: пуск любого открытого типа или уровень любой его ветки.
func _shop(g) -> int:
	var bought := 0
	for k in 20:
		var best_cost := INF
		var best := []
		for t in GameData.TYPE_ORDER:
			if not g.unl[t]:
				continue
			var c: float = g._ball_cost(t)
			if c < best_cost:
				best_cost = c
				best = ["ball", t, ""]
			for tr_ in GameData.TYPES[t]["tracks"]:
				var tc: float = g._track_cost(t, tr_["id"]) * (1.3 if tr_["id"] == "speed" else 1.0)
				if int(g.counts[t]) > 0 and tc < best_cost:
					best_cost = tc
					best = ["track", t, tr_["id"]]
		if best.is_empty():
			break
		var real: float = g._ball_cost(best[1]) if best[0] == "ball" else g._track_cost(best[1], best[2])
		if g.coins < real:
			break
		if best[0] == "ball":
			g.selected = best[1]
			var s := _frontier_shot(g)
			g.aim_angle = s[1]
			g._fire(s[0])
		else:
			g._buy_track(best[1], best[2])
		bought += 1
	return bought


## U-баллы уровня — на открытие типов (1 U), в порядке каталога.
func _spend_u(g) -> int:
	var spent := 0
	for t in GameData.TYPE_ORDER:
		if not g.unl[t] and g.run_u >= 1:
			g._unlock_type(t)
			spent += 1
	return spent


## ★ между уровнями — на самое дешёвое доступное улучшение «Наследия» (типы шаров в приоритете).
func spend_stars() -> void:
	for k in 50:
		var best := ""
		var bc := 999
		for m in GameData.META:
			var id: String = m["id"]
			if GameData.meta_can_buy(id):
				var c := GameData.meta_cost(id)
				if c < bc:
					bc = c
					best = id
		if best == "":
			break
		GameData.meta_buy(best)


func _relaunch_idler(g) -> void:
	for t in GameData.TYPE_ORDER:
		if int(g.counts[t]) > 0 and g.reset_cd[t] <= 0.0:
			g.selected = t
			var s := _frontier_shot(g)
			g.aim_angle = s[1]
			g.reset_armed = true
			g._relaunch_idler(s[0])
			return

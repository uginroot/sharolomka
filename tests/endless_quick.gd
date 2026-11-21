extends Node
## Быстрая проверка темпа бесконечных уровней с прокачанным аккаунтом (как после кампании).
func _ready():
	GameData.reset_all(); GameData.lang_choice = "ru"; GameData.apply_settings()
	for t in GameData.TYPE_ORDER:
		GameData.unlocked[t] = true; GameData.perks[t] = 5; GameData.supers[t] = true
	var bot = load("res://tests/balance_sim.gd").new()
	bot.rng.seed = 7
	var args := OS.get_cmdline_user_args()
	for a in args:
		var i := int(a)
		GameData.maps_done = {}
		for k in i: GameData.maps_done["m%d" % k] = true
		GameData.mastery = 8 + (i - 7) * 2
		GameData.current_map = i
		var g = load("res://scenes/game.tscn").instantiate(); add_child(g)
		await get_tree().process_frame
		var r = bot._play(g, 75.0)
		print("уровень %d: цель %d — за %s мин, самая долгая пауза %.0f с" % [i + 1, g.goal, r["goal_min"], r["max_wait"]])
		g.queue_free(); await get_tree().process_frame
	get_tree().quit()

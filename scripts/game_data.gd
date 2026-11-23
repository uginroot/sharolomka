extends Node
## Глобальные данные: типы шариков, «Наследие», открытые карты, профили, сохранения.

const I18n = preload("res://scripts/i18n.gd")
const LANGS := I18n.LANGS
const LANG_NAMES := I18n.NAMES
## Шесть шаров с ясными ролями — перенесены из pixel-rikoshet («Глубинный пиксель»), v0.26.
## Внутренние id прежние (на них держатся сохранения): basic = Пронизывающий, sniper = Гесиевый,
## splash = Никитиевый, poison = Антониевый, banner = Знаменосец, pierce = Отбойник.
## Порядок как там: orange, pink, red, green, banner, golden.
const TYPE_ORDER := ["basic", "sniper", "splash", "poison", "banner", "pierce"]

## Ветки прокачки за монеты: value — прибавка за уровень; prices — заданные цены, дальше ×1.7 за уровень.
const TRACK_SPEED := {"id": "speed", "name": "Скорость", "value": 0.2, "prices": [50, 117, 250]}
const TRACK_IMPACT := {"id": "impact", "name": "Сила удара", "value": 1.0, "prices": [50, 112, 240]}

## fleet — что тип раздаёт всем шарам за каждую ступень купленных (5, 10, 20…80): +5% или +1.
const TYPES := {
	"basic": {
		"name": "Пронизывающий", "desc": "Базовый шар: бьёт клетку, в которую попал, и отскакивает.",
		"color": Color(1.0, 0.58, 0.2), "radius": 7.0, "speed": 330.0, "damage": 1.0, "launch_base": 4.0,
		"tracks": [TRACK_SPEED, TRACK_IMPACT], "fleet": "points",
	},
	"sniper": {
		"name": "Гесиевый", "desc": "Быстро летает и чаще успевает ударить по породе.",
		"color": Color(1.0, 0.45, 0.72), "radius": 6.0, "speed": 660.0, "damage": 1.0, "launch_base": 50.0,
		"tracks": [TRACK_SPEED, TRACK_IMPACT], "fleet": "speed",
	},
	"splash": {
		"name": "Никитиевый", "desc": "Бьёт клетку на полную силу, а открытые клетки рядом — на 25% этой силы.",
		"color": Color(0.95, 0.3, 0.3), "radius": 7.0, "speed": 330.0, "damage": 1.0, "launch_base": 50.0,
		"smash_share": 0.25, "smash_radius": 1,
		"tracks": [TRACK_SPEED, {"id": "impact", "name": "Сила удара", "value": 1.0, "prices": [50, 96]}], "fleet": "splash",
	},
	"poison": {
		"name": "Антониевый", "desc": "Сам породу не бьёт, только отравляет её при ударе. Яд копится на клетке.",
		"color": Color(0.4, 0.88, 0.42), "radius": 7.0, "speed": 330.0, "damage": 0.0, "launch_base": 50.0,
		"poison_ticks": 1, "poison_rate": 1.0,
		"tracks": [TRACK_SPEED,
			{"id": "ticks", "name": "Количество тиков", "value": 1.0, "prices": [50, 112, 233]},
			{"id": "cadence", "name": "Частота тиков яда", "value": 0.5, "prices": [50, 106, 217, 389]}],
		"fleet": "poison",
	},
	"banner": {
		"name": "Знаменосец", "desc": "Шары, которых коснулся его круг, ещё секунду бьют сильнее. Полезен, когда шаров много.",
		"color": Color(0.78, 0.62, 1.0), "radius": 7.0, "speed": 330.0, "damage": 1.0, "launch_base": 50.0,
		"aura_radius": 3.0, "aura_bonus": 0.3, "aura_hold": 1.0,
		"tracks": [TRACK_SPEED,
			{"id": "radius", "name": "Радиус ауры", "value": 1.0, "prices": [50, 100, 170]},
			{"id": "hold", "name": "Длительность бафа", "value": 0.5, "prices": [50, 100, 170]}],
		"fleet": "damage",
	},
	"pierce": {
		"name": "Отбойник", "desc": "Бьёт сильно: базовый удар снимает 8 HP. Для крепкой породы.",
		"color": Color(0.35, 0.58, 1.0), "radius": 8.0, "speed": 330.0, "damage": 8.0, "launch_base": 50.0,
		"tracks": [TRACK_SPEED, {"id": "impact", "name": "Сила удара", "value": 3.0, "prices": [50, 98, 185]}],
		"fleet": "flat",
	},
}

## Бонусы стаи: ступени по числу купленных шаров типа (решение автора pixel-rikoshet).
const FLEET_STEPS := [5, 10, 20, 30, 40, 50, 60, 70, 80]
## Описание бонуса стаи по виду: %d — текущая прибавка.
const FLEET_DESC := {
	"points": "+%d%% монет", "speed": "+%d%% скорости всем", "splash": "+%d%% удара по соседям всем",
	"poison": "+%d%% урона ядом всем", "damage": "+%d%% урона всем", "flat": "+%d к удару всем",
}


## Эволюции (как в pixel-rikoshet): у каждого шара две. Покупка за U уровня: первая 5 U, вторая 10 U.
## Каждая открывает две бесконечные ветки за U: уровень N стоит N U (до 40). Значение = base + step·уровень.
## Всё внутри уровня: на новом уровне эволюции и ветки начинаются заново.
const EVO_COST := 5
const EVO_LATER_MULT := 2
const LADDER_MAX := 40
const EVOS := {
	"basic": [
		{"id": "scout", "name": "Разведка", "desc": "Удар открывает туман вокруг; разбитые клетки с U с шансом дают ещё U.",
			"tracks": [{"id": "scout_radius", "name": "Радиус разведки", "base": 2.0, "step": 1.0},
				{"id": "scout_find", "name": "Находка", "base": 0.0, "step": 0.1}]},
		{"id": "stitch", "name": "Прошивка", "desc": "Удар идёт дальше по линии полёта: клетки за целью получают половину силы.",
			"tracks": [{"id": "stitch_depth", "name": "Глубина прошивки", "base": 1.0, "step": 1.0},
				{"id": "stitch_share", "name": "Сила прошивки", "base": 0.5, "step": 0.1}]},
	],
	"sniper": [
		{"id": "sprint", "name": "Спринтер", "desc": "Каждая секунда без удара по породе даёт +1% скорости. Удар по породе сбрасывает разгон.",
			"tracks": [{"id": "sprint_cap", "name": "Предел разгона", "base": 0.25, "step": 0.25},
				{"id": "sprint_rate", "name": "Темп разгона", "base": 0.01, "step": 0.005}]},
		{"id": "shotgun", "name": "Дробовик", "desc": "Один пуск выпускает веер из нескольких шаров по цене одного.",
			"tracks": [{"id": "shotgun_balls", "name": "Шаров в залпе", "base": 2.0, "step": 0.5},
				{"id": "shotgun_cheap", "name": "Массовое производство", "base": 0.0, "step": 0.05}]},
	],
	"splash": [
		{"id": "lightning", "name": "Молния", "desc": "Разряды бьют всю открытую породу вокруг на четверть силы удара.",
			"tracks": [{"id": "lightning_rate", "name": "Частота молний", "base": 0.25, "step": 0.25},
				{"id": "lightning_range", "name": "Дальность молний", "base": 3.0, "step": 1.0}]},
		{"id": "area", "name": "Площадь", "desc": "Удар по соседям достаёт дальше: радиус сразу 2.",
			"tracks": [{"id": "area_radius", "name": "Радиус удара", "base": 2.0, "step": 1.0},
				{"id": "area_share", "name": "Сила по площади", "base": 0.0, "step": 0.05}]},
	],
	"poison": [
		{"id": "infection", "name": "Инфекция", "desc": "Яд переходит на соседние клетки.",
			"tracks": [{"id": "infection_chance", "name": "Шанс заражения", "base": 0.28, "step": 0.28},
				{"id": "infection_fade", "name": "Затухание заражения", "base": 0.0, "step": 1.0}]},
		{"id": "corrosion", "name": "Разъедание", "desc": "Отравленная клетка получает на 50% больше урона от всех.",
			"tracks": [{"id": "corrosion_bonus", "name": "Уязвимость", "base": 0.5, "step": 0.1},
				{"id": "corrosion_linger", "name": "Остаточная коррозия", "base": 0.0, "step": 2.0}]},
	],
	"banner": [
		{"id": "war_banner", "name": "Боевое знамя", "desc": "Круг даёт ещё +10% урона. Раз в 10 с боевой клич: на секунду круг вдвое шире.",
			"tracks": [{"id": "war_banner_damage", "name": "Бафф урона", "base": 0.1, "step": 0.1},
				{"id": "war_banner_cry", "name": "Боевой клич", "base": 10.0, "step": -1.0, "min": 3.0}]},
		{"id": "tailwind", "name": "Попутный ветер", "desc": "Круг ещё и ускоряет шары внутри.",
			"tracks": [{"id": "tailwind_speed", "name": "Бафф скорости", "base": 0.1, "step": 0.1},
				{"id": "tailwind_self", "name": "Свой ветер", "base": 0.0, "step": 0.3}]},
	],
	"pierce": [
		{"id": "gravity", "name": "Гравитация", "desc": "Тянется к самой крепкой видимой клетке породы в радиусе.",
			"tracks": [{"id": "gravity_force", "name": "Тяга", "base": 600.0, "step": 250.0},
				{"id": "gravity_range", "name": "Дальность притяжения", "base": 6.0, "step": 2.0}]},
		{"id": "kleshch", "name": "Клещ", "desc": "Не разбил клетку с удара — впивается и бурит её, пока не сломает: за секунду снимает столько, сколько один удар.",
			"tracks": [{"id": "kleshch_deeper", "name": "Глубже", "base": 0.0, "step": 1.0},
				{"id": "kleshch_grip", "name": "Хватка", "base": 1.0, "step": 0.25}]},
	],
}


static func evo_def(t: String, id: String) -> Dictionary:
	for e in EVOS[t]:
		if e["id"] == id:
			return e
	return {}


static func evo_track(t: String, track: String) -> Dictionary:
	for e in EVOS[t]:
		for tr_ in e["tracks"]:
			if tr_["id"] == track:
				return tr_
	return {}


static func fleet_steps(count: int) -> int:
	var k := 0
	for s in FLEET_STEPS:
		if count >= s:
			k += 1
	return k


# ---------------------------------------------------------------- прогресс профиля (слота)
var stars := 0               # ★ — за завершение уровней, тратятся в «Наследии»
var meta := {}               # постоянные улучшения: id → уровень
var unlocked := {}           # типы, открытые на старте уровня (только Пронизывающий)
var maps_unlocked := 1
var maps_done := {}
var map_states := {}
var current_map := 0
var slot := 1                # текущий профиль 1..SLOTS

# ---------------------------------------------------------------- общие настройки (на все профили)
var eco_mode := false        # 30 FPS вместо 60
var keep_screen := false     # не гасить экран во время игры
var music_vol := 0.8         # громкость музыки 0..1 (0 — выключена)
var sfx_vol := 0.8           # громкость звуков 0..1
var music_on := true         # = music_vol > 0
var sfx_on := true           # = sfx_vol > 0
var vibration_on := true     # мини-вибрация при начале прицеливания
var magnet_deg := 2          # режим «ключевые»: притяжение к углам, кратным 45°, в пределах ±N° (1–5)
var vibrations := 0          # счётчик вибраций — для тестов
var keep_on_applied := 0     # сколько раз заново применялся «не блокировать экран» — для тестов
var lang := "ru"             # действующий язык интерфейса
var lang_choice := ""        # выбор игрока; пусто — как в системе

const SLOTS := 3
const SETTINGS_PATH := "user://settings.json"

## «Наследие» — постоянные улучшения за ★. Ветки — цепочки: узел требует предыдущий (req).
## max 0 — без предела; цена = cost + step·уровень.
const META := [
	{"id": "coin_bonus", "branch": "Казна", "name": "Бонус монет", "desc": "+10% монет", "max": 0, "cost": 1, "step": 1, "req": ""},
	{"id": "start_coins", "branch": "Казна", "name": "Стартовые монеты", "desc": "Монеты на старте уровня", "max": 5, "cost": 2, "step": 1, "req": "coin_bonus"},
	{"id": "dmg_bonus", "branch": "Сила", "name": "Урон", "desc": "+10% урона всех шаров", "max": 0, "cost": 1, "step": 1, "req": ""},
	{"id": "frenzy", "branch": "Сила", "name": "Золотая лихорадка", "desc": "+3 с лихорадки", "max": 5, "cost": 2, "step": 1, "req": "dmg_bonus"},
	{"id": "u_find", "branch": "Удача", "name": "Поиск U", "desc": "+20% U-баллов", "max": 5, "cost": 2, "step": 1, "req": ""},
	{"id": "start_u", "branch": "Удача", "name": "Стартовые U", "desc": "+1 U на старте уровня", "max": 5, "cost": 2, "step": 1, "req": "u_find"},
	{"id": "start_balls", "branch": "Старт", "name": "Стартовые шары", "desc": "+1 бесплатный шар на старте", "max": 5, "cost": 3, "step": 1, "req": ""},
	{"id": "gold", "branch": "Старт", "name": "Золотые квадраты", "desc": "+20% золотых квадратов", "max": 5, "cost": 2, "step": 1, "req": "start_balls"},
]
const META_BRANCHES := ["Казна", "Сила", "Удача", "Старт"]
## «Арсенал» (открытие типов за ★) убран в v0.26: типы открываются внутри уровня за 1 U, как в pixel-rikoshet.
## Потраченные на него ★ возвращаются при загрузке (принцип «за убранное возвращаем ресурс»).
const ARSENAL_REFUND := {"splash": 1, "sniper": 2, "pierce": 4, "poison": 6}


func meta_def(id: String) -> Dictionary:
	for m in META:
		if m["id"] == id:
			return m
	return {}


func meta_level(id: String) -> int:
	return int(meta.get(id, 0))


func meta_cost(id: String) -> int:
	var m := meta_def(id)
	return int(m["cost"]) + int(m["step"]) * meta_level(id)


## Можно ли купить следующий уровень узла: предыдущий узел ветки изучен, не максимум, хватает ★.
func meta_can_buy(id: String) -> bool:
	var m := meta_def(id)
	if m.is_empty():
		return false
	if int(m["max"]) > 0 and meta_level(id) >= int(m["max"]):
		return false
	if String(m["req"]) != "" and meta_level(m["req"]) <= 0:
		return false
	return stars >= meta_cost(id)


func meta_buy(id: String) -> bool:
	if not meta_can_buy(id):
		return false
	stars -= meta_cost(id)
	meta[id] = meta_level(id) + 1
	refresh_unlocked()
	save_game()
	return true


## Открытые типы — по умолчанию для нового уровня: только Пронизывающий (остальные — за 1 U в уровне).
func refresh_unlocked() -> void:
	for t in TYPE_ORDER:
		unlocked[t] = t == "basic"


## Эффекты «Наследия».
func coin_mult() -> float:
	return 1.0 + 0.10 * meta_level("coin_bonus")


func dmg_mult() -> float:
	return 1.0 + 0.10 * meta_level("dmg_bonus")


func start_coins() -> int:
	var lv := meta_level("start_coins")
	return 0 if lv == 0 else int(30 * pow(3, lv))


## ★ за выполненную цель уровня: впервые — 3 + номер уровня (с нуля), повторно — 1.
static func stars_for(map_index: int, first: bool) -> int:
	return 3 + map_index if first else 1


func _ready() -> void:
	for code in I18n.LANGS:
		var tab := I18n.table(code)
		if tab.is_empty():
			continue
		var t := Translation.new()
		t.locale = code
		for k in tab:
			t.add_message(k, tab[k])
		TranslationServer.add_translation(t)
	_migrate_old_save()
	load_settings()
	_reset_defaults()
	load_game()
	apply_settings()
	get_tree().root.theme = make_theme()   # тема на всё приложение, включая диалоги


## Язык системы → язык игры: поддерживаемый язык системы, иначе английский.
static func system_lang(code: String) -> String:
	return I18n.from_system(code)


func apply_settings() -> void:
	lang = lang_choice if lang_choice in LANGS else system_lang(OS.get_locale())
	TranslationServer.set_locale(lang)
	Engine.max_fps = 30 if eco_mode else 60
	DisplayServer.screen_set_keep_on(keep_screen)
	music_on = music_vol > 0.01
	sfx_on = sfx_vol > 0.01


func _reset_defaults() -> void:
	stars = 0
	meta = {}
	maps_unlocked = 1
	maps_done = {}
	map_states = {}
	refresh_unlocked()


# ---------------------------------------------------------------- файлы

func slot_dir(n: int = -1) -> String:
	return "user://slot%d/" % (slot if n < 0 else n)


func save_path(n: int = -1) -> String:
	return slot_dir(n) + "save.json"


static func write_atomic(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
		DirAccess.rename_absolute(path + ".tmp", path)


static func read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


var _save_pending := false
var _save_wait := 0.0


## Отложенное сохранение: не чаще раза в 3 с.
func request_save() -> void:
	_save_pending = true


func _process(delta: float) -> void:
	if _save_pending:
		_save_wait += delta
		if _save_wait >= 3.0:
			save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _save_pending:
			save_game()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# флаг «не гасить экран» на некоторых телефонах сбрасывается после сворачивания — включаем заново
		DisplayServer.screen_set_keep_on(keep_screen)
		keep_on_applied += 1


func save_game() -> void:
	_save_pending = false
	_save_wait = 0.0
	write_atomic(save_path(), JSON.stringify({
		"ver": 2, "stars": stars, "meta": meta, "maps_unlocked": maps_unlocked,
		"maps_done": maps_done, "map_states": map_states, "played_at": Time.get_unix_time_from_system(),
	}))


func load_game() -> void:
	_reset_defaults()
	var data = read_json(save_path())
	if typeof(data) != TYPE_DICTIONARY:
		return
	# повреждённый или чужой файл не должен ронять игру: каждое поле проверяем по типу
	stars = _int(data.get("stars", 0))
	var mt: Dictionary = _dict(data.get("meta", {}))
	for t in ARSENAL_REFUND:
		if _int(mt.get(t, 0)) > 0:
			stars += ARSENAL_REFUND[t]
	for m in META:
		var lv := _int(mt.get(m["id"], 0))
		if int(m["max"]) > 0:
			lv = mini(lv, int(m["max"]))
		if lv > 0:
			meta[m["id"]] = lv
	maps_unlocked = maxi(1, _int(data.get("maps_unlocked", 1)))
	maps_done = _dict(data.get("maps_done", {}))
	map_states = _dict(data.get("map_states", {}))
	refresh_unlocked()


func save_settings() -> void:
	write_atomic(SETTINGS_PATH, JSON.stringify({
		"eco_mode": eco_mode, "keep_screen": keep_screen, "lang_choice": lang_choice,
		"music_vol": music_vol, "sfx_vol": sfx_vol, "vibration_on": vibration_on, "slot": slot,
		"magnet_deg": magnet_deg,
	}))


func load_settings() -> void:
	var d = read_json(SETTINGS_PATH)
	if typeof(d) != TYPE_DICTIONARY:
		return
	eco_mode = bool(d.get("eco_mode", false))
	keep_screen = bool(d.get("keep_screen", false))
	lang_choice = String(d.get("lang_choice", ""))
	music_vol = clampf(float(d.get("music_vol", 0.8)), 0.0, 1.0) if typeof(d.get("music_vol", 0.8)) in [TYPE_INT, TYPE_FLOAT] else 0.8
	sfx_vol = clampf(float(d.get("sfx_vol", 0.8)), 0.0, 1.0) if typeof(d.get("sfx_vol", 0.8)) in [TYPE_INT, TYPE_FLOAT] else 0.8
	vibration_on = bool(d.get("vibration_on", true))
	slot = clampi(_int(d.get("slot", 1)), 1, SLOTS)
	magnet_deg = clampi(_int(d.get("magnet_deg", 2)), 1, 5)


## Профили: краткая сводка для экрана выбора (без переключения).
func slot_summary(n: int) -> Dictionary:
	var d = read_json(save_path(n))
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	return {"stars": _int(d.get("stars", 0)), "done": _dict(d.get("maps_done", {})).size(),
		"unlocked": maxi(1, _int(d.get("maps_unlocked", 1)))}


func select_slot(n: int) -> void:
	if _save_pending:
		save_game()
	slot = clampi(n, 1, SLOTS)
	save_settings()
	load_game()


func delete_slot(n: int) -> void:
	var dir := DirAccess.open(slot_dir(n))
	if dir:
		for f in dir.get_files():
			dir.remove(f)
	if n == slot:
		load_game()


## Старое сохранение (до v0.20, один профиль в корне user://) переносится в профиль 1:
## пройденные карты → ★, открытые типы шаров остаются открытыми, «Мастерство» → ★.
func _migrate_old_save() -> void:
	var old = read_json("user://save.json")
	if typeof(old) != TYPE_DICTIONARY:
		return
	DirAccess.make_dir_recursive_absolute(slot_dir(1))
	var done: Dictionary = _dict(old.get("maps_done", {}))
	var st := 0
	var i := 0
	for id in done:
		st += stars_for(i, true)
		i += 1
	st += _int(old.get("mastery", 0))
	var mt := {}
	var ul: Dictionary = _dict(old.get("unlocked", {}))
	for t in ["splash", "sniper", "pierce", "poison"]:
		if bool(ul.get(t, false)):
			mt[t] = 1
	write_atomic(save_path(1), JSON.stringify({"ver": 2, "stars": st, "meta": mt,
		"maps_unlocked": _int(old.get("maps_unlocked", 1)), "maps_done": done, "map_states": {}}))
	write_atomic(SETTINGS_PATH, JSON.stringify({
		"eco_mode": bool(old.get("eco_mode", false)), "keep_screen": bool(old.get("keep_screen", false)),
		"lang_choice": String(old.get("lang_choice", "")),
		"music_vol": 0.8 if bool(old.get("music_on", true)) else 0.0,
		"sfx_vol": 0.8 if bool(old.get("sfx_on", true)) else 0.0,
		"vibration_on": bool(old.get("vibration_on", true)), "slot": 1}))
	var root := DirAccess.open("user://")
	if root:
		for f in root.get_files():
			if f.begins_with("map_") and f.ends_with(".bin"):
				root.remove(f)   # раскладка уровней изменилась — начатые карты всё равно начались бы заново
		root.remove("save.json")


## Мини-вибрация (если включена в настройках). На Android нужно разрешение VIBRATE в экспорт-пресете.
func vibrate(ms: int) -> void:
	if not vibration_on:
		return
	vibrations += 1
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


static func _dict(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func _int(v) -> int:
	return maxi(0, int(v)) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0


## Сбросить текущий профиль.
func reset_all() -> void:
	delete_slot(slot)
	_reset_defaults()
	save_game()


var font: Font
var font_bold: Font
var _theme: Theme

const C_BG := Color(0.07, 0.08, 0.12)
const C_PANEL := Color(0.1, 0.12, 0.18)
const C_CARD := Color(0.14, 0.16, 0.24)
const C_BTN := Color(0.2, 0.23, 0.34)
const C_ACCENT := Color(0.33, 0.52, 1.0)
const C_TEXT := Color(0.93, 0.95, 1.0)
const C_MUTED := Color(0.62, 0.67, 0.8)
const C_GOLD := Color(1.0, 0.82, 0.3)
const C_GEM := Color(0.8, 0.62, 1.0)


func _sb(bg: Color, radius: int = 14, border := Color(0, 0, 0, 0), bw: int = 0, shadow: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	if shadow > 0:
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, 3)
	return sb


func _btn_styles(th: Theme, type: String, base: Color, border: Color) -> void:
	th.set_stylebox("normal", type, _sb(base, 14, border, 1, 3))
	th.set_stylebox("hover", type, _sb(base.lightened(0.08), 14, border.lightened(0.2), 1, 3))
	th.set_stylebox("pressed", type, _sb(base.darkened(0.15), 14, border, 1, 0))
	th.set_stylebox("hover_pressed", type, _sb(base.darkened(0.1), 14, border, 1, 0))
	th.set_stylebox("disabled", type, _sb(Color(base.r, base.g, base.b, 0.35), 14, Color(border.r, border.g, border.b, 0.2), 1, 0))
	th.set_stylebox("focus", type, StyleBoxEmpty.new())
	th.set_color("font_color", type, C_TEXT)
	th.set_color("font_hover_color", type, Color.WHITE)
	th.set_color("font_pressed_color", type, Color.WHITE)
	th.set_color("font_hover_pressed_color", type, Color.WHITE)
	th.set_color("font_disabled_color", type, Color(1, 1, 1, 0.35))
	th.set_constant("h_separation", type, 8)
	th.set_constant("icon_max_width", type, 34)


func make_theme() -> Theme:
	if _theme != null:
		return _theme
	var base_font: FontFile = load("res://fonts/Rubik.ttf")
	base_font.allow_system_fallback = true   # иероглифы, арабское письмо, деванагари — из шрифтов системы
	var fv := FontVariation.new()
	fv.base_font = base_font
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
	font = fv
	var fb := FontVariation.new()
	fb.base_font = base_font
	fb.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	font_bold = fb

	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 26
	th.set_color("font_color", "Label", C_TEXT)

	_btn_styles(th, "Button", C_BTN, Color(1, 1, 1, 0.08))
	# основная кнопка
	th.set_type_variation("AccentButton", "Button")
	_btn_styles(th, "AccentButton", C_ACCENT, Color(0.6, 0.75, 1.0, 0.6))
	th.set_font("font", "AccentButton", font_bold)
	# фишка выбора шара: выбранная подсвечивается рамкой
	th.set_type_variation("ChipButton", "Button")
	_btn_styles(th, "ChipButton", Color(0.16, 0.18, 0.27), Color(1, 1, 1, 0.06))
	th.set_stylebox("pressed", "ChipButton", _sb(Color(0.22, 0.28, 0.45), 14, C_ACCENT, 3, 3))
	th.set_stylebox("hover_pressed", "ChipButton", _sb(Color(0.24, 0.3, 0.48), 14, C_ACCENT, 3, 3))
	th.set_font("font", "ChipButton", font_bold)
	# панели
	th.set_stylebox("panel", "PanelContainer", _sb(Color(C_PANEL.r, C_PANEL.g, C_PANEL.b, 0.88), 0))
	th.set_type_variation("Card", "PanelContainer")
	var card := _sb(C_CARD, 18, Color(1, 1, 1, 0.06), 1, 4)
	card.content_margin_left = 16
	card.content_margin_right = 16
	card.content_margin_top = 14
	card.content_margin_bottom = 14
	th.set_stylebox("panel", "Card", card)
	th.set_type_variation("Pill", "PanelContainer")
	var pill := _sb(Color(0, 0, 0, 0.3), 20, Color(1, 1, 1, 0.07), 1, 0)
	pill.content_margin_left = 10
	pill.content_margin_right = 14
	pill.content_margin_top = 6
	pill.content_margin_bottom = 6
	th.set_stylebox("panel", "Pill", pill)
	# подписи
	th.set_type_variation("Muted", "Label")
	th.set_color("font_color", "Muted", C_MUTED)
	th.set_font_size("font_size", "Muted", 21)
	th.set_type_variation("Title", "Label")
	th.set_font("font", "Title", font_bold)
	th.set_font_size("font_size", "Title", 29)
	# вкладки
	th.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	th.set_stylebox("tab_selected", "TabContainer", _sb(C_ACCENT, 12))
	th.set_stylebox("tab_unselected", "TabContainer", _sb(Color(1, 1, 1, 0.06), 12))
	th.set_stylebox("tab_hovered", "TabContainer", _sb(Color(1, 1, 1, 0.12), 12))
	th.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	th.set_color("font_selected_color", "TabContainer", Color.WHITE)
	th.set_color("font_unselected_color", "TabContainer", C_MUTED)
	th.set_color("font_hovered_color", "TabContainer", C_TEXT)
	th.set_font("font", "TabContainer", font_bold)
	th.set_constant("side_margin", "TabContainer", 0)
	# полосы прогресса и прокрутки
	th.set_stylebox("background", "ProgressBar", _sb(Color(0, 0, 0, 0.35), 6))
	th.set_stylebox("fill", "ProgressBar", _sb(Color(0.4, 0.85, 0.5), 6))
	th.set_stylebox("scroll", "VScrollBar", _sb(Color(1, 1, 1, 0.04), 4))
	th.set_stylebox("grabber", "VScrollBar", _sb(Color(1, 1, 1, 0.25), 4))
	th.set_stylebox("grabber_highlight", "VScrollBar", _sb(Color(1, 1, 1, 0.35), 4))
	th.set_stylebox("grabber_pressed", "VScrollBar", _sb(Color(1, 1, 1, 0.45), 4))
	th.set_stylebox("separator", "HSeparator", _sb(Color(1, 1, 1, 0.06), 0))
	# диалоги
	var dlg := _sb(C_CARD, 18, Color(1, 1, 1, 0.1), 1, 8)
	dlg.content_margin_left = 24
	dlg.content_margin_right = 24
	dlg.content_margin_top = 20
	dlg.content_margin_bottom = 20
	th.set_stylebox("panel", "AcceptDialog", dlg)
	th.set_stylebox("embedded_border", "Window", dlg)
	th.set_stylebox("embedded_unfocused_border", "Window", dlg)
	th.set_font("title_font", "Window", font_bold)
	th.set_color("title_color", "Window", C_TEXT)
	th.set_constant("title_height", "Window", 44)
	_theme = th
	return th


## Короткая запись числа: 999, 1.5K, 2.5M, 3.0B, 4.0T, 5.0Qa, дальше 6.0e18.
static func fmt(n) -> String:
	var v := float(n)
	if v < 1000.0:
		return str(int(v))
	var units := ["K", "M", "B", "T", "Qa"]
	var e := 3
	for u in units:
		if v < pow(10.0, e + 3):
			return "%.1f%s" % [v / pow(10.0, e), u]
		e += 3
	return "%.1fe%d" % [v / pow(10.0, floor(log(v) / log(10.0))), int(floor(log(v) / log(10.0)))]

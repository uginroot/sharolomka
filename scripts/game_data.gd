extends Node
## Глобальные данные: типы шариков, U-баллы, перки, открытые карты, сохранения.

const SAVE_PATH := "user://save.json"
const PERK_MAX := 5
const SUPER_COST := 15
const TYPE_ORDER := ["basic", "splash", "sniper", "pierce", "poison"]

const TYPES := {
	"basic": {
		"name": "Обычный", "color": Color(0.95, 0.95, 0.95), "radius": 7.0,
		"speed": 330.0, "damage": 1.0,
		"ball_cost": 25.0, "dmg_cost": 40.0, "spd_cost": 30.0, "unlock_u": 0,
		"perk": "Крит", "perk_desc": "+6% шанс двойного урона за уровень",
		"super": "Сокрушение", "super_desc": "Крит наносит ×5 урона вместо ×2",
	},
	"splash": {
		"name": "Бомба", "color": Color(1.0, 0.6, 0.2), "radius": 8.0,
		"speed": 280.0, "damage": 2.0,
		"ball_cost": 300.0, "dmg_cost": 250.0, "spd_cost": 200.0, "unlock_u": 1,
		"perk": "Ударная волна", "perk_desc": "Взрыв бьёт соседей: 30% урона +14% за уровень",
		"super": "Мегавзрыв", "super_desc": "Радиус взрыва 2 клетки",
	},
	"sniper": {
		"name": "Снайпер", "color": Color(0.35, 0.9, 1.0), "radius": 6.0,
		"speed": 380.0, "damage": 3.0,
		"ball_cost": 1500.0, "dmg_cost": 1000.0, "spd_cost": 800.0, "unlock_u": 3,
		"perk": "Наведение", "perk_desc": "После удара летит к ближайшему квадрату: шанс 40% +12% за уровень",
		"super": "Охотник", "super_desc": "Наводится и после отскока от стен",
	},
	"pierce": {
		"name": "Пробойник", "color": Color(0.75, 0.5, 1.0), "radius": 7.0,
		"speed": 340.0, "damage": 6.0,
		"ball_cost": 6000.0, "dmg_cost": 4000.0, "spd_cost": 3000.0, "unlock_u": 5,
		"perk": "Заточка", "perk_desc": "+20% урона за уровень. Пролетает сквозь квадрат, если добил его",
		"super": "Призрак", "super_desc": "Пролетает сквозь все квадраты",
	},
	"poison": {
		"name": "Отравитель", "color": Color(0.45, 1.0, 0.35), "radius": 7.0,
		"speed": 300.0, "damage": 4.0,
		"ball_cost": 20000.0, "dmg_cost": 12000.0, "spd_cost": 9000.0, "unlock_u": 8,
		"perk": "Стойкий яд", "perk_desc": "Яд 60% урона в секунду, 3 с +1 с за уровень",
		"super": "Эпидемия", "super_desc": "Яд перекидывается на соседей, когда квадрат разбит",
	},
}

var u := 0
var unlocked := {}
var perks := {}
var supers := {}
var maps_unlocked := 1
var maps_done := {}
var map_states := {}
var current_map := 0
var eco_mode := false       # 30 FPS вместо 60
var keep_screen := false    # не гасить экран во время игры


func _ready() -> void:
	_reset_defaults()
	load_game()
	apply_settings()


func apply_settings() -> void:
	Engine.max_fps = 30 if eco_mode else 60
	DisplayServer.screen_set_keep_on(keep_screen)


func _reset_defaults() -> void:
	u = 0
	unlocked = {}
	perks = {}
	supers = {}
	for t in TYPE_ORDER:
		unlocked[t] = (t == "basic")
		perks[t] = 0
		supers[t] = false
	maps_unlocked = 1
	maps_done = {}
	map_states = {}


func save_game() -> void:
	var data := {
		"u": u, "unlocked": unlocked, "perks": perks, "supers": supers,
		"maps_unlocked": maps_unlocked, "maps_done": maps_done, "map_states": map_states,
		"eco_mode": eco_mode, "keep_screen": keep_screen,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	u = int(data.get("u", 0))
	var ul: Dictionary = data.get("unlocked", {})
	var pk: Dictionary = data.get("perks", {})
	var sp: Dictionary = data.get("supers", {})
	for t in TYPE_ORDER:
		unlocked[t] = bool(ul.get(t, t == "basic"))
		perks[t] = int(pk.get(t, 0))
		supers[t] = bool(sp.get(t, false))
	maps_unlocked = int(data.get("maps_unlocked", 1))
	maps_done = data.get("maps_done", {})
	map_states = data.get("map_states", {})
	eco_mode = bool(data.get("eco_mode", false))
	keep_screen = bool(data.get("keep_screen", false))


func reset_all() -> void:
	var e := eco_mode
	var k := keep_screen
	_reset_defaults()
	var dir := DirAccess.open("user://")
	if dir:
		for f in dir.get_files():
			if f.begins_with("map_") and f.ends_with(".bin"):
				dir.remove(f)
	eco_mode = e
	keep_screen = k
	save_game()


func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 22
	th.set_stylebox("normal", "Button", _box(Color(0.22, 0.27, 0.38)))
	th.set_stylebox("hover", "Button", _box(Color(0.27, 0.33, 0.46)))
	th.set_stylebox("pressed", "Button", _box(Color(0.33, 0.45, 0.65)))
	th.set_stylebox("disabled", "Button", _box(Color(0.15, 0.16, 0.2)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	th.set_stylebox("panel", "PanelContainer", _box(Color(0.1, 0.11, 0.15), 0))
	return th


func _box(c: Color, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func fmt(n) -> String:
	var v := float(n)
	if v < 1000.0:
		return str(int(v))
	if v < 1e6:
		return "%.1fK" % (v / 1000.0)
	if v < 1e9:
		return "%.1fM" % (v / 1e6)
	return "%.1fB" % (v / 1e9)

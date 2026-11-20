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
	get_tree().root.theme = make_theme()   # тема на всё приложение, включая диалоги


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
	th.set_constant("icon_max_width", type, 28)


func make_theme() -> Theme:
	if _theme != null:
		return _theme
	var base_font: FontFile = load("res://fonts/Rubik.ttf")
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
	th.default_font_size = 22
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
	th.set_font_size("font_size", "Muted", 17)
	th.set_type_variation("Title", "Label")
	th.set_font("font", "Title", font_bold)
	th.set_font_size("font_size", "Title", 24)
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


static func fmt(n) -> String:
	var v := float(n)
	if v < 1000.0:
		return str(int(v))
	if v < 1e6:
		return "%.1fK" % (v / 1000.0)
	if v < 1e9:
		return "%.1fM" % (v / 1e6)
	return "%.1fB" % (v / 1e9)

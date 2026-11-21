extends Node
## Музыка и звуки (автозагрузка Sfx). Всё сгенерировано tools/gen_audio.py → audio/*.ogg.
## Частые звуки (удар, разрушение) ограничены по частоте — в поздней игре сотни шаров не превращаются в треск.

const SOUNDS := ["hit", "break", "launch", "aim", "u", "gold", "buy", "goal", "tap", "finale"]
const MIN_GAP := {"hit": 0.07, "break": 0.06, "tap": 0.03, "buy": 0.05}   # не чаще, с
const VOLUME := {"hit": -14.0, "break": -9.0, "tap": -10.0, "launch": -6.0, "aim": -8.0}

var players := {}
var music: AudioStreamPlayer
var _last := {}
var played := {}                 # счётчики воспроизведений — для тестов


func _ready() -> void:
	_ensure_bus("Music", -8.0)
	_ensure_bus("SFX", -2.0)
	for s in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://audio/%s.ogg" % s)
		p.bus = "SFX"
		p.max_polyphony = 6 if s in ["hit", "break"] else 3
		add_child(p)
		players[s] = p
	music = AudioStreamPlayer.new()
	var st: AudioStreamOggVorbis = load("res://audio/music_calm.ogg")
	st.loop = true
	music.stream = st
	music.bus = "Music"
	add_child(music)
	# нажатия любых кнопок — тихий щелчок
	get_tree().node_added.connect(_on_node_added)
	apply()


func _ensure_bus(name: String, db: float) -> void:
	if AudioServer.get_bus_index(name) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(name), db)


## Применить настройки: музыка и звуки включаются/выключаются.
func apply() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not GameData.music_on)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not GameData.sfx_on)
	if GameData.music_on and not music.playing:
		music.play()
	elif not GameData.music_on and music.playing:
		music.stop()


func play(name: String, pitch_var := 0.06) -> void:
	if not GameData.sfx_on or not players.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -1.0)) < float(MIN_GAP.get(name, 0.0)):
		return
	_last[name] = now
	var p: AudioStreamPlayer = players[name]
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.volume_db = float(VOLUME.get(name, 0.0))
	p.play()
	played[name] = int(played.get(name, 0)) + 1


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		n.pressed.connect(play.bind("tap", 0.02))

extends Node
## Прокрутка ScrollContainer пальцем, даже если палец лёг на кнопку. В Godot 4.3 кнопка захватывает
## касание, и ScrollContainer его не получает. Сдвиг по вертикали > SLOP — это прокрутка: список едет
## за пальцем, а нажатие кнопки под пальцем отменяется (ничего не покупается случайно).
## Использование: var ts = TouchScroll.new(); ts.target = scroll_container; add_child(ts)

const SLOP := 14.0

var target: ScrollContainer
var _idx := -1
var _start := Vector2.ZERO
var _v0 := 0
var _on := false
var _held: Array = []   # кнопки, временно выключенные на время прокрутки


func _input(e: InputEvent) -> void:
	if target == null or not target.is_visible_in_tree():
		_idx = -1
		_on = false
		return
	if e is InputEventScreenTouch:
		if e.pressed and _idx < 0 and target.get_global_rect().has_point(e.position):
			_idx = e.index
			_start = e.position
			_v0 = target.scroll_vertical
			_on = false
		elif not e.pressed and e.index == _idx:
			_idx = -1
			if _on:
				_on = false
				get_viewport().set_input_as_handled()
				_release_held.call_deferred()
	elif e is InputEventScreenDrag and e.index == _idx:
		var dy: float = e.position.y - _start.y
		if not _on and absf(dy) > SLOP:
			# отменяем нажатие кнопки под пальцем: выключенная кнопка сбрасывает нажатие и не сработает
			# при отпускании (синтетическое «отпускание мыши» Godot обрабатывал уже после настоящего — v0.26)
			for b in target.find_children("*", "BaseButton", true, false):
				if not b.disabled and b.is_visible_in_tree() and b.get_global_rect().has_point(_start):
					b.disabled = true
					_held.append(b)
			_on = true
		if _on:
			target.scroll_vertical = _v0 - int(dy)
			get_viewport().set_input_as_handled()
	elif (_on or not _held.is_empty()) and e is InputEventMouse and e.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()   # эмулированная мышь во время прокрутки не трогает кнопки


## После отпускания пальца кнопки снова включаются (в следующем кадре — когда эмулированная мышь уже прошла).
func _release_held() -> void:
	await get_tree().process_frame
	for b in _held:
		if is_instance_valid(b):
			b.disabled = false
	_held.clear()

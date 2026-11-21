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
	elif e is InputEventScreenDrag and e.index == _idx:
		var dy: float = e.position.y - _start.y
		if not _on and absf(dy) > SLOP:
			# отменяем нажатие кнопки: «отпускаем» мышь далеко за экраном — кнопка не сработает
			var r := InputEventMouseButton.new()
			r.button_index = MOUSE_BUTTON_LEFT
			r.pressed = false
			r.position = Vector2(-10000, -10000)
			r.global_position = r.position
			Input.parse_input_event(r)
			_on = true
		if _on:
			target.scroll_vertical = _v0 - int(dy)
			get_viewport().set_input_as_handled()
	elif _on and e is InputEventMouse and e.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()   # эмулированная мышь во время прокрутки не трогает кнопки

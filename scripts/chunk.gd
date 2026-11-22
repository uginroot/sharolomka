extends RefCounted
## Кусок мира 32×32 клетки. Создаётся, только когда до него добрались.

var hp := PackedInt32Array()     # жизни квадратов
var kind := PackedByteArray()    # 0 пусто, 1 квадрат, 2 стена, 3 за краем карты
var vis := PackedByteArray()     # 1 — клетка видна (туман: только первый слой)
var gold := PackedByteArray()    # 1 — золотой квадрат (по хешу координат, не сохраняется)
# мягкий край тумана: треугольники кэшируются и пересчитываются только когда рядом открылась клетка
var fog_dirty := true
var fog_pts := PackedVector2Array()
var fog_cols := PackedColorArray()
var fog_idx := PackedInt32Array()
var solid := 0                   # сколько квадратов и стен — для быстрого пролёта пустых кусков
var changed := false             # отличается от сгенерированного — надо сохранять
var blob_dirty := true
var blob: Array = []
var node: Node2D = null
var tex: ImageTexture = null
var tex_dirty := true

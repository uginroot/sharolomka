extends RefCounted
## Один шарик. Физика считается вручную в game.gd.

var type := ""
var ti := 0
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var radius := 7.0
var earned := 0        # монеты, заработанные с последнего сброса (для поиска «застрявшего»)
var recent := {}       # клетка -> время удара (для пробивающих шариков)
var check_t := 0.0
var seek_t := -1.0
var buff := 0.0        # бафф Знаменосца: +доля урона
var buff_t := 0.0      # сколько ещё держится бафф
# эволюции
var sprint := 0.0          # Спринтер: текущий разгон (доля скорости)
var spd_buff := 0.0        # Попутный ветер: бафф скорости от ауры Знаменосца (пока действует buff_t)
var drill_id := -1         # Клещ: клетка, которую бурит шар (-1 — не бурит)
var drill_vel := Vector2.ZERO
var drill_acc := 0.0
var deeper_left := 0       # Клещ «Глубже»: сколько клеток ещё пройти прямо
var zap_t := 0.0           # Молния: время до разряда
var gtarget := Vector2(-1, -1)   # Гравитация: точка притяжения
var gt_t := 0.0


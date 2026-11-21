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

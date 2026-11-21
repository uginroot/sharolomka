# Шароломка — памятка для новой сессии

Игра на Godot 4.3 (GDScript) для Android/Windows/Linux. Владелец — Антон (GitHub: uginroot).
Общение, интерфейс и комментарии в коде — на русском.

## С чего начать
1. Прочитай `docs/SPEC.md` — как игра должна работать, числа, архитектура, история решений.
2. Прогони тесты (ниже) — убедись, что всё зелёное, прежде чем менять код.

## Команды
```bash
# Godot 4.3: https://github.com/godotengine/godot/releases/tag/4.3-stable
godot --headless --path . --import                              # первый раз
godot --headless --path . res://tests/test_runner.tscn          # тесты логики (код выхода = число упавших)
godot --headless --path . res://tests/test_runner.tscn -- test_fire   # один тест
xvfb-run -a -s "-screen 0 800x1700x24" godot --path . --rendering-driver opengl3 \
  --resolution 720x1600 res://tests/ui_playtest.tscn            # UI-тест касаниями + скриншоты в build/screens/
```

## Правила
- **Ошибка скрипта в тесте не даёт FAIL** — после прогона ищи в выводе `SCRIPT ERROR` (CI это проверяет).
- Интерфейс проверяй на двух экранах: 720×1600 (20:9) и 720×1280 (16:9) — `SCREENS_SUFFIX=_16x9 ... --resolution 720x1280`.
- Цены и большие числа — через `_price()` (потолок) и `GameData.fmt()`; запись файлов — атомарно (tmp + rename).
- Любое изменение поведения → обнови `docs/SPEC.md` (включая таблицу «История решений») в том же коммите.
- Нашёл баг → сначала тест, который его ловит (`tests/test_runner.gd`, функции `test_*`), потом исправление.
- После изменений интерфейса **посмотри скриншоты** UI-теста (720×1600, пропорции 20:9) — не выпускай вслепую.
- Производительность и батарея — требование владельца: бюджет в SPEC §7, не ломай тест `test_performance_budget`.
- Не используй MultiMesh для шаров (не рисуется на Android). Интерфейс в CanvasLayer — задавай `theme` явно.
- Любой текст интерфейса — через `tr("русский текст")` + перевод во **все** 15 файлов `scripts/lang/*.gd`
  (тест проверит). После правок интерфейса смотри скриншоты и на длинном языке (de), и на арабском (справа налево).
- Формат сохранения карт поменялся → повысь `ver` в `game.gd` (`_save_state`/`_load_state`).

## Баланс
- Меняешь цены, урон, жизни, U или цели карт → прогони `godot --headless --path . res://tests/balance_sim.tscn -- 45 5`
  и обнови таблицу темпа в SPEC §4а. Скука = длинные паузы без покупок и падающий доход.
  Бесконечные уровни: `godot --headless --path . res://tests/endless_quick.tscn -- 8 9 12 19`.
- Осторожно: `pkill -f <слово>` убивает и собственную оболочку, если слово есть в её команде —
  останавливай по шаблону вида `pgrep -f "[G]odot.*endless_quick"`.

## Звук
- Музыка и звуки — из кода: `pip install numpy soundfile && python3 tools/gen_audio.py` → `audio/*.ogg`.
  Новый звук: добавь в генератор и в `Sfx.SOUNDS` (`scripts/audio.gd`); частые — с ограничением в `MIN_GAP`.

## Релиз
- push в `main` → CI: тесты → UI-тесты → сборки (артефакты в Actions, там же скриншоты).
- Релиз: `git tag vX.Y.Z && git push origin vX.Y.Z` → GitHub Release с APK, zip (Windows), tar.gz (Linux).
- Ключ подписи Android — в секретах репозитория; у владельца есть копия. В репозиторий ключи и токены не коммитить.

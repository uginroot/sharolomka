# Шароломка (Godot 4.3)

![Build](../../actions/workflows/build.yml/badge.svg)

Сборки для Android, Windows и Linux делает GitHub Actions (.github/workflows/build.yml):
- каждый push в main и каждый PR → артефакты во вкладке Actions;
- тег `v*` (например `v0.1.0`) → GitHub Release с APK, zip для Windows и tar.gz для Linux.

Для подписи Android добавьте секреты репозитория (Settings → Secrets and variables → Actions):
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_USER`, `ANDROID_KEYSTORE_PASSWORD`.
Без них собирается debug APK со случайным ключом.

Открыть: Godot 4.3+ → Import → выбрать project.godot.
Запуск на ПК: F5 (окно уменьшено до 405×720, мышь = палец).

## Сборка APK
1. Editor → Manage Export Templates → Download and Install.
2. Установить JDK 17 и Android SDK (проще всего через Android Studio).
3. Editor Settings → Export → Android: указать путь к SDK и debug keystore
   (Godot 4.3 создаёт debug.keystore сам).
4. Project → Export → Add… → Android → Export Project → .apk.
   Для быстрой проверки: включить на телефоне отладку по USB и нажать кнопку Android в правом верхнем углу редактора.

## Где что
- scripts/game_data.gd — типы шариков, цены, перки, сохранение (user://save.json)
- scripts/maps.gd — карты: границы и препятствия-картинки (мир 700×840)
- scripts/game.gd — физика шариков, квадраты, туман, яд, магазин и интерфейс
- scripts/main_menu.gd — выбор карты

Новая карта = новый словарь в Maps.get_maps(): cols (размер сетки), hp_base/hp_growth
(жизни растут с расстоянием от старта), start, aim, border, obstacles.

## Производительность и батарея
- Все шарики рисуются одной MultiMesh (один вызов отрисовки на кадр).
- Поле разбито на куски 6×6 клеток; перерисовываются только изменившиеся куски и не чаще 10 раз/с.
- Физика своя, без физического движка Godot; шаг подбирается по скорости шарика.
- Меню работает в low processor mode (кадры рисуются только при изменениях).
- В меню: «Экономия: 30 FPS» и «Экран: не гаснет / как обычно» (по умолчанию экран гаснет как обычно).
- Рендерер GL Compatibility, VSync включён, лимит 60 FPS.

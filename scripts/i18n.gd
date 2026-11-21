extends RefCounted
## Языки игры. Ключ перевода — русский текст из tr("..."); переводы — scripts/lang/<код>.gd (const T).
## Плейсхолдеры (%d, %s, %.1f, %%) должны совпадать — это проверяет тест test_translations_complete.
## Новая строка в интерфейсе → оберни в tr() и добавь во ВСЕ файлы scripts/lang/.
## Глифы китайского, японского, корейского, арабского, хинди, бенгальского берутся из системных шрифтов
## (Rubik их не содержит; у FontFile включён allow_system_fallback).

## Порядок — как в настройках: сначала самые распространённые.
const LANGS := ["en", "ru", "zh_CN", "hi", "es", "fr", "ar", "bn", "pt_BR", "id", "de", "ja", "tr", "ko", "vi", "it"]

## Названия языков на них самих.
const NAMES := {
	"en": "English", "ru": "Русский", "zh_CN": "简体中文", "hi": "हिन्दी", "es": "Español",
	"fr": "Français", "ar": "العربية", "bn": "বাংলা", "pt_BR": "Português", "id": "Bahasa Indonesia",
	"de": "Deutsch", "ja": "日本語", "tr": "Türkçe", "ko": "한국어", "vi": "Tiếng Việt", "it": "Italiano",
}


## Таблица перевода языка (для ru — пустая: русский текст и есть ключ).
static func table(code: String) -> Dictionary:
	if code == "ru" or not code in LANGS:
		return {}
	return load("res://scripts/lang/%s.gd" % code).T


## Код языка системы (OS.get_locale_language / get_locale) → язык игры; неподдерживаемый — английский.
static func from_system(code: String) -> String:
	var c := code.to_lower().replace("-", "_")
	var base := c.split("_")[0]
	if base == "zh":
		return "zh_CN"
	if base == "pt":
		return "pt_BR"
	for l in LANGS:
		if l == base:
			return l
	return "en"

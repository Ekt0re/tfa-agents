extends CanvasLayer

signal settings_changed(settings: Dictionary)
signal language_changed(language_code: String)

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "settings"
const DEFAULTS := {
	"master_volume": 80.0,
	"window_mode": 0,
	"vsync": true,
	"fps_cap": 60,
	"graphics_preset": 2,
	"language": "it",
	"show_fps": false,
}
const SUPPORTED_LANGUAGES := ["it", "en"]
const FPS_CAP_OPTIONS := [30, 60, 120, 0]
const GRAPHICS_SCALE := [0.75, 0.9, 1.0, 1.15]
const TEXTS := {
	"it": {
		"back": "Indietro",
		"reset_defaults": "Ripristina predefiniti",
		"enabled": "Attivo",
		"disabled": "Disattivato",
		"main_menu_eyebrow": "SCI-FI TACTICAL EXPERIENCE",
		"main_menu_play": "Play",
		"main_menu_settings": "Impostazioni",
		"main_menu_exit": "Esci dal gioco",
		"main_menu_info": "Le impostazioni globali vengono applicate in tempo reale.",
		"settings_title": "IMPOSTAZIONI",
		"settings_subtitle": "Configura audio, grafica e interfaccia con effetti reali e persistenti.",
		"settings_section_audio": "Audio",
		"settings_section_graphics": "Grafica",
		"settings_section_interface": "Interfaccia",
		"settings_master_volume": "Volume master",
		"settings_window_mode": "Modalità finestra",
		"settings_vsync": "VSync",
		"settings_fps_limit": "Limite fotogrammi",
		"settings_graphics_preset": "Preset grafico",
		"settings_language": "Lingua",
		"settings_show_fps": "Mostra FPS",
		"settings_footer_hint": "Le modifiche vengono salvate automaticamente e applicate subito.",
		"window_mode_windowed": "Finestra",
		"window_mode_borderless": "Borderless",
		"window_mode_fullscreen": "Schermo intero",
		"fps_limit_unlimited": "Illimitato",
		"graphics_low": "Basso",
		"graphics_medium": "Medio",
		"graphics_high": "Alto",
		"graphics_ultra": "Ultra",
		"language_italian": "Italiano",
		"language_english": "English",
		"pause_button": "Pausa",
		"pause_title": "PARTITA IN PAUSA",
		"pause_resume": "Riprendi",
		"pause_settings": "Impostazioni",
		"pause_main_menu": "Menu principale",
		"pause_hint": "Premi ESC oppure usa il pulsante in alto a destra per aprire o chiudere il menu.",
		"pause_mode_singleplayer": "Pausa completa: IA, fisica e timer sono sospesi.",
		"pause_mode_multiplayer": "Pausa multiplayer: il menu si apre senza congelare la simulazione.",
		"fps_counter": "FPS: %d",
	},
	"en": {
		"back": "Back",
		"reset_defaults": "Reset defaults",
		"enabled": "Enabled",
		"disabled": "Disabled",
		"main_menu_eyebrow": "SCI-FI TACTICAL EXPERIENCE",
		"main_menu_play": "Play",
		"main_menu_settings": "Settings",
		"main_menu_exit": "Exit game",
		"main_menu_info": "Global settings are applied in real time.",
		"settings_title": "SETTINGS",
		"settings_subtitle": "Configure audio, graphics and interface with real persistent effects.",
		"settings_section_audio": "Audio",
		"settings_section_graphics": "Graphics",
		"settings_section_interface": "Interface",
		"settings_master_volume": "Master volume",
		"settings_window_mode": "Window mode",
		"settings_vsync": "VSync",
		"settings_fps_limit": "Frame rate limit",
		"settings_graphics_preset": "Graphics preset",
		"settings_language": "Language",
		"settings_show_fps": "Show FPS",
		"settings_footer_hint": "Changes are saved automatically and applied immediately.",
		"window_mode_windowed": "Windowed",
		"window_mode_borderless": "Borderless",
		"window_mode_fullscreen": "Fullscreen",
		"fps_limit_unlimited": "Unlimited",
		"graphics_low": "Low",
		"graphics_medium": "Medium",
		"graphics_high": "High",
		"graphics_ultra": "Ultra",
		"language_italian": "Italiano",
		"language_english": "English",
		"pause_button": "Pause",
		"pause_title": "GAME PAUSED",
		"pause_resume": "Resume",
		"pause_settings": "Settings",
		"pause_main_menu": "Main menu",
		"pause_hint": "Press ESC or use the top-right button to open or close the menu.",
		"pause_mode_singleplayer": "Full pause: AI, physics and timers are suspended.",
		"pause_mode_multiplayer": "Multiplayer pause: the menu opens without freezing the simulation.",
		"fps_counter": "FPS: %d",
	},
}

var settings: Dictionary = DEFAULTS.duplicate(true)
var _fps_panel: PanelContainer
var _fps_label: Label
var _last_fps_text := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 256
	_build_fps_overlay()
	_load_settings()


func _process(_delta: float) -> void:
	if not bool(settings.get("show_fps", false)):
		return
	_update_fps_text()


func get_settings() -> Dictionary:
	return settings.duplicate(true)


func get_setting(key: String, fallback: Variant = null) -> Variant:
	return settings.get(key, fallback)


func text(key: String, args: Array = []) -> String:
	var language := _normalize_language(String(settings.get("language", DEFAULTS["language"])))
	var language_table: Dictionary = TEXTS.get(language, TEXTS["it"])
	var template := String(language_table.get(key, TEXTS["it"].get(key, key)))
	if args.is_empty():
		return template
	return template % args


func apply_settings(changes: Dictionary, persist := true) -> void:
	var merged := settings.duplicate(true)
	for key: String in changes.keys():
		if DEFAULTS.has(key):
			merged[key] = changes[key]
	var sanitized := _sanitize_settings(merged)
	var previous_language := String(settings.get("language", DEFAULTS["language"]))
	settings = sanitized
	_apply_master_volume(float(settings["master_volume"]))
	_apply_window_mode(int(settings["window_mode"]))
	_apply_vsync(bool(settings["vsync"]))
	_apply_fps_cap(int(settings["fps_cap"]))
	_apply_graphics_preset(int(settings["graphics_preset"]))
	_apply_language(String(settings["language"]))
	_apply_show_fps(bool(settings["show_fps"]))
	if persist:
		_save_settings()
	settings_changed.emit(get_settings())
	if previous_language != String(settings["language"]):
		language_changed.emit(String(settings["language"]))


func reset_to_defaults() -> void:
	apply_settings(DEFAULTS.duplicate(true), true)


func _load_settings() -> void:
	var config := ConfigFile.new()
	var loaded := DEFAULTS.duplicate(true)
	if config.load(SETTINGS_PATH) == OK:
		for key: String in DEFAULTS.keys():
			loaded[key] = config.get_value(SETTINGS_SECTION, key, loaded[key])
	apply_settings(loaded, false)


func _save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in settings.keys():
		config.set_value(SETTINGS_SECTION, key, settings[key])
	config.save(SETTINGS_PATH)


func _sanitize_settings(values: Dictionary) -> Dictionary:
	var sanitized := DEFAULTS.duplicate(true)
	sanitized["master_volume"] = clampf(float(values.get("master_volume", DEFAULTS["master_volume"])), 0.0, 100.0)
	sanitized["window_mode"] = clampi(int(values.get("window_mode", DEFAULTS["window_mode"])), 0, 2)
	sanitized["vsync"] = bool(values.get("vsync", DEFAULTS["vsync"]))
	var fps_cap := int(values.get("fps_cap", DEFAULTS["fps_cap"]))
	sanitized["fps_cap"] = fps_cap if FPS_CAP_OPTIONS.has(fps_cap) else int(DEFAULTS["fps_cap"])
	sanitized["graphics_preset"] = clampi(int(values.get("graphics_preset", DEFAULTS["graphics_preset"])), 0, GRAPHICS_SCALE.size() - 1)
	sanitized["language"] = _normalize_language(String(values.get("language", DEFAULTS["language"])))
	sanitized["show_fps"] = bool(values.get("show_fps", DEFAULTS["show_fps"]))
	return sanitized


func _normalize_language(language_code: String) -> String:
	var normalized := language_code.to_lower().split("_")[0]
	if SUPPORTED_LANGUAGES.has(normalized):
		return normalized
	return String(DEFAULTS["language"])


func _apply_master_volume(percent: float) -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index == -1:
		return
	AudioServer.set_bus_volume_db(bus_index, _percent_to_db(percent))


func _apply_window_mode(index: int) -> void:
	match index:
		2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)


func _apply_fps_cap(value: int) -> void:
	Engine.max_fps = max(0, value)


func _apply_graphics_preset(index: int) -> void:
	var window := get_window()
	if window == null:
		return
	window.content_scale_factor = GRAPHICS_SCALE[index]


func _apply_language(language_code: String) -> void:
	TranslationServer.set_locale(language_code)
	_last_fps_text = ""
	_update_fps_text()


func _apply_show_fps(enabled: bool) -> void:
	if _fps_panel == null:
		return
	_fps_panel.visible = enabled
	if enabled:
		_update_fps_text()


func _percent_to_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)


func _build_fps_overlay() -> void:
	_fps_panel = PanelContainer.new()
	_fps_panel.name = "FpsOverlay"
	_fps_panel.visible = false
	_fps_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_panel.anchor_left = 1.0
	_fps_panel.anchor_top = 0.0
	_fps_panel.anchor_right = 1.0
	_fps_panel.anchor_bottom = 0.0
	_fps_panel.offset_left = -144.0
	_fps_panel.offset_top = 16.0
	_fps_panel.offset_right = -16.0
	_fps_panel.offset_bottom = 56.0
	add_child(_fps_panel)

	var margin := MarginContainer.new()
	margin.set("theme_override_constants/margin_left", 8)
	margin.set("theme_override_constants/margin_top", 4)
	margin.set("theme_override_constants/margin_right", 8)
	margin.set("theme_override_constants/margin_bottom", 4)
	_fps_panel.add_child(margin)

	_fps_label = Label.new()
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margin.add_child(_fps_label)


func _update_fps_text() -> void:
	if _fps_label == null:
		return
	var next_text := text("fps_counter", [int(Engine.get_frames_per_second())])
	if next_text == _last_fps_text:
		return
	_last_fps_text = next_text
	_fps_label.text = next_text

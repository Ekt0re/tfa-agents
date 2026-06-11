extends CanvasLayer

signal settings_changed(settings: Dictionary)
signal language_changed(language_code: String)
signal release_check_completed(info: Dictionary)
signal update_status_changed(info: Dictionary)

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "settings"
const META_SECTION := "meta"
const RELEASES_API_HOST := "api.github.com"
const RELEASES_API_PORT := 443
const RELEASES_API_PATH := "/repos/Ekt0re/tfa-agents/releases"
const DEFAULTS := {
	"master_volume": 80.0,
	"window_mode": 0,
	"vsync": true,
	"fps_cap": 60,
	"graphics_preset": 2,
	"ui_scale": 1.0,
	"language": "it",
	"show_fps": false,
	"subtitles": true,
	"screen_shake": true,
}
const DEFAULT_META := {
	"last_seen_version": "",
	"last_changelog_version": "",
}
const SUPPORTED_LANGUAGES := ["it", "en"]
const FPS_CAP_OPTIONS := [30, 60, 120, 0]
const UI_SCALE_OPTIONS := [0.85, 1.0, 1.15, 1.3]
const GRAPHICS_PRESET_CONFIGS := [
	{
		"light_energy_multiplier": 0.65,
		"shadows_enabled": false,
		"glow_alpha_multiplier": 0.0,
	},
	{
		"light_energy_multiplier": 0.85,
		"shadows_enabled": false,
		"glow_alpha_multiplier": 0.55,
	},
	{
		"light_energy_multiplier": 1.0,
		"shadows_enabled": true,
		"glow_alpha_multiplier": 1.0,
	},
	{
		"light_energy_multiplier": 1.2,
		"shadows_enabled": true,
		"glow_alpha_multiplier": 1.2,
	},
]
const TEXTS := {
	"it": {
		"back": "Indietro",
		"close": "Chiudi",
		"download": "Download",
		"later": "Più tardi",
		"reset_defaults": "Ripristina predefiniti",
		"enabled": "Attivo",
		"disabled": "Disattivato",
		"main_menu_eyebrow": "AGENTE QGG - TED",
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
		"settings_ui_scale": "Scala UI",
		"settings_language": "Lingua",
		"settings_show_fps": "Mostra FPS",
		"settings_subtitles": "Sottotitoli azioni",
		"settings_screen_shake": "Shake camera",
		"settings_footer_hint": "Le modifiche vengono salvate automaticamente e applicate subito.",
		"window_mode_windowed": "Finestra",
		"window_mode_borderless": "Borderless",
		"window_mode_fullscreen": "Schermo intero",
		"fps_limit_unlimited": "Illimitato",
		"graphics_low": "Basso",
		"graphics_medium": "Medio",
		"graphics_high": "Alto",
		"graphics_ultra": "Ultra",
		"ui_scale_small": "Piccola",
		"ui_scale_normal": "Normale",
		"ui_scale_large": "Grande",
		"ui_scale_huge": "Molto grande",
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
		"subtitle_level_changed": "Piano operativo %d attivo",
		"subtitle_weapon_fired": "Fuoco!",
		"subtitle_enemy_down": "Bersaglio neutralizzato",
		"release_checking": "Controllo aggiornamenti in corso...",
		"release_available_title": "Nuova release disponibile",
		"release_available_body": "È disponibile %s. La tua build attuale è %s.",
		"release_download": "Scarica release",
		"release_downloading": "Download aggiornamento in corso...",
		"release_installing": "Installazione aggiornamento in corso...",
		"release_install_prompt": "APK scaricato: completa l'installazione da Android.",
		"release_latest": "Stai già usando la versione più recente disponibile.",
		"release_none": "Nessuna release GitHub pubblicata al momento.",
		"release_error": "Impossibile controllare le release GitHub in questo momento.",
		"release_notes": "Note release",
		"release_progress": "Scaricati %s di %s (%d%%)",
		"release_progress_unknown": "Scaricati %s",
		"changelog_title": "Changelog %s",
		"changelog_empty": "Nessun changelog disponibile per questa build.",
	},
	"en": {
		"back": "Back",
		"close": "Close",
		"download": "Download",
		"later": "Later",
		"reset_defaults": "Reset defaults",
		"enabled": "Enabled",
		"disabled": "Disabled",
		"main_menu_eyebrow": "QGG AGENT - TED",
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
		"settings_ui_scale": "UI scale",
		"settings_language": "Language",
		"settings_show_fps": "Show FPS",
		"settings_subtitles": "Action subtitles",
		"settings_screen_shake": "Camera shake",
		"settings_footer_hint": "Changes are saved automatically and applied immediately.",
		"window_mode_windowed": "Windowed",
		"window_mode_borderless": "Borderless",
		"window_mode_fullscreen": "Fullscreen",
		"fps_limit_unlimited": "Unlimited",
		"graphics_low": "Low",
		"graphics_medium": "Medium",
		"graphics_high": "High",
		"graphics_ultra": "Ultra",
		"ui_scale_small": "Small",
		"ui_scale_normal": "Normal",
		"ui_scale_large": "Large",
		"ui_scale_huge": "Huge",
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
		"subtitle_level_changed": "Operational floor %d active",
		"subtitle_weapon_fired": "Weapons free!",
		"subtitle_enemy_down": "Target neutralized",
		"release_checking": "Checking for updates...",
		"release_available_title": "New release available",
		"release_available_body": "Version %s is available. Your current build is %s.",
		"release_download": "Download release",
		"release_downloading": "Downloading update...",
		"release_installing": "Installing update...",
		"release_install_prompt": "APK downloaded: complete installation from Android.",
		"release_latest": "You are already using the latest available release.",
		"release_none": "No GitHub releases are currently published.",
		"release_error": "Unable to check GitHub releases right now.",
		"release_notes": "Release notes",
		"release_progress": "Downloaded %s of %s (%d%%)",
		"release_progress_unknown": "Downloaded %s",
		"changelog_title": "Changelog %s",
		"changelog_empty": "No changelog is available for this build.",
	},
}

var settings: Dictionary = DEFAULTS.duplicate(true)
var meta: Dictionary = DEFAULT_META.duplicate(true)
var release_info: Dictionary = {
	"status": "idle",
	"error": "",
	"has_update": false,
	"latest_release": {},
	"current_release": {},
	"releases": [],
}

var _theme_resource: Theme = preload("res://Assets/UI/global_theme.tres")
var _update_request: HTTPRequest
var _pending_update_release: Dictionary = {}
var _pending_update_asset: Dictionary = {}
var _fps_panel: PanelContainer
var _fps_label: Label
var _subtitle_panel: PanelContainer
var _subtitle_label: Label
var _subtitle_time_left := 0.0
var _release_thread: Thread
var _release_check_running := false
var _last_fps_text := ""
var _registered_translations: Array[Translation] = []
var _theme_base_font_sizes: Dictionary = {}
var _theme_base_constants: Dictionary = {}
var _download_in_progress := false
var _last_download_progress := -1.0
var _last_downloaded_bytes := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 256
	_register_builtin_translations()
	_cache_theme_baseline()
	_build_fps_overlay()
	_build_subtitle_overlay()
	_build_update_request()
	if get_tree() and not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)
	_load_config()


func _process(delta: float) -> void:
	if bool(settings.get("show_fps", false)):
		_update_fps_text()
	if _subtitle_time_left > 0.0:
		_subtitle_time_left = maxf(0.0, _subtitle_time_left - delta)
		if _subtitle_time_left <= 0.0 and _subtitle_panel:
			_subtitle_panel.visible = false
	if _download_in_progress:
		_emit_download_progress()


func get_settings() -> Dictionary:
	return settings.duplicate(true)


func get_setting(key: String, fallback: Variant = null) -> Variant:
	return settings.get(key, fallback)


func get_meta_value(key: String, fallback: Variant = null) -> Variant:
	return meta.get(key, fallback)


func set_meta_value(key: String, value: Variant, persist := true) -> void:
	meta[key] = value
	if persist:
		_save_config()


func get_current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func mark_current_version_seen(mark_changelog := false) -> void:
	var current_version := get_current_version()
	meta["last_seen_version"] = current_version
	if mark_changelog:
		meta["last_changelog_version"] = current_version
	_save_config()


func needs_changelog_for_current_version() -> bool:
	return String(meta.get("last_changelog_version", "")) != get_current_version()


func get_changelog_for_version(version: String, release_body := "") -> String:
	var body_text := String(release_body).strip_edges()
	if not body_text.is_empty():
		return body_text
	var changelog_path := "res://CHANGELOG.md"
	if not FileAccess.file_exists(changelog_path):
		return text("changelog_empty")
	var file := FileAccess.open(changelog_path, FileAccess.READ)
	if file == null:
		return text("changelog_empty")
	var raw_text := file.get_as_text()
	var section_text := _extract_changelog_section(raw_text, version)
	if section_text.is_empty():
		return raw_text.strip_edges() if not raw_text.strip_edges().is_empty() else text("changelog_empty")
	return section_text


func text(key: String, args: Array = []) -> String:
	var translated := String(TranslationServer.translate(key))
	if translated == key and TEXTS.has("it") and TEXTS["it"].has(key):
		translated = String(TEXTS["it"][key])
	if args.is_empty():
		return translated
	return translated % args


func show_subtitle(message: String, duration := 2.5) -> void:
	if not bool(settings.get("subtitles", true)):
		return
	if _subtitle_panel == null or _subtitle_label == null:
		return
	_subtitle_label.text = message
	_subtitle_panel.visible = true
	_subtitle_time_left = maxf(0.5, duration)


func show_subtitle_key(key: String, args: Array = [], duration := 2.5) -> void:
	show_subtitle(text(key, args), duration)


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
	_apply_ui_scale(float(settings["ui_scale"]))
	_apply_language(String(settings["language"]))
	_apply_show_fps(bool(settings["show_fps"]))
	_apply_subtitles(bool(settings["subtitles"]))
	if persist:
		_save_config()
	settings_changed.emit(get_settings())
	if previous_language != String(settings["language"]):
		language_changed.emit(String(settings["language"]))


func reset_to_defaults() -> void:
	apply_settings(DEFAULTS.duplicate(true), true)


func request_release_check(force := false) -> void:
	if _release_check_running:
		return
	if not force and String(release_info.get("status", "idle")) == "success":
		release_check_completed.emit(release_info.duplicate(true))
		return
	_release_check_running = true
	release_info = {
		"status": "checking",
		"error": "",
		"has_update": false,
		"latest_release": {},
		"current_release": {},
		"releases": [],
	}
	_release_thread = Thread.new()
	_release_thread.start(Callable(self, "_release_check_worker"))


func _release_check_worker() -> void:
	var result := _fetch_release_info()
	call_deferred("_finish_release_check", result)


func _finish_release_check(result: Dictionary) -> void:
	if _release_thread and _release_thread.is_started():
		_release_thread.wait_to_finish()
	_release_thread = null
	_release_check_running = false
	release_info = result.duplicate(true)
	release_check_completed.emit(release_info.duplicate(true))


func _load_config() -> void:
	var config := ConfigFile.new()
	var loaded_settings := DEFAULTS.duplicate(true)
	meta = DEFAULT_META.duplicate(true)
	if config.load(SETTINGS_PATH) == OK:
		for key: String in DEFAULTS.keys():
			loaded_settings[key] = config.get_value(SETTINGS_SECTION, key, loaded_settings[key])
		for meta_key: String in DEFAULT_META.keys():
			meta[meta_key] = config.get_value(META_SECTION, meta_key, meta[meta_key])
	apply_settings(loaded_settings, false)


func _save_config() -> void:
	var config := ConfigFile.new()
	for key: String in settings.keys():
		config.set_value(SETTINGS_SECTION, key, settings[key])
	for meta_key: String in meta.keys():
		config.set_value(META_SECTION, meta_key, meta[meta_key])
	config.save(SETTINGS_PATH)


func _sanitize_settings(values: Dictionary) -> Dictionary:
	var sanitized := DEFAULTS.duplicate(true)
	sanitized["master_volume"] = clampf(float(values.get("master_volume", DEFAULTS["master_volume"])), 0.0, 100.0)
	sanitized["window_mode"] = clampi(int(values.get("window_mode", DEFAULTS["window_mode"])), 0, 2)
	sanitized["vsync"] = bool(values.get("vsync", DEFAULTS["vsync"]))
	var fps_cap := int(values.get("fps_cap", DEFAULTS["fps_cap"]))
	sanitized["fps_cap"] = fps_cap if FPS_CAP_OPTIONS.has(fps_cap) else int(DEFAULTS["fps_cap"])
	sanitized["graphics_preset"] = clampi(int(values.get("graphics_preset", DEFAULTS["graphics_preset"])), 0, GRAPHICS_PRESET_CONFIGS.size() - 1)
	var ui_scale := float(values.get("ui_scale", DEFAULTS["ui_scale"]))
	sanitized["ui_scale"] = ui_scale if UI_SCALE_OPTIONS.has(ui_scale) else float(DEFAULTS["ui_scale"])
	sanitized["language"] = _normalize_language(String(values.get("language", DEFAULTS["language"])))
	sanitized["show_fps"] = bool(values.get("show_fps", DEFAULTS["show_fps"]))
	sanitized["subtitles"] = bool(values.get("subtitles", DEFAULTS["subtitles"]))
	sanitized["screen_shake"] = bool(values.get("screen_shake", DEFAULTS["screen_shake"]))
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
	var window := get_tree().root
	if window == null or OS.get_name() == "Android":
		return
	match index:
		2:
			window.borderless = true
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if OS.get_name() == "Windows" else Window.MODE_FULLSCREEN
		1:
			window.mode = Window.MODE_WINDOWED
			window.borderless = true
		_:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false


func _apply_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)


func _apply_fps_cap(value: int) -> void:
	Engine.max_fps = max(0, value)


func _apply_graphics_preset(index: int) -> void:
	var config: Dictionary = GRAPHICS_PRESET_CONFIGS[clampi(index, 0, GRAPHICS_PRESET_CONFIGS.size() - 1)]
	if get_tree() == null:
		return
	_apply_graphics_to_branch(get_tree().root, config)


func _apply_ui_scale(ui_scale_value: float) -> void:
	if _theme_resource == null:
		return
	_theme_resource.default_base_scale = ui_scale_value
	for theme_type_variant in _theme_base_font_sizes.keys():
		var theme_type := String(theme_type_variant)
		var font_sizes: Dictionary = _theme_base_font_sizes[theme_type_variant]
		for item_name_variant in font_sizes.keys():
			var item_name := String(item_name_variant)
			var base_size := int(font_sizes[item_name_variant])
			_theme_resource.set_font_size(item_name, theme_type, maxi(1, int(round(float(base_size) * ui_scale_value))))
	for theme_type_variant in _theme_base_constants.keys():
		var theme_type := String(theme_type_variant)
		var constants: Dictionary = _theme_base_constants[theme_type_variant]
		for item_name_variant in constants.keys():
			var item_name := String(item_name_variant)
			var base_value := int(constants[item_name_variant])
			_theme_resource.set_constant(item_name, theme_type, maxi(0, int(round(float(base_value) * ui_scale_value))))
	if get_tree() and get_tree().root:
		get_tree().root.theme = _theme_resource


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


func _apply_subtitles(enabled: bool) -> void:
	if enabled:
		return
	if _subtitle_panel:
		_subtitle_panel.visible = false
		_subtitle_time_left = 0.0


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


func _build_subtitle_overlay() -> void:
	_subtitle_panel = PanelContainer.new()
	_subtitle_panel.name = "SubtitleOverlay"
	_subtitle_panel.visible = false
	_subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_panel.anchor_left = 0.5
	_subtitle_panel.anchor_top = 1.0
	_subtitle_panel.anchor_right = 0.5
	_subtitle_panel.anchor_bottom = 1.0
	_subtitle_panel.offset_left = -320.0
	_subtitle_panel.offset_top = -96.0
	_subtitle_panel.offset_right = 320.0
	_subtitle_panel.offset_bottom = -28.0
	add_child(_subtitle_panel)

	var margin := MarginContainer.new()
	margin.set("theme_override_constants/margin_left", 12)
	margin.set("theme_override_constants/margin_top", 8)
	margin.set("theme_override_constants/margin_right", 12)
	margin.set("theme_override_constants/margin_bottom", 8)
	_subtitle_panel.add_child(margin)

	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(_subtitle_label)


func _build_update_request() -> void:
	_update_request = HTTPRequest.new()
	_update_request.download_file = ""
	_update_request.timeout = 0.0
	_update_request.use_threads = true
	add_child(_update_request)
	_update_request.request_completed.connect(_on_update_download_completed)


func _update_fps_text() -> void:
	if _fps_label == null:
		return
	var next_text := text("fps_counter", [int(Engine.get_frames_per_second())])
	if next_text == _last_fps_text:
		return
	_last_fps_text = next_text
	_fps_label.text = next_text


func _extract_changelog_section(raw_text: String, version: String) -> String:
	var lines := raw_text.split("\n")
	var in_section := false
	var collected: Array[String] = []
	for raw_line: String in lines:
		var line := raw_line.strip_edges()
		if line.begins_with("## "):
			if in_section:
				break
			var heading := line.trim_prefix("## ").strip_edges()
			if heading == version or heading == ("v" + version):
				in_section = true
			continue
		if in_section:
			collected.append(raw_line)
	return "\n".join(collected).strip_edges()


func begin_release_update(release: Dictionary) -> void:
	if release.is_empty():
		update_status_changed.emit({"status": "error", "message": text("release_error")})
		return
	var asset := _select_release_asset(release)
	if asset.is_empty():
		var fallback_url := String(release.get("html_url", "https://github.com/Ekt0re/tfa-agents/releases"))
		OS.shell_open(fallback_url)
		update_status_changed.emit({"status": "external", "message": text("release_download")})
		return
	_pending_update_release = release.duplicate(true)
	_pending_update_asset = asset.duplicate(true)
	var platform := OS.get_name()
	if platform == "Windows":
		_download_release_asset(asset)
	elif platform == "Android":
		OS.shell_open(String(asset.get("download_url", release.get("html_url", ""))))
		update_status_changed.emit({"status": "android_external", "message": text("release_install_prompt")})
	else:
		OS.shell_open(String(asset.get("download_url", release.get("html_url", ""))))
		update_status_changed.emit({"status": "external", "message": text("release_download")})


func _download_release_asset(asset: Dictionary) -> void:
	if _update_request == null:
		update_status_changed.emit({"status": "error", "message": text("release_error")})
		return
	var updates_dir := ProjectSettings.globalize_path("user://updates")
	DirAccess.make_dir_recursive_absolute(updates_dir)
	var file_name := String(asset.get("name", "update_package.zip"))
	var target_path := updates_dir.path_join(file_name)
	_update_request.download_file = target_path
	_download_in_progress = true
	_last_download_progress = -1.0
	_last_downloaded_bytes = -1
	var request_error := _update_request.request(String(asset.get("download_url", "")))
	if request_error != OK:
		_download_in_progress = false
		update_status_changed.emit({"status": "error", "message": "Download error %s" % request_error})
		return
	_emit_download_progress(true)


func _on_update_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_download_in_progress = false
	_last_download_progress = -1.0
	_last_downloaded_bytes = -1
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		update_status_changed.emit({"status": "error", "message": "HTTP %s / result %s" % [response_code, result], "progress": 0.0})
		return
	var asset_path := _update_request.download_file
	var file_size := int(FileAccess.get_file_as_bytes(asset_path).size())
	if OS.get_name() == "Windows":
		update_status_changed.emit({"status": "downloaded", "message": text("release_progress", [_format_bytes(file_size), _format_bytes(file_size), 100]), "progress": 1.0})
		_start_windows_update(asset_path)
	else:
		update_status_changed.emit({"status": "downloaded", "message": text("release_install_prompt"), "progress": 1.0})


func _start_windows_update(asset_path: String) -> void:
	var install_dir := OS.get_executable_path().get_base_dir()
	var exe_path := OS.get_executable_path()
	var updater_dir := ProjectSettings.globalize_path("user://updates/updater")
	var staging_dir := updater_dir.path_join("staging")
	DirAccess.make_dir_recursive_absolute(updater_dir)
	var script_path := updater_dir.path_join("apply_update.ps1")
	var script_content := "$pid = [int]$args[0]\n$package = $args[1]\n$staging = $args[2]\n$target = $args[3]\n$exe = $args[4]\nwhile (Get-Process -Id $pid -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 500 }\nif (Test-Path $staging) { Remove-Item $staging -Recurse -Force }\nNew-Item -ItemType Directory -Path $staging -Force | Out-Null\n$ext = [System.IO.Path]::GetExtension($package).ToLowerInvariant()\nif ($ext -eq '.zip') { Expand-Archive -LiteralPath $package -DestinationPath $staging -Force } else { Copy-Item -LiteralPath $package -Destination (Join-Path $target ([System.IO.Path]::GetFileName($package))) -Force }\nif (Test-Path $staging) { Copy-Item -Path (Join-Path $staging '*') -Destination $target -Recurse -Force }\nStart-Process -FilePath $exe\n"
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		update_status_changed.emit({"status": "error", "message": text("release_error")})
		return
	file.store_string(script_content)
	file.close()
	update_status_changed.emit({"status": "installing", "message": text("release_installing"), "progress": 1.0})
	OS.create_process("powershell.exe", PackedStringArray(["-ExecutionPolicy", "Bypass", "-File", script_path, str(OS.get_process_id()), asset_path, staging_dir, install_dir, exe_path]))
	get_tree().quit()


func _select_release_asset(release: Dictionary) -> Dictionary:
	var assets: Array = release.get("assets", [])
	if assets.is_empty():
		return {}
	var best_score := -1
	var best_asset: Dictionary = {}
	for asset_variant in assets:
		if typeof(asset_variant) != TYPE_DICTIONARY:
			continue
		var asset: Dictionary = asset_variant
		var score := _score_release_asset(asset)
		if score > best_score:
			best_score = score
			best_asset = asset
	return best_asset


func _score_release_asset(asset: Dictionary) -> int:
	var name := String(asset.get("name", "")).to_lower()
	var platform := OS.get_name()
	var score := 0
	if platform == "Windows":
		if name.ends_with(".zip"):
			score += 5
		if name.ends_with(".exe"):
			score += 2
		if name.contains("windows") or name.contains("win"):
			score += 4
		if name.contains("x86_64") or name.contains("64"):
			score += 2
	elif platform == "Android":
		if name.ends_with(".apk"):
			score += 5
		if name.contains("android"):
			score += 4
		if name.contains("arm64"):
			score += 2
	return score


func _fetch_release_info() -> Dictionary:
	var response := _http_get_releases()
	if not bool(response.get("success", false)):
		return {
			"status": "error",
			"error": String(response.get("error", "unknown_error")),
			"has_update": false,
			"latest_release": {},
			"current_release": {},
			"releases": [],
		}

	var releases: Array = response.get("releases", [])
	var latest_release := {}
	var current_release := {}
	var current_version := get_current_version()
	for release_variant in releases:
		if typeof(release_variant) != TYPE_DICTIONARY:
			continue
		var release: Dictionary = release_variant
		if latest_release.is_empty() and not bool(release.get("draft", false)):
			latest_release = _map_release(release)
		if _compare_versions(String(release.get("tag_name", "")), current_version) == 0:
			current_release = _map_release(release)
	var has_update := false
	if not latest_release.is_empty():
		has_update = _compare_versions(String(latest_release.get("tag_name", "")), current_version) > 0
	return {
		"status": "success",
		"error": "",
		"has_update": has_update,
		"latest_release": latest_release,
		"current_release": current_release,
		"releases": releases,
	}


func _map_release(release: Dictionary) -> Dictionary:
	var selected_asset := _select_release_asset(release)
	var download_url := String(release.get("html_url", "https://github.com/Ekt0re/tfa-agents/releases"))
	if not selected_asset.is_empty():
		download_url = String(selected_asset.get("browser_download_url", download_url))
	return {
		"tag_name": String(release.get("tag_name", "")),
		"name": String(release.get("name", "")),
		"body": String(release.get("body", "")),
		"html_url": String(release.get("html_url", "")),
		"download_url": download_url,
		"assets": release.get("assets", []),
		"selected_asset": selected_asset,
	}


func _compare_versions(a: String, b: String) -> int:
	var a_parts := a.trim_prefix("v").split(".")
	var b_parts := b.trim_prefix("v").split(".")
	var total := maxi(a_parts.size(), b_parts.size())
	for index in range(total):
		var a_value := a_parts[index].to_int() if index < a_parts.size() else 0
		var b_value := b_parts[index].to_int() if index < b_parts.size() else 0
		if a_value == b_value:
			continue
		return 1 if a_value > b_value else -1
	return 0


func _http_get_releases() -> Dictionary:
	var client := HTTPClient.new()
	var connect_error := client.connect_to_host(RELEASES_API_HOST, RELEASES_API_PORT, TLSOptions.client())
	if connect_error != OK:
		return {"success": false, "error": "connect_failed_%s" % connect_error}

	while client.get_status() == HTTPClient.STATUS_RESOLVING or client.get_status() == HTTPClient.STATUS_CONNECTING:
		client.poll()
		OS.delay_msec(50)

	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"success": false, "error": "status_%s" % client.get_status()}

	var headers := PackedStringArray([
		"User-Agent: tfa-agents",
		"Accept: application/vnd.github+json",
	])
	var request_error := client.request(HTTPClient.METHOD_GET, RELEASES_API_PATH, headers)
	if request_error != OK:
		return {"success": false, "error": "request_failed_%s" % request_error}

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		OS.delay_msec(50)

	var body := PackedByteArray()
	while true:
		client.poll()
		var status := client.get_status()
		if status == HTTPClient.STATUS_BODY:
			var chunk: PackedByteArray = client.read_response_body_chunk()
			if chunk.size() > 0:
				body.append_array(chunk)
			else:
				OS.delay_msec(50)
		elif status == HTTPClient.STATUS_CONNECTED:
			break
		elif status == HTTPClient.STATUS_DISCONNECTED:
			break
		else:
			OS.delay_msec(50)

	var response_code := client.get_response_code()
	if response_code != 200:
		return {"success": false, "error": "http_%s" % response_code}

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY:
		return {"success": false, "error": "invalid_json"}
	return {"success": true, "releases": parsed}


func _register_builtin_translations() -> void:
	if not _registered_translations.is_empty():
		return
	for locale in SUPPORTED_LANGUAGES:
		var translation := Translation.new()
		translation.locale = locale
		var table: Dictionary = TEXTS.get(locale, {})
		for key_variant in table.keys():
			var key := String(key_variant)
			translation.add_message(key, String(table[key_variant]))
		TranslationServer.add_translation(translation)
		_registered_translations.append(translation)


func _cache_theme_baseline() -> void:
	if _theme_resource == null:
		return
	_theme_base_font_sizes.clear()
	for theme_type in _theme_resource.get_font_size_type_list():
		var values := {}
		for item_name in _theme_resource.get_font_size_list(theme_type):
			values[item_name] = _theme_resource.get_font_size(item_name, theme_type)
		_theme_base_font_sizes[theme_type] = values
	_theme_base_constants.clear()
	for theme_type in _theme_resource.get_constant_type_list():
		var values := {}
		for item_name in _theme_resource.get_constant_list(theme_type):
			values[item_name] = _theme_resource.get_constant(item_name, theme_type)
		_theme_base_constants[theme_type] = values


func _on_tree_node_added(node: Node) -> void:
	if node == null:
		return
	var config: Dictionary = GRAPHICS_PRESET_CONFIGS[clampi(int(settings.get("graphics_preset", DEFAULTS["graphics_preset"])), 0, GRAPHICS_PRESET_CONFIGS.size() - 1)]
	_apply_graphics_to_node(node, config)


func _apply_graphics_to_branch(root: Node, config: Dictionary) -> void:
	if root == null:
		return
	_apply_graphics_to_node(root, config)
	for child in root.get_children():
		if child is Node:
			_apply_graphics_to_branch(child, config)


func _apply_graphics_to_node(node: Node, config: Dictionary) -> void:
	if node is PointLight2D:
		if not node.has_meta("graphics_base_energy"):
			node.set_meta("graphics_base_energy", node.energy)
		if not node.has_meta("graphics_base_shadow_enabled"):
			node.set_meta("graphics_base_shadow_enabled", node.shadow_enabled)
		var base_energy := float(node.get_meta("graphics_base_energy"))
		node.energy = base_energy * float(config.get("light_energy_multiplier", 1.0))
		node.shadow_enabled = bool(config.get("shadows_enabled", true)) and bool(node.get_meta("graphics_base_shadow_enabled"))
	elif node is Sprite2D and String(node.name).to_lower().contains("glow"):
		if not node.has_meta("graphics_base_visible"):
			node.set_meta("graphics_base_visible", node.visible)
		if not node.has_meta("graphics_base_alpha"):
			node.set_meta("graphics_base_alpha", node.modulate.a)
		var glow_multiplier := float(config.get("glow_alpha_multiplier", 1.0))
		var base_alpha := float(node.get_meta("graphics_base_alpha"))
		node.visible = bool(node.get_meta("graphics_base_visible")) and glow_multiplier > 0.01
		var next_modulate := node.modulate
		next_modulate.a = clampf(base_alpha * glow_multiplier, 0.0, 1.0)
		node.modulate = next_modulate


func _emit_download_progress(force := false) -> void:
	if _update_request == null:
		return
	var status := _update_request.get_http_client_status()
	if status != HTTPClient.STATUS_RESOLVING and status != HTTPClient.STATUS_CONNECTING and status != HTTPClient.STATUS_REQUESTING and status != HTTPClient.STATUS_BODY:
		return
	var downloaded_bytes := _update_request.get_downloaded_bytes()
	var body_size := _update_request.get_body_size()
	var progress := -1.0
	if body_size > 0:
		progress = clampf(float(downloaded_bytes) / float(body_size), 0.0, 1.0)
	if not force and downloaded_bytes == _last_downloaded_bytes and is_equal_approx(progress, _last_download_progress):
		return
	_last_downloaded_bytes = downloaded_bytes
	_last_download_progress = progress
	update_status_changed.emit({
		"status": "downloading",
		"message": text("release_downloading"),
		"progress": progress,
		"downloaded_bytes": downloaded_bytes,
		"total_bytes": body_size,
	})


func _format_bytes(byte_count: int) -> String:
	if byte_count < 0:
		return "?"
	var units := ["B", "KB", "MB", "GB"]
	var value := float(byte_count)
	var unit_index := 0
	while value >= 1024.0 and unit_index < units.size() - 1:
		value /= 1024.0
		unit_index += 1
	if unit_index == 0:
		return "%d %s" % [byte_count, units[unit_index]]
	return "%.1f %s" % [value, units[unit_index]]

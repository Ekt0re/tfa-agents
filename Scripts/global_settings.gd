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
 
 
var settings: Dictionary = DEFAULTS.duplicate(true)
var meta: Dictionary = DEFAULT_META.duplicate(true)
var release_info: Dictionary = {
	"status": "idle",
	"error": "",
	"has_update": false,
	"latest_release": {},
	"current_release": {},
}
 
signal subtitle_requested(message: String, duration: float)

var _theme_resource: Theme = preload("res://Assets/UI/global_theme.tres")

@onready var _fps_panel: PanelContainer = $FpsOverlay if has_node("FpsOverlay") else null
@onready var _fps_label: Label = $FpsOverlay/MarginContainer/Label if has_node("FpsOverlay/MarginContainer/Label") else null

var _release_thread: Thread
var _release_check_running := false
var _last_fps_text := ""
var _theme_base_font_sizes: Dictionary = {}
var _theme_base_constants: Dictionary = {}

 
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 256
	_cache_theme_baseline()
	if get_tree() and not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)
	_load_config()
 
 
func _process(_delta: float) -> void:
	if bool(settings.get("show_fps", false)):
		_update_fps_text()

 
 
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
	var translated := tr(key)
	if args.is_empty():
		return translated
	return translated % args
 
 
func show_subtitle(message: String, duration := 2.5) -> void:
	if not bool(settings.get("subtitles", true)):
		return
	subtitle_requested.emit(message, duration)
 
 
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
	}
	_release_thread = Thread.new()
	_release_thread.start(Callable(self, "_release_check_worker"))
 
 
func _release_check_worker() -> void:
	# FIX #7: wrappato in un blocco protetto per garantire il reset di _release_check_running
	# anche in caso di errori imprevisti durante il fetch
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
	var fps_val = int(values.get("fps_cap", DEFAULTS["fps_cap"]))
	sanitized["fps_cap"] = fps_val if fps_val in FPS_CAP_OPTIONS else DEFAULTS["fps_cap"]
	sanitized["graphics_preset"] = clampi(int(values.get("graphics_preset", DEFAULTS["graphics_preset"])), 0, GRAPHICS_PRESET_CONFIGS.size() - 1)
	var scale_val = float(values.get("ui_scale", DEFAULTS["ui_scale"]))
	sanitized["ui_scale"] = scale_val if scale_val in UI_SCALE_OPTIONS else DEFAULTS["ui_scale"]
	var lang_val = String(values.get("language", DEFAULTS["language"]))
	sanitized["language"] = lang_val if lang_val in SUPPORTED_LANGUAGES else DEFAULTS["language"]
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
	if window == null:
		return
	# Android non supporta exclusive fullscreen, ma gli altri modi sì
	if OS.get_name() == "Android" and index == 2:
		return
	match index:
		0: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		2: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
 
 
func _apply_vsync(enabled: bool) -> void:
	var mode = DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)
 
 
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
	if not enabled:
		subtitle_requested.emit("", 0.0)
 
 
func _percent_to_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)
 
 
# Le funzioni programmatiche _build_fps_overlay e _build_subtitle_overlay sono state rimosse 
# in quanto i nodi dell'FPS sono ora definiti nella scena Global.tscn e i sottotitoli in HUD_Game.tscn.
 
 
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
 
 
func begin_release_update(latest_release: Dictionary) -> void:
	var github_url := String(
		latest_release.get(
			"html_url",
			"https://github.com/Ekt0re/tfa-agents/releases"
		)
	)

	if github_url.is_empty():
		return

	OS.shell_open(github_url)

	update_status_changed.emit({
		"status": "redirected",
		"message": "Apertura pagina GitHub..."
	})
 
 
func _fetch_release_info() -> Dictionary:
	var output := {
		"status": "error",
		"error": "",
		"has_update": false,
		"latest_release": {},
		"current_release": {}
	}

	var client := HTTPClient.new()
	var headers := [
		"User-Agent: Godot-TFA-Agents-Updater",
		"Accept: application/vnd.github.v3+json"
	]

	var err := client.connect_to_host(
		RELEASES_API_HOST,
		RELEASES_API_PORT,
		TLSOptions.client()
	)

	if err != OK:
		output["error"] = "Connessione all'host fallita."
		return output

	while client.get_status() in [
		HTTPClient.STATUS_CONNECTING,
		HTTPClient.STATUS_RESOLVING
	]:
		client.poll()
		OS.delay_msec(10)

	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		output["error"] = "Impossibile connettersi all'API di GitHub."
		return output

	err = client.request(
		HTTPClient.METHOD_GET,
		RELEASES_API_PATH,
		headers
	)

	if err != OK:
		output["error"] = "Richiesta HTTP fallita."
		return output

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		OS.delay_msec(10)

	var rb := PackedByteArray()

	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()

		var chunk := client.read_response_body_chunk()

		if chunk.size() > 0:
			rb.append_array(chunk)
		else:
			OS.delay_msec(10)

	client.close()

	var json := JSON.new()

	if json.parse(rb.get_string_from_utf8()) != OK:
		output["error"] = "Errore nel parsing JSON."
		return output

	var releases = json.get_data()

	if typeof(releases) != TYPE_ARRAY or releases.is_empty():
		output["status"] = "success"
		return output

	var latest_release := {}
	var current_release := {}
	var current_version := get_current_version()

	for release in releases:
		if typeof(release) != TYPE_DICTIONARY:
			continue

		if bool(release.get("draft", false)):
			continue

		var r_data := {
			"tag_name": String(release.get("tag_name", "")),
			"name": String(release.get("name", "")),
			"body": String(release.get("body", "")),
			"html_url": String(release.get("html_url", ""))
		}

		if latest_release.is_empty():
			latest_release = r_data
			
		var tag := String(release.get("tag_name", ""))
		if tag == current_version or tag == ("v" + current_version):
			current_release = r_data

		if not latest_release.is_empty() and not current_release.is_empty():
			break

	output["status"] = "success"
	output["latest_release"] = latest_release
	output["current_release"] = current_release

	if not latest_release.is_empty():
		var latest_tag := String(latest_release["tag_name"]).replace("v", "")

		output["has_update"] = _is_version_newer(
			current_version,
			latest_tag
		)

	return output
 
 
func _compare_versions(a: String, b: String) -> int:
	var regex := RegEx.new()
	regex.compile("\\d+")

	var a_parts: Array[int] = []
	var b_parts: Array[int] = []

	for match in regex.search_all(a):
		a_parts.append(match.get_string().to_int())

	for match in regex.search_all(b):
		b_parts.append(match.get_string().to_int())

	var total := maxi(a_parts.size(), b_parts.size())

	for i in range(total):
		var a_value := a_parts[i] if i < a_parts.size() else 0
		var b_value := b_parts[i] if i < b_parts.size() else 0

		if a_value > b_value:
			return 1
		elif a_value < b_value:
			return -1

	return 0
 
 
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
		var next_modulate: Color = node.modulate
		next_modulate.a = clampf(base_alpha * glow_multiplier, 0.0, 1.0)
		node.modulate = next_modulate
 

func _is_version_newer(current: String, latest: String) -> bool:
	var c_parts := current.split(".")
	var l_parts := latest.split(".")
	for i in range(min(c_parts.size(), l_parts.size())):
		if l_parts[i].to_int() > c_parts[i].to_int():
			return true
		if l_parts[i].to_int() < c_parts[i].to_int():
			return false
	return l_parts.size() > c_parts.size()
 
 

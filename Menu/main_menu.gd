extends Control  # v2 — preloader integrato

signal play_requested
signal exit_requested

@export_file("*.tscn") var play_scene_path := "res://Maps/dev_map.tscn"

## Risorse da precaricare in background.
## IMPORTANTE: includere solo le scene "top level", non le loro sub-dipendenze.
## Godot carica automaticamente player.tscn, bot.tscn ecc. come dipendenze di dev_map.
var PRELOAD_RESOURCES: Array[String] = [
	"res://Maps/dev_map.tscn",
]

## Shader da compilare in anticipo (caricamento sincrono — sono semplici file di testo)
var PRELOAD_SHADERS: Array[String] = [
	"res://Shaders/level_transition.gdshader",
	"res://Shaders/ramp_glow.gdshader",
	"res://Shaders/crack_shader.gdshader",
	"res://Shaders/dashed_circle.gdshader",
]

@onready var _global_settings = get_node("/root/GlobalSettings")
@onready var _settings_overlay: Control = %SettingsOverlay
@onready var _version_label: Label = %VersionLabel
@onready var _eyebrow_label: Label = $MainContent/CenterContainer/MenuCard/CardMargin/VBox/Eyebrow
@onready var _play_button: Button = $MainContent/CenterContainer/MenuCard/CardMargin/VBox/ButtonsVBox/PlayButton
var _multiplayer_button: Button = null
@onready var _settings_button: Button = $MainContent/CenterContainer/MenuCard/CardMargin/VBox/ButtonsVBox/SettingsButton
@onready var _exit_button: Button = $MainContent/CenterContainer/MenuCard/CardMargin/VBox/ButtonsVBox/ExitButton
@onready var _info_label: Label = $MainContent/CenterContainer/MenuCard/CardMargin/VBox/InfoLabel
@onready var _release_status_label: Label = %ReleaseStatusLabel
@onready var _release_banner: PanelContainer = %ReleaseBanner
@onready var _release_banner_title: Label = %ReleaseBannerTitle
@onready var _release_banner_body: Label = %ReleaseBannerBody
@onready var _download_release_button: Button = %DownloadReleaseButton
@onready var _dismiss_release_button: Button = %DismissReleaseButton
@onready var _download_progress_bar: ProgressBar = %DownloadProgressBar
@onready var _download_progress_label: Label = %DownloadProgressLabel
@onready var _changelog_overlay: Control = %ChangelogOverlay
@onready var _changelog_title_label: Label = %ChangelogTitleLabel
@onready var _changelog_subtitle_label: Label = %ChangelogSubtitleLabel
@onready var _changelog_body: RichTextLabel = %ChangelogBody
@onready var _close_changelog_button: Button = %CloseChangelogButton

var _last_release_info: Dictionary = {}

# ---------------------------------------------------------------------------
# Overlay di caricamento (creato dinamicamente, non richiede nodi in scena)
# ---------------------------------------------------------------------------
var _load_overlay: Control = null
var _load_bar: ProgressBar = null
var _load_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_overlay.visible = false
	_release_banner.visible = false
	_download_progress_bar.visible = false
	_download_progress_label.visible = false
	_changelog_overlay.visible = false
	_changelog_body.bbcode_enabled = true
	_changelog_body.fit_content = true
	_update_version_label()
	_refresh_texts()
	_global_settings.language_changed.connect(_on_language_changed)
	_global_settings.release_check_completed.connect(_on_release_check_completed)
	_global_settings.update_status_changed.connect(_on_update_status_changed)
	if String(_global_settings.release_info.get("status", "idle")) == "idle":
		_global_settings.request_release_check()
	else:
		_on_release_check_completed(_global_settings.release_info)

	# --- Creazione dinamica bottone Multigiocatore ---
	var buttons_vbox = $MainContent/CenterContainer/MenuCard/CardMargin/VBox/ButtonsVBox
	if buttons_vbox:
		_multiplayer_button = Button.new()
		_multiplayer_button.name = "MultiplayerButton"
		_multiplayer_button.text = "MULTIGIOCATORE"
		buttons_vbox.add_child(_multiplayer_button)
		buttons_vbox.move_child(_multiplayer_button, _play_button.get_index() + 1)
		_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
		_multiplayer_button.custom_minimum_size = _play_button.custom_minimum_size
		_multiplayer_button.theme_type_variation = _play_button.theme_type_variation
		_refresh_texts()

	# ---------------------------------------------------------------------------
	# Avvia il precaricamento asincrono di risorse e shader
	# ---------------------------------------------------------------------------
	var preloader: Node = get_node_or_null("/root/ResourcePreloader")
	if preloader:
		# IMPORTANTE: connetti i segnali PRIMA di chiamare preload_resources.
		# Se si controlla is_done() prima del preload, è sempre true (stato iniziale)
		# e i segnali non vengono mai collegati → overlay bloccato al 100%.
		if not preloader.progress_changed.is_connected(_on_preload_progress):
			preloader.progress_changed.connect(_on_preload_progress)
		if not preloader.all_loaded.is_connected(_on_preload_complete):
			preloader.all_loaded.connect(_on_preload_complete)
		preloader.preload_resources(PRELOAD_RESOURCES)
		preloader.preload_shaders(PRELOAD_SHADERS)
		# Mostra la barra solo se il caricamento è ancora in corso
		if not preloader.is_done():
			_build_load_overlay()
			_update_load_bar(preloader.get_progress())



func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_game"):
		if _changelog_overlay.visible:
			_hide_changelog()
			get_viewport().set_input_as_handled()
		elif _settings_overlay.visible:
			_hide_settings()
			get_viewport().set_input_as_handled()


func _on_play_pressed() -> void:
	play_requested.emit()
	if play_scene_path.is_empty():
		return

	# Pulisci i dati del checkpoint per una nuova partita
	var flow_player := get_node_or_null("/root/MissionFlowPlayer")
	if flow_player and flow_player.has_method("clear_checkpoint_data"):
		flow_player.call("clear_checkpoint_data")

	var preloader: Node = get_node_or_null("/root/ResourcePreloader")
	if preloader and not preloader.is_done():
		# Risorse ancora in caricamento: mostra overlay e aspetta
		_build_load_overlay()
		_update_load_bar(preloader.get_progress())
		preloader.change_scene_when_ready(play_scene_path)
	else:
		# Già tutto pronto: cambio istantaneo senza freeze
		if preloader:
			preloader.change_scene_when_ready(play_scene_path)
		else:
			get_tree().change_scene_to_file(play_scene_path)


func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://Menu/multiplayer_menu.tscn")


func _on_settings_pressed() -> void:
	_settings_overlay.visible = true


func _on_exit_pressed() -> void:
	exit_requested.emit()
	get_tree().quit()


func _on_settings_back_requested() -> void:
	_hide_settings()


func _on_download_release_pressed() -> void:
	var latest_release: Dictionary = _last_release_info.get("latest_release", {})
	$ReleaseBanner.visible = false
	if latest_release.is_empty():
		return
	_global_settings.begin_release_update(latest_release)


func _on_dismiss_release_pressed() -> void:
	_release_banner.visible = false


func _on_close_changelog_pressed() -> void:
	_hide_changelog()


func _hide_settings() -> void:
	_settings_overlay.visible = false


func _hide_changelog() -> void:
	_changelog_overlay.visible = false


func _update_version_label() -> void:
	var version: String = _global_settings.get_current_version()
	_version_label.text = "v%s" % version


func _refresh_texts() -> void:
	_eyebrow_label.text = _tr_text("main_menu_eyebrow")
	_play_button.text = _tr_text("main_menu_play")
	if _multiplayer_button:
		_multiplayer_button.text = _tr_text("MULTIGIOCATORE") if _tr_text("multiplayer") == "multiplayer" else _tr_text("multiplayer")
	_settings_button.text = _tr_text("main_menu_settings")
	_exit_button.text = _tr_text("main_menu_exit")
	_info_label.text = _tr_text("main_menu_info")
	_download_release_button.text = _tr_text("release_download")
	_dismiss_release_button.text = _tr_text("later")
	_close_changelog_button.text = _tr_text("close")
	_refresh_release_ui()


func _refresh_release_ui() -> void:
	var status := String(_last_release_info.get("status", "idle"))
	_release_banner.visible = false
	_download_progress_bar.visible = false
	_download_progress_label.visible = false
	_download_progress_bar.value = 0.0
	_download_progress_label.text = ""
	match status:
		"idle", "checking":
			_release_status_label.text = _tr_text("release_checking")
		"error":
			_release_status_label.text = _tr_text("release_error")
		"success":
			var latest_release: Dictionary = _last_release_info.get("latest_release", {})
			var has_update: bool = bool(_last_release_info.get("has_update", false))
			if has_update:
				var latest_tag := String(latest_release.get("tag_name", "?"))
				var current_version: String = _global_settings.get_current_version()
				_release_banner.visible = true
				_release_banner_title.text = _tr_text("release_available_title")
				_release_banner_body.text = _tr_text("release_available_body", [latest_tag, current_version])
				_release_status_label.text = ""
			elif not latest_release.is_empty():
				_release_status_label.text = _tr_text("release_latest")
			else:
				_release_status_label.text = _tr_text("release_none")
		_:
			_release_status_label.text = ""


func _maybe_show_startup_changelog() -> void:
	if not _global_settings.needs_changelog_for_current_version():
		return
	_refresh_changelog_overlay()
	_changelog_overlay.visible = true
	_global_settings.mark_current_version_seen(true)


func _refresh_changelog_overlay() -> void:
	var current_version: String = _global_settings.get_current_version()
	var current_release: Dictionary = _last_release_info.get("current_release", {})
	var changelog_body: String = _global_settings.get_changelog_for_version(current_version, String(current_release.get("body", "")))
	_changelog_title_label.text = _tr_text("changelog_title", [current_version])
	_changelog_subtitle_label.text = _tr_text("release_notes")
	_changelog_body.text = MarkdownToBBCode.convert(changelog_body)


func _on_release_check_completed(info: Dictionary) -> void:
	print("DEBUG: Dati ricevuti da GlobalSettings: ", info)
	_last_release_info = info.duplicate(true)
	_refresh_release_ui()
	_update_version_label()
	_maybe_show_startup_changelog()


func _on_update_status_changed(info: Dictionary) -> void:
	var status := String(info.get("status", ""))
	var message := String(info.get("message", ""))
	var progress := float(info.get("progress", -1.0))
	var downloaded_bytes := int(info.get("downloaded_bytes", -1))
	var total_bytes := int(info.get("total_bytes", -1))
	if not message.is_empty():
		_release_status_label.text = message
	match status:
		"downloading":
			_download_progress_bar.visible = true
			_download_progress_label.visible = true
			_download_progress_bar.value = clampf(progress * 100.0, 0.0, 100.0) if progress >= 0.0 else 0.0
			_download_progress_label.text = _build_download_details(progress, downloaded_bytes, total_bytes)
			_download_release_button.disabled = true
		"installing", "downloaded":
			_download_progress_bar.visible = true
			_download_progress_label.visible = true
			_download_progress_bar.value = 100.0
			_download_progress_label.text = message
			_download_release_button.disabled = status == "installing"
		"error", "external", "android_external":
			_download_progress_bar.visible = false
			_download_progress_label.visible = false
			_download_progress_bar.value = 0.0
			_download_progress_label.text = ""
			_download_release_button.disabled = false
		_:
			_download_release_button.disabled = false


func _on_language_changed(_language_code: String) -> void:
	_refresh_texts()
	if _changelog_overlay.visible:
		_refresh_changelog_overlay()


# ---------------------------------------------------------------------------
# Overlay di caricamento asincrono
# ---------------------------------------------------------------------------

## Costruisce programmaticamente un overlay di caricamento minimale.
## Viene mostrato solo se le risorse non sono ancora pronte al click Play.
func _build_load_overlay() -> void:
	if is_instance_valid(_load_overlay):
		return

	# Sfondo semitrasparente
	_load_overlay = ColorRect.new()
	var bg := _load_overlay as ColorRect
	bg.color = Color(0.04, 0.06, 0.10, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_load_overlay)

	# Contenitore verticale centrato
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(480.0, 0.0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_load_overlay.add_child(vbox)

	# Etichetta titolo
	var title := Label.new()
	var loading_key := tr("loading_title")
	title.text = loading_key if loading_key != "loading_title" else "CARICAMENTO IN CORSO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color(0.0, 0.9, 1.0, 1.0)
	vbox.add_child(title)

	# Barra di progresso
	_load_bar = ProgressBar.new()
	_load_bar.min_value = 0.0
	_load_bar.max_value = 1.0
	_load_bar.value = 0.0
	_load_bar.show_percentage = false
	_load_bar.custom_minimum_size = Vector2(480.0, 10.0)
	vbox.add_child(_load_bar)

	# Etichetta percentuale
	_load_label = Label.new()
	_load_label.text = "0%"
	_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_label.add_theme_font_size_override("font_size", 14)
	_load_label.modulate = Color(0.7, 0.85, 1.0, 0.9)
	vbox.add_child(_load_label)

	# Animazione fade-in dell'overlay
	_load_overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_load_overlay, "modulate:a", 1.0, 0.25)


## Aggiorna visivamente la barra di caricamento.
func _update_load_bar(p: float) -> void:
	if not is_instance_valid(_load_bar):
		return
	p = clampf(p, 0.0, 1.0)
	_load_bar.value = p
	if is_instance_valid(_load_label):
		_load_label.text = "%d%%" % int(p * 100.0)


## Nasconde e rimuove l'overlay con animazione fade-out.
func _hide_load_overlay() -> void:
	if not is_instance_valid(_load_overlay):
		return
	var overlay := _load_overlay
	_load_overlay = null
	_load_bar = null
	_load_label = null
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 0.0, 0.3)
	tw.tween_callback(overlay.queue_free)


## Callback da ResourcePreloader.progress_changed
func _on_preload_progress(overall: float) -> void:
	_update_load_bar(overall)


## Callback da ResourcePreloader.all_loaded
func _on_preload_complete() -> void:
	_hide_load_overlay()


func _tr_text(key: String, args: Array = []) -> String:
	var translated := tr(key)
	if args.is_empty():
		return translated
	return translated % args


func _build_download_details(progress: float, downloaded_bytes: int, total_bytes: int) -> String:
	if downloaded_bytes < 0:
		return _tr_text("release_downloading")
	if total_bytes > 0:
		# Converte i byte in Megabyte per una lettura più comoda
		var mb_downloaded := downloaded_bytes / 1024.0 / 1024.0
		var mb_total := total_bytes / 1024.0 / 1024.0
		return "%.2f MB / %.2f MB (%.1f%%)" % [mb_downloaded, mb_total, progress * 100.0]
	return "%d bytes scaricati" % downloaded_bytes


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

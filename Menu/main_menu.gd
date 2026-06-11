extends Control

signal play_requested
signal exit_requested

@export_file("*.tscn") var play_scene_path := "res://Maps/dev_map.tscn"

@onready var _global_settings = get_node("/root/GlobalSettings")
@onready var _settings_overlay: Control = %SettingsOverlay
@onready var _version_label: Label = %VersionLabel
@onready var _eyebrow_label: Label = $MainContent/CenterContainer/MenuCard/CardMargin/VBox/Eyebrow
@onready var _play_button: Button = $MainContent/CenterContainer/MenuCard/CardMargin/VBox/ButtonsVBox/PlayButton
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_overlay.visible = false
	_release_banner.visible = false
	_download_progress_bar.visible = false
	_download_progress_label.visible = false
	_changelog_overlay.visible = false
	_update_version_label()
	_refresh_texts()
	_global_settings.language_changed.connect(_on_language_changed)
	_global_settings.release_check_completed.connect(_on_release_check_completed)
	_global_settings.update_status_changed.connect(_on_update_status_changed)
	if String(_global_settings.release_info.get("status", "idle")) == "idle":
		_global_settings.request_release_check()
	else:
		_on_release_check_completed(_global_settings.release_info)


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
	if not play_scene_path.is_empty():
		get_tree().change_scene_to_file(play_scene_path)


func _on_settings_pressed() -> void:
	_settings_overlay.visible = true


func _on_exit_pressed() -> void:
	exit_requested.emit()
	get_tree().quit()


func _on_settings_back_requested() -> void:
	_hide_settings()


func _on_download_release_pressed() -> void:
	var latest_release: Dictionary = _last_release_info.get("latest_release", {})
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
			var releases: Array = _last_release_info.get("releases", [])
			if bool(_last_release_info.get("has_update", false)):
				var latest_release: Dictionary = _last_release_info.get("latest_release", {})
				var latest_tag := String(latest_release.get("tag_name", "?"))
				var current_version: String = _global_settings.get_current_version()
				_release_banner.visible = true
				_release_banner_title.text = _tr_text("release_available_title")
				_release_banner_body.text = _tr_text("release_available_body", [latest_tag, current_version])
				_release_status_label.text = ""
			elif releases.is_empty():
				_release_status_label.text = _tr_text("release_none")
			else:
				_release_status_label.text = _tr_text("release_latest")
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
	_changelog_body.text = changelog_body


func _on_release_check_completed(info: Dictionary) -> void:
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


func _tr_text(key: String, args: Array = []) -> String:
	var translated := tr(key)
	if args.is_empty():
		return translated
	return translated % args


func _build_download_details(progress: float, downloaded_bytes: int, total_bytes: int) -> String:
	if downloaded_bytes < 0:
		return _tr_text("release_downloading")
	if total_bytes > 0 and progress >= 0.0:
		return _tr_text("release_progress", [_format_bytes(downloaded_bytes), _format_bytes(total_bytes), int(round(progress * 100.0))])
	return _tr_text("release_progress_unknown", [_format_bytes(downloaded_bytes)])


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

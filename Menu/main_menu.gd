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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_version_label()
	_refresh_texts()
	_settings_overlay.visible = false
	_global_settings.language_changed.connect(_on_language_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_game") and _settings_overlay.visible:
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


func _hide_settings() -> void:
	_settings_overlay.visible = false


func _update_version_label() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "0.1.0-dev"))
	_version_label.text = "v%s" % version


func _refresh_texts() -> void:
	_eyebrow_label.text = _global_settings.text("main_menu_eyebrow")
	_play_button.text = _global_settings.text("main_menu_play")
	_settings_button.text = _global_settings.text("main_menu_settings")
	_exit_button.text = _global_settings.text("main_menu_exit")
	_info_label.text = _global_settings.text("main_menu_info")


func _on_language_changed(_language_code: String) -> void:
	_refresh_texts()

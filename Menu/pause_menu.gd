extends CanvasLayer

signal pause_opened
signal pause_closed
signal main_menu_requested

@export_file("*.tscn") var main_menu_scene_path := "res://Menu/main_menu.tscn"
@export var pause_action: StringName = &"pause_game"
@export var freeze_game_on_pause := true
@export var disable_pause_button_when_open := true

@onready var _global_settings = get_node("/root/GlobalSettings")
@onready var _pause_button: Button = %PauseButton
@onready var _overlay: Control = %Overlay
@onready var _menu_panel: PanelContainer = %MenuPanel
@onready var _settings_panel: PanelContainer = %SettingsPanel
@onready var _mode_label: Label = %ModeLabel
@onready var _title_label: Label = $Overlay/CenterContainer/MenuPanel/MenuMargin/VBox/TitleLabel
@onready var _resume_button: Button = $Overlay/CenterContainer/MenuPanel/MenuMargin/VBox/ResumeButton
@onready var _settings_button: Button = $Overlay/CenterContainer/MenuPanel/MenuMargin/VBox/SettingsButton
@onready var _main_menu_button: Button = $Overlay/CenterContainer/MenuPanel/MenuMargin/VBox/MainMenuButton
@onready var _hint_label: Label = $Overlay/CenterContainer/MenuPanel/MenuMargin/VBox/HintLabel

var _menu_is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_button.pressed.connect(_open_pause_menu)
	_overlay.visible = false
	_settings_panel.visible = false
	_menu_panel.visible = true
	_refresh_texts()
	_global_settings.language_changed.connect(_on_language_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(pause_action):
		if _menu_is_open:
			_close_pause_menu()
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()


func _open_pause_menu() -> void:
	if _menu_is_open:
		return
	_menu_is_open = true
	_overlay.visible = true
	_menu_panel.visible = true
	_settings_panel.visible = false
	if disable_pause_button_when_open:
		_pause_button.visible = false
	if _should_freeze_game():
		get_tree().paused = true
	_update_mode_label()
	pause_opened.emit()


func _close_pause_menu() -> void:
	if not _menu_is_open:
		return
	if _should_freeze_game():
		get_tree().paused = false
	_menu_is_open = false
	_overlay.visible = false
	_menu_panel.visible = true
	_settings_panel.visible = false
	_pause_button.visible = true
	pause_closed.emit()


func _on_resume_pressed() -> void:
	_close_pause_menu()


func _on_settings_pressed() -> void:
	_menu_panel.visible = false
	_settings_panel.visible = true


func _on_settings_back_requested() -> void:
	_settings_panel.visible = false
	_menu_panel.visible = true


func _on_main_menu_pressed() -> void:
	if _should_freeze_game():
		get_tree().paused = false
	_menu_is_open = false
	main_menu_requested.emit()
	if not main_menu_scene_path.is_empty():
		get_tree().change_scene_to_file(main_menu_scene_path)


func _should_freeze_game() -> bool:
	if not freeze_game_on_pause:
		return false
	return not multiplayer.has_multiplayer_peer()


func _refresh_texts() -> void:
	_pause_button.text = tr("pause_button")
	_title_label.text = tr("pause_title")
	_resume_button.text = tr("pause_resume")
	_settings_button.text = tr("pause_settings")
	_main_menu_button.text = tr("pause_main_menu")
	_hint_label.text = tr("pause_hint")
	_update_mode_label()


func _update_mode_label() -> void:
	if _should_freeze_game():
		_mode_label.text = tr("pause_mode_singleplayer")
	else:
		_mode_label.text = tr("pause_mode_multiplayer")


func _on_language_changed(_language_code: String) -> void:
	_refresh_texts()

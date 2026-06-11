extends PanelContainer

signal back_requested
signal settings_changed(settings: Dictionary)

@onready var _global_settings = get_node("/root/GlobalSettings")
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _back_button: Button = %BackButton
@onready var _reset_button: Button = %ResetButton
@onready var _master_slider: HSlider = %MasterSlider
@onready var _master_value: Label = %MasterValue
@onready var _window_mode: OptionButton = %WindowModeOption
@onready var _vsync_toggle: CheckButton = %VSyncToggle
@onready var _fps_cap: OptionButton = %FpsCapOption
@onready var _graphics_preset: OptionButton = %GraphicsPresetOption
@onready var _language: OptionButton = %LanguageOption
@onready var _show_fps_toggle: CheckButton = %ShowFpsToggle

var _is_loading := false


func _ready() -> void:
	_hide_non_real_rows()
	_connect_global_signals()
	_connect_controls()
	_populate_options()
	_update_texts()
	_apply_settings_to_controls(_global_settings.get_settings())


func _connect_global_signals() -> void:
	_global_settings.settings_changed.connect(_on_global_settings_changed)
	_global_settings.language_changed.connect(_on_language_changed)


func _connect_controls() -> void:
	_back_button.pressed.connect(func() -> void:
		back_requested.emit()
	)
	_reset_button.pressed.connect(_on_reset_pressed)
	_master_slider.value_changed.connect(_on_master_slider_changed)
	_window_mode.item_selected.connect(_on_setting_changed)
	_vsync_toggle.toggled.connect(_on_toggle_changed)
	_fps_cap.item_selected.connect(_on_setting_changed)
	_graphics_preset.item_selected.connect(_on_setting_changed)
	_language.item_selected.connect(_on_setting_changed)
	_show_fps_toggle.toggled.connect(_on_toggle_changed)


func _hide_non_real_rows() -> void:
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/AudioSection/AudioMargin/AudioVBox/MusicRow").visible = false
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/AudioSection/AudioMargin/AudioVBox/SfxRow").visible = false
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/GameplaySection/GameplayMargin/GameplayVBox/SubtitlesRow").visible = false
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/GameplaySection/GameplayMargin/GameplayVBox/ScreenShakeRow").visible = false


func _populate_options() -> void:
	_window_mode.clear()
	for key: String in ["window_mode_windowed", "window_mode_borderless", "window_mode_fullscreen"]:
		_window_mode.add_item(_global_settings.text(key))

	_fps_cap.clear()
	for fps_value: int in [30, 60, 120, 0]:
		var label := "%d FPS" % fps_value if fps_value > 0 else _global_settings.text("fps_limit_unlimited")
		_fps_cap.add_item(label)
		_fps_cap.set_item_metadata(_fps_cap.item_count - 1, fps_value)

	_graphics_preset.clear()
	for key: String in ["graphics_low", "graphics_medium", "graphics_high", "graphics_ultra"]:
		_graphics_preset.add_item(_global_settings.text(key))

	_language.clear()
	_language.add_item(_global_settings.text("language_italian"))
	_language.set_item_metadata(_language.item_count - 1, "it")
	_language.add_item(_global_settings.text("language_english"))
	_language.set_item_metadata(_language.item_count - 1, "en")


func _update_texts() -> void:
	_title_label.text = _global_settings.text("settings_title")
	_subtitle_label.text = _global_settings.text("settings_subtitle")
	_back_button.text = _global_settings.text("back")
	_reset_button.text = _global_settings.text("reset_defaults")
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/AudioSection/AudioMargin/AudioVBox/AudioTitle").text = _global_settings.text("settings_section_audio")
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/AudioSection/AudioMargin/AudioVBox/MasterRow/MasterLabel").text = _global_settings.text("settings_master_volume")
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/GraphicsSection/GraphicsMargin/GraphicsVBox/GraphicsTitle").text = _global_settings.text("settings_section_graphics")
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/GraphicsSection/GraphicsMargin/GraphicsVBox/WindowModeRow/WindowModeLabel").text = _global_settings.text("settings_window_mode")
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/GraphicsSection/GraphicsMargin/GraphicsVBox/VSyncRow/VSyncLabel").text = _global_settings.text("settings_vsync")
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/GraphicsSection/GraphicsMargin/GraphicsVBox/FpsCapRow/FpsCapLabel").text = _global_settings.text("settings_fps_limit")
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/GraphicsSection/GraphicsMargin/GraphicsVBox/PresetRow/PresetLabel").text = _global_settings.text("settings_graphics_preset")
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/GameplaySection/GameplayMargin/GameplayVBox/GameplayTitle").text = _global_settings.text("settings_section_interface")
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/GameplaySection/GameplayMargin/GameplayVBox/LanguageRow/LanguageLabel").text = _global_settings.text("settings_language")
	get_node("ContentMargin/RootVBox/ScrollContainer/SectionsVBox/GameplaySection/GameplayMargin/GameplayVBox/ShowFpsRow/ShowFpsLabel").text = _global_settings.text("settings_show_fps")
	get_node("ContentMargin/RootVBox/Footer/FooterHint").text = _global_settings.text("settings_footer_hint")
	_refresh_toggle_texts()


func _apply_settings_to_controls(settings: Dictionary) -> void:
	_is_loading = true
	_master_slider.value = float(settings.get("master_volume", 80.0))
	_window_mode.select(clampi(int(settings.get("window_mode", 0)), 0, _window_mode.item_count - 1))
	_vsync_toggle.button_pressed = bool(settings.get("vsync", true))
	_select_option_by_metadata(_fps_cap, int(settings.get("fps_cap", 60)))
	_graphics_preset.select(clampi(int(settings.get("graphics_preset", 2)), 0, _graphics_preset.item_count - 1))
	_select_option_by_metadata(_language, String(settings.get("language", "it")))
	_show_fps_toggle.button_pressed = bool(settings.get("show_fps", false))
	_refresh_slider_labels()
	_refresh_toggle_texts()
	_is_loading = false
	settings_changed.emit(settings)


func _collect_settings() -> Dictionary:
	return {
		"master_volume": _master_slider.value,
		"window_mode": _window_mode.selected,
		"vsync": _vsync_toggle.button_pressed,
		"fps_cap": int(_fps_cap.get_selected_metadata()),
		"graphics_preset": _graphics_preset.selected,
		"language": String(_language.get_selected_metadata()),
		"show_fps": _show_fps_toggle.button_pressed,
	}


func _refresh_slider_labels() -> void:
	_master_value.text = "%d%%" % int(round(_master_slider.value))


func _refresh_toggle_texts() -> void:
	_vsync_toggle.text = _global_settings.text("enabled") if _vsync_toggle.button_pressed else _global_settings.text("disabled")
	_show_fps_toggle.text = _global_settings.text("enabled") if _show_fps_toggle.button_pressed else _global_settings.text("disabled")


func _on_master_slider_changed(_value: float) -> void:
	_refresh_slider_labels()
	if _is_loading:
		return
	_global_settings.apply_settings({"master_volume": _master_slider.value})


func _on_setting_changed(_index: int) -> void:
	if _is_loading:
		return
	_global_settings.apply_settings(_collect_settings())


func _on_toggle_changed(_pressed: bool) -> void:
	_refresh_toggle_texts()
	if _is_loading:
		return
	_global_settings.apply_settings(_collect_settings())


func _on_reset_pressed() -> void:
	_global_settings.reset_to_defaults()


func _on_global_settings_changed(settings: Dictionary) -> void:
	_apply_settings_to_controls(settings)


func _on_language_changed(_language_code: String) -> void:
	_populate_options()
	_update_texts()
	_apply_settings_to_controls(_global_settings.get_settings())


func _select_option_by_metadata(option: OptionButton, value: Variant) -> void:
	for index: int in option.item_count:
		if option.get_item_metadata(index) == value:
			option.select(index)
			return
	option.select(0)

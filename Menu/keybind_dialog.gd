extends Window

signal keybinds_changed

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _close_button: Button = %CloseButton
@onready var _reset_button: Button = %ResetButton
@onready var _keybinds_vbox: VBoxContainer = %KeybindsVBox
@onready var _footer_hint: Label = %FooterHint

var _keybind_rows: Array = []
var _current_rebinding: String = ""
var _is_rebinding: bool = false

# Configurazione modulare delle azioni - facile da estendere
var _action_config: Dictionary = {
	"ui_up": {"display_key": "keybind_action_up", "category_key": "keybind_category_movement"},
	"ui_down": {"display_key": "keybind_action_down", "category_key": "keybind_category_movement"},
	"ui_left": {"display_key": "keybind_action_left", "category_key": "keybind_category_movement"},
	"ui_right": {"display_key": "keybind_action_right", "category_key": "keybind_category_movement"},
	"reload": {"display_key": "keybind_action_reload", "category_key": "keybind_category_actions"},
	"deploy_turret": {"display_key": "keybind_action_deploy_turret", "category_key": "keybind_category_actions"},
	"hack": {"display_key": "keybind_action_hack", "category_key": "keybind_category_actions"},
	"weapon_next": {"display_key": "keybind_action_weapon_next", "category_key": "keybind_category_weapons"},
	"weapon_prev": {"display_key": "keybind_action_weapon_prev", "category_key": "keybind_category_weapons"}
}

var _default_keybinds: Dictionary = {
	"ui_up": KEY_W,
	"ui_down": KEY_S,
	"ui_left": KEY_A,
	"ui_right": KEY_D,
	"reload": KEY_R,
	"deploy_turret": KEY_T,
	"hack": KEY_E,
	"weapon_next": KEY_ALT,
	"weapon_prev": KEY_TAB
}

var _current_keybinds: Dictionary = {}


func _ready() -> void:
	_load_keybinds()
	_build_keybind_ui()
	_connect_signals()
	_update_texts()
	
	if get_node("/root/GlobalSettings"):
		get_node("/root/GlobalSettings").language_changed.connect(_on_language_changed)


func _connect_signals() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	close_requested.connect(_on_close_pressed)


func _load_keybinds() -> void:
	var config = ConfigFile.new()
	var error = config.load("user://keybinds.cfg")
	
	if error == OK:
		for action_name in _action_config.keys():
			var key_code = config.get_value("keybinds", action_name, _default_keybinds[action_name])
			_current_keybinds[action_name] = key_code
	else:
		_current_keybinds = _default_keybinds.duplicate()


func _save_keybinds() -> void:
	var config = ConfigFile.new()
	for action_name in _action_config.keys():
		config.set_value("keybinds", action_name, _current_keybinds[action_name])
	config.save("user://keybinds.cfg")
	
	_apply_keybinds_to_input_map()
	keybinds_changed.emit()


func _apply_keybinds_to_input_map() -> void:
	for action_name in _action_config.keys():
		InputMap.action_erase_events(action_name)
		var key_event = InputEventKey.new()
		key_event.keycode = _current_keybinds[action_name]
		InputMap.action_add_event(action_name, key_event)


func _build_keybind_ui() -> void:
	# Pulisci UI esistente
	for child in _keybinds_vbox.get_children():
		child.queue_free()
	_keybind_rows.clear()
	
	var current_category: String = ""
	var category_vbox: VBoxContainer = null
	
	for action_name in _action_config.keys():
		var config_data = _action_config[action_name]
		var category_key = config_data["category_key"]
		
		# Crea nuova sezione categoria se cambia
		if category_key != current_category:
			current_category = category_key
			
			var category_label = Label.new()
			category_label.text = tr(category_key)
			category_label.add_theme_font_size_override("font_size", 18)
			category_label.modulate = Color(0.8, 0.88, 1, 0.9)
			_keybinds_vbox.add_child(category_label)
			
			category_vbox = VBoxContainer.new()
			category_vbox.add_theme_constant_override("separation", 4)
			_keybinds_vbox.add_child(category_vbox)
		
		# Crea riga keybind
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		
		var label = Label.new()
		label.text = tr(config_data["display_key"])
		label.custom_minimum_size = Vector2(200, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		
		var key_button = Button.new()
		key_button.custom_minimum_size = Vector2(150, 0)
		key_button.text = _get_key_name(_current_keybinds[action_name])
		key_button.set_meta("action_name", action_name)
		key_button.pressed.connect(_on_keybind_button_pressed.bind(action_name, key_button))
		row.add_child(key_button)
		
		category_vbox.add_child(row)
		_keybind_rows.append({"action": action_name, "button": key_button})


func _get_key_name(key_code: int) -> String:
	return OS.get_keycode_string(key_code)


func _on_keybind_button_pressed(action_name: String, button: Button) -> void:
	if _is_rebinding:
		return
	
	_is_rebinding = true
	_current_rebinding = action_name
	button.text = tr("keybind_press_key")
	button.modulate = Color(1, 0.5, 0.5)
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if not _is_rebinding:
		return
	
	if event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()
		
		if event.keycode == KEY_ESCAPE:
			_cancel_rebinding()
			return
		
		# Assegna nuovo tasto
		_current_keybinds[_current_rebinding] = event.keycode
		_save_keybinds()
		_cancel_rebinding()
		_refresh_keybind_ui()


func _cancel_rebinding() -> void:
	_is_rebinding = false
	_current_rebinding = ""
	set_process_input(false)
	_refresh_keybind_ui()


func _refresh_keybind_ui() -> void:
	for row_data in _keybind_rows:
		var action_name = row_data["action"]
		var button = row_data["button"]
		button.text = _get_key_name(_current_keybinds[action_name])
		button.modulate = Color.WHITE


func _on_reset_pressed() -> void:
	_current_keybinds = _default_keybinds.duplicate()
	_save_keybinds()
	_refresh_keybind_ui()


func _on_close_pressed() -> void:
	hide()


func _update_texts() -> void:
	_title_label.text = tr("keybind_dialog_title")
	_subtitle_label.text = tr("keybind_dialog_subtitle")
	_close_button.text = tr("keybind_dialog_close")
	_reset_button.text = tr("keybind_dialog_reset")
	_footer_hint.text = tr("keybind_dialog_hint")


func _on_language_changed(_language_code: String) -> void:
	_update_texts()
	_build_keybind_ui()


func apply_keybinds_on_startup() -> void:
	_load_keybinds()
	_apply_keybinds_to_input_map()

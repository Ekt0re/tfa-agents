extends Control

@onready var _message_label: Label = $CenterContainer/VBox/MessageLabel
@onready var _return_button: Button = $CenterContainer/VBox/ReturnButton

func _ready() -> void:
	_return_button.pressed.connect(_on_return_button_pressed)
	
	# Leggi il motivo di disconnessione da GlobalSettings
	var gs = get_node_or_null("/root/GlobalSettings")
	if gs and gs.has_method("get_setting"):
		var reason = gs.call("get_setting", "disconnect_reason", "L'host si è disconnesso dalla partita.")
		if _message_label:
			_message_label.text = reason

func set_disconnect_message(message: String) -> void:
	if _message_label:
		_message_label.text = message

func _on_return_button_pressed() -> void:
	var mp_manager = get_node_or_null("/root/MultiplayerManager")
	if mp_manager:
		mp_manager.disconnect_game()
	get_tree().change_scene_to_file("res://Menu/main_menu.tscn")

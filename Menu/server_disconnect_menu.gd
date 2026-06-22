extends Control

@onready var _return_button: Button = $CenterContainer/VBox/ReturnButton

func _ready() -> void:
	_return_button.pressed.connect(_on_return_button_pressed)

func _on_return_button_pressed() -> void:
	var mp_manager = get_node_or_null("/root/MultiplayerManager")
	if mp_manager:
		mp_manager.disconnect_game()
	get_tree().change_scene_to_file("res://Menu/main_menu.tscn")

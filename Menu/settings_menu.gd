extends Control

@export_file("*.tscn") var back_scene_path := "res://Menu/main_menu.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_game"):
		_on_back_requested()
		get_viewport().set_input_as_handled()


func _on_back_requested() -> void:
	if back_scene_path.is_empty():
		return
	get_tree().change_scene_to_file(back_scene_path)

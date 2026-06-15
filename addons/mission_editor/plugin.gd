## plugin.gd
## Entry point del plugin Mission Flow Editor.
## Registra il dock, i custom type e l'autoload MissionFlowPlayer.
@tool
extends EditorPlugin

const FLOW_PLAYER_PATH := "res://addons/mission_editor/mission_flow_player.gd"
const CHECKPOINT_SCRIPT := "res://addons/mission_editor/checkpoint.gd"
const EDITOR_DOCK_SCRIPT := "res://addons/mission_editor/editor/editor_main.gd"

var _dock: Control = null
var _flow_player_autoload_added: bool = false


func _enter_tree() -> void:
	# Aggiungi autoload MissionFlowPlayer se non esiste
	if not ProjectSettings.has_setting("autoload/MissionFlowPlayer"):
		add_autoload_singleton("MissionFlowPlayer", FLOW_PLAYER_PATH)
		_flow_player_autoload_added = true

	# Registra custom type CheckPoint
	add_custom_type(
		"CheckPoint",
		"Area2D",
		preload(CHECKPOINT_SCRIPT),
		_get_checkpoint_icon()
	)

	# Crea e aggiungi il dock editor
	_dock = _create_dock()
	if _dock:
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	# Rimuovi il dock
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

	# Rimuovi custom type
	remove_custom_type("CheckPoint")

	# Rimuovi autoload se l'abbiamo aggiunto noi
	if _flow_player_autoload_added:
		remove_autoload_singleton("MissionFlowPlayer")


func _create_dock() -> Control:
	var dock_script: GDScript = load(EDITOR_DOCK_SCRIPT) as GDScript
	var dock: Control = dock_script.new()
	dock.name = "MissionFlowEditor"
	# Passa reference al plugin
	if dock.has_method("set_plugin"):
		dock.set_plugin(self)
	return dock


func _get_checkpoint_icon() -> Texture2D:
	# Icona semplice per il CheckPoint nel menu Add Node
	# Ritorna null per usare l'icona di default di Area2D
	return null


## Handler per salvare i file .tres dal dock
func save_flow_resource(flow: Resource, path: String) -> Error:
	var err := ResourceSaver.save(flow, path)
	if err == OK:
		get_editor_interface().get_resource_filesystem().scan()
		print("MissionFlowEditor: Saved flow to %s" % path)
	else:
		push_error("MissionFlowEditor: Failed to save flow to %s" % path)
	return err


## Handler per caricare un flow .tres
func load_flow_resource(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		push_error("MissionFlowEditor: File not found: %s" % path)
		return null
	return load(path)


## Apre l'EditorFileDialog per salvare
func show_save_dialog(callback: Callable, filter: String = "*.tres") -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter(filter, "Godot Resource")
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = "Save Mission Flow"
	dialog.file_selected.connect(callback)
	dialog.canceled.connect(func(): dialog.queue_free())
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))


## Apre l'EditorFileDialog per caricare
func show_open_dialog(callback: Callable, filter: String = "*.tres") -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter(filter, "Godot Resource")
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = "Open Mission Flow"
	dialog.file_selected.connect(callback)
	dialog.canceled.connect(func(): dialog.queue_free())
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))

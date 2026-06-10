extends Area2D
class_name Ramp

@export var level_bottom: int = 0
@export var level_top: int = 1
@export var cooldown_seconds: float = 0.3
@export var breathing_speed: float = 2.2
@export var breathing_scale_amplitude: float = 0.08

var _cooldowns: Dictionary = {}
var _traversed_bodies: Dictionary = {}
var _time_elapsed: float = 0.0
var _level_manager: LevelManager = null


func _process(delta: float) -> void:
	var sprite = get_node_or_null("Sprite2D")
	if not sprite:
		return

	_time_elapsed += delta
	var breath = sin(_time_elapsed * breathing_speed)
	var current_scale = 1.0 - breathing_scale_amplitude * breath
	sprite.scale = Vector2(current_scale, current_scale)


func _ready() -> void:
	add_to_group("ramps")
	call_deferred("_initialize_level_manager")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	call_deferred("_connect_to_player")


func _initialize_level_manager() -> void:
	_level_manager = _get_level_manager()


func _connect_to_player() -> void:
	var players = get_tree().get_nodes_in_group("players")
	if not players.is_empty():
		_setup_player_connection(players[0])
	else:
		get_tree().process_frame.connect(_connect_to_player, CONNECT_ONE_SHOT)


func _setup_player_connection(player: Node2D) -> void:
	if player.has_signal("height_level_changed"):
		player.height_level_changed.connect(_on_player_height_level_changed)
		_update_z_index(player.current_height_level)
		_update_rotation(player.current_height_level)


func _on_player_height_level_changed(player_level: int) -> void:
	_update_z_index(player_level)
	_update_rotation(player_level)


func _update_z_index(player_level: int) -> void:
	if not _level_manager:
		_level_manager = _get_level_manager()
	var visible_level := level_top if player_level >= level_top else level_bottom
	z_index = _level_manager.get_level_z_index(visible_level) if _level_manager else visible_level * 2 + 1


func _update_rotation(player_level: int) -> void:
	var sprite = get_node_or_null("Sprite2D")
	if not sprite:
		return
	sprite.rotation = PI / 2.0 if player_level >= level_top else -PI / 2.0


func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("change_height_level"):
		return
	if not ("current_height_level" in body):
		return
	if "wants_ramp_teleport" in body and not body.wants_ramp_teleport:
		return

	var body_id := body.get_instance_id()
	if _traversed_bodies.has(body_id) or _cooldowns.has(body_id):
		return

	var current_level: int = body.current_height_level
	var new_level := _resolve_destination_level(current_level)
	if new_level == -1:
		return

	print("[RAMPA DEBUG] ", body.name, " attraversa la rampa ", name,
		" | Livello iniziale: L", current_level, " -> Livello destinazione: L", new_level)
	body.change_height_level(new_level)
	_traversed_bodies[body_id] = true

	var ramp_events = get_node_or_null("/root/RampEvents")
	if ramp_events:
		ramp_events.ramp_traversed.emit(body, new_level, self)

	_start_cooldown(body_id)


func _resolve_destination_level(current_level: int) -> int:
	if current_level == level_bottom:
		return level_top
	if current_level == level_top:
		return level_bottom
	return -1


func _on_body_exited(body: Node2D) -> void:
	_traversed_bodies.erase(body.get_instance_id())


func _start_cooldown(body_id: int) -> void:
	_cooldowns[body_id] = true
	get_tree().create_timer(cooldown_seconds).timeout.connect(
		func(): _cooldowns.erase(body_id)
	)


func _get_level_manager() -> LevelManager:
	var current_scene = get_tree().current_scene
	if not current_scene:
		return null

	var manager := current_scene.get_node_or_null("LevelManager") as LevelManager
	if manager:
		manager.setup(current_scene)
		return manager

	return null

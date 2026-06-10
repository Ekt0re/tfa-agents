@tool
extends Area2D
class_name Ramp

@export_range(0, 15, 1) var start_level: int = 0:
	set(value):
		start_level = max(value, 0)
		_refresh_level_membership()
		_apply_collision_mask()
		_update_editor_preview()

@export_range(0, 15, 1) var arrival_level: int = 1:
	set(value):
		arrival_level = max(value, 0)
		_refresh_level_membership()
		_apply_collision_mask()
		_update_editor_preview()

@export var cooldown_seconds: float = 0.3
@export var breathing_speed: float = 2.2
@export var breathing_scale_amplitude: float = 0.08

var _cooldowns: Dictionary = {}
var _traversed_bodies: Dictionary = {}
var _time_elapsed: float = 0.0
var _registered_levels: Array[int] = []


func _ready() -> void:
	_update_editor_preview()

	if Engine.is_editor_hint():
		return

	add_to_group("ramps")
	_refresh_level_membership()
	_apply_collision_mask()
	_connect_area_signals()
	call_deferred("_connect_to_player")


func _process(delta: float) -> void:
	var sprite = get_node_or_null("Sprite2D")
	if not sprite:
		return

	_time_elapsed += delta
	var breath = sin(_time_elapsed * breathing_speed)
	var current_scale = 1.0 - breathing_scale_amplitude * breath
	sprite.scale = Vector2(current_scale, current_scale)


func is_visible_from_level(level: int) -> bool:
	return level == start_level or level == arrival_level


func _connect_area_signals() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _connect_to_player() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return

	var players = get_tree().get_nodes_in_group("players")
	if not players.is_empty():
		_setup_player_connection(players[0])
	else:
		get_tree().process_frame.connect(_connect_to_player, CONNECT_ONE_SHOT)


func _setup_player_connection(player: Node2D) -> void:
	if player.has_signal("height_level_changed"):
		if not player.height_level_changed.is_connected(_on_player_height_level_changed):
			player.height_level_changed.connect(_on_player_height_level_changed)
		_apply_for_player_level(player.current_height_level)


func _on_player_height_level_changed(player_level: int) -> void:
	_apply_for_player_level(player_level)


func _apply_for_player_level(player_level: int) -> void:
	visible = is_visible_from_level(player_level)
	_update_z_index(player_level)
	_update_rotation(player_level)


func _update_z_index(player_level: int) -> void:
	var visible_level := player_level if is_visible_from_level(player_level) else start_level
	z_index = visible_level * 10 + 1


func _update_rotation(player_level: int) -> void:
	var sprite = get_node_or_null("Sprite2D")
	if not sprite:
		return

	sprite.rotation = PI / 2.0 if player_level == arrival_level else -PI / 2.0


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
	if current_level == start_level:
		return arrival_level
	if current_level == arrival_level:
		return start_level
	return -1


func _on_body_exited(body: Node2D) -> void:
	_traversed_bodies.erase(body.get_instance_id())


func _start_cooldown(body_id: int) -> void:
	_cooldowns[body_id] = true
	get_tree().create_timer(cooldown_seconds).timeout.connect(
		func(): _cooldowns.erase(body_id)
	)


func _refresh_level_membership() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return

	for level in _registered_levels:
		remove_from_group("entities_level_" + str(level))
	_registered_levels.clear()

	for level in _get_visible_levels():
		add_to_group("entities_level_" + str(level))
		_registered_levels.append(level)


func _get_visible_levels() -> Array[int]:
	var levels: Array[int] = [start_level]
	if arrival_level != start_level:
		levels.append(arrival_level)
	return levels


func _apply_collision_mask() -> void:
	collision_mask = _character_collision_bit(start_level) | _character_collision_bit(arrival_level)


func _character_collision_bit(level: int) -> int:
	return 1 << (level * 3 + 1)


func _update_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return

	visible = true
	_update_z_index(start_level)
	_update_rotation(start_level)
	update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if start_level == arrival_level:
		warnings.append("Il piano di partenza e il piano di arrivo dovrebbero essere diversi.")
	return warnings

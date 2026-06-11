extends CharacterBody2D
class_name BotSimple

signal height_level_changed(new_level: int)

const NAV_REGION_NODE_NAMES := [
	"L0_NavigationRegion2D",
	"L1_NavigationRegion2D",
	"L2_NavigationRegion2D"
]

@export var speed: float = 320.0
@export var current_height_level: int = 0
@export var total_levels: int = 3
@export var auto_chase_player: bool = true
@export var target_node_path: NodePath
@export var repath_interval: float = 0.12
@export var movement_smoothing: float = 8.0
@export var stop_smoothing: float = 10.0
@export var arrival_distance: float = 18.0
@export var look_smoothing: float = 10.0
@export var debug_pathfinding: bool = true

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null
@onready var path_line: Line2D = $Line2D if has_node("Line2D") else null
@onready var ray_cast: RayCast2D = $RayCast2D if has_node("RayCast2D") else null
@onready var visual_sprite: Node2D = $Sprite2D if has_node("Sprite2D") else null

var _tracked_target: Node2D = null
var _tracked_target_signal_node: Node = null
var _navigation_layer_masks_by_level: Dictionary = {}
var _last_repath_time: float = -1000.0
var _last_target_position: Vector2 = Vector2.INF
var _last_look_direction: Vector2 = Vector2.RIGHT


func _ready() -> void:
	add_to_group("bots")
	call_deferred("_initialize_bot")


func _initialize_bot() -> void:
	_cache_navigation_regions()
	change_height_level(current_height_level, true)

	if ray_cast:
		ray_cast.enabled = true

	if not target_node_path.is_empty():
		var configured_target := get_node_or_null(target_node_path) as Node2D
		if configured_target:
			set_target(configured_target)
			return

	if auto_chase_player:
		_try_assign_player_target()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_tracked_target) and auto_chase_player:
		_try_assign_player_target()

	var has_valid_target := is_instance_valid(_tracked_target)
	if has_valid_target:
		var target_level := _resolve_node_level(_tracked_target)
		if target_level == current_height_level:
			_update_navigation_target_if_needed()
		else:
			_clear_navigation_path()
	else:
		_clear_navigation_path()

	var move_direction := _get_move_direction()
	if move_direction.length() > 0.001:
		_last_look_direction = move_direction
		var movement_weight: float = clampf(movement_smoothing * delta, 0.0, 1.0)
		velocity = velocity.lerp(move_direction * speed, movement_weight)
	else:
		var stop_weight: float = clampf(stop_smoothing * delta, 0.0, 1.0)
		velocity = velocity.lerp(Vector2.ZERO, stop_weight)
		if velocity.length() < 5.0:
			velocity = Vector2.ZERO

	move_and_slide()
	_update_visual_direction(delta)
	_update_debug_path_line()


func set_target(target: Node2D) -> void:
	if not target:
		_tracked_target = null
		_disconnect_target_signals()
		_clear_navigation_path()
		return

	_tracked_target = target
	_connect_target_signals(target)
	_force_repath()


func change_height_level(new_level: int, force_update: bool = false) -> void:
	new_level = clampi(new_level, 0, total_levels - 1)
	if new_level == current_height_level and not force_update:
		return

	var previous_level := current_height_level
	if previous_level != new_level or force_update:
		if is_in_group("entities_level_" + str(previous_level)):
			remove_from_group("entities_level_" + str(previous_level))

	current_height_level = new_level
	if not is_in_group("entities_level_" + str(current_height_level)):
		add_to_group("entities_level_" + str(current_height_level))

	var layer_offset := current_height_level * 3
	var wall_bit := 1 << (0 + layer_offset)
	var character_bit := 1 << (1 + layer_offset)
	collision_layer = character_bit
	collision_mask = wall_bit | character_bit
	z_index = current_height_level * 10

	if navigation_agent:
		navigation_agent.navigation_layers = _get_navigation_layers_for_level(current_height_level)

	visible = true
	height_level_changed.emit(current_height_level)
	_force_repath()

	if debug_pathfinding:
		print("[BOT SIMPLE] cambia piano: L", previous_level, " -> L", current_height_level)


func _try_assign_player_target() -> void:
	var players := get_tree().get_nodes_in_group("players")
	if not players.is_empty() and players[0] is Node2D:
		set_target(players[0] as Node2D)


func _update_navigation_target_if_needed() -> void:
	if not navigation_agent or not is_instance_valid(_tracked_target):
		return

	var now := _get_time_seconds()
	var target_position := _tracked_target.global_position
	var target_moved := _last_target_position == Vector2.INF or target_position.distance_to(_last_target_position) > maxf(arrival_distance, 12.0)
	if target_moved or navigation_agent.is_navigation_finished() or now - _last_repath_time >= repath_interval:
		navigation_agent.target_position = target_position
		_last_target_position = target_position
		_last_repath_time = now
		if debug_pathfinding:
			print("[BOT SIMPLE] repath L", current_height_level, " -> ", target_position)


func _get_move_direction() -> Vector2:
	if not navigation_agent or not is_instance_valid(_tracked_target):
		return Vector2.ZERO
	if _resolve_node_level(_tracked_target) != current_height_level:
		return Vector2.ZERO
	if navigation_agent.is_navigation_finished():
		return Vector2.ZERO

	var next_path_position := navigation_agent.get_next_path_position()
	var direction := next_path_position - global_position
	if direction.length() <= 1.0:
		return Vector2.ZERO
	return direction.normalized()


func _clear_navigation_path() -> void:
	if navigation_agent:
		navigation_agent.target_position = global_position
	_last_target_position = Vector2.INF
	if path_line:
		path_line.clear_points()


func _force_repath() -> void:
	_last_repath_time = -1000.0
	var navigation_map := get_world_2d().get_navigation_map()
	NavigationServer2D.map_force_update(navigation_map)
	if navigation_agent:
		navigation_agent.navigation_layers = _get_navigation_layers_for_level(current_height_level)
		if is_instance_valid(_tracked_target) and _resolve_node_level(_tracked_target) == current_height_level:
			navigation_agent.target_position = _tracked_target.global_position
			_last_target_position = _tracked_target.global_position
		else:
			navigation_agent.target_position = global_position
			_last_target_position = Vector2.INF


func _update_visual_direction(delta: float) -> void:
	rotation = 0.0

	var desired_look_direction := _last_look_direction
	if velocity.length() > 12.0:
		desired_look_direction = velocity.normalized()
	elif is_instance_valid(_tracked_target) and _resolve_node_level(_tracked_target) == current_height_level:
		var direction_to_target := _tracked_target.global_position - global_position
		if direction_to_target.length() > 0.001:
			desired_look_direction = direction_to_target.normalized()

	if desired_look_direction.length() <= 0.001:
		return

	var look_weight: float = clampf(look_smoothing * delta, 0.0, 1.0)
	if visual_sprite:
		visual_sprite.rotation = lerp_angle(visual_sprite.rotation, desired_look_direction.angle(), look_weight)

	if ray_cast:
		var ray_length: float = maxf(ray_cast.target_position.length(), 96.0)
		ray_cast.target_position = desired_look_direction * ray_length
		ray_cast.force_raycast_update()


func _update_debug_path_line() -> void:
	if not path_line or not navigation_agent:
		return

	var navigation_path: PackedVector2Array = navigation_agent.get_current_navigation_path()
	if navigation_path.is_empty() or not is_instance_valid(_tracked_target) or _resolve_node_level(_tracked_target) != current_height_level:
		path_line.clear_points()
		return

	var points: Array[Vector2] = [Vector2.ZERO]
	for world_point in navigation_path:
		var local_point := world_point - global_position
		if points[points.size() - 1].distance_to(local_point) > 1.0:
			points.append(local_point)
	path_line.points = PackedVector2Array(points)


func _resolve_node_level(node: Node2D) -> int:
	if node and "current_height_level" in node:
		return clampi(node.current_height_level, 0, total_levels - 1)
	return current_height_level


func _connect_target_signals(target: Node2D) -> void:
	_disconnect_target_signals()
	_tracked_target_signal_node = target
	if target.has_signal("height_level_changed") and not target.height_level_changed.is_connected(_on_tracked_target_height_level_changed):
		target.height_level_changed.connect(_on_tracked_target_height_level_changed)


func _disconnect_target_signals() -> void:
	if _tracked_target_signal_node and is_instance_valid(_tracked_target_signal_node):
		if _tracked_target_signal_node.has_signal("height_level_changed") and _tracked_target_signal_node.height_level_changed.is_connected(_on_tracked_target_height_level_changed):
			_tracked_target_signal_node.height_level_changed.disconnect(_on_tracked_target_height_level_changed)
	_tracked_target_signal_node = null


func _on_tracked_target_height_level_changed(_new_level: int) -> void:
	_force_repath()


func _cache_navigation_regions() -> void:
	_navigation_layer_masks_by_level.clear()
	for level in range(total_levels):
		var fallback_mask := 1 << level
		var region_name := _get_navigation_region_name(level)
		var region := _find_navigation_region(region_name)
		if region and region.navigation_layers != 0:
			_navigation_layer_masks_by_level[level] = region.navigation_layers
		else:
			_navigation_layer_masks_by_level[level] = fallback_mask
			if debug_pathfinding:
				print("[BOT SIMPLE] NavigationRegion2D non trovata per L", level, " | nome=", region_name)


func _get_navigation_layers_for_level(level: int) -> int:
	var clamped_level := clampi(level, 0, total_levels - 1)
	if _navigation_layer_masks_by_level.is_empty():
		_cache_navigation_regions()
	return int(_navigation_layer_masks_by_level.get(clamped_level, 1 << clamped_level))


func _get_navigation_region_name(level: int) -> String:
	if level >= 0 and level < NAV_REGION_NODE_NAMES.size():
		return String(NAV_REGION_NODE_NAMES[level])
	return "L%d_NavigationRegion2D" % level


func _find_navigation_region(region_name: String) -> NavigationRegion2D:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return null
	return current_scene.find_child(region_name, true, false) as NavigationRegion2D


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0

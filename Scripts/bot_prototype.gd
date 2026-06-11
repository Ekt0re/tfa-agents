extends CharacterBody2D
class_name BotPrototype

signal height_level_changed(new_level: int)

const STEP_TYPE_TARGET := "target"
const STEP_TYPE_RAMP := "ramp"
const ROUTE_COST_INF := 1.0e18
const NAV_REGION_NODE_NAMES := [
	"L0_NavigationRegion2D",
	"L1_NavigationRegion2D",
	"L2_NavigationRegion2D"
]

@export var speed: float = 370.0
@export var current_height_level: int = 0
@export var total_levels: int = 3
@export var auto_chase_player: bool = true
@export var debug_pathfinding: bool = true
@export var target_node_path: NodePath
@export var repath_interval: float = 0.15
@export var movement_smoothing: float = 7.5
@export var stop_smoothing: float = 9.0
@export var look_smoothing: float = 10.0
@export var arrival_distance: float = 20.0
@export var look_at_target_distance: float = 220.0
@export var ramp_transition_cost: float = 64.0

var wants_ramp_teleport: bool = false

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null
@onready var path_line: Line2D = $Line2D if has_node("Line2D") else null
@onready var ray_cast: RayCast2D = $RayCast2D if has_node("RayCast2D") else null
@onready var visual_sprite: Node2D = $Sprite2D if has_node("Sprite2D") else null

var _tracked_target: Node2D = null
var _static_target_position: Vector2 = Vector2.ZERO
var _static_target_level: int = 0
var _has_static_target: bool = false
var _planned_steps: Array = []
var _current_request_position: Vector2 = Vector2.ZERO
var _current_request_level: int = 0
var _current_request_key: String = ""
var _last_repath_time: float = -1000.0
var _last_move_direction: Vector2 = Vector2.RIGHT
var _smoothed_look_direction: Vector2 = Vector2.RIGHT
var _agent_target_position: Vector2 = Vector2.INF
var _agent_target_level: int = -1
var _debug_route_points: Array[Vector2] = []
var _tracked_target_signal_node: Node = null
var _navigation_layer_masks_by_level: Dictionary = {}


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
			go_to_node(configured_target)
			return

	if auto_chase_player:
		var players := get_tree().get_nodes_in_group("players")
		if not players.is_empty() and players[0] is Node2D:
			go_to_node(players[0] as Node2D)


func destroy_from_projectile() -> void:
	queue_free()


func _physics_process(delta: float) -> void:
	_update_target_request_if_needed()
	_advance_completed_steps()

	var move_direction := _get_move_direction()
	if move_direction.length() > 0.001:
		_last_move_direction = move_direction
		var movement_weight: float = clampf(movement_smoothing * delta, 0.0, 1.0)
		velocity = velocity.lerp(move_direction * speed, movement_weight)
	else:
		var stop_weight: float = clampf(stop_smoothing * delta, 0.0, 1.0)
		velocity = velocity.lerp(Vector2.ZERO, stop_weight)
		if velocity.length() < 5.0:
			velocity = Vector2.ZERO

	move_and_slide()
	_advance_completed_steps()
	_update_visual_direction(delta)
	_update_debug_path_line()


func go_to_position(target_position: Vector2, target_level: int = current_height_level) -> void:
	_tracked_target = null
	_has_static_target = true
	_static_target_position = target_position
	_static_target_level = clampi(target_level, 0, total_levels - 1)
	_refresh_route_to(_static_target_position, _static_target_level, "static")


func go_to_node(target: Node2D) -> void:
	if not target:
		stop_navigation()
		return

	_tracked_target = target
	_has_static_target = false
	_connect_target_signals(target)
	_refresh_route_to(target.global_position, _resolve_node_level(target), _build_target_request_key(target))


func follow_node(target: Node2D) -> void:
	go_to_node(target)


func stop_navigation() -> void:
	_tracked_target = null
	_has_static_target = false
	_disconnect_target_signals()
	_planned_steps.clear()
	wants_ramp_teleport = false
	velocity = Vector2.ZERO
	_current_request_key = ""
	_agent_target_position = Vector2.INF
	_agent_target_level = -1
	_debug_route_points.clear()
	if path_line:
		path_line.clear_points()


func change_height_level(new_level: int, force_update: bool = false) -> void:
	new_level = clampi(new_level, 0, total_levels - 1)

	# Se il livello non cambia e non c'è il force_update, esci subito
	if new_level == current_height_level and not force_update:
		return

	# Gestione pulita dei gruppi: rimuove dal vecchio SOLO se è cambiato o se forzato
	var previous_level := current_height_level
	if previous_level != new_level or force_update:
		if is_in_group("entities_level_" + str(previous_level)):
			remove_from_group("entities_level_" + str(previous_level))

	current_height_level = new_level

	# Evita duplicati nel gruppo se già presente
	if not is_in_group("entities_level_" + str(current_height_level)):
		add_to_group("entities_level_" + str(current_height_level))

	# Calcolo offset collisioni (Piano 0 = 0, Piano 1 = 3, Piano 2 = 6)
	var layer_offset := current_height_level * 3

	# Ogni piano usa due bit: muri + personaggi.
	# Il bot appartiene solo al bit personaggio del piano.
	# L0 = layer 2, mask 1|2 | L1 = layer 5, mask 4|5 | L2 = layer 8, mask 7|8
	var wall_bit := 1 << (0 + layer_offset)
	var character_bit := 1 << (1 + layer_offset)
	collision_layer = character_bit
	collision_mask = wall_bit | character_bit

	# Gestione visiva dell'altezza
	z_index = current_height_level * 10

	# Configurazione Navigation Agent
	if navigation_agent:
		navigation_agent.navigation_layers = _get_navigation_layers_for_level(current_height_level)
		_agent_target_level = -1

	visible = true
	height_level_changed.emit(current_height_level)
	print("Bot cambia piano: ", new_level, " da piano: ", previous_level)
	_force_route_refresh_after_level_change()


func _update_target_request_if_needed() -> void:
	var request: Dictionary = _get_active_navigation_request()
	if request.is_empty():
		return

	var now: float = _get_time_seconds()
	if now - _last_repath_time < repath_interval:
		return

	var target_position: Vector2 = request.get("position", global_position)
	var target_level: int = int(request.get("level", current_height_level))
	var request_key: String = String(request.get("key", ""))
	var target_moved: bool = target_position.distance_to(_current_request_position) > maxf(arrival_distance, 16.0)
	var level_changed: bool = target_level != _current_request_level
	var request_changed: bool = request_key != _current_request_key
	var route_finished: bool = _planned_steps.is_empty()

	if target_moved or level_changed or request_changed or route_finished:
		_refresh_route_to(target_position, target_level, request_key)


func _refresh_route_to(target_position: Vector2, target_level: int, request_key: String = "") -> void:
	target_level = clampi(target_level, 0, total_levels - 1)
	_current_request_position = target_position
	_current_request_level = target_level
	_current_request_key = request_key
	_last_repath_time = _get_time_seconds()

	if debug_pathfinding:
		print("[BOT PATH] richiesta route | from L", current_height_level, " ", global_position,
			" -> to L", target_level, " ", target_position, " | key=", request_key)

	var route: Dictionary = _build_best_route(global_position, current_height_level, target_position, target_level, {})
	if float(route.get("cost", ROUTE_COST_INF)) < ROUTE_COST_INF:
		_planned_steps = route.get("steps", [])
		_debug_route_points = route.get("path_points", [])
		if debug_pathfinding:
			_print_route_summary(route)
	else:
		_planned_steps = []
		_debug_route_points.clear()
		if debug_pathfinding:
			print("[BOT PATH] nessun percorso valido trovato verso target L", target_level, " ", target_position)
	_agent_target_level = -1


func _build_best_route(from_position: Vector2, from_level: int, target_position: Vector2, target_level: int, visited_ramps: Dictionary) -> Dictionary:
	var best_cost := ROUTE_COST_INF
	var best_steps: Array = []
	var best_path_points: Array[Vector2] = []

	if from_level == target_level:
		var direct_result: Dictionary = _get_path_result(from_position, target_position, from_level, arrival_distance)
		if bool(direct_result["reachable"]):
			best_cost = float(direct_result["distance"])
			best_steps = [{
				"type": STEP_TYPE_TARGET,
				"position": target_position,
				"nav_target_position": direct_result["path_end"],
				"path_points": _duplicate_vector2_array(direct_result["points"]),
				"level": target_level,
				"acceptance_distance": arrival_distance
			}]
			best_path_points = _duplicate_vector2_array(direct_result["points"])
			if debug_pathfinding:
				print("[BOT PATH] diretto valido su L", from_level, " costo=", best_cost)
		elif debug_pathfinding and visited_ramps.is_empty():
			print("[BOT PATH] diretto non valido su L", from_level,
				" | path_end=", direct_result["path_end"], " target=", target_position)

	for ramp in _get_ramps_for_level(from_level):
		if not is_instance_valid(ramp):
			continue

		var ramp_id: int = ramp.get_instance_id()
		if visited_ramps.has(ramp_id):
			if debug_pathfinding:
				print("[BOT PATH] scarto rampa ", ramp.name, " | già visitata")
			continue

		var next_level: int = _get_ramp_destination_level(ramp, from_level)
		if next_level == -1:
			if debug_pathfinding:
				print("[BOT PATH] scarto rampa ", ramp.name, " | nessuna destinazione valida da L", from_level)
			continue

		var ramp_acceptance_distance: float = _get_ramp_acceptance_distance(ramp)
		var ramp_result: Dictionary = _get_path_result(from_position, ramp.global_position, from_level, ramp_acceptance_distance)
		if not bool(ramp_result["reachable"]):
			if debug_pathfinding:
				print("[BOT PATH] scarto rampa ", ramp.name, " | non raggiungibile da L", from_level,
					" | path_end=", ramp_result["path_end"], " ramp_pos=", ramp.global_position)
			continue

		var next_visited: Dictionary = visited_ramps.duplicate()
		next_visited[ramp_id] = true

		var transition_position: Vector2 = ramp_result["path_end"]
		var next_route: Dictionary = _build_best_route(transition_position, next_level, target_position, target_level, next_visited)
		var next_cost: float = float(next_route.get("cost", ROUTE_COST_INF))
		if next_cost >= ROUTE_COST_INF:
			if debug_pathfinding:
				print("[BOT PATH] scarto rampa ", ramp.name, " | nessuna prosecuzione valida da L", next_level)
			continue

		var total_cost: float = float(ramp_result["distance"]) + ramp_transition_cost + next_cost
		if debug_pathfinding:
			print("[BOT PATH] candidata rampa ", ramp.name, " | L", from_level, " -> L", next_level,
				" | costo tratto=", float(ramp_result["distance"]), " totale=", total_cost)
		if total_cost >= best_cost:
			if debug_pathfinding:
				print("[BOT PATH] scarto rampa ", ramp.name, " | costo peggiore del best=", best_cost)
			continue

		best_cost = total_cost
		best_steps = [{
			"type": STEP_TYPE_RAMP,
			"position": ramp.global_position,
			"nav_target_position": ramp_result["path_end"],
			"path_points": _duplicate_vector2_array(ramp_result["points"]),
			"from_level": from_level,
			"to_level": next_level,
			"acceptance_distance": ramp_acceptance_distance,
			"ramp": ramp
		}]
		for step in next_route.get("steps", []):
			best_steps.append(step)
		best_path_points = _duplicate_vector2_array(ramp_result["points"])
		_append_path_points(best_path_points, [ramp.global_position])
		_append_path_points(best_path_points, _duplicate_vector2_array(next_route.get("path_points", [])))
		if debug_pathfinding:
			print("[BOT PATH] nuova best rampa ", ramp.name, " | costo=", best_cost)

	return {
		"cost": best_cost,
		"steps": best_steps,
		"path_points": best_path_points
	}


func _get_move_direction() -> Vector2:
	if _planned_steps.is_empty():
		wants_ramp_teleport = false
		return Vector2.ZERO

	var step: Dictionary = _planned_steps[0]
	var step_type: String = step.get("type", "")
	var target_position: Vector2 = step.get("position", global_position)
	var nav_target_position: Vector2 = step.get("nav_target_position", target_position)

	if step_type == STEP_TYPE_RAMP:
		wants_ramp_teleport = true
		if current_height_level != int(step.get("from_level", current_height_level)):
			return Vector2.ZERO
	else:
		wants_ramp_teleport = false
		if current_height_level != int(step.get("level", current_height_level)):
			return Vector2.ZERO

	var next_path_point: Vector2 = _get_current_step_move_point(step, nav_target_position)
	var direction: Vector2 = next_path_point - global_position
	if direction.length() <= 1.0:
		return Vector2.ZERO

	return direction.normalized()


func _advance_completed_steps() -> void:
	while not _planned_steps.is_empty():
		var step: Dictionary = _planned_steps[0]
		var step_type: String = step.get("type", "")
		_trim_reached_step_points(step)
		_planned_steps[0] = step

		if step_type == STEP_TYPE_RAMP:
			var to_level: int = int(step.get("to_level", current_height_level))
			if current_height_level == to_level:
				_planned_steps.remove_at(0)
				_agent_target_level = -1
				continue
			break

		var step_level: int = int(step.get("level", current_height_level))
		var step_position: Vector2 = step.get("position", global_position)
		var acceptance_distance: float = float(step.get("acceptance_distance", arrival_distance))
		if current_height_level == step_level and global_position.distance_to(step_position) <= acceptance_distance:
			_planned_steps.remove_at(0)
			_agent_target_level = -1
			continue
		break

	if _planned_steps.is_empty():
		wants_ramp_teleport = false


func _get_current_step_move_point(step: Dictionary, fallback_position: Vector2) -> Vector2:
	var step_path_points: Array[Vector2] = step.get("path_points", [])
	for point in step_path_points:
		if global_position.distance_to(point) > maxf(arrival_distance * 0.35, 8.0):
			return point
	return fallback_position


func _trim_reached_step_points(step: Dictionary) -> void:
	var step_path_points: Array[Vector2] = step.get("path_points", [])
	var changed: bool = false
	while not step_path_points.is_empty() and global_position.distance_to(step_path_points[0]) <= maxf(arrival_distance * 0.35, 8.0):
		step_path_points.remove_at(0)
		changed = true
	if changed:
		step["path_points"] = step_path_points


func _update_visual_direction(delta: float) -> void:
	rotation = 0.0

	var desired_look_direction: Vector2 = _last_move_direction
	if velocity.length() > 12.0:
		desired_look_direction = velocity.normalized()

	if is_instance_valid(_tracked_target) and _resolve_node_level(_tracked_target) == current_height_level:
		var direction_to_target: Vector2 = _tracked_target.global_position - global_position
		if direction_to_target.length() <= look_at_target_distance and direction_to_target.length() > 0.001:
			desired_look_direction = direction_to_target.normalized()

	if desired_look_direction.length() <= 0.001:
		return

	var look_weight: float = clampf(look_smoothing * delta, 0.0, 1.0)
	var blended_direction: Vector2 = _smoothed_look_direction.lerp(desired_look_direction, look_weight)
	if blended_direction.length() > 0.001:
		_smoothed_look_direction = blended_direction.normalized()
	else:
		_smoothed_look_direction = desired_look_direction

	if visual_sprite:
		visual_sprite.rotation = lerp_angle(visual_sprite.rotation, _smoothed_look_direction.angle(), look_weight)

	if ray_cast:
		var ray_length: float = maxf(ray_cast.target_position.length(), 96.0)
		ray_cast.target_position = _smoothed_look_direction * ray_length
		ray_cast.force_raycast_update()


func _update_debug_path_line() -> void:
	if not path_line:
		return

	if _debug_route_points.is_empty():
		path_line.clear_points()
		return

	var points: Array[Vector2] = [Vector2.ZERO]
	for world_point in _debug_route_points:
		var local_point: Vector2 = world_point - global_position
		if points[points.size() - 1].distance_to(local_point) > 1.0:
			points.append(local_point)

	path_line.points = PackedVector2Array(points)


func _get_active_navigation_request() -> Dictionary:
	if is_instance_valid(_tracked_target):
		return {
			"position": _tracked_target.global_position,
			"level": _resolve_node_level(_tracked_target),
			"key": _build_target_request_key(_tracked_target)
		}

	if _has_static_target:
		return {
			"position": _static_target_position,
			"level": _static_target_level,
			"key": "static"
		}

	return {}


func _build_target_request_key(target: Node2D) -> String:
	return "target_%s" % str(target.get_instance_id())


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
	_force_route_refresh_after_level_change()


func _force_route_refresh_after_level_change() -> void:
	# 1. Forza il server di navigazione ad aggiornare la mappa dei Piani
	var map_rid := get_world_2d().get_navigation_map()
	NavigationServer2D.map_force_update(map_rid)

	# 2. Sincronizza l'agente con il server per applicare SUBITO il cambio di layer
	if navigation_agent:
		navigation_agent.get_next_path_position()

	# 3. Recupera la richiesta attiva attuale
	var request: Dictionary = _get_active_navigation_request()
	if request.is_empty():
		return

	# 4. Bypassa il cooldown del repath e avvia il ricalcolo immediato della rotta
	_last_repath_time = -1000.0
	_refresh_route_to(
		request.get("position", global_position),
		int(request.get("level", current_height_level)),
		String(request.get("key", ""))
	)


func _print_route_summary(route: Dictionary) -> void:
	var steps: Array = route.get("steps", [])
	var description: Array[String] = []
	for step in steps:
		description.append(_describe_step(step))
	print("[BOT PATH] route scelta | costo=", float(route.get("cost", ROUTE_COST_INF)),
		" | steps=", " -> ".join(description))


func _describe_step(step: Dictionary) -> String:
	var step_type: String = String(step.get("type", "?"))
	if step_type == STEP_TYPE_RAMP:
		var ramp = step.get("ramp", null)
		var ramp_name: String = ramp.name if is_instance_valid(ramp) else "Ramp?"
		return "%s(L%d->L%d @ %s)" % [
			ramp_name,
			int(step.get("from_level", -1)),
			int(step.get("to_level", -1)),
			str(step.get("position", Vector2.ZERO))
		]
	return "TARGET(L%d @ %s)" % [
		int(step.get("level", -1)),
		str(step.get("position", Vector2.ZERO))
	]


func _resolve_node_level(node: Node2D) -> int:
	if node and "current_height_level" in node:
		return clampi(node.current_height_level, 0, total_levels - 1)
	return current_height_level


func _get_ramps_for_level(level: int) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("ramps"):
		if node is Ramp and (node.start_level == level or node.arrival_level == level):
			result.append(node)
	return result


func _get_ramp_destination_level(ramp: Ramp, from_level: int) -> int:
	if ramp.start_level == from_level:
		return ramp.arrival_level
	if ramp.arrival_level == from_level:
		return ramp.start_level
	return -1


func _get_path_result(from_position: Vector2, to_position: Vector2, level: int, acceptance_distance: float) -> Dictionary:
	if from_position.distance_to(to_position) <= acceptance_distance:
		return {
			"reachable": true,
			"distance": from_position.distance_to(to_position),
			"path_end": to_position,
			"points": [to_position]
		}

	var navigation_map := get_world_2d().navigation_map
	var navigation_layers := _get_navigation_layers_for_level(level)
	var path: PackedVector2Array = NavigationServer2D.map_get_path(
		navigation_map,
		from_position,
		to_position,
		true,
		navigation_layers
	)

	if path.is_empty():
		return {
			"reachable": false,
			"distance": ROUTE_COST_INF,
			"path_end": from_position,
			"points": []
		}

	var last_point: Vector2 = path[path.size() - 1]
	if last_point.distance_to(to_position) > maxf(acceptance_distance, 24.0):
		return {
			"reachable": false,
			"distance": ROUTE_COST_INF,
			"path_end": last_point,
			"points": _packed_to_array(path)
		}

	var distance: float = 0.0
	var previous: Vector2 = from_position
	for point in path:
		distance += previous.distance_to(point)
		previous = point

	return {
		"reachable": true,
		"distance": distance,
		"path_end": last_point,
		"points": _packed_to_array(path)
		}


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
				print("[BOT PATH] NavigationRegion2D non trovata o senza layer per L", level,
					" | nome=", region_name, " | uso fallback mask=", fallback_mask)


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


func _get_ramp_acceptance_distance(ramp: Ramp) -> float:
	var collision_shape := ramp.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var rectangle_shape := collision_shape.shape as RectangleShape2D
		return maxf(rectangle_shape.size.x, rectangle_shape.size.y) * 0.5
	if collision_shape and collision_shape.shape is CircleShape2D:
		var circle_shape := collision_shape.shape as CircleShape2D
		return circle_shape.radius
	return 128.0


func _packed_to_array(points: PackedVector2Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in points:
		result.append(point)
	return result


func _duplicate_vector2_array(source: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in source:
		result.append(point)
	return result


func _append_path_points(target: Array[Vector2], points_to_add: Array[Vector2]) -> void:
	for point in points_to_add:
		if target.is_empty() or target[target.size() - 1].distance_to(point) > 1.0:
			target.append(point)


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0

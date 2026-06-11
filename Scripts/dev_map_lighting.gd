extends Node
class_name DevMapLighting

const WALL_LAYER_NAMES := [
	"L0_Walls",
	"L1_Walls",
	"L2_Walls"
]
const OCCLUDER_CONTAINER_NAME := "DynamicShadowOccluders"

var _occluder_containers_by_level: Dictionary = {}
var _tracked_player: Node = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_rebuild_wall_occluders()
	_configure_scene_lights()
	call_deferred("_connect_to_player")


func _rebuild_wall_occluders() -> void:
	_occluder_containers_by_level.clear()

	for level in range(WALL_LAYER_NAMES.size()):
		var wall_layer := find_child(WALL_LAYER_NAMES[level], true, false) as TileMapLayer
		if not wall_layer:
			continue

		var existing_container := wall_layer.get_node_or_null(OCCLUDER_CONTAINER_NAME)
		if existing_container:
			existing_container.queue_free()

		var container := Node2D.new()
		container.name = OCCLUDER_CONTAINER_NAME
		wall_layer.add_child(container)
		_occluder_containers_by_level[level] = container
		_build_occluders_for_wall_layer(wall_layer, container)


func _build_occluders_for_wall_layer(wall_layer: TileMapLayer, container: Node2D) -> void:
	var used_cells: Array[Vector2i] = wall_layer.get_used_cells()
	if used_cells.is_empty():
		return

	for cell in used_cells:
		_create_cell_occluders(wall_layer, container, cell)


func _create_cell_occluders(wall_layer: TileMapLayer, container: Node2D, cell: Vector2i) -> void:
	var tile_data := wall_layer.get_cell_tile_data(cell)
	if not tile_data:
		return

	var cell_origin := wall_layer.map_to_local(cell)
	for physics_layer in range(3):
		var polygon_count := tile_data.get_collision_polygons_count(physics_layer)
		for polygon_index in range(polygon_count):
			var points: PackedVector2Array = tile_data.get_collision_polygon_points(physics_layer, polygon_index)
			if points.size() < 3:
				continue

			var polygon := OccluderPolygon2D.new()
			polygon.polygon = points
			polygon.closed = true
			polygon.cull_mode = OccluderPolygon2D.CULL_DISABLED

			var occluder := LightOccluder2D.new()
			occluder.position = cell_origin
			occluder.occluder = polygon
			container.add_child(occluder)


func _configure_scene_lights() -> void:
	for node in _collect_point_lights(self):
		node.shadow_enabled = true


func _collect_point_lights(root: Node) -> Array[PointLight2D]:
	var lights: Array[PointLight2D] = []
	for child in root.get_children():
		if child is PointLight2D:
			lights.append(child)
		lights.append_array(_collect_point_lights(child))
	return lights


func _connect_to_player() -> void:
	if not is_inside_tree():
		return

	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_set_occluders_visible_for_level(0)
		get_tree().process_frame.connect(_connect_to_player, CONNECT_ONE_SHOT)
		return

	var player := players[0]
	if player != _tracked_player:
		if _tracked_player and is_instance_valid(_tracked_player) and _tracked_player.has_signal("height_level_changed") and _tracked_player.height_level_changed.is_connected(_on_player_height_level_changed):
			_tracked_player.height_level_changed.disconnect(_on_player_height_level_changed)

		_tracked_player = player
		if _tracked_player.has_signal("height_level_changed") and not _tracked_player.height_level_changed.is_connected(_on_player_height_level_changed):
			_tracked_player.height_level_changed.connect(_on_player_height_level_changed)

	_apply_player_level_occluders()


func _apply_player_level_occluders() -> void:
	var level := 0
	if _tracked_player and is_instance_valid(_tracked_player) and "current_height_level" in _tracked_player:
		level = int(_tracked_player.current_height_level)
	_set_occluders_visible_for_level(level)


func _on_player_height_level_changed(new_level: int) -> void:
	_set_occluders_visible_for_level(new_level)


func _set_occluders_visible_for_level(level: int) -> void:
	for stored_level in _occluder_containers_by_level.keys():
		var container := _occluder_containers_by_level[stored_level] as CanvasItem
		if container:
			container.visible = int(stored_level) == level

extends Control

@export var scale_factor: float = 0.05
@export var border_color: Color = Color("00b0ff") # Azzurro ciano dell'immagine
@export var bg_color: Color = Color("050c14ee") # Sfondo scuro semitrasparente
@export var player_color: Color = Color("a6ff00") # Verde brillante
@export var enemy_color: Color = Color("ff6b4a") # Arancione dell'immagine
@export var friend_color: Color = Color("2c4800ff") # Verde scuro
@export var item_color: Color = Color("b18a1bff") # Giallo oro

# Quality level: 0=Low, 1=Medium, 2=High, 3=Ultra
var _quality_level: int = 2

var player: Node2D = null

func _ready() -> void:
	# Leggi qualità iniziale da GlobalSettings
	var gs = get_node_or_null("/root/GlobalSettings")
	if gs:
		_quality_level = int(gs.get_setting("graphics_preset", 2))
		if gs.has_signal("settings_changed"):
			gs.settings_changed.connect(_on_settings_changed)

	# Trova il player
	var players = get_tree().get_nodes_in_group("players")
	if not players.is_empty():
		player = players[0] as Node2D
	else:
		get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node.is_in_group("players") and node is Node2D:
		player = node

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	var map_size = get_size()
	var center = map_size / 2.0

	# Low quality: no sfondo/bordo, solo punti
	if _quality_level >= 1:
		# Disegna lo sfondo
		draw_rect(Rect2(Vector2.ZERO, map_size), bg_color)
		# Disegna il bordo
		draw_rect(Rect2(Vector2.ZERO, map_size), border_color, false, 1.5)

	if not player or not is_instance_valid(player):
		return

	# Disegna il player al centro (rombo)
	var player_size = 5.0
	var points = PackedVector2Array([
		center + Vector2(0, -player_size),
		center + Vector2(player_size, 0),
		center + Vector2(0, player_size),
		center + Vector2(-player_size, 0)
	])
	draw_colored_polygon(points, player_color)

	# Trova tutti i nemici
	var enemies = get_tree().get_nodes_in_group("team_2")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue

		# Height filtering (solo High/Ultra)
		if _quality_level >= 2 and "current_height_level" in enemy and "current_height_level" in player:
			if enemy.current_height_level != player.current_height_level:
				continue

		var offset = (enemy.global_position - player.global_position) * scale_factor
		var enemy_pos = center + offset

		if enemy_pos.x > 3.0 and enemy_pos.x < map_size.x - 3.0 and enemy_pos.y > 3.0 and enemy_pos.y < map_size.y - 3.0:
			draw_circle(enemy_pos, 3.5, enemy_color)

	# Trova tutti gli amici
	var friends = get_tree().get_nodes_in_group("team_1")
	for friend in friends:
		if not is_instance_valid(friend) or not friend is Node2D:
			continue

		if _quality_level >= 2 and "current_height_level" in friend and "current_height_level" in player:
			if friend.current_height_level != player.current_height_level:
				continue

		var offset = (friend.global_position - player.global_position) * scale_factor
		var friend_pos = center + offset

		if friend_pos.x > 3.0 and friend_pos.x < map_size.x - 3.0 and friend_pos.y > 3.0 and friend_pos.y < map_size.y - 3.0:
			draw_circle(friend_pos, 3.5, friend_color)

	# Trova tutti gli Item
	var items = get_tree().get_nodes_in_group("item")
	for item in items:
		if not is_instance_valid(item) or not item is Node2D:
			continue

		if _quality_level >= 2 and "current_height_level" in item and "current_height_level" in player:
			if item.current_height_level != player.current_height_level:
				continue

		var offset = (item.global_position - player.global_position) * scale_factor
		var item_pos = center + offset

		if item_pos.x > 3.0 and item_pos.x < map_size.x - 3.0 and item_pos.y > 3.0 and item_pos.y < map_size.y - 3.0:
			draw_circle(item_pos, 3.5, item_color)


func _on_settings_changed(new_settings: Dictionary) -> void:
	_quality_level = int(new_settings.get("graphics_preset", 2))

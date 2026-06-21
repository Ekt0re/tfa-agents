extends "res://Scripts/dev_map_lighting.gd"

const PLAYER_SCENE = preload("res://player.tscn")

@onready var _mp_manager: Node = get_node("/root/MultiplayerManager")

var _kills: Dictionary = {}
var _target_kills: int = 10
var _match_over: bool = false

# Handshake: lista dei peer che hanno confermato di aver caricato la scena
var _ready_peers: Array[int] = []

var _scoreboard_label: Label
var _players_node: Node2D
var _spawner: MultiplayerSpawner

signal match_ended(winner_team_id: int)


func _ready() -> void:
	super._ready()
	
	# Rimuove entità indesiderate ereditate da dev_map.tscn
	for child in get_children():
		if child is CharacterBody2D or child.name.begins_with("Bot") or child.name == "Tutorial":
			child.queue_free()
	
	# Nodo contenitore player — deve essere aggiunto PRIMA del spawner
	_players_node = Node2D.new()
	_players_node.name = "Players"
	add_child(_players_node)
	
	# MultiplayerSpawner — deve conoscere il percorso di spawn e la scena
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "PlayerSpawner"
	_spawner.spawn_path = NodePath("../Players")
	_spawner.add_spawnable_scene("res://player.tscn")
	add_child(_spawner)
	
	_setup_scoreboard()
	
	# Handshake: ogni peer notifica il server di essere pronto
	# Il server si conta da solo, i client inviano l'RPC
	if multiplayer.is_server():
		# Il server si aggiunge alla lista e poi aspetta i client
		call_deferred("_on_peer_scene_ready", 1)
	else:
		# Client notifica il server tramite RPC
		call_deferred("_send_ready_to_server")


func _send_ready_to_server() -> void:
	_notify_server_scene_ready.rpc_id(1)


# ── Handshake RPC ─────────────────────────────────────────────────────────────

## Client→Server: il client ha finito di caricare la scena
@rpc("any_peer", "reliable")
func _notify_server_scene_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_on_peer_scene_ready(sender_id)


func _on_peer_scene_ready(peer_id: int) -> void:
	if peer_id in _ready_peers:
		return
	_ready_peers.append(peer_id)
	print("PvPMap: Peer %d pronto. (%d/%d)" % [peer_id, _ready_peers.size(), _mp_manager.players_info.size()])
	
	# Controlla se tutti i peer attesi hanno confermato
	var all_confirmed := true
	for expected_id in _mp_manager.players_info.keys():
		if not (expected_id in _ready_peers):
			all_confirmed = false
			break
	
	if all_confirmed:
		print("PvPMap: Tutti i peer pronti → spawn!")
		_spawn_all_players()


# ── Spawn ─────────────────────────────────────────────────────────────────────

func _setup_scoreboard() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	
	_scoreboard_label = Label.new()
	_scoreboard_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_scoreboard_label.offset_left = -300
	_scoreboard_label.offset_bottom = 200
	_scoreboard_label.add_theme_font_size_override("font_size", 18)
	_scoreboard_label.add_theme_color_override("font_color", Color.WHITE)
	_scoreboard_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_scoreboard_label.add_theme_constant_override("outline_size", 4)
	canvas.add_child(_scoreboard_label)
	_update_scoreboard_text()


func _spawn_all_players() -> void:
	var info: Dictionary = _mp_manager.get("players_info") as Dictionary
	var idx := 0
	for peer_id in info:
		_spawn_player(peer_id, info[peer_id], idx)
		idx += 1


func _get_spawn_points() -> Array[Vector2]:
	var spawn_node = get_node_or_null("SpawnPoints")
	if spawn_node and spawn_node.get_child_count() > 0:
		var pts: Array[Vector2] = []
		for child in spawn_node.get_children():
			if child is Node2D:
				pts.append(child.global_position)
		if pts.size() > 0:
			return pts
	return [Vector2(0, 0)]

func _get_valid_spawn_level(pos: Vector2, default_level: int = 0) -> int:
	var offsets = [0, 1, -1, 2, -2]
	for offset in offsets:
		var check_level = default_level + offset
		if check_level >= 0 and check_level <= 2:
			var layer_name = "L" + str(check_level) + "/L" + str(check_level) + "_Ground"
			var ground_layer = get_node_or_null(layer_name) as TileMapLayer
			if ground_layer:
				var local_pos = ground_layer.to_local(pos)
				var cell = ground_layer.local_to_map(local_pos)
				if ground_layer.get_cell_source_id(cell) != -1:
					return check_level
	return default_level

func _spawn_player(peer_id: int, player_info: Dictionary, spawn_index: int) -> void:
	var player_inst = PLAYER_SCENE.instantiate()
	player_inst.name = str(peer_id)
	
	# IMPORTANTE: set_multiplayer_authority PRIMA di add_child
	player_inst.set_multiplayer_authority(peer_id)
	
	var spawn_pts = _get_spawn_points()
	var spawn_pos: Vector2 = spawn_pts[spawn_index % spawn_pts.size()]
	player_inst.global_position = spawn_pos
	
	# Trova il piano valido e posiziona il player
	var valid_level = _get_valid_spawn_level(spawn_pos, 0)
	player_inst.current_height_level = valid_level
	
	# Configura dati prima di add_child (il sync spawn li porta ai client)
	player_inst.team_id = int(player_info.get("team_id", 0))
	player_inst.skin_index = int(player_info.get("skin_index", 0))
	
	player_inst.add_to_group("pvp_team_" + str(player_inst.team_id))
	player_inst.add_to_group("pvp_all_players")
	
	# add_child attiva la replica tramite MultiplayerSpawner
	_players_node.add_child(player_inst)


# ── Kill / Win condition ──────────────────────────────────────────────────────

func _on_player_killed(killer_peer_id: int, victim_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _match_over:
		return
	
	var killer_team: int = 0
	var info = _mp_manager.get("players_info")
	if info.has(killer_peer_id):
		killer_team = int(info[killer_peer_id].get("team_id", 0))
	
	if not _kills.has(killer_team):
		_kills[killer_team] = 0
	_kills[killer_team] += 1
	
	_sync_kills.rpc(_kills)
	_check_win_condition()
	_schedule_respawn(victim_peer_id)


func _schedule_respawn(peer_id: int) -> void:
	await get_tree().create_timer(3.0).timeout
	if _match_over:
		return
	var victim_node = _players_node.get_node_or_null(str(peer_id))
	if victim_node and victim_node.has_method("respawn"):
		var spawn_pts = _get_spawn_points()
		var rand_spawn = spawn_pts[randi() % spawn_pts.size()]
		var valid_level = _get_valid_spawn_level(rand_spawn, 0)
		victim_node.respawn.rpc(rand_spawn, valid_level)


func _check_win_condition() -> void:
	for team_id in _kills:
		if _kills[team_id] >= _target_kills:
			_match_over = true
			_end_match.rpc(team_id)
			return


@rpc("authority", "call_local", "reliable")
func _sync_kills(new_kills: Dictionary) -> void:
	_kills = new_kills
	_update_scoreboard_text()


func _update_scoreboard_text() -> void:
	var txt := "SCOREBOARD (Target: %d)\n\n" % _target_kills
	var mode = _mp_manager.get("team_mode")
	
	if mode == "teams":
		for team_id in _kills:
			txt += "Team %d: %d kill\n" % [team_id, _kills[team_id]]
	else:
		var info = _mp_manager.get("players_info")
		for team_id in _kills:
			var p_name := "Player"
			for peer in info:
				if info[peer].get("team_id") == team_id:
					p_name = str(info[peer].get("name", "Player"))
					break
			txt += "%s: %d kill\n" % [p_name, _kills[team_id]]
	
	_scoreboard_label.text = txt


# ── Fine partita ──────────────────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _end_match(winner_team_id: int) -> void:
	match_ended.emit(winner_team_id)
	
	for p in get_tree().get_nodes_in_group("pvp_all_players"):
		if p.has_method("set_physics_process"):
			p.set_physics_process(false)
			p.set_process(false)
	
	var winner_name := ""
	var mode = _mp_manager.get("team_mode")
	if mode == "ffa":
		var info = _mp_manager.get("players_info")
		for peer in info:
			if info[peer].get("team_id") == winner_team_id:
				winner_name = str(info[peer].get("name", "Giocatore"))
				break
	else:
		winner_name = "Team " + str(winner_team_id)
	
	_scoreboard_label.text = "PARTITA TERMINATA!\nVince: %s" % winner_name
	_show_victory_screen.rpc(winner_team_id, winner_name)
	
	if multiplayer.is_server():
		await get_tree().create_timer(8.0).timeout
		_return_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _show_victory_screen(winner_team_id: int, winner_name: String) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 200
	add_child(canvas)
	
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.7)
	canvas.add_child(bg)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)
	
	var vbox := VBoxContainer.new()
	center.add_child(vbox)
	
	var trophy := Label.new()
	trophy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(trophy)
	
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var winner_lbl := Label.new()
	winner_lbl.text = winner_name
	winner_lbl.add_theme_font_size_override("font_size", 42)
	winner_lbl.add_theme_color_override("font_color", Color.WHITE)
	winner_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	winner_lbl.add_theme_constant_override("outline_size", 4)
	winner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(winner_lbl)
	
	var kills_val: int = _kills.get(winner_team_id, 0)
	var score_lbl := Label.new()
	score_lbl.text = "%d kill" % kills_val
	score_lbl.add_theme_font_size_override("font_size", 28)
	score_lbl.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7, 1.0))
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(score_lbl)
	
	var sub := Label.new()
	sub.text = "Ritorno in lobby tra 8 secondi..."
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)
	
	# Determina se il peer locale ha vinto
	var local_id: int = multiplayer.get_unique_id()
	var local_info = _mp_manager.get("players_info")
	var is_winner := false
	if local_info.has(local_id):
		is_winner = (int(local_info[local_id].get("team_id", -1)) == winner_team_id)
	
	if is_winner:
		trophy.text = "🏆"
		trophy.add_theme_font_size_override("font_size", 96)
		title.text = "VITTORIA!"
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1, 1.0))
	else:
		trophy.text = "💀"
		trophy.add_theme_font_size_override("font_size", 80)
		title.text = "SCONFITTA"
		title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 1.0))


@rpc("authority", "call_local", "reliable")
func _return_to_lobby() -> void:
	get_tree().change_scene_to_file("res://Menu/lobby.tscn")

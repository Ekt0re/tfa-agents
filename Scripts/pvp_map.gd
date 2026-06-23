extends "res://Scripts/dev_map_lighting.gd"

const PLAYER_SCENE = preload("res://player.tscn")

@onready var _mp_manager: Node = get_node("/root/MultiplayerManager")

var _kills: Dictionary = {}
var _target_kills: int = 10
var _match_over: bool = false

# Handshake: lista dei peer che hanno confermato di aver caricato la scena
var _ready_peers: Array[int] = []

var _players_node: Node2D
var _spawner: MultiplayerSpawner

signal match_ended(winner_team_id: int)


const SpawnPointScript = preload("res://Scripts/spawn_point.gd")


## Helper sicuro per ottenere le info di un peer indipendentemente dal tipo di chiave (int/String).
func _get_peer_info(peer_id: int) -> Dictionary:
	var info: Dictionary = _mp_manager.get("players_info") as Dictionary
	if not info:
		return {}
	if info.has(peer_id):
		return info[peer_id]
	if info.has(str(peer_id)):
		return info[str(peer_id)]
	return {}


func _get_all_peer_ids() -> Array:
	var info: Dictionary = _mp_manager.get("players_info") as Dictionary
	if not info:
		return []
	var result: Array = []
	for key in info.keys():
		result.append(int(key) if str(key).is_valid_int() else key)
	return result

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
	
	# Ora la scoreboard è gestita in HUD_Game, quindi chiamiamo solo l'aggiornamento.
	call_deferred("_update_scoreboard_text")
	
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
	var expected_ids := _get_all_peer_ids()
	print("PvPMap: Peer %d pronto. (%d/%d)" % [peer_id, _ready_peers.size(), expected_ids.size()])
	
	# Controlla se tutti i peer attesi hanno confermato
	var all_confirmed := true
	for expected_id in expected_ids:
		if not (expected_id in _ready_peers):
			all_confirmed = false
			break
	
	if all_confirmed:
		print("PvPMap: Tutti i peer pronti → spawn!")
		_spawn_all_players()


# ── Spawn ─────────────────────────────────────────────────────────────────────

func _setup_scoreboard() -> void:
	pass # Deprecato: gestito da HUD_Game


## Invia la posizione di spawn al client via RPC dopo che il nodo è nell'albero.
func _send_spawn_data(peer_id: int, spawn_pos: Vector2, spawn_level: int) -> void:
	var player_node = _players_node.get_node_or_null(str(peer_id))
	if player_node and player_node.has_method("_apply_spawn_data"):
		player_node._apply_spawn_data.rpc(spawn_pos, spawn_level)

func _spawn_all_players() -> void:
	var idx := 0
	for peer_id in _get_all_peer_ids():
		var p_info := _get_peer_info(int(peer_id))
		_spawn_player(int(peer_id), p_info, idx)
		idx += 1
		
		var t_id: int = int(p_info.get("team_id", 0))
		if not _kills.has(t_id):
			_kills[t_id] = 0


func _get_spawn_points(for_team: int = 0) -> Array[Node2D]:
	var spawn_node = get_node_or_null("SpawnPoints")
	if spawn_node and spawn_node.get_child_count() > 0:
		var pts: Array[Node2D] = []
		for child in spawn_node.get_children():
			if child is Node2D:
				if child is SpawnPointScript:
					if child.team_id == 0 or child.team_id == for_team:
						pts.append(child)
				else:
					pts.append(child)
		if pts.size() > 0:
			return pts
	return []

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
	
	var p_team: int = int(player_info.get("team_id", 0))
	var spawn_pts = _get_spawn_points(p_team)
	var spawn_node: Node2D = null
	var spawn_pos: Vector2 = Vector2.ZERO
	var valid_level: int = 0
	
	if spawn_pts.size() > 0:
		spawn_node = spawn_pts[spawn_index % spawn_pts.size()]
		spawn_pos = spawn_node.global_position
		if spawn_node is SpawnPointScript:
			valid_level = spawn_node.height_level
		else:
			valid_level = _get_valid_spawn_level(spawn_pos, 0)
	else:
		# Fallback: usa qualsiasi spawn point disponibile
		var all_pts = _get_spawn_points(0)
		if all_pts.size() > 0:
			spawn_node = all_pts[spawn_index % all_pts.size()]
			spawn_pos = spawn_node.global_position
			valid_level = _get_valid_spawn_level(spawn_pos, 0)
	
	# Imposta SIA position che global_position per compatibilità
	player_inst.position = spawn_pos
	player_inst.global_position = spawn_pos
	player_inst.current_height_level = valid_level
	
	# Configura dati prima di add_child (il sync spawn li porta ai client)
	player_inst.team_id = p_team
	player_inst.skin_index = int(player_info.get("skin_index", 0))
	
	player_inst.add_to_group("pvp_team_" + str(player_inst.team_id))
	player_inst.add_to_group("pvp_all_players")
	
	# add_child attiva la replica tramite MultiplayerSpawner
	_players_node.add_child(player_inst)
	
	# Safety net: invia posizione di spawn via RPC dopo che il nodo è nell'albero.
	# Il MultiplayerSpawner potrebbe non replicare la proprietà position.
	call_deferred("_send_spawn_data", peer_id, spawn_pos, valid_level)


# ── Kill / Win condition ──────────────────────────────────────────────────────

func _on_player_killed(killer_peer_id: int, victim_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _match_over:
		return
	
	var killer_info := _get_peer_info(killer_peer_id)
	var killer_team: int = int(killer_info.get("team_id", 0))
	
	if not _kills.has(killer_team):
		_kills[killer_team] = 0
	_kills[killer_team] += 1
	
	_sync_kills.rpc(_kills)
	_check_win_condition()
	
	# Verifica se il respawn è abilitato dalle impostazioni di gioco
	var mp_manager = get_node_or_null("/root/MultiplayerManager")
	var respawn_enabled = mp_manager != null and mp_manager.get("respawn_enabled") == true
	
	if respawn_enabled:
		_schedule_respawn(victim_peer_id)
	else:
		# Senza respawn: verifica se una squadra è stata completamente eliminata
		_check_team_elimination()


func _schedule_respawn(peer_id: int) -> void:
	# Leggi il tempo di respawn dalle impostazioni
	var mp_manager = get_node_or_null("/root/MultiplayerManager")
	var respawn_time = 3.0
	if mp_manager and mp_manager.get("respawn_time") != null:
		respawn_time = float(mp_manager.get("respawn_time"))
	
	await get_tree().create_timer(respawn_time).timeout
	if _match_over:
		return
	var victim_node = _players_node.get_node_or_null(str(peer_id))
	if victim_node and victim_node.has_method("respawn"):
		var p_info := _get_peer_info(peer_id)
		var p_team: int = int(p_info.get("team_id", 0))
			
		var spawn_pts = _get_spawn_points(p_team)
		if spawn_pts.size() == 0:
			spawn_pts = _get_spawn_points(0)
		var rand_spawn_node: Node2D = spawn_pts[randi() % spawn_pts.size()] if spawn_pts.size() > 0 else null
		
		var rand_spawn: Vector2 = rand_spawn_node.global_position if rand_spawn_node else Vector2.ZERO
		var valid_level: int = 0
		if rand_spawn_node is SpawnPointScript:
			valid_level = rand_spawn_node.height_level
		else:
			valid_level = _get_valid_spawn_level(rand_spawn, 0)
			
		victim_node.respawn.rpc(rand_spawn, valid_level)


func _check_win_condition() -> void:
	for team_id in _kills:
		if _kills[team_id] >= _target_kills:
			_match_over = true
			_end_match.rpc(team_id)
			return


## Verifica se una squadra è stata completamente eliminata (senza respawn).
func _check_team_elimination() -> void:
	if _match_over:
		return
	
	var mp_manager = get_node_or_null("/root/MultiplayerManager")
	if not mp_manager:
		return
	
	var mode: String = str(mp_manager.get("team_mode"))
	var all_peers := _get_all_peer_ids()
	
	if mode == "ffa":
		# In FFA, la partita finisce quando rimane un solo giocatore vivo
		var alive_count := 0
		var last_alive_peer := 0
		for peer_id in all_peers:
			var player_node = _players_node.get_node_or_null(str(peer_id))
			if player_node and is_instance_valid(player_node) and player_node.get("vita") > 0.0:
				alive_count += 1
				last_alive_peer = peer_id
		
		if alive_count <= 1:
			_match_over = true
			var winner_team := 0
			if last_alive_peer > 0:
				var winner_info := _get_peer_info(last_alive_peer)
				winner_team = int(winner_info.get("team_id", 0))
			_end_match.rpc(winner_team)
	else:
		# In team mode, la partita finisce quando tutti i membri di una squadra sono morti
		var team_players: Dictionary = {}
		var team_alive: Dictionary = {}
		
		for peer_id in all_peers:
			var p_info := _get_peer_info(int(peer_id))
			var t_id: int = int(p_info.get("team_id", 0))
			if not team_players.has(t_id):
				team_players[t_id] = []
				team_alive[t_id] = 0
			team_players[t_id].append(peer_id)
			
			var player_node = _players_node.get_node_or_null(str(peer_id))
			if player_node and is_instance_valid(player_node) and player_node.get("vita") > 0.0:
				team_alive[t_id] += 1
		
		# Trova una squadra con zero giocatori vivi
		for t_id in team_players:
			if team_alive.get(t_id, 0) == 0 and team_players[t_id].size() > 0:
				# Questa squadra è stata eliminata, vincono gli altri
				# Trova la squadra vincente (prima squadra con giocatori vivi)
				for other_t_id in team_alive:
					if other_t_id != t_id and team_alive.get(other_t_id, 0) > 0:
						_match_over = true
						_end_match.rpc(other_t_id)
						return


@rpc("authority", "call_local", "reliable")
func _sync_kills(new_kills: Dictionary) -> void:
	# Normalizza chiavi (Godot 4 RPC converte int → String)
	_kills = {}
	for key in new_kills.keys():
		var int_key: int = int(key) if str(key).is_valid_int() else key
		_kills[int_key] = new_kills[key]
	_update_scoreboard_text()


func _update_scoreboard_text() -> void:
	var txt := "SCOREBOARD (Target: %d)\n\n" % _target_kills
	var mode: String = str(_mp_manager.get("team_mode"))
	
	# Determina la modalità: preferisci il valore sincronizzato, con fallback auto-detect
	var is_ffa: bool = (mode == "ffa")
	if not is_ffa:
		# Auto-detect FFA: se ogni giocatore ha un team_id unico
		var all_peer_ids := _get_all_peer_ids()
		var team_ids_seen: Array = []
		var all_unique := true
		for peer_id in all_peer_ids:
			var p_info := _get_peer_info(int(peer_id))
			var t_id: int = int(p_info.get("team_id", 0))
			if t_id in team_ids_seen:
				all_unique = false
				break
			team_ids_seen.append(t_id)
		if all_unique and all_peer_ids.size() > 1:
			is_ffa = true
	
	if is_ffa:
		# FFA: mostra una riga per ogni giocatore (non per team_id in _kills)
		for peer_id in _get_all_peer_ids():
			var p_info := _get_peer_info(int(peer_id))
			var p_name: String = str(p_info.get("name", "Player"))
			var p_team: int = int(p_info.get("team_id", 0))
			var kill_count: int = _kills.get(p_team, 0)
			txt += "%s: %d kill\n" % [p_name, kill_count]
	else:
		# Teams mode
		for team_id_val in _kills:
			txt += "Team %d: %d kill\n" % [team_id_val, _kills[team_id_val]]
			
	var hud = get_node_or_null("HudGame")
	if not hud:
		var canvas_layers = get_children()
		for c in canvas_layers:
			if c is CanvasLayer and c.has_method("update_scoreboard"):
				hud = c
				break
				
	if hud and hud.has_method("update_scoreboard"):
		hud.update_scoreboard(txt)


# ── Fine partita ──────────────────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _end_match(winner_team_id: int) -> void:
	match_ended.emit(winner_team_id)
	
	for p in get_tree().get_nodes_in_group("pvp_all_players"):
		if p.has_method("set_physics_process"):
			p.set_physics_process(false)
			p.set_process(false)
	
	var winner_name := ""
	var mode: String = str(_mp_manager.get("team_mode"))
	if mode == "ffa":
		for peer_id in _get_all_peer_ids():
			var p_info := _get_peer_info(int(peer_id))
			if int(p_info.get("team_id", -1)) == winner_team_id:
				winner_name = str(p_info.get("name", "Giocatore"))
				break
	else:
		winner_name = "Team " + str(winner_team_id)
	
	var hud = get_node_or_null("HudGame")
	if not hud:
		for c in get_children():
			if c is CanvasLayer and c.has_method("update_scoreboard"):
				hud = c
				break
				
	if hud and hud.has_method("update_scoreboard"):
		hud.update_scoreboard("PARTITA TERMINATA!\nVince: %s" % winner_name)
		
	_show_victory_screen(winner_team_id, winner_name)
	
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
	
	# Countdown visivo: aggiorna il testo ogni secondo
	_start_lobby_countdown(sub)
	
	# Determina se il peer locale ha vinto usando il helper sicuro
	var local_id: int = multiplayer.get_unique_id()
	var local_info := _get_peer_info(local_id)
	var local_team: int = int(local_info.get("team_id", -1))
	var is_winner: bool = (local_team == winner_team_id)
	
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


func _start_lobby_countdown(label: Label) -> void:
	for i in range(7, 0, -1):
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(label):
			label.text = "Ritorno in lobby tra %d secondi..." % i

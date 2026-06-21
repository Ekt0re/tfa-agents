## game_over_menu.gd
## Script di controllo per la schermata di Game Over.
## Supporta il riavvio (inizio/checkpoint) in single player e lo spectating in multiplayer.

extends CanvasLayer

# Percorsi scene
@export_file("*.tscn") var main_menu_scene_path := "res://Menu/main_menu.tscn"
@export_file("*.tscn") var lobby_scene_path := "res://Menu/main_menu.tscn" # Placeholder per la lobby multiplayer

# Riferimenti nodi UI (saranno agganciati nella scena)
@onready var singleplayer_container: Control = %SingleplayerContainer
@onready var multiplayer_container: Control = %MultiplayerContainer

@onready var restart_begin_btn: Button = %RestartBeginButton
@onready var restart_checkpoint_btn: Button = %RestartCheckpointButton
@onready var main_menu_btn: Button = %MainMenuButton

@onready var spectate_prev_btn: Button = %SpectatePrevButton
@onready var spectate_next_btn: Button = %SpectateNextButton
@onready var spectator_label: Label = %SpectatorLabel
@onready var lobby_btn: Button = %LobbyButton

# Stato interno
var local_player: PlayerPrototype = null
var spectatable_players: Array[Node2D] = []
var spectated_index: int = 0
var is_multiplayer_mode := false
var _poll_timer: float = 0.0


func _ready() -> void:
	# Il menu deve poter elaborare input anche quando il gioco è in pausa
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "GameOverMenu"
	
	is_multiplayer_mode = multiplayer.has_multiplayer_peer()
	
	_setup_connections()
	_configure_ui()


func setup(player: PlayerPrototype) -> void:
	local_player = player
	_configure_ui()


func _setup_connections() -> void:
	# Singleplayer Buttons
	restart_begin_btn.pressed.connect(_on_restart_begin_pressed)
	restart_checkpoint_btn.pressed.connect(_on_restart_checkpoint_pressed)
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	
	# Multiplayer Buttons
	spectate_prev_btn.pressed.connect(_on_spectate_prev_pressed)
	spectate_next_btn.pressed.connect(_on_spectate_next_pressed)
	lobby_btn.pressed.connect(_on_lobby_pressed)


func _configure_ui() -> void:
	if not is_inside_tree():
		return
		
	if is_multiplayer_mode:
		# Modalità Multiplayer
		singleplayer_container.visible = false
		multiplayer_container.visible = true
		
		# Inizializza spettatore
		_update_spectatable_players()
		_spectate_current()
	else:
		# Modalità Singleplayer
		singleplayer_container.visible = true
		multiplayer_container.visible = false
		
		# Metti in pausa il gioco per non far muovere i nemici o sparare
		get_tree().paused = true
		
		# Abilita il pulsante checkpoint solo se è stato salvato un checkpoint valido
		var flow_player = get_node_or_null("/root/MissionFlowPlayer")
		if flow_player and flow_player.get("last_checkpoint_id") != "":
			restart_checkpoint_btn.disabled = false
		else:
			restart_checkpoint_btn.disabled = true


func _process(delta: float) -> void:
	if not is_multiplayer_mode:
		return
		
	# Polling per aggiornare l'elenco dei giocatori vivi e gestire la morte del target osservato
	_poll_timer += delta
	if _poll_timer >= 0.5:
		_poll_timer = 0.0
		_update_spectatable_players()
		_check_spectated_validity()


# ---------------------------------------------------------------------------
# Gestione Spettatore (Multiplayer)
# ---------------------------------------------------------------------------

func _update_spectatable_players() -> void:
	var all_players = get_tree().get_nodes_in_group("players")
	var same_team_players: Array[Node2D] = []
	var other_team_players: Array[Node2D] = []
	
	# Trova il gruppo team della persona locale
	var my_team := ""
	if is_instance_valid(local_player):
		for g in local_player.get_groups():
			if g.begins_with("team_"):
				my_team = g
				break
				
	for p in all_players:
		if not p is Node2D or not is_instance_valid(p):
			continue
		if p == local_player:
			continue # Non osservare se stessi (che siamo morti)
		if p.get("vita") != null and p.get("vita") <= 0.0:
			continue # Ignora i morti
			
		var belongs_to_my_team := false
		if not my_team.is_empty():
			belongs_to_my_team = p.is_in_group(my_team)
			
		if belongs_to_my_team:
			same_team_players.append(p)
		else:
			other_team_players.append(p)
			
	var old_target = spectatable_players[spectated_index] if spectated_index < spectatable_players.size() else null
	
	# Combina le due liste dando priorità allo stesso team
	spectatable_players.clear()
	spectatable_players.append_array(same_team_players)
	spectatable_players.append_array(other_team_players)
	
	# Prova a ri-selezionare il vecchio target se è ancora valido e vivo
	if old_target and is_instance_valid(old_target) and old_target.get("vita") > 0.0:
		spectated_index = spectatable_players.find(old_target)
		if spectated_index == -1:
			spectated_index = 0
	else:
		if spectated_index >= spectatable_players.size():
			spectated_index = 0


func _check_spectated_validity() -> void:
	if spectatable_players.is_empty():
		spectator_label.text = "Nessun giocatore rimasto in vita da osservare."
		spectate_prev_btn.disabled = true
		spectate_next_btn.disabled = true
		return
		
	spectate_prev_btn.disabled = false
	spectate_next_btn.disabled = false
	
	var current_target = spectatable_players[spectated_index]
	if not is_instance_valid(current_target) or current_target.get("vita") <= 0.0:
		# Il giocatore osservato è morto, passa al successivo
		_on_spectate_next_pressed()
	else:
		_spectate_current()


func _spectate_current() -> void:
	if spectatable_players.is_empty():
		return
		
	var target = spectatable_players[spectated_index]
	if is_instance_valid(target):
		var target_camera = target.get_node_or_null("Camera2D") as Camera2D
		if target_camera:
			target_camera.make_current()
			
		# Recupera il nome
		var display_name: String = target.name
		if "player_name" in target:
			display_name = str(target.get("player_name"))
			
		# Mostra il team di appartenenza se presente
		var team_str := ""
		for g in target.get_groups():
			if g.begins_with("team_"):
				team_str = " (" + g.replace("team_", "Team ") + ")"
				break
				
		spectator_label.text = "Stai osservando: " + display_name + team_str


func _on_spectate_prev_pressed() -> void:
	if spectatable_players.is_empty():
		return
	spectated_index -= 1
	if spectated_index < 0:
		spectated_index = spectatable_players.size() - 1
	_spectate_current()


func _on_spectate_next_pressed() -> void:
	if spectatable_players.is_empty():
		return
	spectated_index += 1
	if spectated_index >= spectatable_players.size():
		spectated_index = 0
	_spectate_current()


# ---------------------------------------------------------------------------
# Segnali e Transizioni
# ---------------------------------------------------------------------------

func _cleanup_game() -> void:
	# Ripristina la pausa prima di caricare nuove scene
	get_tree().paused = false
	
	# Pulisci i dati del manager missioni
	var flow_player = get_node_or_null("/root/MissionFlowPlayer")
	if flow_player:
		flow_player.stop_flow()
	MissionManager.clear()


func _on_restart_begin_pressed() -> void:
	_cleanup_game()
	
	# Resetta completamente checkpoint per iniziare da zero
	var flow_player = get_node_or_null("/root/MissionFlowPlayer")
	if flow_player and flow_player.has_method("clear_checkpoint_data"):
		flow_player.call("clear_checkpoint_data")
		
	get_tree().reload_current_scene()
	queue_free()


func _on_restart_checkpoint_pressed() -> void:
	_cleanup_game()
	
	# Ricarica mantenendo l'ultimo checkpoint salvato
	get_tree().reload_current_scene()
	queue_free()


func _on_main_menu_pressed() -> void:
	_cleanup_game()
	
	# Resetta checkpoint prima di tornare al menu
	var flow_player = get_node_or_null("/root/MissionFlowPlayer")
	if flow_player and flow_player.has_method("clear_checkpoint_data"):
		flow_player.call("clear_checkpoint_data")
		
	get_tree().change_scene_to_file(main_menu_scene_path)
	queue_free()


func _on_lobby_pressed() -> void:
	_cleanup_game()
	
	# Resetta checkpoint
	var flow_player = get_node_or_null("/root/MissionFlowPlayer")
	if flow_player and flow_player.has_method("clear_checkpoint_data"):
		flow_player.call("clear_checkpoint_data")
		
	get_tree().change_scene_to_file(lobby_scene_path)
	queue_free()

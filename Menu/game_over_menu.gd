## game_over_menu.gd
## Singleplayer: pannello con Rigioca + Menu principale.
## Multiplayer: pannello con "Inizia a osservare" + "Torna alla lobby".
##   Al click su "Inizia a osservare" il pannello scompare e appaiono i
##   controlli HUD fissi (prev/next in basso a destra, lobby in basso a sinistra).

extends CanvasLayer

@export_file("*.tscn") var main_menu_scene_path := "res://Menu/main_menu.tscn"
@export_file("*.tscn") var lobby_scene_path     := "res://Menu/main_menu.tscn"

# Pannello centrale
@onready var dim:                  ColorRect      = %Dim
@onready var center_panel:         CenterContainer = %CenterPanel
@onready var singleplayer_container: VBoxContainer = %SingleplayerContainer
@onready var multiplayer_container:  VBoxContainer = %MultiplayerContainer

# Pulsanti singleplayer
@onready var restart_begin_btn: Button = %RestartBeginButton
@onready var main_menu_btn:     Button = %MainMenuButton

# Pulsanti multiplayer (nel pannello)
@onready var spectate_start_btn: Button = %SpectateStartButton
@onready var lobby_btn_panel:    Button = %LobbyButtonPanel

# HUD spettatore (overlay fisso, inizialmente nascosto)
@onready var spectator_hud:   Control = %SpectatorHUD
@onready var spectator_label: Label   = %SpectatorLabel
@onready var spectate_prev_btn: Button = %SpectatePrevButton
@onready var spectate_next_btn: Button = %SpectateNextButton
@onready var lobby_btn:         Button = %LobbyButton

# Stato
var local_player: PlayerPrototype = null
var spectatable_players: Array[Node2D] = []
var spectated_index: int = 0
var is_multiplayer_mode := false
var _poll_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "GameOverMenu"

	# Determina la modalità usando il MultiplayerManager se disponibile,
	# altrimenti cade su has_multiplayer_peer()
	var mp_manager = get_node_or_null("/root/MultiplayerManager")
	if mp_manager and mp_manager.has_method("is_active_multiplayer_session"):
		is_multiplayer_mode = mp_manager.is_active_multiplayer_session()
	else:
		is_multiplayer_mode = multiplayer.has_multiplayer_peer() \
			and not multiplayer.get_peers().is_empty()

	_setup_connections()
	_configure_ui()


func setup(player: PlayerPrototype) -> void:
	local_player = player
	_configure_ui()


func _setup_connections() -> void:
	# Singleplayer
	restart_begin_btn.pressed.connect(_on_restart_begin_pressed)
	main_menu_btn.pressed.connect(_on_main_menu_pressed)

	# Multiplayer — pannello
	spectate_start_btn.pressed.connect(_on_spectate_start_pressed)
	lobby_btn_panel.pressed.connect(_on_lobby_pressed)

	# HUD spettatore
	spectate_prev_btn.pressed.connect(_on_spectate_prev_pressed)
	spectate_next_btn.pressed.connect(_on_spectate_next_pressed)
	lobby_btn.pressed.connect(_on_lobby_pressed)


func _configure_ui() -> void:
	if not is_inside_tree():
		return

	if is_multiplayer_mode:
		singleplayer_container.visible = false
		multiplayer_container.visible  = true
		spectator_hud.visible          = false
	else:
		# Singleplayer: mostra solo il pannello con Rigioca / Menu
		singleplayer_container.visible = true
		multiplayer_container.visible  = false
		spectator_hud.visible          = false
		get_tree().paused = true


# ---------------------------------------------------------------------------
# Spectating
# ---------------------------------------------------------------------------

func _on_spectate_start_pressed() -> void:
	# Nasconde tutto il pannello centrale e l'overlay scuro
	dim.visible          = false
	center_panel.visible = false
	# Mostra HUD fisso
	spectator_hud.visible = true

	_update_spectatable_players()
	_spectate_current()


func _process(delta: float) -> void:
	if not is_multiplayer_mode or not spectator_hud.visible:
		return

	_poll_timer += delta
	if _poll_timer >= 0.5:
		_poll_timer = 0.0
		_update_spectatable_players()
		_check_spectated_validity()


func _update_spectatable_players() -> void:
	var all_players := get_tree().get_nodes_in_group("players")
	var same_team:  Array[Node2D] = []
	var other_team: Array[Node2D] = []

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
			continue
		if p.get("vita") != null and p.get("vita") <= 0.0:
			continue
		if not my_team.is_empty() and p.is_in_group(my_team):
			same_team.append(p)
		else:
			other_team.append(p)

	var old_target = spectatable_players[spectated_index] \
		if spectated_index < spectatable_players.size() else null

	spectatable_players.clear()
	spectatable_players.append_array(same_team)
	spectatable_players.append_array(other_team)

	if old_target and is_instance_valid(old_target) and old_target.get("vita") > 0.0:
		spectated_index = spectatable_players.find(old_target)
		if spectated_index == -1:
			spectated_index = 0
	elif spectated_index >= spectatable_players.size():
		spectated_index = 0


func _check_spectated_validity() -> void:
	if spectatable_players.is_empty():
		spectator_label.text = "Nessun giocatore rimasto in vita."
		spectate_prev_btn.disabled = true
		spectate_next_btn.disabled = true
		return

	spectate_prev_btn.disabled = false
	spectate_next_btn.disabled = false

	var current_target = spectatable_players[spectated_index]
	if not is_instance_valid(current_target) or current_target.get("vita") <= 0.0:
		_on_spectate_next_pressed()
	else:
		_spectate_current()


func _spectate_current() -> void:
	if spectatable_players.is_empty():
		return

	var target = spectatable_players[spectated_index]
	if not is_instance_valid(target):
		return

	var target_camera := target.get_node_or_null("Camera2D") as Camera2D
	if target_camera and target_camera.is_inside_tree():
		target_camera.call_deferred("make_current")

	var display_name: String = target.name
	if "player_name" in target:
		display_name = str(target.get("player_name"))

	var team_str := ""
	for g in target.get_groups():
		if g.begins_with("pvp_team_"):
			team_str = "  •  Team " + g.replace("pvp_team_", "")
			break

	spectator_label.text = "▶  " + display_name + team_str


func _on_spectate_prev_pressed() -> void:
	if spectatable_players.is_empty():
		return
	spectated_index = (spectated_index - 1 + spectatable_players.size()) % spectatable_players.size()
	_spectate_current()


func _on_spectate_next_pressed() -> void:
	if spectatable_players.is_empty():
		return
	spectated_index = (spectated_index + 1) % spectatable_players.size()
	_spectate_current()


# ---------------------------------------------------------------------------
# Transizioni scena
# ---------------------------------------------------------------------------

func _cleanup_game() -> void:
	get_tree().paused = false
	var flow_player = get_node_or_null("/root/MissionFlowPlayer")
	if flow_player:
		flow_player.stop_flow()
	MissionManager.clear()


func _on_restart_begin_pressed() -> void:
	_cleanup_game()
	var flow_player = get_node_or_null("/root/MissionFlowPlayer")
	if flow_player and flow_player.has_method("clear_checkpoint_data"):
		flow_player.call("clear_checkpoint_data")
	get_tree().reload_current_scene()
	queue_free()


func _on_main_menu_pressed() -> void:
	_cleanup_game()
	var flow_player = get_node_or_null("/root/MissionFlowPlayer")
	if flow_player and flow_player.has_method("clear_checkpoint_data"):
		flow_player.call("clear_checkpoint_data")
	get_tree().change_scene_to_file(main_menu_scene_path)
	queue_free()


func _on_lobby_pressed() -> void:
	_cleanup_game()
	var flow_player = get_node_or_null("/root/MissionFlowPlayer")
	if flow_player and flow_player.has_method("clear_checkpoint_data"):
		flow_player.call("clear_checkpoint_data")
	get_tree().change_scene_to_file(lobby_scene_path)
	queue_free()

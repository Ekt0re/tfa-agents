extends Control

@onready var _player_name_field: LineEdit = %PlayerNameField
@onready var _status_label: Label = %StatusLabel

# --- Tab Crea ---
@onready var _game_mode_option: OptionButton = %GameModeOption
@onready var _respawn_checkbox: CheckBox = %RespawnCheckbox
@onready var _create_button: Button = %CreateButton

# --- Advanced Settings Popup ---
@onready var _advanced_settings_popup: AcceptDialog = %AdvancedSettingsPopup
@onready var _host_port_field: LineEdit = %HostPortField
@onready var _max_players_slider: HSlider = %MaxPlayersSlider
@onready var _max_players_label: Label = %MaxPlayersLabel
@onready var _team_mode_option: OptionButton = %TeamModeOption
@onready var _team_count_spin: SpinBox = %TeamCountSpin
@onready var _respawn_time_slider: HSlider = %RespawnTimeSlider
@onready var _respawn_time_label: Label = %RespawnTimeLabel

# --- Tab Unisciti ---
@onready var _join_ip_field: LineEdit = %JoinIPField
@onready var _join_port_field: LineEdit = %JoinPortField
@onready var _join_button: Button = %JoinButton
@onready var _discover_button: Button = %DiscoverButton
@onready var _servers_container: VBoxContainer = %ServersContainer

var _mp_manager: Node = null
var _found_servers: Array[Dictionary] = []


func _ready() -> void:
	_mp_manager = get_node_or_null("/root/MultiplayerManager")
	if not _mp_manager:
		push_error("MultiplaryerMenu: MultiplayerManager autoload non trovato!")
		return

	_mp_manager.connection_failed.connect(_on_connection_failed)
	_mp_manager.lobby_updated.connect(_on_lobby_updated)
	_mp_manager.servers_discovered.connect(_on_servers_discovered)
	_mp_manager.version_mismatch.connect(_on_version_mismatch)

	# Valori default
	_host_port_field.text = str(_mp_manager.DEFAULT_PORT)
	_join_port_field.text = str(_mp_manager.DEFAULT_PORT)
	_join_ip_field.text = "127.0.0.1"
	_max_players_slider.min_value = 2
	_max_players_slider.max_value = _mp_manager.MAX_PLAYERS
	_max_players_slider.value = _mp_manager.DEFAULT_MAX_PLAYERS
	_max_players_label.text = tr("max_players_label") + ": " + str(int(_max_players_slider.value))
	_team_mode_option.clear()
	_team_mode_option.add_item(tr("mode_teams"), 0)
	_team_mode_option.add_item(tr("mode_ffa"), 1)
	_team_count_spin.min_value = 2
	_team_count_spin.max_value = 10
	_team_count_spin.value = 2
	
	# Configura le modalità di gioco
	_game_mode_option.clear()
	_populate_game_mode_options()
	
	# Configura respawn
	_respawn_checkbox.button_pressed = true
	_respawn_time_slider.min_value = 1.0
	_respawn_time_slider.max_value = 10.0
	_respawn_time_slider.step = 0.5
	_respawn_time_slider.value = 3.0
	_respawn_time_label.text = tr("respawn_time_setting_label") % _respawn_time_slider.value
	_status_label.text = ""

	# Carica il nome del giocatore salvato, se presente
	var gs = get_node_or_null("/root/GlobalSettings")
	if gs and gs.has_method("get_setting"):
		var saved_name: String = gs.call("get_setting", "player_name", "")
		if not saved_name.is_empty():
			_player_name_field.text = saved_name


func _on_max_players_slider_value_changed(value: float) -> void:
	_max_players_label.text = tr("max_players_label") + ": " + str(int(value))


func _on_team_mode_option_item_selected(index: int) -> void:
	_team_count_spin.visible = (index == 0)
	# Aggiorna le modalità di gioco disponibili in base alla modalità team
	_populate_game_mode_options()


func _on_advanced_settings_button_pressed() -> void:
	_advanced_settings_popup.popup_centered(Vector2(400, 500))


func _on_create_button_pressed() -> void:
	_apply_player_name()
	var port: int = int(_host_port_field.text) if _host_port_field.text.is_valid_int() else int(_mp_manager.DEFAULT_PORT)
	var max_pl := int(_max_players_slider.value)
	_mp_manager.team_mode = "teams" if _team_mode_option.selected == 0 else "ffa"
	_mp_manager.team_count = int(_team_count_spin.value)
	
	# Applica le impostazioni della modalità di gioco
	var selected_game_mode_id = _game_mode_option.get_selected_id()
	_mp_manager.game_mode = _game_mode_option.get_item_text(selected_game_mode_id).to_lower().replace(" ", "_")
	_mp_manager.respawn_enabled = _respawn_checkbox.button_pressed
	_mp_manager.respawn_time = float(_respawn_time_slider.value)

	_status_label.text = "Avvio server in corso..."
	_create_button.disabled = true
	var err = _mp_manager.host_game(port, max_pl)
	if err == OK:
		get_tree().change_scene_to_file("res://Menu/lobby.tscn")
	else:
		_status_label.text = "Errore avvio server (porta %d occupata?)" % port
		_create_button.disabled = false


func _on_join_button_pressed() -> void:
	_apply_player_name()
	var ip := _join_ip_field.text.strip_edges()
	var port: int = int(_join_port_field.text) if _join_port_field.text.is_valid_int() else int(_mp_manager.DEFAULT_PORT)
	if ip.is_empty():
		_status_label.text = "Inserisci un indirizzo IP valido."
		return

	_status_label.text = "Connessione a %s:%d..." % [ip, port]
	_join_button.disabled = true
	var err = _mp_manager.join_game(ip, port)
	if err != OK:
		_status_label.text = "Impossibile avviare la connessione."
		_join_button.disabled = false


func _on_back_button_pressed() -> void:
	_mp_manager.disconnect_game()
	get_tree().change_scene_to_file("res://Menu/main_menu.tscn")


func _populate_game_mode_options() -> void:
	_game_mode_option.clear()
	var is_teams = _team_mode_option.selected == 0
	
	if is_teams:
		# Modalità per squadre
		_game_mode_option.add_item(tr("game_mode_team_battle"), 0)
		_game_mode_option.add_item(tr("game_mode_capture_flag"), 1)
		_game_mode_option.add_item(tr("game_mode_team_gun_match"), 2)
	else:
		# Modalità singoli
		_game_mode_option.add_item(tr("game_mode_deathmatch"), 0)
		_game_mode_option.add_item(tr("game_mode_gun_match"), 1)
		_game_mode_option.add_item(tr("game_mode_player_vs_bot"), 2)


func _on_game_mode_option_item_selected(_index: int) -> void:
	# Puoi aggiungere logica specifica per modalità qui se necessario
	pass


func _on_respawn_time_slider_value_changed(value: float) -> void:
	_respawn_time_label.text = tr("respawn_time_setting_label") % value


func _on_discover_button_pressed() -> void:
	_status_label.text = "Ricerca server in corso..."
	_discover_button.disabled = true
	# Pulisci i figli del container
	for child in _servers_container.get_children():
		child.queue_free()
	_found_servers.clear()
	_mp_manager.start_server_discovery(3.0)


func _on_servers_discovered(servers: Array[Dictionary]) -> void:
	_status_label.text = ""
	_discover_button.disabled = false
	# Pulisci i figli del container
	for child in _servers_container.get_children():
		child.queue_free()
	_found_servers = servers
	
	# Filtra solo i server con >0 giocatori
	var active_servers = servers.filter(func(s): return s.get("players", 0) > 0)
	
	if active_servers.is_empty():
		_status_label.text = "Nessun server attivo trovato sulla rete locale."
		return
	
	_status_label.text = "Server attivi trovati: %d" % active_servers.size()
	
	for server in active_servers:
		# Crea una card per ogni server
		var card = _create_server_card(server)
		_servers_container.add_child(card)


func _create_server_card(server: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 140)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	
	# Nome server / Host
	var host_name = server.get("host_name", server.get("name", "Server Sconosciuto"))
	var name_label = Label.new()
	name_label.text = "🏠 Host: %s" % host_name
	name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_label)
	
	# IP e Porta
	var ip_label = Label.new()
	ip_label.text = "📍 IP: %s:%d" % [server.get("ip", "???"), server.get("port", 7777)]
	ip_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(ip_label)
	
	# Giocatori attuali / massimi
	var players_label = Label.new()
	var current = server.get("players", 0)
	var max_p = server.get("max_players", 12)
	players_label.text = "👥 Giocatori: %d/%d" % [current, max_p]
	players_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(players_label)
	
	# Modalità di gioco
	var game_mode_label = Label.new()
	var game_mode = server.get("game_mode", "deathmatch")
	var game_mode_display = game_mode.capitalize()
	game_mode_label.text = "🎮 Modalità: %s" % game_mode_display
	game_mode_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(game_mode_label)
	
	# Versione del server
	var version_label = Label.new()
	var version = server.get("version", "???")
	version_label.text = "📦 Versione: %s" % version
	version_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(version_label)
	
	margin.add_child(vbox)
	card.add_child(margin)
	
	# Click per selezionare il server
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_on_server_selected(server)
	)
	
	return card


func _on_server_selected(server: Dictionary) -> void:
	var ip = server.get("ip", "127.0.0.1")
	var port = server.get("port", _mp_manager.DEFAULT_PORT)
	_join_ip_field.text = ip
	_join_port_field.text = str(port)
	_status_label.text = "Server selezionato: %s" % ip


func _on_connection_failed(reason: String) -> void:
	_status_label.text = reason
	_join_button.disabled = false
	_create_button.disabled = false


func _on_version_mismatch(host_version: String, client_version: String) -> void:
	_status_label.text = "Versione incompatibile! Host: %s, Tuo client: %s" % [host_version, client_version]
	_join_button.disabled = false


func _on_lobby_updated(_info: Dictionary) -> void:
	# Il join è riuscito: apri la lobby
	if not _mp_manager.is_host():
		get_tree().change_scene_to_file("res://Menu/lobby.tscn")


func _apply_player_name() -> void:
	var pname := _player_name_field.text.strip_edges()
	if pname.is_empty():
		pname = "Giocatore"
	_mp_manager.set_player_name(pname)
	var gs = get_node_or_null("/root/GlobalSettings")
	if gs and gs.has_method("set_setting"):
		gs.call("set_setting", "player_name", pname)

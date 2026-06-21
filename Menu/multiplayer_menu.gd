extends Control

@onready var _player_name_field: LineEdit = %PlayerNameField
@onready var _status_label: Label = %StatusLabel

# --- Tab Crea ---
@onready var _host_port_field: LineEdit = %HostPortField
@onready var _max_players_slider: HSlider = %MaxPlayersSlider
@onready var _max_players_label: Label = %MaxPlayersLabel
@onready var _team_mode_option: OptionButton = %TeamModeOption
@onready var _team_count_spin: SpinBox = %TeamCountSpin
@onready var _create_button: Button = %CreateButton

# --- Tab Unisciti ---
@onready var _join_ip_field: LineEdit = %JoinIPField
@onready var _join_port_field: LineEdit = %JoinPortField
@onready var _join_button: Button = %JoinButton

var _mp_manager: Node = null


func _ready() -> void:
	_mp_manager = get_node_or_null("/root/MultiplayerManager")
	if not _mp_manager:
		push_error("MultiplaryerMenu: MultiplayerManager autoload non trovato!")
		return

	_mp_manager.connection_failed.connect(_on_connection_failed)
	_mp_manager.lobby_updated.connect(_on_lobby_updated)

	# Valori default
	_host_port_field.text = str(_mp_manager.DEFAULT_PORT)
	_join_port_field.text = str(_mp_manager.DEFAULT_PORT)
	_join_ip_field.text = "127.0.0.1"
	_max_players_slider.min_value = 2
	_max_players_slider.max_value = _mp_manager.MAX_PLAYERS
	_max_players_slider.value = _mp_manager.DEFAULT_MAX_PLAYERS
	_max_players_label.text = str(int(_max_players_slider.value))
	_team_mode_option.clear()
	_team_mode_option.add_item("A squadre", 0)
	_team_mode_option.add_item("Tutti contro tutti (FFA)", 1)
	_team_count_spin.min_value = 2
	_team_count_spin.max_value = 10
	_team_count_spin.value = 2
	_status_label.text = ""

	# Carica il nome del giocatore salvato, se presente
	var gs = get_node_or_null("/root/GlobalSettings")
	if gs and gs.has_method("get_setting"):
		var saved_name: String = gs.call("get_setting", "player_name", "")
		if not saved_name.is_empty():
			_player_name_field.text = saved_name


func _on_max_players_slider_value_changed(value: float) -> void:
	_max_players_label.text = str(int(value))


func _on_team_mode_option_item_selected(index: int) -> void:
	_team_count_spin.visible = (index == 0)


func _on_create_button_pressed() -> void:
	_apply_player_name()
	var port: int = int(_host_port_field.text) if _host_port_field.text.is_valid_int() else int(_mp_manager.DEFAULT_PORT)
	var max_pl := int(_max_players_slider.value)
	_mp_manager.team_mode = "teams" if _team_mode_option.selected == 0 else "ffa"
	_mp_manager.team_count = int(_team_count_spin.value)

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


func _on_connection_failed(reason: String) -> void:
	_status_label.text = reason
	_join_button.disabled = false
	_create_button.disabled = false


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

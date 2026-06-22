## Lobby di attesa multiplayer.
## Mostra i giocatori connessi, il loro stato "pronto" e permette all'host di avviare la partita.
extends Control

@onready var _player_list: VBoxContainer = %PlayerList
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _edit_settings_button: Button = %EditSettingsButton
@onready var _host_ip_label: Label = %HostIPLabel
@onready var _status_label: Label = %StatusLabel
@onready var _game_mode_info_label: Label = %GameModeInfoLabel
@onready var _chat_log: RichTextLabel = %ChatLog
@onready var _chat_input: LineEdit = %ChatInput

# --- Advanced Settings Popup ---
@onready var _advanced_settings_popup: AcceptDialog = %AdvancedSettingsPopup
@onready var _host_port_field: LineEdit = %HostPortField
@onready var _max_players_slider: HSlider = %MaxPlayersSlider
@onready var _max_players_label: Label = %MaxPlayersLabel
@onready var _team_mode_option: OptionButton = %TeamModeOption
@onready var _team_count_spin: SpinBox = %TeamCountSpin
@onready var _respawn_time_slider: HSlider = %RespawnTimeSlider
@onready var _respawn_time_label: Label = %RespawnTimeLabel

var _mp_manager: Node = null
var _is_local_ready: bool = false


func _ready() -> void:
	_mp_manager = get_node("/root/MultiplayerManager")
	_mp_manager.lobby_updated.connect(_on_lobby_updated)
	_mp_manager.player_disconnected.connect(_on_player_disconnected)
	_mp_manager.game_started.connect(_on_game_started)
	_mp_manager.connection_failed.connect(_on_connection_failed)
	_mp_manager.map_selected.connect(_on_map_selected)

	_start_button.visible = _mp_manager.is_host()
	_start_button.disabled = true
	
	# Mostra il pulsante di modifica impostazioni solo per l'host
	_edit_settings_button.visible = _mp_manager.is_host()

	_chat_log.bbcode_enabled = true
	_chat_log.text = ""

	# Mostra IP locale per condivisione
	var ip := _get_local_ip()
	_host_ip_label.text = "IP: %s  |  Porta: %d" % [ip, _mp_manager.DEFAULT_PORT]
	
	# Inizializza il popup con i valori correnti
	_init_advanced_settings_popup()
	
	# Mostra le impostazioni della modalità di gioco
	_update_game_mode_display()

	_on_lobby_updated(_mp_manager.players_info)


# ---------------------------------------------------------------------------
# UI — Lista giocatori
# ---------------------------------------------------------------------------
func _on_lobby_updated(players_info: Dictionary) -> void:
	# Svuota lista
	for child in _player_list.get_children():
		child.queue_free()

	var local_id: int = _mp_manager.get_local_peer_id()
	var all_ready := true

	for peer_id in players_info:
		var info: Dictionary = players_info[peer_id]
		var row := _build_player_row(peer_id, info, local_id)
		_player_list.add_child(row)
		if not bool(info.get("ready", false)):
			all_ready = false

	_start_button.disabled = not all_ready or players_info.size() < 2
	_status_label.text = tr("lobby_players_connected") % players_info.size()


func _build_player_row(peer_id: int, info: Dictionary, local_id: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 36)

	# Icona pronto
	var ready_icon := Label.new()
	ready_icon.text = "[PRONTO]" if bool(info.get("ready", false)) else "[ATTESA]"
	ready_icon.modulate = Color.LIME_GREEN if bool(info.get("ready", false)) else Color.GRAY
	ready_icon.custom_minimum_size = Vector2(90, 0)
	row.add_child(ready_icon)

	# Nome giocatore
	var name_label := Label.new()
	var display_name := String(info.get("name", "?"))
	if peer_id == local_id:
		display_name += " (Tu)"
	if peer_id == 1:
		display_name += " [Host]"
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Team badge
	var team_label := Label.new()
	var tid := int(info.get("team_id", 0))
	team_label.text = ("Team %d" % tid) if tid > 0 else "—"
	team_label.custom_minimum_size = Vector2(70, 0)
	team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(team_label)

	return row


# ---------------------------------------------------------------------------
# Pulsanti
# ---------------------------------------------------------------------------
func _on_ready_button_pressed() -> void:
	_is_local_ready = not _is_local_ready
	_mp_manager.set_ready(_is_local_ready)
	_ready_button.text = "Annulla pronto" if _is_local_ready else "PRONTO"


func _on_start_button_pressed() -> void:
	_mp_manager.start_game()


func _on_back_button_pressed() -> void:
	_mp_manager.disconnect_game()
	get_tree().change_scene_to_file("res://Menu/multiplayer_menu.tscn")


# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------
func _on_send_chat_button_pressed() -> void:
	_send_chat_message()


func _on_chat_input_text_submitted(_text: String) -> void:
	_send_chat_message()


func _send_chat_message() -> void:
	var msg := _chat_input.text.strip_edges()
	if msg.is_empty():
		return
	_chat_input.text = ""
	var sender_name := String(_mp_manager.players_info.get(
		_mp_manager.get_local_peer_id(), {}).get("name", "?"))
	_receive_chat_message.rpc("[b]%s[/b]: %s" % [sender_name, msg])


@rpc("any_peer", "call_local", "reliable")
func _receive_chat_message(formatted: String) -> void:
	_chat_log.append_text(formatted + "\n")


# ---------------------------------------------------------------------------
# Callbacks di rete
# ---------------------------------------------------------------------------
func _on_player_disconnected(_peer_id: int) -> void:
	_status_label.text = tr("lobby_player_disconnected")


func _on_game_started(_map_path: String) -> void:
	pass  # La scena viene cambiata automaticamente dal MultiplayerManager


func _on_connection_failed(reason: String) -> void:
	_status_label.text = reason
	_mp_manager.disconnect_game()
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://Menu/multiplayer_menu.tscn")


func _on_map_selected(map_path: String) -> void:
	var map_name = _mp_manager.get_map_name(map_path)
	_status_label.text = tr("lobby_map_selected") % map_name


# ---------------------------------------------------------------------------
# Display modalità di gioco
# ---------------------------------------------------------------------------
func _update_game_mode_display() -> void:
	var game_mode_display = _mp_manager.game_mode.capitalize()
	var respawn_display = tr("respawn_yes") % _mp_manager.respawn_time if _mp_manager.respawn_enabled else tr("respawn_no")
	
	var team_mode_display = ""
	if _mp_manager.team_mode == "teams":
		team_mode_display = "|%d %s" % [_mp_manager.team_count, tr("mode_teams")]
	else:
		team_mode_display = "|" + tr("mode_ffa")
	
	_game_mode_info_label.text = tr("lobby_game_mode_info") % [game_mode_display, team_mode_display, respawn_display]


# ---------------------------------------------------------------------------
# Advanced Settings Popup
# ---------------------------------------------------------------------------
func _init_advanced_settings_popup() -> void:
	# Configura il popup con i valori correnti del MultiplayerManager
	_host_port_field.text = str(_mp_manager.DEFAULT_PORT)
	_max_players_slider.min_value = 2
	_max_players_slider.max_value = _mp_manager.MAX_PLAYERS
	_max_players_slider.value = _mp_manager.session_max_players
	_max_players_label.text = tr("max_players_label") + ": " + str(int(_max_players_slider.value))
	
	_team_mode_option.clear()
	_team_mode_option.add_item(tr("mode_teams"), 0)
	_team_mode_option.add_item(tr("mode_ffa"), 1)
	
	if _mp_manager.team_mode == "teams":
		_team_mode_option.selected = 0
	else:
		_team_mode_option.selected = 1
	
	_team_count_spin.min_value = 2
	_team_count_spin.max_value = 10
	_team_count_spin.value = _mp_manager.team_count
	_team_count_spin.visible = (_team_mode_option.selected == 0)
	
	_respawn_time_slider.min_value = 1.0
	_respawn_time_slider.max_value = 10.0
	_respawn_time_slider.step = 0.5
	_respawn_time_slider.value = _mp_manager.respawn_time
	_respawn_time_label.text = tr("respawn_time_setting_label") % _respawn_time_slider.value
	
	# Collega il segnale di conferma
	_advanced_settings_popup.confirmed.connect(_apply_advanced_settings)


func _on_edit_settings_button_pressed() -> void:
	if _mp_manager.is_host():
		_advanced_settings_popup.popup_centered(Vector2(400, 500))


func _on_max_players_slider_value_changed(value: float) -> void:
	_max_players_label.text = tr("max_players_label") + ": " + str(int(value))


func _on_team_mode_option_item_selected(index: int) -> void:
	_team_count_spin.visible = (index == 0)


func _on_respawn_time_slider_value_changed(value: float) -> void:
	_respawn_time_label.text = tr("respawn_time_setting_label") % value


func _apply_advanced_settings() -> void:
	# Applica le impostazioni modificate dall'host
	var max_pl := int(_max_players_slider.value)
	_mp_manager.session_max_players = max_pl
	_mp_manager.team_mode = "teams" if _team_mode_option.selected == 0 else "ffa"
	_mp_manager.team_count = int(_team_count_spin.value)
	_mp_manager.respawn_time = float(_respawn_time_slider.value)
	
	# Aggiorna il display delle impostazioni
	_update_game_mode_display()
	
	# Notifica i giocatori connessi
	_status_label.text = "Impostazioni aggiornate"
	
	# Sincronizza le impostazioni con tutti i client
	if _mp_manager.is_host():
		_sync_settings_to_clients.rpc(
			_mp_manager.session_max_players,
			_mp_manager.team_mode,
			_mp_manager.team_count,
			_mp_manager.respawn_time
		)


@rpc("authority", "call_remote", "reliable")
func _sync_settings_to_clients(max_players: int, team_mode: String, team_count: int, respawn_time: float) -> void:
	# Aggiorna le impostazioni sui client
	_mp_manager.session_max_players = max_players
	_mp_manager.team_mode = team_mode
	_mp_manager.team_count = team_count
	_mp_manager.respawn_time = respawn_time
	
	# Aggiorna il display
	_update_game_mode_display()
	_status_label.text = "Impostazioni aggiornate dall'host"


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
func _get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"

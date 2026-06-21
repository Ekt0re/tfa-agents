## Lobby di attesa multiplayer.
## Mostra i giocatori connessi, il loro stato "pronto" e permette all'host di avviare la partita.
extends Control

@onready var _player_list: VBoxContainer = %PlayerList
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _host_ip_label: Label = %HostIPLabel
@onready var _status_label: Label = %StatusLabel
@onready var _chat_log: RichTextLabel = %ChatLog
@onready var _chat_input: LineEdit = %ChatInput

var _mp_manager: Node = null
var _is_local_ready: bool = false


func _ready() -> void:
	_mp_manager = get_node("/root/MultiplayerManager")
	_mp_manager.lobby_updated.connect(_on_lobby_updated)
	_mp_manager.player_disconnected.connect(_on_player_disconnected)
	_mp_manager.game_started.connect(_on_game_started)
	_mp_manager.connection_failed.connect(_on_connection_failed)

	_start_button.visible = _mp_manager.is_host()
	_start_button.disabled = true

	_chat_log.bbcode_enabled = true
	_chat_log.text = ""

	# Mostra IP locale per condivisione
	var ip := _get_local_ip()
	_host_ip_label.text = "IP: %s  |  Porta: %d" % [ip, _mp_manager.DEFAULT_PORT]

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
	_status_label.text = "%d giocatori connessi" % players_info.size()


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
	_status_label.text = "Un giocatore si è disconnesso."


func _on_game_started(_map_path: String) -> void:
	pass  # La scena viene cambiata automaticamente dal MultiplayerManager


func _on_connection_failed(reason: String) -> void:
	_status_label.text = reason
	_mp_manager.disconnect_game()
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://Menu/multiplayer_menu.tscn")


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
func _get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"

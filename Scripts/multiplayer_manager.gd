## MultiplayerManager — Autoload singleton per la gestione del multiplayer.
## Incapsula la connessione ENet e fornisce una API pulita per lobby, team e spawn.
## È progettato per essere modulare: il backend ENet è separato dalla logica di lobby,
## permettendo future integrazioni con relay server o backend dedicati.
extends Node

# ---------------------------------------------------------------------------
# Costanti
# ---------------------------------------------------------------------------
const MAX_PLAYERS: int = 20
const DEFAULT_MAX_PLAYERS: int = 12
const DEFAULT_PORT: int = 7777

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------
signal lobby_updated(players_info: Dictionary)
signal game_started(map_path: String)
signal connection_failed(reason: String)
signal player_disconnected(peer_id: int)
signal player_connected(peer_id: int)
signal all_players_ready()

# ---------------------------------------------------------------------------
# Stato Lobby
# ---------------------------------------------------------------------------

## Dizionario {peer_id: {name, team_id, ready, skin_index}}
var players_info: Dictionary = {}

## Numero massimo di giocatori per questa sessione (impostato dall'host)
var session_max_players: int = DEFAULT_MAX_PLAYERS

## Modalità team: "teams" (squadre bilanciate) o "ffa" (tutti contro tutti)
var team_mode: String = "teams"

## Numero di team in modalità "teams"
var team_count: int = 2

## Mappa da caricare (impostata dall'host)
var pending_map_path: String = "res://Maps/pvp_map.tscn"

## Nome del giocatore locale
var local_player_name: String = "Giocatore"

## Skin del giocatore locale (indice)
var local_skin_index: int = 0

# ---------------------------------------------------------------------------
# Stato connessione interna
# ---------------------------------------------------------------------------
var _peer: ENetMultiplayerPeer = null
var _is_host: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
# API pubblica — Backend ENet
# ---------------------------------------------------------------------------

## Crea una lobby come host.
## [param port] Porta UDP su cui mettersi in ascolto.
## [param max_players] Limite massimo di giocatori (2-MAX_PLAYERS).
func host_game(port: int = DEFAULT_PORT, max_players: int = DEFAULT_MAX_PLAYERS) -> Error:
	session_max_players = clampi(max_players, 2, MAX_PLAYERS)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, session_max_players - 1)  # -1 perché il server stesso è 1
	if err != OK:
		push_error("MultiplayerManager: impossibile avviare il server sulla porta %d — errore %d" % [port, err])
		connection_failed.emit("Impossibile avviare il server sulla porta %d" % port)
		return err

	multiplayer.multiplayer_peer = _peer
	_is_host = true

	# Registra il giocatore locale (peer_id 1 = server)
	_register_local_player(1)
	print("MultiplayerManager: Server avviato sulla porta %d (max %d giocatori)" % [port, session_max_players])
	return OK


## Connette al server di un host come client.
## [param ip] Indirizzo IP dell'host.
## [param port] Porta UDP dell'host.
func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port)
	if err != OK:
		push_error("MultiplayerManager: impossibile connettersi a %s:%d — errore %d" % [ip, port, err])
		connection_failed.emit("Impossibile connettersi a %s:%d" % [ip, port])
		return err

	multiplayer.multiplayer_peer = _peer
	_is_host = false
	print("MultiplayerManager: Connessione in corso a %s:%d..." % [ip, port])
	return OK


## Disconnette e resetta lo stato della lobby.
func disconnect_game() -> void:
	if _peer:
		multiplayer.multiplayer_peer = null
		_peer = null
	players_info.clear()
	_is_host = false
	print("MultiplayerManager: Disconnesso.")


## Imposta il nome del giocatore locale (prima di host/join).
func set_player_name(player_name: String) -> void:
	local_player_name = player_name


## Imposta la skin locale.
func set_skin_index(idx: int) -> void:
	local_skin_index = idx


## Segna il giocatore locale come "pronto" e notifica il server.
func set_ready(is_ready: bool) -> void:
	_set_ready_on_server.rpc_id(1, multiplayer.get_unique_id(), is_ready)


## [Solo host] Avvia la partita se tutti i giocatori sono pronti.
func start_game() -> void:
	if not _is_host:
		push_warning("MultiplayerManager: solo l'host può avviare la partita.")
		return
	if not _all_players_ready():
		push_warning("MultiplayerManager: non tutti i giocatori sono pronti.")
		return
	_assign_teams()
	_start_game_on_all.rpc(pending_map_path, players_info)


## Restituisce true se il peer locale è l'host.
func is_host() -> bool:
	return _is_host


## Restituisce true se siamo connessi a una sessione multiplayer.
func is_connected_to_session() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Restituisce il peer_id locale.
func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()


# ---------------------------------------------------------------------------
# Logica interna — Registrazione giocatori
# ---------------------------------------------------------------------------
func _register_local_player(peer_id: int) -> void:
	players_info[peer_id] = {
		"name": local_player_name,
		"team_id": 0,  # assegnato dall'host prima dello start
		"ready": false,
		"skin_index": local_skin_index
	}
	lobby_updated.emit(players_info.duplicate(true))


## [Solo host] Assegna i team in base alla modalità scelta.
func _assign_teams() -> void:
	var peer_ids := players_info.keys()
	if team_mode == "ffa":
		# Ogni giocatore nel suo team
		for i in range(peer_ids.size()):
			players_info[peer_ids[i]]["team_id"] = i + 1
	else:
		# Distribuzione round-robin tra i team
		for i in range(peer_ids.size()):
			players_info[peer_ids[i]]["team_id"] = (i % team_count) + 1


func _all_players_ready() -> bool:
	if players_info.is_empty():
		return false
	for info in players_info.values():
		if not bool(info.get("ready", false)):
			return false
	return true


# ---------------------------------------------------------------------------
# RPC — Lobby
# ---------------------------------------------------------------------------

## Invia i dati del giocatore al server non appena ci si connette.
@rpc("any_peer", "reliable")
func _register_player_on_server(peer_id: int, player_name: String, skin_index: int) -> void:
	if not multiplayer.is_server():
		return
	if players_info.size() >= session_max_players:
		# Lobby piena: disconnetti il peer
		push_warning("MultiplayerManager: Lobby piena, rifiuto peer %d" % peer_id)
		return

	players_info[peer_id] = {
		"name": player_name,
		"team_id": 0,
		"ready": false,
		"skin_index": skin_index
	}
	print("MultiplayerManager: Registrato peer %d come '%s'" % [peer_id, player_name])
	_broadcast_lobby_update.rpc(players_info)


## [Solo host→tutti] Aggiorna la lobby su tutti i client.
@rpc("authority", "call_local", "reliable")
func _broadcast_lobby_update(info: Dictionary) -> void:
	players_info = info.duplicate(true)
	lobby_updated.emit(players_info.duplicate(true))


## [Client→Server] Imposta lo stato "pronto" di un giocatore.
@rpc("any_peer", "call_local", "reliable")
func _set_ready_on_server(peer_id: int, is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	if players_info.has(peer_id):
		players_info[peer_id]["ready"] = is_ready
		_broadcast_lobby_update.rpc(players_info)
		if _all_players_ready():
			all_players_ready.emit()


## [Host→tutti] Avvia la partita su tutti i client.
@rpc("authority", "call_local", "reliable")
func _start_game_on_all(map_path: String, final_players_info: Dictionary) -> void:
	players_info = final_players_info.duplicate(true)
	game_started.emit(map_path)
	get_tree().change_scene_to_file(map_path)


# ---------------------------------------------------------------------------
# Callback peer_connected / disconnected
# ---------------------------------------------------------------------------
func _on_peer_connected(peer_id: int) -> void:
	print("MultiplayerManager: Peer connesso: %d" % peer_id)
	player_connected.emit(peer_id)
	# Se siamo il client appena connesso, inviamo i nostri dati al server
	if not _is_host and peer_id == 1:
		_register_player_on_server.rpc_id(1, multiplayer.get_unique_id(), local_player_name, local_skin_index)


func _on_peer_disconnected(peer_id: int) -> void:
	print("MultiplayerManager: Peer disconnesso: %d" % peer_id)
	players_info.erase(peer_id)
	player_disconnected.emit(peer_id)
	if multiplayer.is_server():
		_broadcast_lobby_update.rpc(players_info)


func _on_connected_to_server() -> void:
	print("MultiplayerManager: Connesso al server come peer %d" % multiplayer.get_unique_id())
	_register_local_player(multiplayer.get_unique_id())
	_register_player_on_server.rpc_id(1, multiplayer.get_unique_id(), local_player_name, local_skin_index)


func _on_connection_failed() -> void:
	push_error("MultiplayerManager: Connessione al server fallita.")
	_peer = null
	connection_failed.emit("Connessione al server fallita.")


func _on_server_disconnected() -> void:
	print("MultiplayerManager: Server disconnesso.")
	disconnect_game()
	connection_failed.emit("Il server si è disconnesso.")

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
const DISCOVERY_PORT: int = 7778       # Porta su cui il server ascolta i broadcast
const DISCOVERY_REPLY_PORT: int = 7779 # Porta su cui il client riceve le risposte

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------
signal lobby_updated(players_info: Dictionary)
signal game_started(map_path: String)
signal connection_failed(reason: String)
signal player_disconnected(peer_id: int)
signal player_connected(peer_id: int)
signal all_players_ready()
signal map_selected(map_path: String)
signal servers_discovered(servers: Array[Dictionary])
signal version_mismatch(host_version: String, client_version: String)
signal connection_quality_warning(peer_id: int, is_poor: bool)

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

## Modalità di gioco: "deathmatch", "team_deathmatch", "gun_match", "capture_flag", "player_vs_bot"
var game_mode: String = "deathmatch"

## Abilita respawn dopo la morte
var respawn_enabled: bool = true

## Tempo di respawn in secondi
var respawn_time: float = 3.0

## Lista delle mappe PVP disponibili
var pvp_maps: Array[String] = [
	"res://Maps/pvp_map.tscn",
	"res://Maps/PVP_maps/pvp_map2.tscn"
]

## Mappa da caricare (impostata dall'host)
var pending_map_path: String = "res://Maps/pvp_map.tscn"

## Nome del giocatore locale
var local_player_name: String = "Giocatore"

## Skin del giocatore locale (indice)
var local_skin_index: int = 0

## Versione corrente del gioco
var game_version: String = "0.1.10"

# ---------------------------------------------------------------------------
# Stato connessione interna
# ---------------------------------------------------------------------------
var is_match_running: bool = false
var _peer: ENetMultiplayerPeer = null
var _is_host: bool = false

# Monitoraggio qualità connessione
var _ping_timer: float = 0.0
const PING_CHECK_INTERVAL: float = 2.0  # Controlla ogni 2 secondi
var _peer_last_ping: Dictionary = {}  # {peer_id: last_ping_time}
var _peer_poor_connection: Dictionary = {}  # {peer_id: bool}

# Timeout lato client per rilevare disconnessione server
var _last_server_data_time: float = 0.0
const SERVER_TIMEOUT_SECONDS: float = 15.0  # Timeout 15 secondi

# ---------------------------------------------------------------------------
# Server Discovery
# ---------------------------------------------------------------------------
var _broadcast_listener: PacketPeerUDP = null  # Usato dal server per ricevere i broadcast
var _discovery_servers: Array[Dictionary] = []
var _is_discovering: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	# Il server risponde ai broadcast di discovery in arrivo
	if _broadcast_listener and _broadcast_listener.get_available_packet_count() > 0:
		var _data = _broadcast_listener.get_packet()
		var sender_ip: String = _broadcast_listener.get_packet_ip()
		var response: String = JSON.stringify({
			"name": local_player_name,
			"host_name": local_player_name,
			"port": DEFAULT_PORT,
			"players": players_info.size(),
			"max_players": session_max_players,
			"team_mode": team_mode,
			"team_count": team_count,
			"game_mode": game_mode,
			"version": game_version
		})
		# Risponde direttamente all'IP del client sulla porta di risposta
		_broadcast_listener.set_dest_address(sender_ip, DISCOVERY_REPLY_PORT)
		_broadcast_listener.put_packet(response.to_utf8_buffer())
		print("MultiplayerManager: Risposta discovery inviata a %s" % sender_ip)
	
	# Monitoraggio qualità connessione (solo server)
	if _is_host and is_match_running:
		_ping_timer += delta
		if _ping_timer >= PING_CHECK_INTERVAL:
			_ping_timer = 0.0
			_check_peer_connection_quality()
	
	# Monitoraggio timeout server (solo client)
	if not _is_host and is_connected_to_session():
		_check_server_timeout(delta)


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

	# Avvia il listener UDP per il discovery
	_start_broadcast_listener()

	# Registra il giocatore locale (peer_id 1 = server)
	_register_local_player(1)
	print("MultiplayerManager: Server avviato sulla porta %d (max %d giocatori)" % [port, session_max_players])
	return OK


## Avvia il listener UDP per rispondere ai broadcast di discovery.
func _start_broadcast_listener() -> void:
	_broadcast_listener = PacketPeerUDP.new()
	var err := _broadcast_listener.bind(DISCOVERY_PORT)
	if err != OK:
		push_error("MultiplayerManager: impossibile aprire la porta discovery %d — errore %d" % [DISCOVERY_PORT, err])
		_broadcast_listener = null
		return
	print("MultiplayerManager: In ascolto per discovery sulla porta %d" % DISCOVERY_PORT)


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


## Avvia la ricerca di server sulla rete locale tramite UDP broadcast.
## I risultati verranno emessi tramite il signal 'servers_discovered'.
func start_server_discovery(timeout_seconds: float = 3.0) -> void:
	if _is_discovering:
		print("MultiplayerManager: Discovery già in corso.")
		return

	_is_discovering = true
	_discovery_servers.clear()

	# Socket per ricevere le risposte dai server
	var recv_socket := PacketPeerUDP.new()
	var err := recv_socket.bind(DISCOVERY_REPLY_PORT)
	if err != OK:
		push_error("MultiplayerManager: impossibile aprire socket di ricezione discovery (porta %d) — errore %d" % [DISCOVERY_REPLY_PORT, err])
		_is_discovering = false
		servers_discovered.emit(_discovery_servers)
		return

	# Socket per inviare il broadcast
	var send_socket := PacketPeerUDP.new()
	send_socket.set_broadcast_enabled(true)
	send_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	send_socket.put_packet("DISCOVER".to_utf8_buffer())
	send_socket.close()
	print("MultiplayerManager: Broadcast discovery inviato, attendo risposte per %.1fs..." % timeout_seconds)

	# Raccoglie le risposte fino al timeout
	var start_time := Time.get_ticks_msec()
	var timeout_ms := int(timeout_seconds * 1000)
	while (Time.get_ticks_msec() - start_time) < timeout_ms:
		while recv_socket.get_available_packet_count() > 0:
			var data := recv_socket.get_packet()
			var sender_ip: String = recv_socket.get_packet_ip()
			var text := data.get_string_from_utf8()
			var parsed = JSON.parse_string(text)
			if parsed is Dictionary:
				# Evita duplicati
				var already_found := false
				for s in _discovery_servers:
					if s.get("ip") == sender_ip:
						already_found = true
						break
				if not already_found:
					parsed["ip"] = sender_ip
					_discovery_servers.append(parsed)
					print("✓ MultiplayerManager: Server trovato: %s ('%s', %d/%d giocatori)" % [
						sender_ip,
						parsed.get("name", "?"),
						parsed.get("players", 0),
						parsed.get("max_players", 0)
					])
		await get_tree().create_timer(0.1).timeout

	recv_socket.close()
	_is_discovering = false
	print("MultiplayerManager: Discovery completato. Server trovati: %d" % _discovery_servers.size())
	servers_discovered.emit(_discovery_servers)


func disconnect_game() -> void:
	if _broadcast_listener:
		_broadcast_listener.close()
		_broadcast_listener = null
	if _peer:
		multiplayer.multiplayer_peer = null
		_peer = null
	players_info.clear()
	_is_host = false
	is_match_running = false
	print("MultiplayerManager: Disconnesso.")


func leave_current_match() -> void:
	if is_connected_to_session():
		if multiplayer.is_server():
			_despawn_player_on_server(multiplayer.get_unique_id())
		else:
			_request_despawn.rpc_id(1)
		get_tree().change_scene_to_file("res://Menu/lobby.tscn")
	else:
		disconnect_game()
		get_tree().change_scene_to_file("res://Menu/main_menu.tscn")


func _despawn_player_on_server(peer_id: int) -> void:
	if not multiplayer.is_server(): return
	var map = get_tree().current_scene
	if map and map.has_node("Players"):
		var players_container = map.get_node("Players")
		var p_node = players_container.get_node_or_null(str(peer_id))
		if p_node:
			# Usa call_deferred per evitare problemi con il sistema di replica
			# durante la transizione di scena
			p_node.set_multiplayer_authority(1)  # Trasferisci autorità al server
			p_node.call_deferred("queue_free")


@rpc("any_peer", "reliable")
func _request_despawn() -> void:
	if multiplayer.is_server():
		_despawn_player_on_server(multiplayer.get_remote_sender_id())


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
	var random_index := randi() % pvp_maps.size()
	var selected_map: String = pvp_maps[random_index]
	print("MultiplayerManager: Mappa selezionata: ", selected_map)
	map_selected.emit(selected_map)
	_start_game_on_all.rpc(selected_map, players_info, team_mode, team_count, game_mode, respawn_enabled, respawn_time)


## Restituisce true se il peer locale è l'host.
func is_host() -> bool:
	return _is_host


## Restituisce true se siamo connessi a una sessione multiplayer.
func is_connected_to_session() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Restituisce il peer_id locale.
func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()


## Restituisce la lista delle mappe PVP disponibili.
func get_pvp_maps() -> Array[String]:
	return pvp_maps.duplicate()


## Restituisce il nome della mappa dal percorso.
func get_map_name(map_path: String) -> String:
	var map_file := map_path.get_file()
	return map_file.get_basename().capitalize()


## Confronta due versioni nel formato Major.Minor.Patch[.Build]
## Ritorna: 1 se v1 > v2, -1 se v1 < v2, 0 se uguali
func compare_versions(v1: String, v2: String) -> int:
	var parts1 = v1.split(".")
	var parts2 = v2.split(".")
	
	# Confronta ogni segmento, trattando i segmenti mancanti come 0
	var max_len = maxi(parts1.size(), parts2.size())
	for i in range(max_len):
		var num1 = int(parts1[i]) if i < parts1.size() else 0
		var num2 = int(parts2[i]) if i < parts2.size() else 0
		
		if num1 > num2:
			return 1
		elif num1 < num2:
			return -1
	
	return 0


## Verifica se la versione del client è compatibile con quella dell'host
## Il client deve avere almeno la stessa versione dell'host
func is_version_compatible(client_version: String, host_version: String) -> bool:
	var cmp = compare_versions(client_version, host_version)
	# Client version must be >= host version
	return cmp >= 0


# ---------------------------------------------------------------------------
# Logica interna — Registrazione giocatori
# ---------------------------------------------------------------------------
func _register_local_player(peer_id: int) -> void:
	players_info[peer_id] = {
		"name": local_player_name,
		"team_id": 0,
		"ready": false,
		"skin_index": local_skin_index
	}
	lobby_updated.emit(players_info.duplicate(true))


## [Solo host] Assegna i team in base alla modalità scelta.
func _assign_teams() -> void:
	var peer_ids := players_info.keys()
	if team_mode == "ffa":
		for i in range(peer_ids.size()):
			players_info[peer_ids[i]]["team_id"] = i + 1
	else:
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
	_normalize_players_info()
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
func _start_game_on_all(map_path: String, final_players_info: Dictionary, synced_team_mode: String = "teams", synced_team_count: int = 2, synced_game_mode: String = "deathmatch", synced_respawn_enabled: bool = true, synced_respawn_time: float = 3.0) -> void:
	players_info = final_players_info.duplicate(true)
	_normalize_players_info()
	team_mode = synced_team_mode
	team_count = synced_team_count
	game_mode = synced_game_mode
	respawn_enabled = synced_respawn_enabled
	respawn_time = synced_respawn_time
	is_match_running = true
	game_started.emit(map_path)
	get_tree().change_scene_to_file(map_path)


# ---------------------------------------------------------------------------
# Callback peer_connected / disconnected
# ---------------------------------------------------------------------------
func _on_peer_connected(peer_id: int) -> void:
	print("MultiplayerManager: Peer connesso: %d" % peer_id)
	player_connected.emit(peer_id)
	
	# Se sono un client, richiedi la versione all'host
	if not _is_host and peer_id == 1:
		_request_version_check.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_version_check() -> void:
	# L'host risponde con la sua versione
	_send_version_response.rpc_id(multiplayer.get_remote_sender_id(), game_version)


@rpc("any_peer", "call_local", "reliable")
func _send_version_response(host_version: String) -> void:
	# Se sono un client, verifica la versione dell'host
	if not _is_host:
		var client_version = game_version
		
		if not is_version_compatible(client_version, host_version):
			print("MultiplayerManager: Version mismatch! Host: %s, Client: %s" % [host_version, client_version])
			version_mismatch.emit(host_version, client_version)
			connection_failed.emit("Versione incompatibile!\nHost: %s\nTuo client: %s\n\nAggiorna il gioco per unirti." % [host_version, client_version])
			disconnect_game()
		else:
			print("MultiplayerManager: Version check passed! Host: %s, Client: %s" % [host_version, client_version])


func _on_peer_disconnected(peer_id: int) -> void:
	print("MultiplayerManager: Peer disconnesso: %d" % peer_id)
	players_info.erase(peer_id)
	player_disconnected.emit(peer_id)
	if multiplayer.is_server():
		_broadcast_lobby_update.rpc(players_info)


func _on_connected_to_server() -> void:
	print("MultiplayerManager: Connesso al server come peer %d" % multiplayer.get_unique_id())
	_last_server_data_time = Time.get_ticks_msec() / 1000.0  # Inizializza timer
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


## Controlla se il server non invia dati da troppo tempo (solo client)
func _check_server_timeout(_delta: float) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Se è la prima volta, inizializza
	if _last_server_data_time == 0.0:
		_last_server_data_time = current_time
		return
	
	var time_since_last_data = current_time - _last_server_data_time
	
	if time_since_last_data >= SERVER_TIMEOUT_SECONDS:
		print("MultiplayerManager: Timeout server - nessun dato ricevuto per %.1f secondi" % time_since_last_data)
		disconnect_game()
		connection_failed.emit("Connessione persa con il server.
Nessun dato ricevuto per %.0f secondi." % SERVER_TIMEOUT_SECONDS)


# ---------------------------------------------------------------------------
# Monitoraggio qualità connessione
# ---------------------------------------------------------------------------

## Controlla la qualità della connessione con i peer (solo server)
func _check_peer_connection_quality() -> void:
	if not multiplayer.is_server():
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var timeout_threshold = PING_CHECK_INTERVAL * 3.0  # 3x l'intervallo = 6 secondi
	
	for peer_id in players_info.keys():
		if peer_id == 1:  # Skip il server stesso
			continue
		
		# Invia ping al client
		if players_info.has(peer_id):
			_ping_check.rpc_id(peer_id)
		
		var last_ping = _peer_last_ping.get(peer_id, current_time)
		var time_since_ping = current_time - last_ping
		
		# Se non abbiamo ricevuto aggiornamenti da molto tempo, connessione scarsa
		var is_poor = time_since_ping > timeout_threshold
		
		# Emitte segnale solo se lo stato è cambiato
		if _peer_poor_connection.get(peer_id, false) != is_poor:
			_peer_poor_connection[peer_id] = is_poor
			connection_quality_warning.emit(peer_id, is_poor)
			
			if is_poor:
				print("MultiplayerManager: Connessione scarsa rilevata per peer %d" % peer_id)
			else:
				print("MultiplayerManager: Connessione ripristinata per peer %d" % peer_id)


## RPC: Il server invia un ping ai client per testare la connessione
@rpc("authority", "call_remote", "reliable")
func _ping_check() -> void:
	# Il client aggiorna il timer dell'ultimo dato ricevuto dal server
	_last_server_data_time = Time.get_ticks_msec() / 1000.0
	# Il client risponde al ping
	_pong_check.rpc_id(1)


## RPC: Il client risponde al ping del server
@rpc("any_peer", "call_local", "reliable")
func _pong_check() -> void:
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	_peer_last_ping[sender_id] = Time.get_ticks_msec() / 1000.0
	
	# Se la connessione era scarsa ora è buona
	if _peer_poor_connection.get(sender_id, false):
		_peer_poor_connection[sender_id] = false
		connection_quality_warning.emit(sender_id, false)


## Aggiorna il timer quando ricevi qualsiasi RPC dal server
func _on_rpc_received() -> void:
	if not _is_host:
		_last_server_data_time = Time.get_ticks_msec() / 1000.0


# ---------------------------------------------------------------------------
# Normalizzazione chiavi — Godot 4 converte le chiavi int in String dopo RPC
# ---------------------------------------------------------------------------

## Normalizza le chiavi di players_info da String a int dopo la serializzazione RPC.
func _normalize_players_info() -> void:
	var normalized: Dictionary = {}
	for key in players_info.keys():
		var int_key: int = int(key) if str(key).is_valid_int() else key
		normalized[int_key] = players_info[key]
	players_info = normalized
	
	
# In multiplayer_manager.gd — aggiungi questa funzione
func is_active_multiplayer_session() -> bool:
	if not is_match_running:
		return false
	if _peer == null:
		return false
	if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return true

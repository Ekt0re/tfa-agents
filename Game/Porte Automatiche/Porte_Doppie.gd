## Porte_Doppie.gd
## Gestore per porte doppie sincronizzate
##
## Questo script gestisce due porte che si aprono/chiudono insieme
## con le stesse impostazioni centralizzate.

@tool
extends Node2D
class_name DoubleDoor

# ---------------------------------------------------------------------------
# Export — Configurazione Centralizzata
# ---------------------------------------------------------------------------

@export_group("Porte Doppie")

@export var door_type: Door.DoorType = Door.DoorType.AUTOMATIC:
	set(value):
		door_type = value
		_sync_settings()

@export var auto_close_delay: float = 2.0:
	set(value):
		auto_close_delay = maxf(value, 0.0)
		_sync_settings()

@export var open_speed: float = 25.0:
	set(value):
		open_speed = maxf(value, 1.0)
		_sync_settings()

@export_group("Team")

@export var team_id: int = 0:
	set(value):
		team_id = value
		_sync_settings()

@export_group("Livello")

@export_range(0, 15, 1) var livello: int = 0:
	set(value):
		livello = maxi(value, 0)
		_sync_settings()

@export_group("Hacking")

@export var hack_duration: float = 3.0:
	set(value):
		hack_duration = maxf(value, 0.5)
		_sync_settings()

@export var hack_target_team: int = 1:
	set(value):
		hack_target_team = value
		_sync_settings()

@export_group("Raggio Attivazione")

@export var activation_range: float = 60.0:
	set(value):
		activation_range = maxf(value, 10.0)
		_sync_settings()

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------

signal doors_opened()
signal doors_closed()
signal hacking_started()
signal hacking_completed()

# ---------------------------------------------------------------------------
# Stato interno
# ---------------------------------------------------------------------------

var _door_left: Door = null
var _door_right: Door = null
var _is_syncing: bool = false

# ---------------------------------------------------------------------------
# Riferimenti ai nodi
# ---------------------------------------------------------------------------

var _door_1: Node = null
var _door_2: Node = null

# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------

func _enter_tree() -> void:
	# Ottieni i riferimenti PRIMA che i figli eseguano _ready()
	_door_1 = get_node_or_null("Porta automatica")
	_door_2 = get_node_or_null("Porta automatica2")
	
	# Disabilita la hack bar della porta destra PRIMA del suo _ready()
	if _door_2:
		_door_2.disable_hack_bar = true

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_door_left = _door_1 as Door
	_door_right = _door_2 as Door
	
	# Se la hack bar è già stata creata, rimuovila
	if _door_right:
		var right_hack_bar = _door_right.get_node_or_null("HackBarPivot")
		if right_hack_bar:
			right_hack_bar.queue_free()

	# Collega segnali delle porte
	if _door_left:
		_door_left.door_opened.connect(_on_door_opened)
		_door_left.door_closed.connect(_on_door_closed)
		_door_left.hacking_started.connect(_on_hacking_started)
		_door_left.hacking_completed.connect(_on_hacking_completed)

	if _door_right:
		_door_right.door_opened.connect(_on_door_opened)
		_door_right.door_closed.connect(_on_door_closed)
		# NON collegare hacking_started/completed della porta destra
		# per evitare duplicazioni (usa solo quella sinistra)

	# Sincronizza impostazioni iniziali
	_sync_settings()

# ---------------------------------------------------------------------------
# Sincronizzazione Impostazioni
# ---------------------------------------------------------------------------

func _sync_settings() -> void:
	if _is_syncing:
		return
	_is_syncing = true

	if _door_left:
		_door_left.door_type = door_type
		_door_left.auto_close_delay = auto_close_delay
		_door_left.open_speed = open_speed
		_door_left.team_id = team_id
		_door_left.livello = livello
		_door_left.hack_duration = hack_duration
		_door_left.hack_target_team = hack_target_team
		_door_left.activation_range = activation_range

	if _door_right:
		_door_right.door_type = door_type
		_door_right.auto_close_delay = auto_close_delay
		_door_right.open_speed = open_speed
		_door_right.team_id = team_id
		_door_right.livello = livello
		_door_right.hack_duration = hack_duration
		_door_right.hack_target_team = hack_target_team
		_door_right.activation_range = activation_range

	_is_syncing = false

# ---------------------------------------------------------------------------
# Callback Porte
# ---------------------------------------------------------------------------

func _on_door_opened() -> void:
	# Se una porta si apre, apri anche l'altra
	if _door_left and _door_right:
		if _door_left.is_door_open() and not _door_right.is_door_open():
			_door_right.open_door()
		elif _door_right.is_door_open() and not _door_left.is_door_open():
			_door_left.open_door()
	doors_opened.emit()

func _on_door_closed() -> void:
	# Se una porta si chiude, chiudi anche l'altra
	if _door_left and _door_right:
		if not _door_left.is_door_open() and _door_right.is_door_open():
			_door_right.close_door()
		elif not _door_right.is_door_open() and _door_left.is_door_open():
			_door_left.close_door()
	doors_closed.emit()

func _on_hacking_started() -> void:
	hacking_started.emit()

func _on_hacking_completed() -> void:
	hacking_completed.emit()

# ---------------------------------------------------------------------------
# API Pubblica
# ---------------------------------------------------------------------------

## Apre entrambe le porte
func open_doors() -> void:
	if _door_left:
		_door_left.open_door()
	if _door_right:
		_door_right.open_door()

## Chiude entrambe le porte
func close_doors() -> void:
	if _door_left:
		_door_left.close_door()
	if _door_right:
		_door_right.close_door()

## Blocca/sblocca entrambe le porte
func set_locked(p_locked: bool) -> void:
	if p_locked:
		door_type = Door.DoorType.LOCKED
	elif door_type == Door.DoorType.LOCKED:
		door_type = Door.DoorType.AUTOMATIC
	_sync_settings()

## Verifica se le porte sono aperte
func are_doors_open() -> bool:
	if _door_left and _door_right:
		return _door_left.is_door_open() and _door_right.is_door_open()
	return false

## Verifica se le porte sono bloccate
func are_doors_locked() -> bool:
	if _door_left and _door_right:
		return _door_left.is_locked() and _door_right.is_locked()
	return false

## Avvia hacking su entrambe le porte
func start_hack(peer_id: int = 0) -> void:
	if _door_left:
		_door_left.start_hack(peer_id)
	if _door_right:
		_door_right.start_hack(peer_id)

## Cancella hacking su entrambe le porte
func cancel_hack() -> void:
	if _door_left:
		_door_left.cancel_hack()
	if _door_right:
		_door_right.cancel_hack()

# ---------------------------------------------------------------------------
# Editor
# ---------------------------------------------------------------------------

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	
	# Aggiorna i riferimenti per i controlli
	var door1 = get_node_or_null("Porta automatica")
	var door2 = get_node_or_null("Porta automatica2")
	
	if not door1 or not door2:
		w.append("Entrambe le porte devono essere presenti come istanze di Porte_automatiche.tscn")
	
	if door1 and not door1 is Door:
		w.append("'Porta automatica' deve essere un'istanza dello script Door")
	
	if door2 and not door2 is Door:
		w.append("'Porta automatica2' deve essere un'istanza dello script Door")
	
	return w

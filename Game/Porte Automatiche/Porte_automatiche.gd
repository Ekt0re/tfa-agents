## Porte_automatiche.gd
## Sistema porte avanzato per Godot 4.x — v1
##
## Funzionalità:
## - Porte chiuse/bloccate che bloccano il player
## - Porte che si aprono solo per determinati team
## - Porte automatiche (apertura quando ci si avvicina)
## - Porte hackabili (apertura con barra di caricamento)
## - Sistema livelli/piani (come torrette)
## - Sincronizzazione multiplayer

@tool
extends StaticBody2D
class_name Door

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------

signal door_opened()
signal door_closed()
signal hacking_started()
signal hacking_completed()
signal team_changed(new_team_id: int)

# ---------------------------------------------------------------------------
# Export — Configurazione Porta
# ---------------------------------------------------------------------------

@export_group("Porta")

@export var door_type: DoorType = DoorType.AUTOMATIC:
	set(value):
		door_type = value
		_update_editor_preview()

@export var auto_close_delay: float = 2.0:
	set(value):
		auto_close_delay = maxf(value, 0.0)
		if _close_timer:
			_close_timer.wait_time = auto_close_delay

@export var open_speed: float = 25.0:
	set(value):
		open_speed = maxf(value, 1.0)
		_update_animation_speed()

@export_group("Team")

@export var team_id: int = 0:
	set(value):
		team_id = value
		_on_team_changed()
		_update_editor_preview()

@export_group("Livello")

@export_range(0, 15, 1) var livello: int = 0:
	set(value):
		livello = maxi(value, 0)
		_refresh_level_membership()
		_apply_collision_layers()
		_update_editor_preview()

@export_group("Hacking")

@export var hack_duration: float = 3.0:
	set(value):
		hack_duration = maxf(value, 0.5)

@export var hack_target_team: int = 1  ## Fallback se il team di chi ha hackerato non è determinabile

@export var hack_bar_vertical_offset: float = 80.0  ## Distanza (px) sopra la porta a cui mostrare la progress bar

@export var hack_bar_size: Vector2 = Vector2(160.0, 34.0)  ## Larghezza/altezza della progress bar

@export var hack_input_action: String = "hack"  ## Nome dell'azione nell'Input Map da tenere premuta per hackare

@export_group("Raggio Attivazione")

@export var activation_range: float = 60.0:
	set(value):
		activation_range = maxf(value, 10.0)
		_update_activation_area_shape()

@export_group("Debug")

@export var disable_hack_bar: bool = false  ## Se true, questa porta non crea/mostra la hack bar (usato da DoubleDoor)

# ---------------------------------------------------------------------------
# Enum DoorType
# ---------------------------------------------------------------------------

enum DoorType {
	AUTOMATIC,      ## Si apre automaticamente quando ci si avvicina
	MANUAL,         ## Si apre solo con hack
	TEAM_ONLY,      ## Si apre solo per il team specificato
	LOCKED          ## Porta bloccata, non si apre
}

# ---------------------------------------------------------------------------
# Getter per proprietà derivate da door_type
# ---------------------------------------------------------------------------

func is_locked() -> bool:
	return door_type == DoorType.LOCKED

func is_team_restricted() -> bool:
	return door_type == DoorType.TEAM_ONLY

func is_hackable() -> bool:
	return door_type == DoorType.MANUAL

# ---------------------------------------------------------------------------
# Stato interno
# ---------------------------------------------------------------------------

var _is_open: bool = false
var _is_hacking: bool = false
var _hack_progress: float = 0.0
var _entities_in_range: Array[Node2D] = []
var _registered_levels: Array[int] = []
var _player_node: Node2D = null
var _screen_visible: bool = true
var _hack_peer_id: int = 0  ## Peer ID del player che sta attualmente hackando (0 = nessuno)
var _hack_entity_team: int = -1  ## Team dell'entità che ha avviato l'hack in corso
var _nav_obstacle: NavigationObstacle2D = null  ## Ostacolo navigazione per porte LOCKED

# ---------------------------------------------------------------------------
# Riferimenti ai nodi
# ---------------------------------------------------------------------------

@onready var _door_sprite: AnimatedSprite2D = $DoorSprite
@onready var _collision_shape: CollisionShape2D = $CollisionShape
@onready var _activation_area: Area2D = $ActivationArea
@onready var _activation_shape: CollisionShape2D = $ActivationArea/ActivationShape
@onready var _close_timer: Timer = $CloseTimer
@onready var _screen_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D

# Nodo opzionale hack bar — pivot figlio della porta che resta sempre con
# rotazione globale 0, così la barra non ruota mai insieme alla porta.
var _hack_bar_pivot: Node2D = null
var _hack_bar_panel: Node2D = null

# Nodi opzionali
var _sfx: AudioStreamPlayer2D = null
var _hack_bar_progress: float = 0.0  # Per il nodo HackBar

# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()
		return

	# Nodi opzionali
	_sfx = get_node_or_null("SFX")

	# Gruppi
	#add_to_group("objects")
	_on_team_changed()
	_refresh_level_membership()
	_apply_collision_layers()
	_update_activation_area_shape()

	# Timer
	_close_timer.wait_time = auto_close_delay
	_close_timer.one_shot = true
	_close_timer.timeout.connect(_on_close_timer_timeout)

	# Segnali ActivationArea
	_activation_area.body_entered.connect(_on_activation_body_entered)
	_activation_area.body_exited.connect(_on_activation_body_exited)
	_activation_area.area_entered.connect(_on_activation_area_entered)
	_activation_area.area_exited.connect(_on_activation_area_exited)

	# FPS boost
	_screen_notifier.screen_entered.connect(_on_screen_entered)
	_screen_notifier.screen_exited.connect(_on_screen_exited)

	# Impostazioni grafiche
	_setup_global_settings()

	# Collegamento player per livello
	_connect_to_player()

	# Imposta velocità animazione
	_update_animation_speed()

	# Carica HackBarPivot se esiste, altrimenti crealo dinamicamente
	_hack_bar_pivot = get_node_or_null("HackBarPivot")
	if not _hack_bar_pivot and not disable_hack_bar:
		_crea_hack_bar()

	# Nascondi hack bar inizialmente
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false

	# Crea NavigationObstacle2D per porte LOCKED (influenza la NavMesh)
	_setup_nav_obstacle()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var am_authority := _is_hack_authority()

	# Avvio/interruzione hacking: legati alla pressione del tasto "hack"
	# da parte del player controllato localmente, mentre è nel raggio.
	if is_hackable() and not is_locked() and not _is_open:
		var local_entity := _get_local_hacking_entity()
		var hack_held := local_entity != null and Input.is_action_pressed(hack_input_action)
		var my_peer_id := multiplayer.get_unique_id() if _is_multiplayer_session() else 0

		if hack_held and not _is_hacking:
			var entity_team := _get_team_id(local_entity)
			if am_authority:
				start_hack(my_peer_id, entity_team)
			else:
				# Non sono l'autorità: chiedo al server, che deciderà se
				# questa porta è libera o già occupata da un altro player.
				_request_hack_start.rpc_id(1, entity_team)
		elif not hack_held and _is_hacking and _hack_peer_id == my_peer_id and _hack_peer_id >= 0:
			# Sto rilasciando IO il tasto, e sono io quello che stava hackando.
			# Nota: _hack_peer_id < 0 indica un hack avviato da un bot → non cancellare.
			if am_authority:
				cancel_hack()
			else:
				_request_hack_cancel.rpc_id(1)

	# Avanzamento progresso: SOLO lato autorità (server, o single-player).
	# I client non-autoritativi ricevono il progresso via _sync_hack_progress.
	if am_authority and _is_hacking:
		_hack_progress += delta
		_hack_bar_progress = clampf(_hack_progress / hack_duration, 0.0, 1.0)
		print("[HACK] Progress: %.2f / %.2f (%.0f%%)" % [_hack_progress, hack_duration, _hack_bar_progress * 100.0])
		_update_hack_bar()
		if _is_multiplayer_session():
			_sync_hack_progress.rpc(_hack_progress)
		if _hack_progress >= hack_duration:
			print("[HACK] Hack completo!")
			_complete_hack()

# ---------------------------------------------------------------------------
# Sistema attivazione — event-driven via Area2D (zero polling)
# ---------------------------------------------------------------------------

func _on_activation_body_entered(body: Node2D) -> void:
	if _can_activate(body) and _is_same_level(body):
		if body not in _entities_in_range:
			_entities_in_range.append(body)
		_try_open_door(body)

func _on_activation_body_exited(body: Node2D) -> void:
	_entities_in_range.erase(body)
	if _entities_in_range.is_empty():
		# Se non ci sono più entity e sto hackando, annulla (solo lato autorità)
		if _is_hacking and door_type == DoorType.MANUAL and _is_hack_authority():
			cancel_hack()
		_schedule_close()

func _on_activation_area_entered(area: Area2D) -> void:
	if _can_activate(area) and _is_same_level(area):
		if area not in _entities_in_range:
			_entities_in_range.append(area)
		_try_open_door(area)

func _on_activation_area_exited(area: Area2D) -> void:
	_entities_in_range.erase(area)
	if _entities_in_range.is_empty():
		# Se non ci sono più entity e sto hackando, annulla (solo lato autorità)
		if _is_hacking and door_type == DoorType.MANUAL and _is_hack_authority():
			cancel_hack()
		_schedule_close()

func _can_activate(entity: Node) -> bool:
	if not entity.is_in_group("damageable"):
		return false
	if entity == self:
		return false

	# Verifica team se restrizione attiva
	if is_team_restricted():
		var entity_team := _get_team_id(entity)
		if entity_team != team_id:
			return false

	return true

## Trova, tra le entity nel raggio d'attivazione, quella controllata
## localmente da questo client — così il tasto "hack" fa partire l'hacking
## solo per il player che lo preme davvero, e solo se è nel raggio.
func _get_local_hacking_entity() -> Node2D:
	for entity: Node2D in _entities_in_range:
		if not is_instance_valid(entity):
			continue
		if entity.has_method("is_multiplayer_authority") and entity.is_multiplayer_authority():
			return entity
	return null

func _try_open_door(entity: Node) -> void:
	if is_locked():
		print("[DOOR] '%s' bloccata — ignoro entity '%s'" % [name, entity.name])
		return

	var entity_team := _get_team_id(entity)
	var is_bot := entity.is_in_group("bots")

	match door_type:
		DoorType.AUTOMATIC:
			print("[DOOR] '%s' automatica — apro per '%s' (team %d)" % [name, entity.name, entity_team])
			_open_door()
		DoorType.TEAM_ONLY:
			if entity_team == team_id:
				print("[DOOR] '%s' team-only — team corretto (%d), apro" % [name, entity_team])
				_open_door()
			else:
				print("[DOOR] '%s' team-only — team errato (entity=%d, porta=%d)" % [name, entity_team, team_id])
		DoorType.MANUAL:
			# I bot avviano l'hack automaticamente all'entrata nell'area.
			# I player devono tenere premuto il tasto "hack".
			if is_bot and not _is_open and not _is_hacking:
				print("[DOOR] '%s' manual — bot '%s' (team %d) avvia hack automatico" % [name, entity.name, entity_team])
				if _is_hack_authority():
					start_hack(-1, entity_team)
				else:
					_request_hack_start.rpc_id(1, entity_team)
			else:
				print("[DOOR] '%s' manual — player '%s' nel raggio, attendo tasto hack" % [name, entity.name])
		DoorType.LOCKED:
			print("[DOOR] '%s' LOCKED — nessun accesso" % [name])

func _schedule_close() -> void:
	if not is_inside_tree():
		return
	if _close_timer and _close_timer.is_inside_tree() and _is_open and door_type != DoorType.LOCKED:
		_close_timer.start()

func _on_close_timer_timeout() -> void:
	if _entities_in_range.is_empty():
		_close_door()

# ---------------------------------------------------------------------------
# Apertura/Chiusura Porta
# ---------------------------------------------------------------------------

func _open_door() -> void:
	if _is_open:
		return
	_is_open = true

	# Disabilita collisione
	set_deferred("collision_layer", 0)
	if _collision_shape:
		_collision_shape.set_deferred("disabled", true)

	# Animazione
	if _door_sprite and _door_sprite.sprite_frames:
		if _door_sprite.sprite_frames.has_animation(&"Apertura"):
			_door_sprite.animation = &"Apertura"
			_door_sprite.play()

	# Suono
	if _sfx:
		_sfx.play()

	# Sincronizzazione multiplayer
	if _is_multiplayer_session():
		_sync_door_state.rpc(true)

	door_opened.emit()

func _close_door() -> void:
	if not _is_open:
		return
	_is_open = false

	# Riabilita collisione
	_apply_collision_layers()
	if _collision_shape:
		_collision_shape.set_deferred("disabled", false)

	# Animazione
	if _door_sprite and _door_sprite.sprite_frames:
		if _door_sprite.sprite_frames.has_animation(&"Chiusura"):
			_door_sprite.animation = &"Chiusura"
			_door_sprite.play()

	# Suono
	if _sfx:
		_sfx.play()

	# Sincronizzazione multiplayer
	if _is_multiplayer_session():
		_sync_door_state.rpc(false)

	door_closed.emit()

func _update_animation_speed() -> void:
	if not _door_sprite or not is_node_ready():
		return
	if _door_sprite.sprite_frames:
		if _door_sprite.sprite_frames.has_animation(&"Apertura"):
			_door_sprite.sprite_frames.set_animation_speed(&"Apertura", open_speed)
		if _door_sprite.sprite_frames.has_animation(&"Chiusura"):
			_door_sprite.sprite_frames.set_animation_speed(&"Chiusura", open_speed)

# ---------------------------------------------------------------------------
# Hacking
# ---------------------------------------------------------------------------

func _crea_hack_bar() -> void:
	# Pivot Node2D, figlio della porta stessa.
	# global_rotation = 0 assicura che la barra resti sempre orizzontale.
	var pivot := Node2D.new()
	pivot.name = "HackBarPivot"
	pivot.z_index = 1000
	pivot.z_as_relative = false
	add_child(pivot)
	pivot.global_position = global_position + Vector2(0, -hack_bar_vertical_offset)
	pivot.global_rotation = 0.0

	# ── Sfondo scuro con bordo ──────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.06, 0.06, 0.08, 0.92)
	bg.size = hack_bar_size + Vector2(6, 6)
	bg.position = -(hack_bar_size + Vector2(6, 6)) * 0.5
	pivot.add_child(bg)

	# ── Barra di riempimento (ColorRect che scala in X) ─────────────────────
	var bar_bg := ColorRect.new()
	bar_bg.name = "BarBG"
	bar_bg.color = Color(0.15, 0.15, 0.18, 1.0)
	bar_bg.size = hack_bar_size
	bar_bg.position = -hack_bar_size * 0.5
	pivot.add_child(bar_bg)

	var bar_fill := ColorRect.new()
	bar_fill.name = "BarFill"
	bar_fill.color = Color(0.0, 0.85, 1.0, 1.0)
	bar_fill.size = Vector2(0.0, hack_bar_size.y)
	bar_fill.position = -hack_bar_size * 0.5
	pivot.add_child(bar_fill)

	# ── Bordo sovrapposto ───────────────────────────────────────────────────
	var border := ColorRect.new()
	border.name = "Border"
	border.color = Color(0.0, 0.9, 1.0, 0.7)
	border.size = hack_bar_size + Vector2(4, 4)
	border.position = -(hack_bar_size + Vector2(4, 4)) * 0.5
	pivot.add_child(border)
	border.z_index = 1

	# ── Label percentuale ───────────────────────────────────────────────────
	var label := Label.new()
	label.name = "Label"
	label.size = hack_bar_size
	label.position = -hack_bar_size * 0.5
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 2
	pivot.add_child(label)

	_hack_bar_pivot = pivot
	_hack_bar_panel = pivot  ## Riuso _hack_bar_panel come riferimento al pivot per compatibilità

func _update_hack_bar() -> void:
	if not _hack_bar_pivot or not is_node_ready():
		return

	var fill := _hack_bar_pivot.get_node_or_null("BarFill") as ColorRect
	if fill:
		fill.size.x = hack_bar_size.x * _hack_bar_progress
		# Colore: blu freddo → verde al completamento
		fill.color = Color(0.0, 0.85, 1.0).lerp(Color(0.1, 1.0, 0.4), _hack_bar_progress)

	var label := _hack_bar_pivot.get_node_or_null("Label") as Label
	if label:
		label.text = "HACK %d%%" % int(_hack_bar_progress * 100.0)


func start_hack(peer_id: int = 0, entity_team: int = -1) -> void:
	if not is_hackable() or is_locked() or _is_hacking or _is_open:
		print("[HACK] '%s': start fallito (hackable=%s locked=%s hacking=%s open=%s)" % [name, is_hackable(), is_locked(), _is_hacking, _is_open])
		return
	print("[HACK] '%s': inizio hack — peer=%d team=%d durata=%.1fs" % [name, peer_id, entity_team, hack_duration])
	_is_hacking = true
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	_hack_peer_id = peer_id
	_hack_entity_team = entity_team
	if _hack_bar_pivot:
		print("[HACK] '%s': hack bar mostrata" % name)
		_hack_bar_pivot.visible = true
		_update_hack_bar()
	if _is_multiplayer_session():
		_sync_hack_started.rpc(peer_id, entity_team)
	hacking_started.emit()
	print("[HACK] '%s': hack avviato con successo!" % name)

func cancel_hack() -> void:
	if not _is_hacking:
		return
	_is_hacking = false
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	_hack_peer_id = 0
	_hack_entity_team = -1
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false
	if _is_multiplayer_session():
		_sync_hack_ended.rpc()

func _complete_hack() -> void:
	print("[HACK] _complete_hack chiamato")
	_is_hacking = false

	# Nascondi hack bar
	if _hack_bar_pivot:
		print("[HACK] Nascondo hack bar")
		_hack_bar_pivot.visible = false

	# Cambia team in base a CHI ha hackerato la porta. Se per qualche
	# motivo il team dell'entità non è determinabile (-1), uso il
	# fallback configurato in hack_target_team.
	var new_team := _hack_entity_team if _hack_entity_team >= 0 else hack_target_team
	var new_door_type := door_type
	if door_type == DoorType.LOCKED or door_type == DoorType.MANUAL:
		new_door_type = DoorType.AUTOMATIC

	if new_team != team_id:
		team_id = new_team
	if new_door_type != door_type:
		door_type = new_door_type
		_update_editor_preview()
	_hack_entity_team = -1

	if _is_multiplayer_session():
		_sync_hack_ended.rpc()
		# team_id/door_type non sono replicati automaticamente: li
		# sincronizzo esplicitamente su tutti i client.
		_sync_hack_completed.rpc(new_team, new_door_type)

	_open_door()
	hacking_completed.emit()

# ---------------------------------------------------------------------------
# Utility Team
# ---------------------------------------------------------------------------

func _get_team_id(node: Node) -> int:
	# Prima cerca nei gruppi team_X
	for group: String in node.get_groups():
		if group.begins_with("team_"):
			return int(group.get_slice("_", 1))
	# Fallback: proprietà diretta team_id
	if "team_id" in node:
		return int(node.get("team_id"))
	return -1

func _is_same_level(node: Node) -> bool:
	var node_level: int = livello
	if "livello" in node:
		node_level = node.get("livello")
	elif "current_height_level" in node:
		node_level = node.get("current_height_level")
	return node_level == livello

## Metodo pubblico per controllare il livello (usato da SoldatoBot)
func is_same_level(node: Node) -> bool:
	return _is_same_level(node)

func _on_team_changed() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	for group: String in get_groups():
		if group.begins_with("team_"):
			remove_from_group(group)
	add_to_group("team_" + str(team_id))
	_update_team_visuals()
	if not Engine.is_editor_hint():
		team_changed.emit(team_id)

func _update_team_visuals() -> void:
	if not is_node_ready():
		return
	if _door_sprite:
		match team_id:
			0: _door_sprite.modulate = Color.WHITE
			1: _door_sprite.modulate = Color(0.4, 0.8, 1.0)
			2: _door_sprite.modulate = Color(1.0, 0.4, 0.4)
			_: _door_sprite.modulate = Color(0.8, 0.8, 0.8)

# ---------------------------------------------------------------------------
# Collision layer/mask — identici a torrette
# ---------------------------------------------------------------------------

func _apply_collision_layers() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	if _is_open:
		collision_layer = 0
		collision_mask = 0
		return

	var base_layer    := livello * 3 + 1
	var wall_bit      := 1 << (base_layer - 1)
	var character_bit := 1 << base_layer

	# StaticBody2D (self): occupa il wall_layer
	collision_layer = wall_bit
	collision_mask = 0

	if _activation_area:
		_activation_area.collision_layer = 0
		_activation_area.collision_mask = wall_bit | character_bit

# ---------------------------------------------------------------------------
# Gruppi livello — identici a torrette
# ---------------------------------------------------------------------------

func _refresh_level_membership() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	for lv: int in _registered_levels:
		remove_from_group("entities_level_" + str(lv))
	_registered_levels.clear()
	add_to_group("entities_level_" + str(livello))
	_registered_levels.append(livello)

# ---------------------------------------------------------------------------
# Forma ActivationArea
# ---------------------------------------------------------------------------

func _update_activation_area_shape() -> void:
	if Engine.is_editor_hint() or not is_inside_tree() or not is_node_ready():
		return
	if _activation_shape and _activation_shape.shape is CircleShape2D:
		(_activation_shape.shape as CircleShape2D).radius = activation_range

# ---------------------------------------------------------------------------
# FPS boost
# ---------------------------------------------------------------------------

func _on_screen_entered() -> void:
	_screen_visible = true
	set_process(true)

func _on_screen_exited() -> void:
	_screen_visible = false
	set_process(_is_hacking)

# ---------------------------------------------------------------------------
# Impostazioni grafiche
# ---------------------------------------------------------------------------

func _setup_global_settings() -> void:
	var gs := get_node_or_null("/root/GlobalSettings")
	if gs:
		if gs.has_signal("settings_changed"):
			if not gs.settings_changed.is_connected(_on_settings_changed):
				gs.settings_changed.connect(_on_settings_changed)
		var preset: int = gs.call("get_setting", "graphics_preset", 2)
		_apply_graphics_settings(preset)

func _on_settings_changed(new_settings: Dictionary) -> void:
	_apply_graphics_settings(new_settings.get("graphics_preset", 2))

func _apply_graphics_settings(_preset: int) -> void:
	# Ombre PointLight2D - rimossi per compatibilità
	pass

# ---------------------------------------------------------------------------
# Connessione player per visibilità livello — identica a torrette
# ---------------------------------------------------------------------------

func is_visible_from_level(player_level: int) -> bool:
	return player_level == livello

func _connect_to_player() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	if not players.is_empty():
		var local_player: Node2D = null
		for p: Node in players:
			if p.has_method("is_multiplayer_authority") and p.is_multiplayer_authority():
				local_player = p as Node2D
				break
		if not local_player:
			local_player = players[0] as Node2D
		_setup_player_connection(local_player)
	else:
		get_tree().process_frame.connect(_connect_to_player, CONNECT_ONE_SHOT)

func _setup_player_connection(player: Node2D) -> void:
	_player_node = player
	if player.has_signal("height_level_changed"):
		if not player.height_level_changed.is_connected(_on_player_height_level_changed):
			player.height_level_changed.connect(_on_player_height_level_changed)
	if "current_height_level" in player:
		_apply_for_player_level(player.current_height_level)

func _on_player_height_level_changed(player_level: int) -> void:
	_apply_for_player_level(player_level)

func _apply_for_player_level(player_level: int) -> void:
	visible = is_visible_from_level(player_level)
	z_index = (player_level if is_visible_from_level(player_level) else livello) * 10 + 1

# ---------------------------------------------------------------------------
# Multiplayer
# ---------------------------------------------------------------------------

func _is_multiplayer_session() -> bool:
	var mm := get_node_or_null("/root/MultiplayerManager")
	if mm and mm.has_method("is_active_multiplayer_session"):
		return mm.call("is_active_multiplayer_session")
	return multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty()

## Vero se questo peer è "l'autorità" per le decisioni sull'hacking:
## il server in multiplayer, oppure sempre vero in single-player.
## Solo l'autorità può avviare/annullare/avanzare l'hacking in modo
## definitivo; gli altri client devono passare per le richieste RPC.
func _is_hack_authority() -> bool:
	return not _is_multiplayer_session() or multiplayer.is_server()

## RPC per sincronizzare lo stato della porta nel multiplayer
@rpc("authority", "call_local", "reliable")
func _sync_door_state(is_open_state: bool) -> void:
	if is_open_state:
		if not _is_open:
			_is_open = true
			set_deferred("collision_layer", 0)
			if _collision_shape:
				_collision_shape.set_deferred("disabled", true)
			if _door_sprite and _door_sprite.sprite_frames:
				if _door_sprite.sprite_frames.has_animation(&"Apertura"):
					_door_sprite.animation = &"Apertura"
					_door_sprite.play()
	else:
		if _is_open:
			_is_open = false
			_apply_collision_layers()
			if _collision_shape:
				_collision_shape.set_deferred("disabled", false)
			if _door_sprite and _door_sprite.sprite_frames:
				if _door_sprite.sprite_frames.has_animation(&"Chiusura"):
					_door_sprite.animation = &"Chiusura"
					_door_sprite.play()

## --- RPC hacking: richieste dei client al server ---------------------------

## Un client chiede al server di avviare l'hacking su questa porta.
## Il server accetta SOLO se nessun altro player la sta già hackerando:
## questo garantisce che, per quella porta, l'hack sia esclusivo di un
## singolo player/team alla volta.
@rpc("any_peer", "reliable")
func _request_hack_start(entity_team: int) -> void:
	if not multiplayer.is_server():
		return
	if _is_hacking:
		print("[HACK] Richiesta rifiutata: porta già occupata da peer %d" % _hack_peer_id)
		return
	var requester_id := multiplayer.get_remote_sender_id()
	start_hack(requester_id, entity_team)

## Un client chiede al server di annullare l'hacking che STA FACENDO LUI.
## Solo il player che possiede l'hack in corso può annullarlo.
@rpc("any_peer", "reliable")
func _request_hack_cancel() -> void:
	if not multiplayer.is_server():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	if not _is_hacking or _hack_peer_id != requester_id:
		return
	cancel_hack()

## --- RPC hacking: sincronizzazione dal server (autorità) a tutti i client --

## Notifica tutti i client che un hacking è iniziato su questa porta,
## da parte di un peer/team specifico.
@rpc("authority", "call_local", "reliable")
func _sync_hack_started(peer_id: int, entity_team: int) -> void:
	_is_hacking = true
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	_hack_peer_id = peer_id
	_hack_entity_team = entity_team
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = true
		_update_hack_bar()

## Notifica tutti i client del progresso corrente (chiamata ogni frame
## mentre l'autorità sta hackando; il valore è puramente visuale).
@rpc("authority", "call_local", "unreliable")
func _sync_hack_progress(progress: float) -> void:
	_hack_progress = progress
	_hack_bar_progress = clampf(_hack_progress / hack_duration, 0.0, 1.0)
	_update_hack_bar()

## Notifica tutti i client che l'hacking è terminato (annullato o
## completato — l'apertura/team della porta arriva separatamente
## tramite _sync_door_state e la proprietà team_id sincronizzata).
@rpc("authority", "call_local", "reliable")
func _sync_hack_ended() -> void:
	_is_hacking = false
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	_hack_peer_id = 0
	_hack_entity_team = -1
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false

## Sincronizza il completamento dell'hack con il nuovo team e door_type
@rpc("authority", "call_local", "reliable")
func _sync_hack_completed(new_team: int, new_door_type: int) -> void:
	team_id = new_team
	door_type = new_door_type as DoorType
	_on_team_changed()
	_update_editor_preview()

# ---------------------------------------------------------------------------
# API pubblica
# ---------------------------------------------------------------------------

## Apre la porta manualmente (per script/trigger)
func open_door() -> void:
	_open_door()

## Chiude la porta manualmente (per script/trigger)
func close_door() -> void:
	_close_door()

## Blocca/sblocca la porta
func set_locked(p_locked: bool) -> void:
	door_type = DoorType.LOCKED if p_locked else DoorType.AUTOMATIC
	_update_editor_preview()

## Verifica se la porta è aperta
func is_door_open() -> bool:
	return _is_open

## Verifica se la porta è bloccata
func is_door_locked() -> bool:
	return is_locked()

## Setup NavigationObstacle2D — crea l'ostacolo solo per porte LOCKED
## per escluderle dalla NavMesh e far sì che i bot le aggirino.
func _setup_nav_obstacle() -> void:
	# Rimuove un eventuale ostacolo precedente
	if _nav_obstacle and is_instance_valid(_nav_obstacle):
		_nav_obstacle.queue_free()
		_nav_obstacle = null
	if door_type != DoorType.LOCKED:
		return
	_nav_obstacle = NavigationObstacle2D.new()
	_nav_obstacle.avoidance_enabled = false
	## Abilita la bake della maschera sulla NavMesh statica
	_nav_obstacle.affect_navigation_mesh = true
	_nav_obstacle.carve_navigation_mesh = true
	_nav_obstacle.navigation_layers = 1 << livello
	## Forma rettangolare proporzionale alla CollisionShape
	var half: float = 50.0
	if _collision_shape and _collision_shape.shape:
		if _collision_shape.shape is RectangleShape2D:
			half = maxf((_collision_shape.shape as RectangleShape2D).size.x,
					   (_collision_shape.shape as RectangleShape2D).size.y) * 0.5
		elif _collision_shape.shape is CircleShape2D:
			half = (_collision_shape.shape as CircleShape2D).radius
	_nav_obstacle.vertices = PackedVector2Array([
		Vector2(-half, -half),
		Vector2( half, -half),
		Vector2( half,  half),
		Vector2(-half,  half)
	])
	add_child(_nav_obstacle)

# ---------------------------------------------------------------------------
# Editor
# ---------------------------------------------------------------------------

func _update_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	visible = true
	z_index = livello * 10 + 1
	update_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if auto_close_delay < 0.0:
		w.append("auto_close_delay deve essere >= 0.")
	if hack_duration < 0.5:
		w.append("hack_duration deve essere >= 0.5.")
	if activation_range < 10.0:
		w.append("activation_range deve essere >= 10.0.")
	return w

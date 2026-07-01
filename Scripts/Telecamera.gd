## Telecamera.gd
## Telecamera di sorveglianza per Godot 4.x — v1
##
## Funzionalità:
## - Rileva nemici in un raggio ampio
## - Usa RayCast per line-of-sight (non vede dietro muri)
## - Broadcasta posizioni nemiche via segnale globale
## - Hackabile come le porte (cambia team)
## - Distruttibile con esplosione

@tool
extends Area2D
class_name Telecamera

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------

signal team_changed(new_team_id: int)
signal enemy_detected(enemy: Node2D, position: Vector2)
signal hacking_started()
signal hacking_completed(new_team_id: int)
signal destroyed()

# ---------------------------------------------------------------------------
# Export — Telecamera
# ---------------------------------------------------------------------------

@export_group("Telecamera")

@export var team_id: int = 0:
	set(value):
		team_id = value
		_on_team_changed()
		_update_editor_preview()

@export var vita_max: float = 30.0

@export_group("Rilevamento")

@export var detection_range: float = 800.0:
	set(value):
		detection_range = maxf(value, 0.0)
		_update_detection_area_shape()
		_update_editor_preview()

@export var scan_interval: float = 0.5  ## Secondi tra ogni scan

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

@export var hack_bar_vertical_offset: float = 50.0

@export var hack_bar_size: Vector2 = Vector2(48.0, 20.0)

@export var hack_input_action: String = "hack"

@export_group("Esplosione")

@export var explosion_damage: float = 50.0
@export var explosion_radius: float = 400.0

# ---------------------------------------------------------------------------
# Risorse precaricate
# ---------------------------------------------------------------------------

const DASHED_CIRCLE_SHADER := preload("res://Shaders/dashed_circle.gdshader")

# ---------------------------------------------------------------------------
# Stato interno
# ---------------------------------------------------------------------------

var vita: float = 0.0
var _is_dead: bool = false
var _is_hacking: bool = false
var _hack_progress: float = 0.0
var _hack_peer_id: int = 0
var _hack_entity_team: int = -1
var _entities_in_range: Array[Node2D] = []
var _registered_levels: Array[int] = []
var _player_node: Node2D = null
var _screen_visible: bool = true
var _scan_timer: float = 0.0
var _hack_bar_progress: float = 0.0

# Materiali shader
var _danger_indicator: ColorRect = null
var _shader_material: ShaderMaterial = null
var _point_light: PointLight2D = null

# Nodi hack bar
var _hack_bar_pivot: Node2D = null
var _hack_bar_panel: Panel = null

# ---------------------------------------------------------------------------
# Riferimenti ai nodi
# ---------------------------------------------------------------------------

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _ray_cast: RayCast2D = $RayCast2D
@onready var _detection_area: Area2D = $DetectionArea
@onready var _detection_shape: CollisionShape2D = $DetectionArea/DetectionShape
@onready var _anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _particles: CPUParticles2D = $ExplosionParticles
@onready var _screen_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D

# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()
		return

	vita = vita_max

	# Gruppi
	add_to_group("objects")
	add_to_group("damageable")
	_on_team_changed()
	_refresh_level_membership()
	_apply_collision_layers()
	_update_detection_area_shape()

	# ── Indicatore dashed circle (come mina.gd) ──
	var explosion_rad := explosion_radius
	var rect_size := explosion_rad * 2.5
	_danger_indicator = ColorRect.new()
	_danger_indicator.size = Vector2(rect_size, rect_size)
	_danger_indicator.position = -_danger_indicator.size / 2.0
	_danger_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = DASHED_CIRCLE_SHADER
	_shader_material.set_shader_parameter("quality", 1.0)
	_danger_indicator.material = _shader_material
	add_child(_danger_indicator)
	move_child(_danger_indicator, 0)

	# ── PointLight2D (come mina.gd) ──
	_point_light = PointLight2D.new()
	var tex = GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad = Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	tex.gradient = grad
	tex.width = int(explosion_rad * 2.5)
	tex.height = int(explosion_rad * 2.5)
	_point_light.texture = tex
	_point_light.blend_mode = Light2D.BLEND_MODE_ADD
	_point_light.energy = 0.4
	add_child(_point_light)

	# Segnali DetectionArea
	_detection_area.body_entered.connect(_on_detection_body_entered)
	_detection_area.body_exited.connect(_on_detection_body_exited)
	_detection_area.area_entered.connect(_on_detection_area_entered)
	_detection_area.area_exited.connect(_on_detection_area_exited)

	# FPS boost
	_screen_notifier.screen_entered.connect(_on_screen_entered)
	_screen_notifier.screen_exited.connect(_on_screen_exited)

	# Impostazioni grafiche
	_setup_global_settings()

	# Collegamento player per livello
	_connect_to_player()

	# Crea HackBarPivot
	_hack_bar_pivot = get_node_or_null("HackBarPivot")
	if not _hack_bar_pivot:
		_crea_hack_bar()

	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _is_dead:
		if _danger_indicator and _danger_indicator.visible:
			_danger_indicator.visible = false
		if _point_light and _point_light.visible:
			_point_light.visible = false
		return

	# Hacking
	var am_authority := _is_hack_authority()

	if not _is_hacking:
		var local_entity := _get_local_hacking_entity()
		var hack_held := local_entity != null and Input.is_action_pressed(hack_input_action)
		var my_peer_id := multiplayer.get_unique_id() if _is_multiplayer_session() else 0

		if hack_held and not _is_hacking:
			var entity_team := _get_team_id(local_entity)
			if am_authority:
				start_hack(my_peer_id, entity_team)
			else:
				_request_hack_start.rpc_id(1, entity_team)
		elif not hack_held and _is_hacking and _hack_peer_id == my_peer_id:
			if am_authority:
				cancel_hack()
			else:
				_request_hack_cancel.rpc_id(1)

	# Avanzamento progresso: SOLO lato autorità
	if am_authority and _is_hacking:
		_hack_progress += delta
		_hack_bar_progress = clampf(_hack_progress / hack_duration, 0.0, 1.0)
		_update_hack_bar()
		if _is_multiplayer_session():
			_sync_hack_progress.rpc(_hack_progress)
		if _hack_progress >= hack_duration:
			_complete_hack()

	# Scansione nemici
	_scan_timer += delta
	if _scan_timer >= scan_interval:
		_scan_timer = 0.0
		_scan_for_enemies()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _is_dead or _is_hacking:
		return
	if not _screen_visible:
		return

# ---------------------------------------------------------------------------
# Sistema rilevamento — event-driven via Area2D
# ---------------------------------------------------------------------------

func _on_detection_body_entered(body: Node2D) -> void:
	if _is_enemy(body) and _is_same_level(body):
		if body not in _entities_in_range:
			_entities_in_range.append(body)

func _on_detection_body_exited(body: Node2D) -> void:
	_entities_in_range.erase(body)

func _on_detection_area_entered(area: Area2D) -> void:
	if _is_enemy(area) and _is_same_level(area):
		if area not in _entities_in_range:
			_entities_in_range.append(area)

func _on_detection_area_exited(area: Area2D) -> void:
	_entities_in_range.erase(area)

## Scansiona i nemici nel raggio e broadcasta posizioni
func _scan_for_enemies() -> void:
	if _is_dead or _is_hacking:
		return

	# Filtra entity valide
	_entities_in_range = _entities_in_range.filter(
		func(n: Node2D) -> bool:
			return is_instance_valid(n) and _is_enemy(n) and _is_same_level(n)
	)

	# Per ogni nemico, verifica line-of-sight con RayCast
	for enemy: Node2D in _entities_in_range:
		if not is_instance_valid(enemy):
			continue

		var dir := global_position.direction_to(enemy.global_position)

		# Configura RayCast
		var ray_end_local := to_local(global_position + dir * detection_range)
		_ray_cast.target_position = ray_end_local
		_ray_cast.force_raycast_update()

		# Verifica se il RayCast colpisce il nemico (nessun ostacolo)
		if _ray_cast.is_colliding():
			var collider := _ray_cast.get_collider()
			if collider == enemy or _is_part_of_enemy(collider, enemy):
				# Line-of-sight chiara: broadcasta posizione
				_broadcast_enemy_position(enemy)

## Broadcasta la posizione di un nemico a tutti i bot/player/oggetti
func _broadcast_enemy_position(enemy: Node2D) -> void:
	emit_signal("enemy_detected", enemy, enemy.global_position)

	# Notifica tutti i bot nel raggio ampio
	var alert_radius := detection_range
	for bot: Node in get_tree().get_nodes_in_group("bots"):
		if not is_instance_valid(bot):
			continue
		var bot_pos: Vector2 = bot.global_position if bot is Node2D else Vector2.ZERO
		if global_position.distance_to(bot_pos) < alert_radius:
			if bot.has_method("on_enemy_spotted"):
				bot.call_deferred("on_enemy_spotted", enemy.global_position, enemy)

	# Notifica tutti i player
	for player: Node in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player):
			continue
		var player_pos: Vector2 = player.global_position if player is Node2D else Vector2.ZERO
		if global_position.distance_to(player_pos) < alert_radius:
			if player.has_method("on_camera_alert"):
				player.call_deferred("on_camera_alert", enemy.global_position, enemy)

## Verifica se il collider fa parte del nemico (es. child node)
func _is_part_of_enemy(collider: Node, enemy: Node) -> bool:
	var current := collider
	var limit := 4
	while current and limit > 0:
		if current == enemy:
			return true
		current = current.get_parent()
		limit -= 1
	return false

# ---------------------------------------------------------------------------
# Hacking
# ---------------------------------------------------------------------------

func _crea_hack_bar() -> void:
	var pivot := Node2D.new()
	pivot.name = "HackBarPivot"
	pivot.z_index = 1000
	pivot.z_as_relative = false
	add_child(pivot)

	pivot.global_position = global_position + Vector2(0, -hack_bar_vertical_offset)
	pivot.global_rotation = 0.0

	var panel := Panel.new()
	panel.name = "Panel"
	panel.position = -hack_bar_size * 0.5
	panel.size = hack_bar_size
	pivot.add_child(panel)

	var progress_bar := ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	panel.add_child(progress_bar)

	var label := Label.new()
	label.name = "Label"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	panel.add_child(label)

	_hack_bar_pivot = pivot
	_hack_bar_panel = panel

func _update_hack_bar() -> void:
	if not _hack_bar_pivot or not is_node_ready():
		return

	if _hack_bar_panel:
		var progress_bar := _hack_bar_panel.get_node_or_null("ProgressBar")
		if progress_bar:
			progress_bar.value = _hack_bar_progress * 100.0

		var label := _hack_bar_panel.get_node_or_null("Label")
		if label:
			label.text = str(int(_hack_bar_progress * 100.0)) + "%"

func _get_local_hacking_entity() -> Node2D:
	for entity: Node2D in _entities_in_range:
		if not is_instance_valid(entity):
			continue
		if entity.has_method("is_multiplayer_authority") and entity.is_multiplayer_authority():
			return entity
	return null

func start_hack(peer_id: int = 0, entity_team: int = -1) -> void:
	if _is_dead or _is_hacking:
		return
	_is_hacking = true
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	_hack_peer_id = peer_id
	_hack_entity_team = entity_team
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = true
		_update_hack_bar()
	if _is_multiplayer_session():
		_sync_hack_started.rpc(peer_id, entity_team)
	hacking_started.emit()

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
	_is_hacking = false

	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false

	var new_team := _hack_entity_team if _hack_entity_team >= 0 else hack_target_team
	if new_team != team_id:
		team_id = new_team
	_hack_entity_team = -1

	if _is_multiplayer_session():
		_sync_hack_ended.rpc()
		_sync_hack_completed.rpc(new_team)

	hacking_completed.emit(team_id)

# ---------------------------------------------------------------------------
# Danno e distruzione
# ---------------------------------------------------------------------------

func apply_damage(amount: float, _source: Node = null) -> void:
	if _is_dead or vita <= 0.0:
		return

	vita = maxf(vita - amount, 0.0)
	if vita <= 0.0:
		if _is_multiplayer_session():
			_die_rpc.rpc()
		else:
			_die()

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_is_hacking = false
	_entities_in_range.clear()

	# Disabilita collisioni
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	_detection_area.set_deferred("collision_layer", 0)
	_detection_area.set_deferred("collision_mask", 0)

	# Nasconde indicatori
	if _danger_indicator:
		_danger_indicator.visible = false
	if _point_light:
		_point_light.visible = false

	# Rimuove shader per esplosione pulita
	if _sprite:
		_sprite.material = null

	# ── Animazione esplosione ──
	var radius := explosion_radius
	if _anim_sprite and _anim_sprite.sprite_frames \
			and _anim_sprite.sprite_frames.has_animation(&"Esplosione"):
		_anim_sprite.animation = &"Esplosione"
		var target_scale := (radius * 2.0 * 1.4) / 256.0
		_anim_sprite.scale = Vector2(target_scale, target_scale)
		_anim_sprite.visible = true
		_anim_sprite.play()
		_anim_sprite.animation_finished.connect(
			func() -> void: _anim_sprite.visible = false, CONNECT_ONE_SHOT
		)

	# ── Particelle esplosione ──
	var global_settings := get_node_or_null("/root/GlobalSettings")
	var preset := 2
	if global_settings:
		preset = global_settings.call("get_setting", "graphics_preset", 2)

	if _particles and preset > 0:
		_particles.emission_sphere_radius = radius
		_particles.initial_velocity_min = radius * 0.4
		_particles.initial_velocity_max = radius * 1.2
		_particles.scale_amount_min = maxf(4.0, radius * 0.015)
		_particles.scale_amount_max = maxf(12.0, radius * 0.045)
		_particles.emitting = true

	# Danno esplosivo (come mina)
	if not _is_multiplayer_session() or multiplayer.is_server():
		for body: Node in get_tree().get_nodes_in_group("damageable"):
			if body == self:
				continue
			if not body.has_method("apply_damage"):
				continue

			var target_level: int = livello
			if "livello" in body:
				target_level = body.get("livello")
			elif "current_height_level" in body:
				target_level = body.get("current_height_level")

			if target_level != livello:
				continue

			var target := body as Node2D
			if target == null:
				continue
			var dist: float = global_position.distance_to(target.global_position)
			if dist > radius:
				continue
			var falloff: float = 1.0 - (dist / radius)
			body.call("apply_damage", explosion_damage * falloff)

	await get_tree().create_timer(0.8).timeout
	queue_free()

	destroyed.emit()

@rpc("authority", "call_local", "reliable")
func _die_rpc() -> void:
	_die()

# ---------------------------------------------------------------------------
# Utility Team
# ---------------------------------------------------------------------------

func _get_team_id(node: Node) -> int:
	for group: String in node.get_groups():
		if group.begins_with("team_"):
			return int(group.get_slice("_", 1))
	if "team_id" in node:
		return int(node.get("team_id"))
	return -1

func _is_enemy(node: Node) -> bool:
	if not node.is_in_group("damageable"):
		return false
	if node == self:
		return false
	
	var node_team := _get_team_id(node)
	if node_team == -1:
		return false
	return node_team != team_id

func _is_same_level(node: Node) -> bool:
	var node_level: int = livello
	if "livello" in node:
		node_level = node.get("livello")
	elif "current_height_level" in node:
		node_level = node.get("current_height_level")
	return node_level == livello

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
	if _sprite:
		match team_id:
			0: _sprite.modulate = Color.WHITE
			1: _sprite.modulate = Color(0.4, 0.8, 1.0)
			2: _sprite.modulate = Color(1.0, 0.4, 0.4)
			_: _sprite.modulate = Color(0.8, 0.8, 0.8)

# ---------------------------------------------------------------------------
# Collision layer/mask
# ---------------------------------------------------------------------------

func _apply_collision_layers() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	var base_layer := livello * 3 + 1
	var wall_bit := 1 << (base_layer - 1)
	var character_bit := 1 << base_layer

	# Area2D: rilevamento nemici
	collision_layer = 0
	collision_mask = wall_bit | character_bit

	if _detection_area:
		_detection_area.collision_layer = 0
		_detection_area.collision_mask = wall_bit | character_bit

	if _ray_cast:
		_ray_cast.collision_mask = wall_bit | character_bit

# ---------------------------------------------------------------------------
# Gruppi livello
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
# Forma DetectionArea
# ---------------------------------------------------------------------------

func _update_detection_area_shape() -> void:
	if Engine.is_editor_hint() or not is_inside_tree() or not is_node_ready():
		return
	if _detection_shape and _detection_shape.shape is CircleShape2D:
		(_detection_shape.shape as CircleShape2D).radius = detection_range

# ---------------------------------------------------------------------------
# FPS boost
# ---------------------------------------------------------------------------

func _on_screen_entered() -> void:
	_screen_visible = true
	set_process(true)
	set_physics_process(true)

func _on_screen_exited() -> void:
	_screen_visible = false
	set_process(_is_hacking)
	set_physics_process(false)

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

func _apply_graphics_settings(preset: int) -> void:
	if _shader_material:
		_shader_material.set_shader_parameter("quality", 0.0 if preset == 0 else 1.0)

	if _point_light:
		_point_light.shadow_enabled = (preset >= 3)

	if _anim_sprite and _anim_sprite.sprite_frames \
			and _anim_sprite.sprite_frames.has_animation(&"Esplosione"):
		match preset:
			0: _anim_sprite.sprite_frames.set_animation_speed(&"Esplosione", 6.0)
			1: _anim_sprite.sprite_frames.set_animation_speed(&"Esplosione", 9.0)
			_: _anim_sprite.sprite_frames.set_animation_speed(&"Esplosione", 12.0)

	if _particles:
		match preset:
			0: _particles.amount = 1
			1: _particles.amount = 40
			_: _particles.amount = 120

# ---------------------------------------------------------------------------
# Connessione player per visibilità livello
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

func _is_hack_authority() -> bool:
	return not _is_multiplayer_session() or multiplayer.is_server()

@rpc("any_peer", "reliable")
func _request_hack_start(entity_team: int) -> void:
	if not multiplayer.is_server():
		return
	if _is_hacking:
		return
	var requester_id := multiplayer.get_remote_sender_id()
	start_hack(requester_id, entity_team)

@rpc("any_peer", "reliable")
func _request_hack_cancel() -> void:
	if not multiplayer.is_server():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	if not _is_hacking or _hack_peer_id != requester_id:
		return
	cancel_hack()

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

@rpc("authority", "call_local", "unreliable")
func _sync_hack_progress(progress: float) -> void:
	_hack_progress = progress
	_hack_bar_progress = clampf(_hack_progress / hack_duration, 0.0, 1.0)
	_update_hack_bar()

@rpc("authority", "call_local", "reliable")
func _sync_hack_ended() -> void:
	_is_hacking = false
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	_hack_peer_id = 0
	_hack_entity_team = -1
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false

@rpc("authority", "call_local", "reliable")
func _sync_hack_completed(new_team: int) -> void:
	team_id = new_team
	_on_team_changed()

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
	if vita_max <= 0.0:
		w.append("vita_max deve essere > 0.")
	if hack_duration < 0.5:
		w.append("hack_duration deve essere >= 0.5.")
	if detection_range < 50.0:
		w.append("detection_range deve essere >= 50.0.")
	return w

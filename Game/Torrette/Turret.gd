## turret.gd
## Torretta autonoma per Godot 4.x — v2
##
## Proiettili:  sistema hitscan identico al player (ProjectileVisual).
## Laser beam:  Line2D con shader attivato quando un target entra nell'area.
## Esplosione:  identica a mina.gd (AnimatedSprite2D + CPUParticles2D + GlobalSettings).
## Indicatori:  dashed_circle shader + PointLight2D come mina.gd.
## Team/Livello: pattern identico a mina.gd.
## Hacking:     barra disegnata via _draw().

@tool
extends StaticBody2D
class_name Turret

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------

signal team_changed(new_team_id: int)
signal target_acquired(target: Node2D)
signal target_lost()
signal hacking_started()
signal hacking_completed(new_team_id: int)
signal destroyed()
signal noise_emitted(pos: Vector2, noise_radius: float)

# ---------------------------------------------------------------------------
# Export — Torretta
# ---------------------------------------------------------------------------

@export_group("Torretta")

@export var team_id: int = 0:
	set(value):
		team_id = value
		_on_team_changed()
		_update_editor_preview()

@export var vita_max: float = 40.0
@export var danno: float = 25.0
@export var cadenza_fuoco: float = 0.4        ## Secondi tra un colpo e l'altro
@export var shot_range: float = 1600.0        ## Portata massima del RayCast/proiettile
@export var projectile_visual_speed: float    = 2200.0

@export_group("Raggio Azione")

@export var raggio_azione: float = 400.0:
	set(value):
		raggio_azione = maxf(value, 0.0)
		_update_action_area_shape()
		_update_editor_preview()

@export_group("Livello")

@export_range(0, 15, 1) var livello: int = 0:
	set(value):
		livello = maxi(value, 0)
		_refresh_level_membership()
		_apply_collision_layers()
		_update_editor_preview()

@export_group("Hacking")

@export var hackable: bool        = true
@export var hack_duration: float  = 5.0   ## Secondi per completare l'hack
@export var hack_bar_vertical_offset: float = 80.0  ## Distanza (px) sopra la torretta a cui mostrare la progress bar
@export var hack_bar_size: Vector2 = Vector2(160.0, 34.0)  ## Larghezza/altezza della progress bar
@export var activation_range: float = 120.0  ## Raggio per attivare l'hacking

@export_group("Difficoltà")
## 0=Facile 1=Normale 2=Difficile 3=Agente Caduto
@export_range(0, 3, 1) var difficulty_level: int = 1
## Se true, legge la difficoltà da GlobalSettings automaticamente.
@export var use_global_difficulty: bool = true

## Moltiplicatori difficoltà — [Facile, Normale, Difficile, Agente Caduto]
const DIFFICULTY_MULTIPLIERS: Array[Dictionary] = [
	{ "danno": 0.65, "vita": 0.65, "cadenza": 1.3, "raggio": 0.85, "hack_duration": 0.8 },
	{ "danno": 1.00, "vita": 1.00, "cadenza": 1.0, "raggio": 1.00, "hack_duration": 1.0 },
	{ "danno": 1.35, "vita": 1.35, "cadenza": 0.85, "raggio": 1.15, "hack_duration": 1.2 },
	{ "danno": 1.80, "vita": 1.80, "cadenza": 0.7, "raggio": 1.30, "hack_duration": 1.5 },
]

# ---------------------------------------------------------------------------
# Risorse precaricate
# ---------------------------------------------------------------------------

const PROJECTILE_VISUAL_SCENE := preload("res://Scenes/projectile_visual.tscn")
const DASHED_CIRCLE_SHADER    := preload("res://Shaders/dashed_circle.gdshader")
const LASER_BEAM_SHADER       := preload("res://Shaders/laser_beam.gdshader")

# ---------------------------------------------------------------------------
# UI / Hacking Bar
# ---------------------------------------------------------------------------

var _hack_bar_pivot: Node2D = null
var _hack_bar_progress: float = 0.0
var _hack_target_team: int = 1  ## Team a cui passa dopo l'hack (gestito dinamicamente)
var _entities_in_hacking_range: Array[Node2D] = []
var _hacking_body: Node2D = null  ## Entità che sta attualmente effettuando l'hack

# ---------------------------------------------------------------------------
# Stato interno
# ---------------------------------------------------------------------------

var vita: float                      = 0.0
var _target: Node2D                  = null
var _targets_in_range: Array[Node2D] = []
var _is_dead: bool                   = false
var _is_hacking: bool                = false
var _hack_progress: float            = 0.0
var _can_shoot: bool                 = true
var _registered_levels: Array[int]   = []
var _player_node: Node2D             = null
var _screen_visible: bool            = true
var _last_shot_time: float           = -1000.0
var _deployer_peer_id: int           = 0  ## Peer ID del player che ha piazzato la torretta

# Materiali shader (inizializzati in _ready)
var _danger_indicator: ColorRect      = null
var _shader_material: ShaderMaterial  = null
var _point_light: PointLight2D        = null
var _laser_shader_mat: ShaderMaterial = null

# ---------------------------------------------------------------------------
# Riferimenti ai nodi
# ---------------------------------------------------------------------------

@onready var _base_sprite    : Sprite2D                  = $BaseSprite
@onready var _gun_sprite     : Node2D                    = $GunSprite
@onready var _ray_cast       : RayCast2D                 = $RayCast2D
@onready var _action_area    : Area2D                    = $ActionArea
@onready var _action_shape   : CollisionShape2D          = $ActionArea/ActionShape
@onready var _reload_timer   : Timer                     = $ReloadTimer
@onready var _anim_sprite    : AnimatedSprite2D          = $AnimatedSprite2D
@onready var _particles      : CPUParticles2D            = $ExplosionParticles
@onready var _sfx_shoot      : AudioStreamPlayer2D       = $SfxShoot
@onready var _sfx_explosion  : AudioStreamPlayer2D       = $SfxExplosion
@onready var _screen_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D
@onready var _laser_line     : Line2D                    = $GunSprite/LaserLine

# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()
		return

	# Risolvi e applica difficoltà
	_resolve_difficulty()
	_apply_difficulty()
	vita = vita_max

	# Gruppi
	add_to_group("objects")
	add_to_group("damageable")
	add_to_group("noise_makers")
	_on_team_changed()
	_refresh_level_membership()
	_apply_collision_layers()
	_update_action_area_shape()

	# ── Indicatore dashed circle (come mina.gd) ──
	var explosion_rad := raggio_azione
	var rect_size     := explosion_rad * 2.5
	_danger_indicator             = ColorRect.new()
	_danger_indicator.size        = Vector2(rect_size, rect_size)
	_danger_indicator.position    = -_danger_indicator.size / 2.0
	_danger_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_material              = ShaderMaterial.new()
	_shader_material.shader       = DASHED_CIRCLE_SHADER
	_shader_material.set_shader_parameter("quality", 1.0)
	_danger_indicator.material    = _shader_material
	add_child(_danger_indicator)
	move_child(_danger_indicator, 0)

	# ── PointLight2D (come mina.gd) ──
	_point_light = PointLight2D.new()
	var tex             = GradientTexture2D.new()
	tex.fill            = GradientTexture2D.FILL_RADIAL
	tex.fill_from       = Vector2(0.5, 0.5)
	tex.fill_to         = Vector2(0.5, 0.0)
	var grad            = Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	tex.gradient        = grad
	tex.width           = int(explosion_rad * 2.5)
	tex.height          = int(explosion_rad * 2.5)
	_point_light.texture     = tex
	_point_light.blend_mode  = Light2D.BLEND_MODE_ADD
	_point_light.energy      = 0.4
	add_child(_point_light)

	# ── Laser beam shader ──
	_laser_shader_mat         = ShaderMaterial.new()
	_laser_shader_mat.shader  = LASER_BEAM_SHADER
	_laser_shader_mat.set_shader_parameter("quality", 1.0)
	if _laser_line:
		_laser_line.material = _laser_shader_mat
		_laser_line.visible  = false

	# Segnali ActionArea
	_action_area.body_entered.connect(_on_action_body_entered)
	_action_area.body_exited.connect(_on_action_body_exited)
	_action_area.area_entered.connect(_on_action_area_entered)
	_action_area.area_exited.connect(_on_action_area_exited)

	# Timer ricarica
	_reload_timer.wait_time = cadenza_fuoco
	_reload_timer.one_shot  = true
	_reload_timer.timeout.connect(_on_reload_timeout)

	# FPS boost
	_screen_notifier.screen_entered.connect(_on_screen_entered)
	_screen_notifier.screen_exited.connect(_on_screen_exited)

	_ray_cast.enabled = false

	# Impostazioni grafiche
	_setup_global_settings()

	# Collegamento player per livello
	_connect_to_player()

	# Inizializza hack bar
	_crea_hack_bar()
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false

	# Setup area di hacking

# ---------------------------------------------------------------------------
# Sistema Difficoltà
# ---------------------------------------------------------------------------

func _resolve_difficulty() -> void:
	if use_global_difficulty:
		var global_settings = get_node_or_null("/root/GlobalSettings")
		if global_settings:
			difficulty_level = global_settings.call("get_setting", "difficulty", 1)
	# In multiplayer, forza sempre difficoltà normale (1)
	if _is_multiplayer_session():
		difficulty_level = 1

func _apply_difficulty() -> void:
	var mults = DIFFICULTY_MULTIPLIERS[clampi(difficulty_level, 0, DIFFICULTY_MULTIPLIERS.size() - 1)]
	danno *= mults["danno"]
	vita_max *= mults["vita"]
	cadenza_fuoco *= mults["cadenza"]
	raggio_azione *= mults["raggio"]
	hack_duration *= mults["hack_duration"]

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
	if _is_hacking:
		_hack_progress += delta
		_hack_bar_progress = clampf(_hack_progress / hack_duration, 0.0, 1.0)
		_update_hack_bar()
		if _hack_progress >= hack_duration:
			_complete_hack()
		return

	# Gestione hacking da parte del player (tiene premuto il tasto hack nel raggio)
	if hackable and not _is_hacking:
		for body in _entities_in_hacking_range:
			if not is_instance_valid(body):
				continue
			if not body.is_in_group("players"):
				continue
			var player_team := _get_team_id(body)
			if player_team == team_id:
				continue  # Ormai alleato (es. torretta appena hackerata): niente barra
			if Input.is_action_pressed("hack"):
				print("[TURRET] Player (team %d) inizia hack torretta (team %d)" % [player_team, team_id])
				start_hack(player_team, body)
				break

	# Aggiorna effetti prossimità (come mina.gd)
	_update_proximity_effects()

	# Orientamento verso il target
	if _target != null and is_instance_valid(_target):
		var dir := global_position.direction_to(_target.global_position)
		_gun_sprite.rotation = dir.angle()
		_update_laser_line(dir)
	else:
		_pick_best_target()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _is_dead or _is_hacking:
		return
	if not _screen_visible:
		return
	if _target != null and is_instance_valid(_target) and _can_shoot:
		_try_shoot()

# (La barra di hacking è ora disegnata tramite nodi UI, rimosso _draw)

# ---------------------------------------------------------------------------
# Effetti prossimità — identici a mina.gd
# ---------------------------------------------------------------------------

func _update_proximity_effects() -> void:
	if not _player_node or not is_instance_valid(_player_node):
		return
	var dist      := global_position.distance_to(_player_node.global_position)
	var trigger   := raggio_azione * 1.5

	var is_friendly := false
	var player_team := _get_team_id(_player_node)
	if player_team != -1 and player_team == team_id:
		is_friendly = true

	var target_color   := Color(0.0, 1.0, 0.0) if is_friendly else Color(1.0, 0.2, 0.2)
	var base_safe_col  := Color(1.0, 1.0, 1.0)
	var deep_safe_col  := Color(0.2, 0.5, 1.0)

	if dist < trigger:
		var danger := 1.0 - (dist / trigger)
		if _point_light:
			_point_light.color  = target_color
			_point_light.energy = lerpf(0.6, 1.2, clampf(danger, 0.0, 1.0))
		if _danger_indicator:
			_danger_indicator.color = target_color
	else:
		var breathe_val  := (sin(Time.get_ticks_msec() * 0.003) * 0.5) + 0.5
		var breathed_col := base_safe_col.lerp(deep_safe_col, breathe_val)
		if _point_light:
			_point_light.color  = breathed_col
			_point_light.energy = (sin(Time.get_ticks_msec() * 0.003) * 0.15) + 0.3
		if _danger_indicator:
			_danger_indicator.color = breathed_col

# ---------------------------------------------------------------------------
# Laser Line — aggiornamento visivo
# ---------------------------------------------------------------------------

func _update_laser_line(dir: Vector2) -> void:
	if not _laser_line:
		return
	if not _laser_line.visible:
		return

	# Calcola punto di impatto tramite RayCast (aggiornamento leggero)
	var ray_end_local := to_local(global_position + dir * raggio_azione)
	_ray_cast.target_position = ray_end_local
	_ray_cast.force_raycast_update()

	var end_local: Vector2
	if _ray_cast.is_colliding():
		end_local = _gun_sprite.to_local(_ray_cast.get_collision_point())
	else:
		end_local = _gun_sprite.to_local(global_position + dir * raggio_azione)

	_laser_line.set_point_position(0, Vector2.ZERO)
	_laser_line.set_point_position(1, end_local)

	# Colore laser in base al team
	var lc := _get_laser_color()
	_laser_shader_mat.set_shader_parameter("color", lc)

func _get_laser_color() -> Color:
	match team_id:
		0: return Color(1.0, 0.2, 0.1, 0.85)   ## Rosso
		1: return Color(0.1, 0.6, 1.0, 0.85)   ## Azzurro
		2: return Color(0.1, 1.0, 0.4, 0.85)   ## Verde
		_: return Color(0.9, 0.5, 1.0, 0.85)   ## Viola

func _show_laser(p_show: bool) -> void:
	if _laser_line:
		_laser_line.visible = p_show

# ---------------------------------------------------------------------------
# Sistema di targeting — event-driven via Area2D (zero polling)
# ---------------------------------------------------------------------------

func _on_action_body_entered(body: Node2D) -> void:
	# Targeting nemici
	if _is_enemy(body) and _is_same_level(body):
		if body not in _targets_in_range:
			_targets_in_range.append(body)
		_pick_best_target()
		_show_laser(true)
	
	# Hacking: rileva entità amiche nel raggio (player/bot del team diverso)
	if hackable and not _is_dead and _is_same_level(body):
		var body_team := _get_team_id(body)
		if body_team != team_id:
			if body not in _entities_in_hacking_range:
				_entities_in_hacking_range.append(body)
				print("[TURRET] Entità nel raggio di hacking: '%s' (team %d vs turret team %d)" % [body.name, body_team, team_id])
			# Bot nemico → avvia hack automatico
			if body.is_in_group("bots") and not _is_hacking:
				print("[TURRET] Bot '%s' avvia hack automatico" % body.name)
				start_hack(body_team, body)

func _on_action_body_exited(body: Node2D) -> void:
	_targets_in_range.erase(body)
	if _target == body:
		_target = null
		_pick_best_target()
	if _targets_in_range.is_empty():
		_show_laser(false)
	
	# Hacking: rimuovi dalla lista e annulla se era proprio lui a hackerare
	_entities_in_hacking_range.erase(body)
	if _is_hacking and body == _hacking_body:
		print("[TURRET] Player che stava hackerando è uscito dal raggio, hack annullato")
		cancel_hack()
	elif _entities_in_hacking_range.is_empty() and _is_hacking:
		print("[TURRET] Entità uscita, hack annullato")
		cancel_hack()

func _on_action_area_entered(area: Area2D) -> void:
	if _is_enemy(area) and _is_same_level(area):
		if area not in _targets_in_range:
			_targets_in_range.append(area)
		_pick_best_target()
		_show_laser(true)

func _on_action_area_exited(area: Area2D) -> void:
	_targets_in_range.erase(area)
	if _target == area:
		_target = null
		_pick_best_target()
	if _targets_in_range.is_empty():
		_show_laser(false)

## Sceglie il target più vicino tra quelli validi.
func _pick_best_target() -> void:
	_targets_in_range = _targets_in_range.filter(
		func(n: Node2D) -> bool:
			return is_instance_valid(n) and _is_enemy(n) and _is_same_level(n)
	)

	if _targets_in_range.is_empty():
		_target = null
		_show_laser(false)
		target_lost.emit()
		return

	var best: Node2D    = null
	var best_dsq: float = INF
	for candidate: Node2D in _targets_in_range:
		var d := global_position.distance_squared_to(candidate.global_position)
		if d < best_dsq:
			best_dsq = d
			best     = candidate

	if best != _target:
		_target = best
		target_acquired.emit(_target)

# ---------------------------------------------------------------------------
# Sparo — sistema hitscan identico al player (ProjectileVisual)
# ---------------------------------------------------------------------------

func _try_shoot() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_shot_time < cadenza_fuoco:
		return

	var dir         := global_position.direction_to(_target.global_position).normalized()
	var fire_origin := global_position

	# RayCast LoS check (on-demand, nessun overhead)
	var ray_end_local := to_local(global_position + dir * shot_range)
	_ray_cast.target_position = ray_end_local
	_ray_cast.force_raycast_update()

	var impact_pos  := global_position + dir * shot_range
	var target_path := NodePath()

	if _ray_cast.is_colliding():
		impact_pos = _ray_cast.get_collision_point()
		var collider := _ray_cast.get_collider() as Node
		if collider:
			# Cerca il nodo nemico: il collider stesso o un suo antenato
			var dmg_target := _find_damageable_ancestor(collider)
			if dmg_target and _is_enemy(dmg_target):
				target_path = dmg_target.get_path()
			else:
				return  ## Ostacolo tra torretta e target: non sparare

	_fire_projectile(fire_origin, impact_pos, target_path)

func _fire_projectile(origin: Vector2, impact: Vector2, target_path: NodePath) -> void:
	_last_shot_time = Time.get_ticks_msec() / 1000.0
	_can_shoot      = false
	_reload_timer.start(cadenza_fuoco)

	if _sfx_shoot:
		_sfx_shoot.play()
	noise_emitted.emit(global_position, raggio_azione * 1.5)

	# Istanzia ProjectileVisual esattamente come il player
	var projectile := PROJECTILE_VISUAL_SCENE.instantiate() as ProjectileVisual
	if not projectile:
		return

	get_tree().current_scene.add_child(projectile)
	projectile.setup_projectile(origin, impact, projectile_visual_speed, livello, target_path)

	if not target_path.is_empty():
		projectile.impact_reached.connect(_on_projectile_impact, CONNECT_ONE_SHOT)

func _on_projectile_impact(hit_path: NodePath, _shooter_peer_id: int) -> void:
	if hit_path.is_empty():
		return
	var target := get_tree().root.get_node_or_null(hit_path)
	if not target or not is_instance_valid(target):
		return

	if target.has_method("apply_damage"):
		target.call_deferred("apply_damage", danno, self)
	elif target.has_method("receive_damage"):
		target.call_deferred("receive_damage", danno, _deployer_peer_id)
	
	## Notifica la mappa per il conteggio delle kill (solo se il target è un player)
	if target is PlayerPrototype:
		_notify_turret_kill.rpc(target.name, _deployer_peer_id)


## RPC per notificare alla mappa che la torretta ha ucciso un player
@rpc("authority", "call_local", "reliable")
func _notify_turret_kill(victim_name: String, turret_deployer_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var current_scene := get_tree().current_scene
	if current_scene and current_scene.has_method("_on_turret_kill"):
		current_scene.call("_on_turret_kill", turret_deployer_peer_id, int(victim_name) if victim_name.is_valid_int() else 0)

## Risale la gerarchia fino a trovare un nodo con apply_damage o in damageable.
func _find_damageable_ancestor(node: Node) -> Node:
	var current := node
	var limit    := 4  ## Max livelli di gerarchia da controllare
	while current and limit > 0:
		if current.is_in_group("damageable") or current.has_method("apply_damage"):
			return current
		current = current.get_parent()
		limit -= 1
	return node  ## Fallback: ritorna il nodo originale

func _on_reload_timeout() -> void:
	_can_shoot = true

# ---------------------------------------------------------------------------
# Ricezione danni
# ---------------------------------------------------------------------------

## API pubblica — stessa firma di mina.gd.
## Essendo StaticBody2D, il player la trova direttamente via RayCast.
## Supporta source_peer_id per attribuzione kill nel multiplayer.
func apply_damage(amount: float, source: Node = null) -> void:
	if _is_dead or vita <= 0.0:
		return
	
	## Verifica friendly fire: se source è un player dello stesso team, ignora il danno
	if source and source is PlayerPrototype:
		var source_player := source as PlayerPrototype
		if source_player.team_id == team_id:
			return  ## No friendly fire sulle torrette del proprio team
	
	vita = maxf(vita - amount, 0.0)
	if vita <= 0.0:
		## Nel multiplayer, sincronizza la distruzione
		if _is_multiplayer_session():
			_die_rpc.rpc()
		else:
			_die()


## Verifica se è una sessione multiplayer
func _is_multiplayer_session() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty()

# ---------------------------------------------------------------------------
# Distruzione — identica a mina.gd
# ---------------------------------------------------------------------------

func _die() -> void:
	if _is_dead:
		return
	_is_dead    = true
	_target     = null
	_can_shoot  = false
	_is_hacking = false
	_targets_in_range.clear()
	_show_laser(false)

	# Disabilita collisioni (StaticBody2D self + ActionArea)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask",  0)
	_action_area.set_deferred("collision_layer", 0)
	_action_area.set_deferred("collision_mask",  0)

	# Suono esplosione
	if _sfx_explosion:
		_sfx_explosion.play()

	# Nasconde indicatori
	if _danger_indicator:
		_danger_indicator.visible = false
	if _point_light:
		_point_light.visible = false

	# Rimuove shader per riprodurre l'esplosione pulita (come mina.gd)
	_base_sprite.visible = false
	_gun_sprite.visible = false
	
	if _anim_sprite:
		_anim_sprite.material = null

	# ── Animazione esplosione (identica a mina.gd) ──
	var radius := raggio_azione * 0.4  # Raggio esplosione proporzionale al raggio azione
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

	# ── Particelle esplosione scalate come mina.gd ──
	var global_settings := get_node_or_null("/root/GlobalSettings")
	var preset          := 2
	if global_settings:
		preset = global_settings.call("get_setting", "graphics_preset", 2)

	if _particles and preset > 0:
		_particles.emission_sphere_radius = radius
		_particles.initial_velocity_min   = radius * 0.4
		_particles.initial_velocity_max   = radius * 1.2
		_particles.scale_amount_min       = maxf(4.0,  radius * 0.015)
		_particles.scale_amount_max       = maxf(12.0, radius * 0.045)
		_particles.emitting               = true

	await get_tree().create_timer(0.8).timeout
	queue_free()

	destroyed.emit()


## RPC per sincronizzare la distruzione della torretta nel multiplayer
@rpc("authority", "call_local", "reliable")
func _die_rpc() -> void:
	_die()

# ---------------------------------------------------------------------------
# Hacking
# ---------------------------------------------------------------------------

## Imposta il peer ID del player che ha piazzato questa torretta
func set_deployer_peer_id(peer_id: int) -> void:
	_deployer_peer_id = peer_id

func start_hack(new_team: int = -1, body: Node2D = null) -> void:
	if not hackable or _is_dead or _is_hacking:
		return
	if new_team >= 0:
		_hack_target_team = new_team
	_hacking_body = body
	_is_hacking    = true
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = true
		_update_hack_bar()
	hacking_started.emit()

func cancel_hack() -> void:
	if not _is_hacking:
		return
	_is_hacking    = false
	_hacking_body  = null
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false

func _complete_hack() -> void:
	_is_hacking = false
	_hacking_body = null
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false
	team_id = _hack_target_team  # setter: aggiorna gruppi + visuals
	_targets_in_range.clear()
	_target = null
	_pick_best_target()
	# Rimuove dal raggio di hacking chi ora è diventato alleato,
	# così non può ri-hackerare (o mostrare la barra su) una torretta già sua
	for i in range(_entities_in_hacking_range.size() - 1, -1, -1):
		var b := _entities_in_hacking_range[i]
		if not is_instance_valid(b) or _get_team_id(b) == team_id:
			_entities_in_hacking_range.remove_at(i)
	hacking_completed.emit(team_id)

func _crea_hack_bar() -> void:
	var pivot := Node2D.new()
	pivot.name = "HackBarPivot"
	pivot.z_index = 1000
	pivot.z_as_relative = false
	add_child(pivot)
	pivot.global_position = global_position + Vector2(0, -hack_bar_vertical_offset)
	pivot.global_rotation = 0.0

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.06, 0.06, 0.08, 0.92)
	bg.size = hack_bar_size + Vector2(6, 6)
	bg.position = -(hack_bar_size + Vector2(6, 6)) * 0.5
	pivot.add_child(bg)

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

	var border := ColorRect.new()
	border.name = "Border"
	border.color = Color(0.0, 0.9, 1.0, 0.7)
	border.size = hack_bar_size + Vector2(4, 4)
	border.position = -(hack_bar_size + Vector2(4, 4)) * 0.5
	pivot.add_child(border)
	border.z_index = 1

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

func _update_hack_bar() -> void:
	if not _hack_bar_pivot or not is_node_ready():
		return

	var fill := _hack_bar_pivot.get_node_or_null("BarFill") as ColorRect
	if fill:
		fill.size.x = hack_bar_size.x * _hack_bar_progress
		fill.color = Color(0.0, 0.85, 1.0).lerp(Color(0.1, 1.0, 0.4), _hack_bar_progress)

	var label := _hack_bar_pivot.get_node_or_null("Label") as Label
	if label:
		label.text = "HACK %d%%" % int(_hack_bar_progress * 100.0)


# ---------------------------------------------------------------------------
# Utility Team
# ---------------------------------------------------------------------------

func _get_team_id(node: Node) -> int:
	# Prima cerca nei gruppi team_X
	for group: String in node.get_groups():
		if group.begins_with("team_"):
			return int(group.get_slice("_", 1))
	# Fallback: proprietà diretta team_id (usata da player, bot, altre torrette)
	if "team_id" in node:
		return int(node.get("team_id"))
	return -1

func _is_enemy(node: Node) -> bool:
	if not node.is_in_group("damageable"):
		return false
	if node == self:
		return false
	
	## Le torrette ignorano le mine
	if node is Mina:
		return false
	
	var node_team := _get_team_id(node)
	if node_team == -1:
		return false  ## Team sconosciuto: mai nemico
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
	match team_id:
		0: _base_sprite.modulate = Color.WHITE
		1: _base_sprite.modulate = Color(0.4, 0.8, 1.0)
		2: _base_sprite.modulate = Color(1.0, 0.4, 0.4)
		_: _base_sprite.modulate = Color(0.8, 0.8, 0.8)
	# Aggiorna colore laser al cambio team
	if _laser_shader_mat:
		_laser_shader_mat.set_shader_parameter("color", _get_laser_color())

# ---------------------------------------------------------------------------
# Deployment — verifica statica area libera
# ---------------------------------------------------------------------------

static func can_deploy_at(
	scene_tree: SceneTree,
	space_state: PhysicsDirectSpaceState2D,
	p_position: Vector2,
	check_radius: float,
	target_level: int
) -> bool:
	var level_group := "entities_level_" + str(target_level)
	if scene_tree.has_group(level_group):
		for entity: Node in scene_tree.get_nodes_in_group(level_group):
			if entity is Node2D:
				if p_position.distance_to((entity as Node2D).global_position) < check_radius:
					return false

	var params := PhysicsShapeQueryParameters2D.new()
	var circle  := CircleShape2D.new()
	circle.radius            = check_radius * 0.5
	params.shape             = circle
	params.transform         = Transform2D(0.0, p_position)
	params.collision_mask    = 1 << (target_level * 3)
	params.collide_with_areas  = false
	params.collide_with_bodies = true
	return space_state.intersect_shape(params, 1).is_empty()

# ---------------------------------------------------------------------------
# Collision layer/mask — identici a mina.gd
# ---------------------------------------------------------------------------

func _apply_collision_layers() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	var base_layer    := livello * 3 + 1
	var wall_bit      := 1 << (base_layer - 1)
	var character_bit := 1 << base_layer

	# StaticBody2D (self): occupa il wall_layer → player e proiettili ci collidono
	collision_layer = wall_bit
	collision_mask  = 0  ## Non ha bisogno di rilevare nulla direttamente

	if _action_area:
		# Rileva sia CharacterBody2D (player/bot) che altri StaticBody2D (torrette)
		_action_area.collision_layer = 0
		_action_area.collision_mask  = wall_bit | character_bit

	if _ray_cast:
		_ray_cast.collision_mask = wall_bit | character_bit

# ---------------------------------------------------------------------------
# Gruppi livello — identici a mina.gd
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
# Forma ActionArea
# ---------------------------------------------------------------------------

func _update_action_area_shape() -> void:
	if Engine.is_editor_hint() or not is_inside_tree() or not is_node_ready():
		return
	if _action_shape and _action_shape.shape is CircleShape2D:
		(_action_shape.shape as CircleShape2D).radius = raggio_azione

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
	_show_laser(false)

# ---------------------------------------------------------------------------
# Impostazioni grafiche (come mina.gd)
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
	# Qualità dashed circle
	if _shader_material:
		_shader_material.set_shader_parameter("quality", 0.0 if preset == 0 else 1.0)

	# Qualità laser
	if _laser_shader_mat:
		_laser_shader_mat.set_shader_parameter("quality", 0.0 if preset == 0 else 1.0)

	# Ombre PointLight2D
	if _point_light:
		_point_light.shadow_enabled = (preset >= 3)

	# Velocità animazione esplosione (come mina.gd)
	if _anim_sprite and _anim_sprite.sprite_frames \
			and _anim_sprite.sprite_frames.has_animation(&"Esplosione"):
		match preset:
			0: _anim_sprite.sprite_frames.set_animation_speed(&"Esplosione", 6.0)
			1: _anim_sprite.sprite_frames.set_animation_speed(&"Esplosione", 9.0)
			_: _anim_sprite.sprite_frames.set_animation_speed(&"Esplosione", 12.0)

	# Quantità particelle (come mina.gd)
	if _particles:
		match preset:
			0: _particles.amount = 1
			1: _particles.amount = 40
			_: _particles.amount = 120

# ---------------------------------------------------------------------------
# Connessione player per visibilità livello — identica a mina.gd
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
	return w

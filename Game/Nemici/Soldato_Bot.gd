## Soldato_Bot.gd
## Bot soldato IA per TFA Agents — Godot 4.6
##
## Sistema AI:   LimboAI HSM (Hierarchical State Machine)
## Sistema armi: hitscan identico a player_prototype.gd / Turret.gd
## Supporto:     multi-team, multi-piano, difficoltà, multiplayer (server-side),
##               sistema allarme via segnale (mine, altri bot)

extends CharacterBody2D
class_name SoldatoBot

# ─── Segnali ───────────────────────────────────────────────────────────────

signal eliminato(bot: SoldatoBot)
signal danno_subito(amount: float, vita_rimanente: float)
signal nemico_avvistato(target: Node2D, position: Vector2)
signal allarme_ricevuto(position: Vector2)
signal noise_emitted(pos: Vector2, noise_radius: float)

# ─── Costanti ──────────────────────────────────────────────────────────────

const PROJECTILE_VISUAL_SCENE := preload("res://Scenes/projectile_visual.tscn")

## Statistiche base per classe. Vengono poi scalate dalla difficoltà.
const CLASSE_STATS: Dictionary = {
	0: { "nome": "Soldato",    "vita": 100.0, "speed": 150.0, "danno": 20.0,  "cooldown": 0.35, "range": 1000.0, "fov_range": 750.0, "attack_range": 500.0 },
	1: { "nome": "Medico",     "vita": 80.0,  "speed": 130.0, "danno": 12.0,  "cooldown": 0.55, "range": 800.0,  "fov_range": 600.0, "attack_range": 400.0 },
	2: { "nome": "Cecchino",   "vita": 70.0,  "speed": 80.0,  "danno": 60.0,  "cooldown": 1.8,  "range": 2200.0, "fov_range": 1500.0, "attack_range": 1200.0 },
	3: { "nome": "Pesante",    "vita": 280.0, "speed": 75.0,  "danno": 45.0,  "cooldown": 0.65, "range": 600.0,  "fov_range": 450.0, "attack_range": 350.0 },
	4: { "nome": "Ninja",      "vita": 75.0,  "speed": 260.0, "danno": 40.0,  "cooldown": 0.4,  "range": 150.0,  "fov_range": 600.0, "attack_range": 100.0  },
	5: { "nome": "Granatiere", "vita": 130.0, "speed": 120.0, "danno": 18.0,  "cooldown": 0.4,  "range": 900.0,  "fov_range": 750.0, "attack_range": 550.0 },
	6: { "nome": "MiniBoss",   "vita": 550.0, "speed": 110.0, "danno": 38.0,  "cooldown": 0.22, "range": 1300.0, "fov_range": 900.0, "attack_range": 650.0 },
	7: { "nome": "Altro",      "vita": 100.0, "speed": 150.0, "danno": 20.0,  "cooldown": 0.35, "range": 1000.0, "fov_range": 750.0, "attack_range": 500.0 },
}

## Moltiplicatori difficoltà — [Facile, Normale, Difficile, Agente Caduto]
const DIFFICULTY_MULTIPLIERS: Array[Dictionary] = [
	{ "vita": 0.65, "speed": 0.80, "danno": 0.65, "fov_range": 0.70, "chase_time": 0.55, "investigate_time": 0.60, "fov_angle": 0.75 },
	{ "vita": 1.00, "speed": 1.00, "danno": 1.00, "fov_range": 1.00, "chase_time": 1.00, "investigate_time": 1.00, "fov_angle": 1.00 },
	{ "vita": 1.35, "speed": 1.18, "danno": 1.35, "fov_range": 1.30, "chase_time": 1.60, "investigate_time": 1.40, "fov_angle": 1.25 },
	{ "vita": 1.80, "speed": 1.40, "danno": 1.80, "fov_range": 1.70, "chase_time": 2.80, "investigate_time": 2.00, "fov_angle": 1.50 },
]

# ─── Export: Identità ──────────────────────────────────────────────────────

@export_group("Identità")
## ID team del bot. Corrisponde al gruppo "team_X".
@export var team_id: int = 0:
	set(value):
		team_id = value
		if is_inside_tree():
			_refresh_team_group()
## Piano operativo (0 = piano terra, 1 = primo piano, ecc.).
## Determina collision layer/mask e navigation layer.
@export_range(0, 15, 1) var current_height_level: int = 0
## Classe del soldato — determina statistiche e comportamenti AI.
@export_enum("Soldato","Medico","Cecchino","Pesante","Ninja","Granatiere","MiniBoss","Altro")
var classe: int = 0
## Nome dell'animazione da riprodurre sull'AnimatedSprite2D.
@export var skin: String = "Soldato"

# ─── Export: Statistiche ───────────────────────────────────────────────────

@export_group("Statistiche")
@export var vita_max: float = 100.0
@export var speed: float = 150.0
## Danno inflitto al nemico per contatto fisico (Area2D).
@export var danno_tocco: float = 8.0

# ─── Export: Arma ──────────────────────────────────────────────────────────

@export_group("Arma — Hitscan (identico al player)")
@export var projectile_damage: float = 20.0
@export var fire_cooldown: float = 0.35
@export var shot_range: float = 1000.0
@export var projectile_visual_speed: float = 2200.0
@export var nome_arma: String = "mitra"

# ─── Export: AI — Campo Visione ────────────────────────────────────────────

@export_group("AI — Campo Visione")
## Apertura del cono frontale di visione (gradi).
@export_range(30.0, 360.0, 5.0) var fov_angle: float = 120.0
## Distanza massima del cono di visione.
@export var fov_range: float = 750.0
## Distanza di attacco (entro cui passa in stato Attack).
@export var attack_range: float = 500.0
## Range periferico a 360° — simula udito/vicinanza ravvicinata.
@export var peripheral_range: float = 120.0

# ─── Export: AI — Tempi ────────────────────────────────────────────────────

@export_group("AI — Tempi & Caparbietà")
## Secondi di inseguimento senza LoS prima di perdere il nemico.
@export var chase_time: float = 5.0
## Secondi di investigazione prima di tornare in pattuglia/idle.
@export var investigate_time: float = 4.0
## Secondi di attesa su ogni waypoint di pattuglia.
@export var patrol_wait_time: float = 1.5
## Raggio del wander casuale (se patrol_path è assente).
@export var wander_radius: float = 220.0

# ─── Export: AI — Pattuglia ────────────────────────────────────────────────

@export_group("AI — Pattuglia")
## Path2D da seguire. Se null → wander casuale.
@export var patrol_path: Path2D = null
@export var patrol_loop: bool = true

# ─── Export: Difficoltà ────────────────────────────────────────────────────

@export_group("Difficoltà")
## 0=Facile 1=Normale 2=Difficile 3=Agente Caduto
@export_range(0, 3, 1) var difficulty_level: int = 1
## Se true, legge la difficoltà da Global.difficolta o GlobalSettings automaticamente.
@export var use_global_difficulty: bool = true

# ─── Export: Medico ────────────────────────────────────────────────────────

@export_group("Medico (solo classe Medico)")
@export var heal_range: float = 150.0
@export var heal_amount: float = 30.0
## Cura alleati con vita < heal_threshold (0.5 = 50%).
@export var heal_threshold: float = 0.5

# ─── Export: Ottimizzazione ────────────────────────────────────────────────

@export_group("Ottimizzazione Mobile")
## Esegue il FOV check ogni N physics frame (riduci su mobile).
@export_range(1, 10, 1) var fov_check_every_frames: int = 3
## Aggiorna il percorso di navigazione ogni N physics frame.
@export_range(1, 10, 1) var nav_update_every_frames: int = 4

# ─── Export: Debug ─────────────────────────────────────────────────────────

@export_group("Debug")
## Se true, mostra il percorso di navigazione corrente con una Line2D.
@export var debug_show_path: bool = false

# ─── Stato interno ─────────────────────────────────────────────────────────

var vita: float = 100.0
var _is_dead: bool = false
var _screen_visible: bool = true
var _last_shot_time: float = -999.0
var _current_target: Node2D = null
var _frame_counter: int = 0
var _can_receive_alert: bool = true
var _registered_levels: Array[int] = []

var _stuck_timer: float = 0.0
var _unstuck_active: bool = false
var _unstuck_timer: float = 0.0
var _unstuck_direction: Vector2 = Vector2.ZERO
var _last_position: Vector2 = Vector2.ZERO

## Blackboard condiviso tra stati AI — accessibile dagli LimboState.
var ai_blackboard: Dictionary = {
	"target": null,
	"last_known_pos": Vector2.ZERO,
	"alert_position": Vector2.ZERO,
	"has_alert": false,
	"patrol_index": 0,
}

## Punto di spawn (usato per il wander casuale in Patrol).
var spawn_position: Vector2 = Vector2.ZERO

# ─── Nodi (lazy — assegnati in _ready con get_node_or_null) ────────────────

@onready var _sprite: AnimatedSprite2D                   = $AnimatedSprite2D
@onready var _collision: CollisionShape2D                = $CollisionShape2D
@onready var _nav_agent: NavigationAgent2D               = $NavigationAgent2D
@onready var _shot_ray: RayCast2D                        = $ShotRayCast
@onready var _los_ray: RayCast2D                         = $LOSRayCast
@onready var _action_area: Area2D                        = $ActionArea
@onready var _muzzle: Marker2D                           = $Muzzle
@onready var _screen_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D
@onready var _sfx_shoot: AudioStreamPlayer2D             = $SfxShoot
@onready var _reload_timer: Timer                        = $ReloadTimer
@onready var _hsm: LimboHSM                             = $LimboHSM
@onready var _debug_path_line: Line2D                    = get_node_or_null("DebugPathLine")

## Riferimenti stati AI
@onready var _state_idle: LimboState        = $LimboHSM/Idle
@onready var _state_patrol: LimboState      = $LimboHSM/Patrol
@onready var _state_investigate: LimboState = $LimboHSM/Investigate
@onready var _state_chase: LimboState       = $LimboHSM/Chase
@onready var _state_attack: LimboState      = $LimboHSM/Attack
@onready var _state_heal: LimboState        = $LimboHSM/Heal
@onready var _state_hack_door: LimboState   = $LimboHSM/HackDoor

# ─── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	spawn_position = global_position

	# 1. Statistiche: classe → difficoltà
	_resolve_difficulty()
	_apply_class_stats()
	_apply_difficulty()
	vita = vita_max

	# 2. Gruppi
	add_to_group("bots")
	add_to_group("damageable")
	add_to_group("Enemy")
	add_to_group("noise_makers")
	_refresh_team_group()
	_refresh_level_membership()

	# 3. Collision layers per piano
	_apply_collision_layers()

	# 4. Sprite
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(skin):
		_sprite.play(skin)

	# 5. NavigationAgent
	_nav_agent.avoidance_enabled = false
	_nav_agent.navigation_layers = 1 << current_height_level
	_nav_agent.path_desired_distance = 8.0
	_nav_agent.target_desired_distance = 12.0

	# 6. RayCast collision masks
	_configure_raycasts()

	# 7. ActionArea — segnali body/area touch
	_action_area.body_entered.connect(_on_action_body_entered)

	# 8. FPS boost — disattiva fisica fuori schermo
	_screen_notifier.screen_entered.connect(_on_screen_entered)
	_screen_notifier.screen_exited.connect(_on_screen_exited)

	# 9. ReloadTimer
	_reload_timer.one_shot = true

	# 10. Setup HSM (LimboAI)
	_setup_hsm()

	# 11. Connessione segnali allarme (mine ecc.) — differita
	call_deferred("_connect_alert_signals")

	# 12. Setup Debug Line
	if _debug_path_line:
		_debug_path_line.global_position = Vector2.ZERO
		_debug_path_line.global_rotation = 0.0
		_debug_path_line.global_scale = Vector2.ONE


func _physics_process(_delta: float) -> void:
	if _is_dead:
		return

	_frame_counter += 1

	# FOV check ogni N frame — ottimizzazione mobile
	if _frame_counter % fov_check_every_frames == 0:
		_update_fov_detection()

	# Movimento via NavigationAgent (il percorso è impostato dagli stati AI)
	if not _nav_agent.is_navigation_finished():
		if _unstuck_active:
			_unstuck_timer -= _delta
			if _unstuck_timer <= 0.0:
				_unstuck_active = false
				_stuck_timer = 0.0
			else:
				velocity = _unstuck_direction * speed
		else:
			var dist_moved := global_position.distance_to(_last_position)
			if dist_moved < (speed * _delta * 0.15):
				_stuck_timer += _delta
				if _stuck_timer >= 0.5:
					# Prima controlla se siamo bloccati da una porta
					if _check_door_blocking():
						pass  # _check_door_blocking gestisce la transizione HSM
					else:
						_unstuck_active = true
						_unstuck_timer = 0.6
						var next_pos := _nav_agent.get_next_path_position()
						var desired_dir := global_position.direction_to(next_pos)
						if desired_dir.length_squared() < 0.1:
							desired_dir = Vector2.RIGHT.rotated(randf() * TAU)
						var angle := randf_range(deg_to_rad(60.0), deg_to_rad(180.0))
						if randf() > 0.5:
							angle = -angle
						_unstuck_direction = desired_dir.rotated(angle).normalized()
			else:
				_stuck_timer = maxf(_stuck_timer - _delta * 2.0, 0.0)
			
			if not _unstuck_active:
				var next_pos := _nav_agent.get_next_path_position()
				var move_dir := global_position.direction_to(next_pos)
				velocity = move_dir * speed
	else:
		_stuck_timer = 0.0
		_unstuck_active = false
		velocity = velocity.lerp(Vector2.ZERO, 0.25)
		
	_last_position = global_position

	move_and_slide()

	# Orienta il bot verso la direzione di movimento, a meno che non stia
	# mirando a un target (gli stati Chase/Attack gestiscono già la rotazione).
	if velocity.length_squared() > 400.0 and _current_target == null:
		var move_dir := velocity.normalized()
		global_rotation = lerp_angle(global_rotation, move_dir.angle(), 10.0 * _delta)

	# Aggiorna visualizzazione del percorso di debug
	if _debug_path_line:
		if debug_show_path and not _nav_agent.is_navigation_finished():
			_debug_path_line.visible = true
			var path := _nav_agent.get_current_navigation_path()
			if path.size() > 1:
				_debug_path_line.points = path
			else:
				_debug_path_line.clear_points()
		else:
			_debug_path_line.visible = false
			_debug_path_line.clear_points()

# ─── Setup LimboAI HSM ─────────────────────────────────────────────────────

func _setup_hsm() -> void:
	# Transizioni universali
	_hsm.add_transition(_state_idle,        _state_patrol,      &"go_patrol")
	_hsm.add_transition(_state_idle,        _state_chase,       &"enemy_spotted")
	_hsm.add_transition(_state_idle,        _state_investigate, &"go_investigate")

	_hsm.add_transition(_state_patrol,      _state_chase,       &"enemy_spotted")
	_hsm.add_transition(_state_patrol,      _state_investigate, &"go_investigate")

	_hsm.add_transition(_state_chase,       _state_attack,      &"in_attack_range")
	_hsm.add_transition(_state_chase,       _state_investigate, &"target_lost")

	_hsm.add_transition(_state_attack,      _state_chase,       &"out_of_range")
	_hsm.add_transition(_state_attack,      _state_investigate, &"target_lost")

	_hsm.add_transition(_state_investigate, _state_idle,        &"investigation_done")
	_hsm.add_transition(_state_investigate, _state_patrol,      &"go_patrol")
	_hsm.add_transition(_state_investigate, _state_chase,       &"enemy_spotted")

	# Transizioni HackDoor — da tutti gli stati "di movimento" verso hack porta
	for from_state: LimboState in [_state_patrol, _state_investigate, _state_chase]:
		_hsm.add_transition(from_state,   _state_hack_door, &"hack_door")
	_hsm.add_transition(_state_hack_door, _state_patrol,       &"door_hacked")
	_hsm.add_transition(_state_hack_door, _state_investigate,  &"go_investigate")
	_hsm.add_transition(_state_hack_door, _state_chase,        &"enemy_spotted")

	# Transizioni Medico (classe == 1)
	if classe == 1:
		_hsm.add_transition(_state_idle,   _state_heal, &"go_heal")
		_hsm.add_transition(_state_patrol, _state_heal, &"go_heal")
		_hsm.add_transition(_state_heal,   _state_idle, &"heal_done")
		_hsm.add_transition(_state_heal,   _state_chase, &"enemy_spotted")

	# Stato iniziale
	_hsm.initial_state = _state_patrol if patrol_path != null else _state_idle

	_hsm.initialize(self)
	_hsm.set_active(true)

# ─── FOV Detection ─────────────────────────────────────────────────────────

## Scansiona nemici nel raggio e aggiorna il target corrente.
func _update_fov_detection() -> void:
	# Se abbiamo già un target valido, controlla se è ancora visibile
	if _current_target != null and is_instance_valid(_current_target):
		if not is_in_fov(_current_target):
			# Salva ultima posizione nota ma non rimuovere il target —
			# ci pensa lo stato Chase/Attack col proprio timer
			ai_blackboard["last_known_pos"] = _current_target.global_position
		return

	# Cerca nuovi nemici
	for candidate in _find_enemies_in_range():
		if is_in_fov(candidate):
			_set_target(candidate)
			_hsm.dispatch(&"enemy_spotted")
			nemico_avvistato.emit(candidate, candidate.global_position)
			_broadcast_alert(candidate.global_position)
			return

## Restituisce i nemici nel raggio (filtrati per team + livello).
func _find_enemies_in_range() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for group_name in ["players", "bots"]:
		for node: Node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node2D):
				continue
			if not is_enemy_node(node):
				continue
			if not is_same_level(node):
				continue
			var dist: float = global_position.distance_to((node as Node2D).global_position)
			if dist <= fov_range:
				result.append(node as Node2D)
	return result

## Controlla se il target è nel cono di visione (angolo + LoS).
func is_in_fov(target: Node2D) -> bool:
	if not is_instance_valid(target):
		return false

	var dist: float = global_position.distance_to(target.global_position)

	# Range periferico a 360° (simula udito/vicinanza)
	if dist <= peripheral_range:
		return has_line_of_sight(target)

	if dist > fov_range:
		return false

	# Controllo angolo del cono
	var forward: Vector2 = Vector2.RIGHT.rotated(global_rotation)
	var to_target: Vector2 = global_position.direction_to(target.global_position)
	var angle_deg: float = rad_to_deg(forward.angle_to(to_target))

	if absf(angle_deg) > fov_angle * 0.5:
		return false

	return has_line_of_sight(target)

## Line of Sight check via RayCast2D (on-demand, nessun overhead).
func has_line_of_sight(target: Node2D) -> bool:
	if not _los_ray:
		return true  # Fallback sicuro

	var origin: Vector2 = _muzzle.global_position if _muzzle else global_position
	_los_ray.global_position = origin
	_los_ray.target_position = _los_ray.to_local(target.global_position)
	_los_ray.force_raycast_update()

	if not _los_ray.is_colliding():
		return true  # Nessun ostacolo → LoS libera

	var collider := _los_ray.get_collider()
	if collider and collider is Node:
		# Il raycast colpisce il target stesso o qualcuno nel suo gruppo
		return (collider as Node) == target or _is_part_of_node(collider as Node, target)
	return false

func _is_part_of_node(collider: Node, target: Node2D) -> bool:
	var current := collider
	var limit := 4
	while current and limit > 0:
		if current == target:
			return true
		current = current.get_parent()
		limit -= 1
	return false

# ─── Targeting ─────────────────────────────────────────────────────────────

func _set_target(new_target: Node2D) -> void:
	_current_target = new_target
	ai_blackboard["target"] = new_target

func get_current_target() -> Node2D:
	if _current_target and not is_instance_valid(_current_target):
		_current_target = null
		ai_blackboard["target"] = null
	return _current_target

func clear_target() -> void:
	if _current_target:
		ai_blackboard["last_known_pos"] = _current_target.global_position
	_current_target = null
	ai_blackboard["target"] = null

# ─── Sparo Hitscan (identico a player_prototype.gd e Turret.gd) ───────────

## Restituisce true se il bot può sparare ora.
func can_shoot() -> bool:
	if _is_dead or not _reload_timer.is_stopped():
		return false
	var now: float = Time.get_ticks_msec() / 1000.0
	return (now - _last_shot_time) >= fire_cooldown

## Tenta di sparare verso il target.
func try_shoot(target: Node2D) -> void:
	if not can_shoot() or not is_instance_valid(target):
		return

	# Ninja: attacco corpo a corpo (nessun proiettile)
	if classe == 4:
		_melee_attack(target)
		return

	var fire_origin: Vector2 = _muzzle.global_position if _muzzle else global_position
	var dir: Vector2 = fire_origin.direction_to(target.global_position).normalized()

	_shot_ray.global_position = fire_origin
	_shot_ray.target_position = _shot_ray.to_local(fire_origin + dir * shot_range)
	_shot_ray.force_raycast_update()

	var impact_pos: Vector2 = fire_origin + dir * shot_range
	var target_path := NodePath()

	if _shot_ray.is_colliding():
		impact_pos = _shot_ray.get_collision_point()
		var collider := _shot_ray.get_collider()
		if collider is Node:
			var dmg_node: Node = _find_damageable_ancestor(collider as Node)
			if dmg_node and is_enemy_node(dmg_node):
				target_path = dmg_node.get_path()
			else:
				return  # Ostacolo tra bot e target: non sparare

	_fire_projectile(fire_origin, impact_pos, target_path)

func _fire_projectile(origin: Vector2, impact: Vector2, target_path: NodePath) -> void:
	_last_shot_time = Time.get_ticks_msec() / 1000.0
	_reload_timer.start(fire_cooldown)

	if _sfx_shoot:
		_sfx_shoot.play()
	
	noise_emitted.emit(origin, 1200.0)

	var projectile := PROJECTILE_VISUAL_SCENE.instantiate() as ProjectileVisual
	if not projectile:
		return

	get_tree().current_scene.add_child(projectile)
	projectile.setup_projectile(origin, impact, projectile_visual_speed, current_height_level, target_path)

	if not target_path.is_empty():
		projectile.impact_reached.connect(_on_projectile_impact, CONNECT_ONE_SHOT)

func _on_projectile_impact(target_path: NodePath, _shooter_peer_id: int) -> void:
	if target_path.is_empty():
		return
	var target: Node = get_tree().root.get_node_or_null(target_path)
	if not target or not is_instance_valid(target):
		return
	if target.has_method("receive_damage"):
		target.call_deferred("receive_damage", projectile_damage, 0)
	elif target.has_method("apply_damage"):
		target.call_deferred("apply_damage", projectile_damage, self)

## Attacco corpo a corpo (solo Ninja).
func _melee_attack(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > attack_range * 1.1:
		return
	_last_shot_time = Time.get_ticks_msec() / 1000.0
	_reload_timer.start(fire_cooldown)
	if target.has_method("apply_damage"):
		target.apply_damage(projectile_damage)
	elif target.has_method("receive_damage"):
		target.receive_damage(projectile_damage, 0)

# ─── Navigazione ───────────────────────────────────────────────────────────

## Imposta la destinazione di navigazione del bot.
func navigate_to(world_position: Vector2) -> void:
	_nav_agent.target_position = world_position

## Restituisce l'agente di navigazione (usato dagli stati).
func get_nav_agent() -> NavigationAgent2D:
	return _nav_agent

## True se il bot ha raggiunto la destinazione corrente.
func is_at_destination() -> bool:
	return _nav_agent.is_navigation_finished()

## Verifica se il bot è bloccato da una porta e, se hackabile, avvia l'hack.
## Restituisce true se ha rilevato una porta bloccante e ha attivato lo stato HackDoor.
func _check_door_blocking() -> bool:
	# Usa il raycast in direzione del prossimo waypoint
	if not _nav_agent.is_navigation_finished():
		var next_pos := _nav_agent.get_next_path_position()
		var dir := global_position.direction_to(next_pos)
		_los_ray.global_position = global_position
		_los_ray.target_position = _los_ray.to_local(global_position + dir * 120.0)
		_los_ray.force_raycast_update()
		if _los_ray.is_colliding():
			var collider := _los_ray.get_collider()
			# Risali la gerarchia per trovare una Door
			var door: Door = null
			var current: Node = collider as Node
			var limit := 4
			while current and limit > 0:
				if current is Door:
					door = current as Door
					break
				current = current.get_parent()
				limit -= 1
			if door and is_instance_valid(door) and door.is_same_level(self):
				if door.is_locked():
					return false  # Porta bloccata permanentemente: sblocco normale
				if door.is_door_open():
					return false  # Già aperta: non serve hack
				if door.is_hackable() and not door.is_locked():
					# Porta hackabile: attiva lo stato HackDoor
					ai_blackboard["door_to_hack"] = door
					_stuck_timer = 0.0
					_hsm.dispatch(&"hack_door")
					return true
	return false

# ─── Sistema Allarme ───────────────────────────────────────────────────────

## Ricezione allarme (da altri bot, mine, esplosioni).
## position: posizione 2D da investigare.
func receive_alert(alert_position: Vector2) -> void:
	if _is_dead or not _can_receive_alert:
		return
	# Ignora se già in combattimento attivo
	if _current_target != null and is_instance_valid(_current_target):
		return

	ai_blackboard["alert_position"] = alert_position
	ai_blackboard["has_alert"] = true

	# Forza transizione verso Investigate
	_hsm.dispatch(&"go_investigate")
	allarme_ricevuto.emit(alert_position)

	# Anti-spam: ignora ulteriori allarmi per 2 secondi
	_can_receive_alert = false
	get_tree().create_timer(2.0).timeout.connect(
		func() -> void: _can_receive_alert = true, CONNECT_ONE_SHOT
	)

## Trasmette un allarme ai bot alleati vicini (stesso team e piano).
func _broadcast_alert(alert_pos: Vector2) -> void:
	var broadcast_range: float = fov_range * 1.5
	for bot: Node in get_tree().get_nodes_in_group("bots"):
		if bot == self or not (bot is Node2D):
			continue
		if _get_team_id(bot) != team_id:
			continue
		if not is_same_level(bot):
			continue
		if global_position.distance_to((bot as Node2D).global_position) <= broadcast_range:
			if bot.has_method("receive_alert"):
				bot.call("receive_alert", alert_pos)

## Connette automaticamente i segnali delle mine e oggetti esplosivi.
func _connect_alert_signals() -> void:
	for explodable: Node in get_tree().get_nodes_in_group("explodable"):
		if explodable.has_signal("exploded"):
			if not explodable.exploded.is_connected(_on_explosion_nearby):
				explodable.exploded.connect(_on_explosion_nearby)
	for nm: Node in get_tree().get_nodes_in_group("noise_makers"):
		if nm.has_signal("noise_emitted"):
			if not nm.noise_emitted.is_connected(_on_explosion_nearby):
				nm.noise_emitted.connect(_on_explosion_nearby)

## Callback esplosione vicina — innesca allarme se nel raggio.
func _on_explosion_nearby(explosion_position: Vector2, noise_radius: float) -> void:
	var dist: float = global_position.distance_to(explosion_position)
	if dist <= noise_radius:
		receive_alert(explosion_position)

# ─── Danni & Morte ─────────────────────────────────────────────────────────

## API pubblica di danno (compatibile con Turret.gd e PlayerPrototype).
func apply_damage(amount: float, _source: Node = null) -> void:
	if _is_dead:
		return
	vita = maxf(vita - amount, 0.0)
	danno_subito.emit(amount, vita)
	
	if _source and is_instance_valid(_source) and _source != self:
		if is_enemy_node(_source) and is_same_level(_source):
			_set_target(_source as Node2D)
			_hsm.dispatch(&"enemy_spotted")
			_broadcast_alert(_source.global_position)
	
	if vita <= 0.0:
		_die()

## API danno con source_peer_id (compatibile multiplayer).
func receive_damage(amount: float, _source_peer_id: int = 0) -> void:
	var source_node: Node = null
	if _source_peer_id != 0:
		var players_node = get_tree().current_scene.get_node_or_null("Players")
		if players_node and players_node.has_node(str(_source_peer_id)):
			source_node = players_node.get_node(str(_source_peer_id))
		else:
			source_node = get_tree().current_scene.get_node_or_null(str(_source_peer_id))
	apply_damage(amount, source_node)

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true

	_hsm.set_active(false)
	set_physics_process(false)

	_collision.set_deferred("disabled", true)
	_action_area.set_deferred("collision_layer", 0)
	_action_area.set_deferred("collision_mask", 0)

	# Effetto morte: lampeggio rosso + fade
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 0.15, 0.15, 1.0), 0.08)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void:
		eliminato.emit(self)
		queue_free()
	)

# ─── Cura (Medico) ─────────────────────────────────────────────────────────

## Cura il bot (chiamata da SoldatoState_Heal su alleati).
func heal(amount: float) -> void:
	if _is_dead:
		return
	vita = minf(vita + amount, vita_max)

## Cerca l'alleato ferito più vicino nel range (usato dallo stato Heal).
func find_wounded_ally() -> Node2D:
	var best: Node2D = null
	var best_dist: float = heal_range
	for bot: Node in get_tree().get_nodes_in_group("bots"):
		if not (bot is Node2D) or bot == self:
			continue
		if _get_team_id(bot) != team_id or not is_same_level(bot):
			continue
		if "vita" not in bot or "vita_max" not in bot:
			continue
		var bvita: float  = float(bot.get("vita"))
		var bvmax: float  = float(bot.get("vita_max"))
		if bvmax <= 0.0 or (bvita / bvmax) >= heal_threshold:
			continue
		var dist: float = global_position.distance_to((bot as Node2D).global_position)
		if dist < best_dist:
			best_dist = dist
			best = bot as Node2D
	return best

# ─── Touch Damage (Area2D) ─────────────────────────────────────────────────

func _on_action_body_entered(body: Node2D) -> void:
	if _is_dead:
		return
	if is_enemy_node(body) and is_same_level(body):
		if body.has_method("apply_damage"):
			body.apply_damage(danno_tocco)

# ─── FPS Boost ─────────────────────────────────────────────────────────────

func _on_screen_entered() -> void:
	_screen_visible = true
	set_physics_process(true)

func _on_screen_exited() -> void:
	_screen_visible = false
	set_physics_process(false)

# ─── Utility: Team & Livello ───────────────────────────────────────────────

## Restituisce il team_id di un nodo (cerca prima i gruppi "team_X").
func _get_team_id(node: Node) -> int:
	for group: String in node.get_groups():
		if group.begins_with("team_"):
			return int(group.get_slice("_", 1))
	if "team_id" in node:
		return int(node.get("team_id"))
	return -1

## True se il nodo appartiene a un team diverso (e quindi è nemico).
func is_enemy_node(node: Node) -> bool:
	if not node.is_in_group("damageable") or node == self:
		return false
	var node_team: int = _get_team_id(node)
	if node_team == -1:
		return false
	return node_team != team_id

## True se il nodo si trova sullo stesso piano del bot.
func is_same_level(node: Node) -> bool:
	if "current_height_level" in node:
		return int(node.get("current_height_level")) == current_height_level
	if "livello" in node:
		return int(node.get("livello")) == current_height_level
	return false

func _refresh_team_group() -> void:
	for group: String in get_groups():
		if group.begins_with("team_"):
			remove_from_group(group)
	add_to_group("team_" + str(team_id))

func _refresh_level_membership() -> void:
	for lv: int in _registered_levels:
		remove_from_group("entities_level_" + str(lv))
	_registered_levels.clear()
	add_to_group("entities_level_" + str(current_height_level))
	_registered_levels.append(current_height_level)

## Applica collision layer e mask in base al piano (pattern identico a Turret.gd).
func _apply_collision_layers() -> void:
	var layer_offset: int = current_height_level * 3
	var wall_bit: int      = 1 << (0 + layer_offset)
	var character_bit: int = 1 << (1 + layer_offset)

	collision_layer = character_bit
	collision_mask  = wall_bit | character_bit

	if _nav_agent:
		_nav_agent.navigation_layers = 1 << current_height_level

	if _action_area:
		_action_area.collision_layer = 0
		_action_area.collision_mask  = wall_bit | character_bit

func _configure_raycasts() -> void:
	var layer_offset: int = current_height_level * 3
	var wall_bit: int      = 1 << (0 + layer_offset)
	var character_bit: int = 1 << (1 + layer_offset)
	var mask: int          = wall_bit | character_bit

	if _shot_ray:
		_shot_ray.collision_mask = mask
		_shot_ray.add_exception(self)
		_shot_ray.enabled = false  # Usato on-demand con force_raycast_update()

	if _los_ray:
		_los_ray.collision_mask = mask
		_los_ray.add_exception(self)
		_los_ray.enabled = false

# ─── Statistiche (Classe + Difficoltà) ────────────────────────────────────

func _apply_class_stats() -> void:
	if not CLASSE_STATS.has(classe):
		return
	var s: Dictionary = CLASSE_STATS[classe]
	vita_max          = float(s.get("vita",         vita_max))
	speed             = float(s.get("speed",        speed))
	projectile_damage = float(s.get("danno",        projectile_damage))
	fire_cooldown     = float(s.get("cooldown",     fire_cooldown))
	shot_range        = float(s.get("range",        shot_range))
	fov_range         = float(s.get("fov_range",    fov_range))
	attack_range      = float(s.get("attack_range", attack_range))

func _resolve_difficulty() -> void:
	if not use_global_difficulty:
		return
	# Prima prova GlobalSettings (nuovo sistema)
	var gs: Node = get_node_or_null("/root/GlobalSettings")
	if gs and gs.has_method("get_setting"):
		difficulty_level = int(gs.call("get_setting", "difficulty", 1))
		return
	# Fallback: Global.gd legacy
	var g: Node = get_node_or_null("/root/Global")
	if g and "difficolta" in g:
		difficulty_level = int(g.get("difficolta"))

func _apply_difficulty() -> void:
	var idx: int = clampi(difficulty_level, 0, DIFFICULTY_MULTIPLIERS.size() - 1)
	var m: Dictionary = DIFFICULTY_MULTIPLIERS[idx]
	vita_max          *= float(m.get("vita",             1.0))
	speed             *= float(m.get("speed",            1.0))
	projectile_damage *= float(m.get("danno",            1.0))
	fov_range         *= float(m.get("fov_range",        1.0))
	attack_range      *= float(m.get("fov_range",        1.0))  # Scala insieme al range
	chase_time        *= float(m.get("chase_time",       1.0))
	investigate_time  *= float(m.get("investigate_time", 1.0))
	fov_angle         *= float(m.get("fov_angle",        1.0))
	danno_tocco       *= float(m.get("danno",            1.0))

# ─── Helper ────────────────────────────────────────────────────────────────

## Risale la gerarchia per trovare il nodo con apply_damage (identico a Turret.gd).
func _find_damageable_ancestor(node: Node) -> Node:
	var current: Node = node
	var limit: int = 4
	while current and limit > 0:
		if current.is_in_group("damageable") or current.has_method("apply_damage"):
			return current
		current = current.get_parent()
		limit -= 1
	return node

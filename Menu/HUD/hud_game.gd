extends CanvasLayer

@onready var health_bar: ProgressBar = %HealthBar
@onready var enemy_count_label: Label = %EnemyCountLabel
@onready var weapon_name_label: Label = %WeaponNameLabel
@onready var ammo_current_label: Label = %AmmoCurrentLabel
@onready var ammo_total_label: Label = %AmmoTotalLabel
@onready var subtitle_panel: PanelContainer = %SubtitlePanel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var pause_btn: Button = %PauseBtn
@onready var _top_left: MarginContainer = $HUD/TopLeft

var player: CharacterBody2D = null
var _enemy_update_timer := 0.0
var _subtitle_time_left := 0.0

const HEALTH_Y_DEFAULT: int = 16
const HEALTH_Y_FPS_OFFSET: int = 88  # abbassa di 28px quando FPS panel è visibile

func _ready() -> void:
	# Nascondi i sottotitoli all'inizio
	if subtitle_panel:
		subtitle_panel.visible = false

	# Connetti pulsante pausa
	if pause_btn:
		pause_btn.pressed.connect(_on_pause_pressed)

	# Connessione al player
	var players = get_tree().get_nodes_in_group("players")
	if not players.is_empty():
		_setup_player(players[0])
	else:
		get_tree().node_added.connect(_on_node_added)

	# Connessione a GlobalSettings per i sottotitoli
	var global_settings = get_node_or_null("/root/GlobalSettings")
	if global_settings and global_settings.has_signal("subtitle_requested"):
		global_settings.subtitle_requested.connect(_on_subtitle_requested)

	# Primo aggiornamento contatore nemici
	_update_enemies_count()
	
	await get_tree().process_frame
	if is_instance_valid(GlobalSettings._fps_panel):
		GlobalSettings._fps_panel.visibility_changed.connect(_update_health_position)
	_update_health_position()
	

func _on_node_added(node: Node) -> void:
	if node.is_in_group("players") and node is CharacterBody2D:
		_setup_player(node)

func _setup_player(p: CharacterBody2D) -> void:
	player = p
	if player.has_signal("health_changed") and not player.health_changed.is_connected(_on_player_health_changed):
		player.health_changed.connect(_on_player_health_changed)
	if player.has_signal("ammo_changed") and not player.ammo_changed.is_connected(_on_player_ammo_changed):
		player.ammo_changed.connect(_on_player_ammo_changed)

	# Aggiorna subito lo stato iniziale
	if "vita" in player and "vita_max" in player:
		_on_player_health_changed(player.vita, player.vita_max)
	if "colpi_correnti" in player and "colpi_totali" in player:
		_on_player_ammo_changed(player.colpi_correnti, player.colpi_totali)
	if "nome_arma" in player and weapon_name_label:
		weapon_name_label.text = player.nome_arma

func _process(delta: float) -> void:
	# Contatore nemici periodico
	_enemy_update_timer += delta
	if _enemy_update_timer >= 0.2:
		_enemy_update_timer = 0.0
		_update_enemies_count()

	# Gestione della durata dei sottotitoli
	if _subtitle_time_left > 0.0:
		_subtitle_time_left = maxf(0.0, _subtitle_time_left - delta)
		if _subtitle_time_left <= 0.0 and subtitle_panel:
			subtitle_panel.visible = false
			

func _on_player_health_changed(current: float, max_val: float) -> void:
	if health_bar:
		health_bar.max_value = max_val
		health_bar.value = current
		

func _on_player_ammo_changed(current: int, total: int) -> void:
	if ammo_current_label:
		ammo_current_label.text = str(current)
	if ammo_total_label:
		ammo_total_label.text = " / " + str(total)

func _update_enemies_count() -> void:
	if not enemy_count_label:
		return
	# Conta i nodi nemici attivi (bot o enemy)
	var bots = get_tree().get_nodes_in_group("bots")
	var count = bots.size()
	enemy_count_label.text = str(count)

func _on_subtitle_requested(message: String, duration: float) -> void:
	if subtitle_panel and subtitle_label:
		if message.is_empty() or duration <= 0.0:
			subtitle_panel.visible = false
			_subtitle_time_left = 0.0
		else:
			subtitle_label.text = message
			subtitle_panel.visible = true
			_subtitle_time_left = duration

func _on_pause_pressed() -> void:
	# Simula la pressione dell'azione pause_game per attivare il menu di pausa
	var a = InputEventAction.new()
	a.action = &"pause_game"
	a.pressed = true
	Input.parse_input_event(a)

func _on_shoot_down() -> void:
	# Avvia lo sparo touch simulando l'azione del mouse o di sparo
	# (Nei controlli mouse andrebbe ad attivare lo sparo automatico o a invocare _try_fire nel player)
	if player and player.has_method("_try_fire"):
		player.call("_try_fire")
	# Per lo sparo continuo su stick mobile, il player_prototype rileva già right_stick,
	# ma questo pulsante touch serve come sparo manuale fisso.
	var shoot_action = InputEventAction.new()
	shoot_action.action = &"ui_accept" # o altra azione di sparo se mappata
	shoot_action.pressed = true
	Input.parse_input_event(shoot_action)

func _on_shoot_up() -> void:
	var shoot_action = InputEventAction.new()
	shoot_action.action = &"ui_accept"
	shoot_action.pressed = false
	Input.parse_input_event(shoot_action)

func _on_reload_pressed() -> void:
	# Chiama la ricarica sul player
	if player and player.has_method("_try_reload"):
		player.call("_try_reload")


func _update_health_position() -> void:
	if not is_instance_valid(_top_left):
		return
	if is_instance_valid(GlobalSettings._fps_panel) and GlobalSettings._fps_panel.visible:
		_top_left.offset_top = HEALTH_Y_FPS_OFFSET
		_top_left.offset_bottom = HEALTH_Y_FPS_OFFSET + 54
	else:
		_top_left.offset_top = HEALTH_Y_DEFAULT
		_top_left.offset_bottom = HEALTH_Y_DEFAULT + 54

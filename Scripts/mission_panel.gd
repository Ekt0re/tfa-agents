## mission_panel.gd
## Attacca questo script al nodo TopCenter (MarginContainer) nel tuo HUD.
## Si connette automaticamente a MissionManager e aggiorna la UI.
class_name MissionPanel
extends MarginContainer

# ---------------------------------------------------------------------------
# Nodi interni (unique name %)
# ---------------------------------------------------------------------------
@onready var _panel:        PanelContainer = get_node_or_null("%MissionPanelInner")
@onready var _label:        Label          = get_node_or_null("%MissionLabel")
@onready var _counter:      Label          = get_node_or_null("%MissionCounter")
@onready var _progress_bar: ProgressBar    = get_node_or_null("%MissionProgressBar")
@onready var _status_label: Label          = get_node_or_null("%MissionStatus")
@onready var _anim:         AnimationPlayer = get_node_or_null("%MissionAnim")

# StyleBox panels pre-configurati per stato
@export var style_active:    StyleBoxFlat
@export var style_completed: StyleBoxFlat
@export var style_failed:    StyleBoxFlat

# Quality level: 0=Low, 1=Medium, 2=High, 3=Ultra
var _quality_level: int = 2

# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Nascondi di default
	hide()

	# Leggi qualità iniziale da GlobalSettings
	var gs = get_node_or_null("/root/GlobalSettings")
	if gs:
		_quality_level = int(gs.get_setting("graphics_preset", 2))
		if gs.has_signal("settings_changed"):
			gs.settings_changed.connect(_on_settings_changed)

	# Crea le animazioni via codice (in base alla qualità)
	_build_animations()

	# Connetti i segnali di MissionManager
	MissionManager.mission_started.connect(_on_mission_started)
	MissionManager.mission_progress_changed.connect(_on_progress_changed)
	MissionManager.mission_completed.connect(_on_mission_completed)
	MissionManager.mission_failed.connect(_on_mission_failed)
	MissionManager.mission_cleared.connect(_on_mission_cleared)

# ---------------------------------------------------------------------------
# Handlers segnali
# ---------------------------------------------------------------------------
func _on_mission_started(data: MissionData) -> void:
	_on_mission_started_shader_patch(data)
	# Reset visivo e interrompi animazioni in corso
	if _anim and _anim.is_playing():
		_anim.stop()
	# Ripristina proprietà che slide_out potrebbe aver lasciato alterate
	modulate = Color(1, 1, 1, 1)
	scale = Vector2(1, 1)

	if _status_label:
		_status_label.hide()
		_status_label.text = ""
	if _counter:
		_counter.show()
	if _progress_bar:
		_progress_bar.visible = data.show_progress_bar
	if _counter:
		_counter.visible = not data.show_progress_bar and data.target > 0

	# Contenuto — la label è una chiave di traduzione
	if _label:
		_label.text = tr(data.label)
		_label.add_theme_color_override("font_color", Color(0.686275, 0.72549, 0.768627))

	# Accent color su counter
	if _counter:
		_counter.add_theme_color_override("font_color", data.accent_color)

	# Counter iniziale
	if data.target > 0:
		if data.show_progress_bar and _progress_bar:
			_progress_bar.max_value = data.target
			_progress_bar.value     = 0
		elif _counter:
			_counter.text = "0 / %d" % data.target

	# Per missioni booleane (REACH, ACTIVATE) nascondi counter
	if data.target == 0:
		if _counter:
			_counter.hide()
		if _progress_bar:
			_progress_bar.hide()

	# Applica stile active
	if style_active and _panel:
		_panel.add_theme_stylebox_override("panel", style_active)

	show()
	if _quality_level > 0 and _anim and _anim.has_animation("slide_in"):
		_anim.play("slide_in")

func _on_progress_changed(current: int, target: int) -> void:
	var data: MissionData = MissionManager.active_mission
	if data == null:
		return

	if data.show_progress_bar and _progress_bar:
		_progress_bar.value = current
	elif _counter:
		_counter.text = "%d / %d" % [current, target]
		# Accent color pulsa verso bianco avvicinandosi al target
		var t: float = float(current) / float(target) if target > 0 else 0.0
		var c: Color = data.accent_color.lerp(Color.WHITE, t * 0.3)
		_counter.add_theme_color_override("font_color", c)

func _on_mission_completed(data: MissionData) -> void:
	_on_mission_completed_shader_patch(data)
	if _counter:
		_counter.hide()
	if _progress_bar:
		_progress_bar.hide()
	if _status_label:
		_status_label.text = tr("mission_completed")
		_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1.0))
		_status_label.show()

	if style_completed and _panel:
		_panel.add_theme_stylebox_override("panel", style_completed)

	if _quality_level >= 2 and _anim and _anim.has_animation("complete_flash"):
		_anim.play("complete_flash")

	# Auto-clear dopo 2.5 secondi (solo se la missione è ancora quella)
	await get_tree().create_timer(2.5).timeout
	if MissionManager.active_mission == data:
		MissionManager.clear()

func _on_mission_failed(data: MissionData) -> void:
	_on_mission_failed_shader_patch(data)
	if _counter:
		_counter.hide()
	if _progress_bar:
		_progress_bar.hide()
	if _status_label:
		_status_label.text = tr("mission_failed")
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
		_status_label.show()

	if style_failed and _panel:
		_panel.add_theme_stylebox_override("panel", style_failed)

	if _quality_level >= 2 and _anim and _anim.has_animation("fail_flash"):
		_anim.play("fail_flash")

	await get_tree().create_timer(2.5).timeout
	# Clear solo se la missione è ancora quella attiva
	if MissionManager.active_mission == data:
		MissionManager.clear()

func _on_mission_cleared() -> void:
	_on_mission_cleared_shader_patch()
	if _quality_level > 0 and _anim and _anim.has_animation("slide_out"):
		_anim.play("slide_out")
		await _anim.animation_finished
	# Nascondi solo se non è già partita una nuova missione
	if MissionManager.active_mission == null:
		hide()


func _on_settings_changed(new_settings: Dictionary) -> void:
	var new_level := int(new_settings.get("graphics_preset", 2))
	if new_level != _quality_level:
		_quality_level = new_level
		_build_animations()

# ---------------------------------------------------------------------------
# Animazioni — create via codice (root_node = "../.." → TopCenter)
# ---------------------------------------------------------------------------
func _build_animations() -> void:
	if not _anim:
		return

	# Root node = nonno dell'AnimationPlayer: TopCenter (MarginContainer con questo script).
	_anim.root_node = "../.."

	var lib_name := ""
	if not _anim.has_animation_library(lib_name):
		_anim.add_animation_library(lib_name, AnimationLibrary.new())
	var lib: AnimationLibrary = _anim.get_animation_library(lib_name)

	# Rimuovi animazioni esistenti
	for anim_name: String in ["slide_in", "slide_out", "complete_flash", "fail_flash"]:
		if lib.has_animation(anim_name):
			lib.remove_animation(anim_name)

	# Low quality: nessuna animazione
	if _quality_level <= 0:
		return

	# ================================================================
	# slide_in — Medium: solo fade+Y, High/Ultra: bounce+fade+scale
	# ================================================================
	var si := Animation.new()
	si.length = 0.45 if _quality_level >= 2 else 0.3

	# Posizione Y
	var t := si.add_track(Animation.TYPE_VALUE)
	si.track_set_path(t, "offset_top")
	if _quality_level >= 2:
		si.track_insert_key(t, 0.0,  -60.0)
		si.track_insert_key(t, 0.25,   5.0)
		si.track_insert_key(t, 0.35,  -2.0)
		si.track_insert_key(t, 0.45,   0.0)
	else:
		si.track_insert_key(t, 0.0, -30.0)
		si.track_insert_key(t, 0.3,  0.0)

	# Opacità
	t = si.add_track(Animation.TYPE_VALUE)
	si.track_set_path(t, "modulate")
	if _quality_level >= 2:
		si.track_insert_key(t, 0.0,  Color(1, 1, 1, 0.0))
		si.track_insert_key(t, 0.12, Color(1, 1, 1, 0.7))
		si.track_insert_key(t, 0.25, Color(1, 1, 1, 1.0))
	else:
		si.track_insert_key(t, 0.0,  Color(1, 1, 1, 0.0))
		si.track_insert_key(t, 0.3,  Color(1, 1, 1, 1.0))

	# Scala (solo High/Ultra)
	if _quality_level >= 2:
		t = si.add_track(Animation.TYPE_VALUE)
		si.track_set_path(t, "scale:x")
		si.track_insert_key(t, 0.0,  0.92)
		si.track_insert_key(t, 0.30, 1.03)
		si.track_insert_key(t, 0.45, 1.0)
		t = si.add_track(Animation.TYPE_VALUE)
		si.track_set_path(t, "scale:y")
		si.track_insert_key(t, 0.0,  0.92)
		si.track_insert_key(t, 0.30, 1.03)
		si.track_insert_key(t, 0.45, 1.0)

	lib.add_animation("slide_in", si)

	# ================================================================
	# slide_out — Medium: semplice, High/Ultra: con shrink
	# ================================================================
	var so := Animation.new()
	so.length = 0.3 if _quality_level >= 2 else 0.2

	t = so.add_track(Animation.TYPE_VALUE)
	so.track_set_path(t, "offset_top")
	so.track_insert_key(t, 0.0,  0.0)
	so.track_insert_key(t, so.length, -50.0 if _quality_level >= 2 else -30.0)

	t = so.add_track(Animation.TYPE_VALUE)
	so.track_set_path(t, "modulate")
	so.track_insert_key(t, 0.0,  Color(1, 1, 1, 1.0))
	so.track_insert_key(t, so.length, Color(1, 1, 1, 0.0))

	if _quality_level >= 2:
		t = so.add_track(Animation.TYPE_VALUE)
		so.track_set_path(t, "scale:x")
		so.track_insert_key(t, 0.0, 1.0)
		so.track_insert_key(t, 0.3, 0.95)
		t = so.add_track(Animation.TYPE_VALUE)
		so.track_set_path(t, "scale:y")
		so.track_insert_key(t, 0.0, 1.0)
		so.track_insert_key(t, 0.3, 0.95)

	lib.add_animation("slide_out", so)

	# Flash animations (solo High/Ultra)
	if _quality_level < 2:
		return

	# ================================================================
	# complete_flash — celebrazione verde con pulse
	# ================================================================
	var cf := Animation.new()
	cf.length = 0.7

	t = cf.add_track(Animation.TYPE_VALUE)
	cf.track_set_path(t, "MissionPanelInner:modulate")
	cf.track_insert_key(t, 0.0,  Color(1.0, 1.0, 1.0, 1.0))
	cf.track_insert_key(t, 0.12, Color(0.6, 1.6, 0.6, 1.0))
	cf.track_insert_key(t, 0.30, Color(0.85, 1.2, 0.85, 1.0))
	cf.track_insert_key(t, 0.50, Color(1.05, 1.05, 1.05, 1.0))
	cf.track_insert_key(t, 0.7,  Color(1.0, 1.0, 1.0, 1.0))

	t = cf.add_track(Animation.TYPE_VALUE)
	cf.track_set_path(t, "scale:x")
	cf.track_insert_key(t, 0.0,  1.0)
	cf.track_insert_key(t, 0.10, 1.04)
	cf.track_insert_key(t, 0.25, 0.98)
	cf.track_insert_key(t, 0.40, 1.01)
	cf.track_insert_key(t, 0.55, 1.0)

	t = cf.add_track(Animation.TYPE_VALUE)
	cf.track_set_path(t, "scale:y")
	cf.track_insert_key(t, 0.0,  1.0)
	cf.track_insert_key(t, 0.10, 1.04)
	cf.track_insert_key(t, 0.25, 0.98)
	cf.track_insert_key(t, 0.40, 1.01)
	cf.track_insert_key(t, 0.55, 1.0)

	lib.add_animation("complete_flash", cf)

	# ================================================================
	# fail_flash — flash rosso di fallimento
	# ================================================================
	var ff := Animation.new()
	ff.length = 0.6

	t = ff.add_track(Animation.TYPE_VALUE)
	ff.track_set_path(t, "MissionPanelInner:modulate")
	ff.track_insert_key(t, 0.0,  Color(1.0, 1.0, 1.0, 1.0))
	ff.track_insert_key(t, 0.10, Color(1.6, 0.4, 0.4, 1.0))
	ff.track_insert_key(t, 0.30, Color(1.2, 0.7, 0.7, 1.0))
	ff.track_insert_key(t, 0.6,  Color(1.0, 1.0, 1.0, 1.0))

	t = ff.add_track(Animation.TYPE_VALUE)
	ff.track_set_path(t, "scale:x")
	ff.track_insert_key(t, 0.0,  1.0)
	ff.track_insert_key(t, 0.08, 1.015)
	ff.track_insert_key(t, 0.16, 0.985)
	ff.track_insert_key(t, 0.24, 1.008)
	ff.track_insert_key(t, 0.32, 0.995)
	ff.track_insert_key(t, 0.40, 1.0)

	lib.add_animation("fail_flash", ff)

func _process(delta: float) -> void:
	# Incrementa state_time sullo shader del pannello
	if _panel and _panel.material is ShaderMaterial:
		var t = _panel.material.get_shader_parameter("state_time")
		_panel.material.set_shader_parameter(
			"state_time",
			(float(t) if t != null else 0.0) + delta
		)
	# Sincronizza fill_pct della progress bar
	if _progress_bar and _progress_bar.material is ShaderMaterial:
		var pct: float = 0.0
		if _progress_bar.max_value > 0:
			pct = _progress_bar.value / _progress_bar.max_value
		_progress_bar.material.set_shader_parameter("fill_pct", pct)
		
func _set_shader_state(state: float) -> void:
	# Pannello
	if _panel and _panel.material is ShaderMaterial:
		_panel.material.set_shader_parameter("mission_state", state)
		_panel.material.set_shader_parameter("state_time", 0.0)
	# Barra progresso
	if _progress_bar and _progress_bar.material is ShaderMaterial:
		_progress_bar.material.set_shader_parameter("mission_state", state)
		
# ---------------------------------------------------------------------------
func _on_mission_started_shader_patch(data: MissionData) -> void:
	_set_shader_state(0.0)   # stato normale

func _on_mission_completed_shader_patch(_data: MissionData) -> void:
	_set_shader_state(1.0)   # completato → verde
	
func _on_mission_failed_shader_patch(_data: MissionData) -> void:
	_set_shader_state(-1.0)  # fallito → rosso

func _on_mission_cleared_shader_patch() -> void:
	_set_shader_state(0.0)

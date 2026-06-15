## mission_panel.gd
## Attacca questo script al nodo TopCenter (MarginContainer) nel tuo HUD.
## Si connette automaticamente a MissionManager e aggiorna la UI.
class_name MissionPanel
extends MarginContainer

# ---------------------------------------------------------------------------
# Nodi interni (unique name %)
# ---------------------------------------------------------------------------
@onready var _panel:        PanelContainer = %MissionPanelInner
@onready var _icon_label:   Label          = %MissionIcon
@onready var _label:        Label          = %MissionLabel
@onready var _counter:      Label          = %MissionCounter
@onready var _progress_bar: ProgressBar    = %MissionProgressBar
@onready var _status_label: Label          = %MissionStatus
@onready var _anim:         AnimationPlayer = %MissionAnim

# ---------------------------------------------------------------------------
# Costanti di stile
# ---------------------------------------------------------------------------
const ICON_MAP: Dictionary = {
	MissionData.Type.ELIMINATE: "✖",
	MissionData.Type.COLLECT:   "◆",
	MissionData.Type.REACH:     "▶",
	MissionData.Type.ACTIVATE:  "◉",
	MissionData.Type.SURVIVE:   "◷",
	MissionData.Type.CUSTOM:    "◈",
}

# StyleBox panels pre-configurati per stato
@export var style_active:    StyleBoxFlat
@export var style_completed: StyleBoxFlat
@export var style_failed:    StyleBoxFlat

# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Nascondi di default
	hide()

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
	# Reset visual
	_status_label.hide()
	_status_label.text = ""
	_counter.show()
	_progress_bar.visible = data.show_progress_bar
	_counter.visible      = not data.show_progress_bar and data.target > 0

	# Contenuto
	_icon_label.text  = ICON_MAP.get(data.type, "◈")
	_label.text       = data.label
	_label.add_theme_color_override("font_color", Color(0.686275, 0.72549, 0.768627))

	# Accent color su counter e icon
	_counter.add_theme_color_override("font_color", data.accent_color)
	_icon_label.add_theme_color_override("font_color", data.accent_color)

	# Counter iniziale
	if data.target > 0:
		if data.show_progress_bar:
			_progress_bar.max_value = data.target
			_progress_bar.value     = 0
		else:
			_counter.text = "0 / %d" % data.target

	# Per missioni booleane (REACH, ACTIVATE) nascondi counter
	if data.target == 0:
		_counter.hide()
		_progress_bar.hide()

	# Applica stile active
	if style_active:
		_panel.add_theme_stylebox_override("panel", style_active)

	show()
	if _anim.has_animation("slide_in"):
		_anim.play("slide_in")

func _on_progress_changed(current: int, target: int) -> void:
	var data: MissionData = MissionManager.active_mission
	if data == null:
		return

	if data.show_progress_bar:
		_progress_bar.value = current
	else:
		_counter.text = "%d / %d" % [current, target]
		# Accent color pulsa verso bianco avvicinandosi al target
		var t: float = float(current) / float(target) if target > 0 else 0.0
		var c: Color = data.accent_color.lerp(Color.WHITE, t * 0.3)
		_counter.add_theme_color_override("font_color", c)

func _on_mission_completed(data: MissionData) -> void:
	_counter.hide()
	_progress_bar.hide()
	_status_label.text = "✔ COMPLETATA"
	_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1.0))
	_status_label.show()

	if style_completed:
		_panel.add_theme_stylebox_override("panel", style_completed)

	if _anim.has_animation("complete_flash"):
		_anim.play("complete_flash")

	# Auto-clear dopo 2.5 secondi
	await get_tree().create_timer(2.5).timeout
	if MissionManager.active_mission == null or \
	   MissionManager.active_mission == data:
		MissionManager.clear()

func _on_mission_failed(data: MissionData) -> void:
	_counter.hide()
	_progress_bar.hide()
	_status_label.text = "✖ FALLITA"
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	_status_label.show()

	if style_failed:
		_panel.add_theme_stylebox_override("panel", style_failed)

	await get_tree().create_timer(2.5).timeout
	MissionManager.clear()

func _on_mission_cleared() -> void:
	if _anim.has_animation("slide_out"):
		_anim.play("slide_out")
		await _anim.animation_finished
	hide()

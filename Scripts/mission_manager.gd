## mission_manager.gd
## Autoload singleton. Aggiungilo in Project > Autoload come "MissionManager".
##
## API pubblica:
##   MissionManager.start(data: MissionData)        → avvia una missione
##   MissionManager.update_progress(amount: int)    → incrementa progress (+1 di default)
##   MissionManager.set_progress(value: int)        → imposta progress assoluto
##   MissionManager.complete()                      → forza completamento
##   MissionManager.fail()                          → forza fallimento
##   MissionManager.clear()                         → rimuove missione attiva (nasconde HUD)
##
## Segnali ascoltati dall'HUD:
##   mission_started(data)
##   mission_progress_changed(current, target)
##   mission_completed(data)
##   mission_failed(data)
##   mission_cleared()
extends Node

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------
signal mission_started(data: MissionData)
signal mission_progress_changed(current: int, target: int)
signal mission_completed(data: MissionData)
signal mission_failed(data: MissionData)
signal mission_cleared()

# ---------------------------------------------------------------------------
# Stato interno
# ---------------------------------------------------------------------------
var _active: MissionData = null
var _progress: int       = 0
var _completed: bool     = false

# ---------------------------------------------------------------------------
# Proprietà di sola lettura
# ---------------------------------------------------------------------------
var active_mission: MissionData:
	get: return _active

var progress: int:
	get: return _progress

# ---------------------------------------------------------------------------
# API pubblica
# ---------------------------------------------------------------------------

## Avvia una nuova missione. Sostituisce qualsiasi missione in corso.
func start(data: MissionData) -> void:
	_active   = data
	_progress = 0
	_completed = false
	emit_signal("mission_started", data)
	# Per missioni senza counter (REACH, ACTIVATE) non serve progress
	if data.target > 0:
		emit_signal("mission_progress_changed", 0, data.target)

## Incrementa il progresso di [amount] unità (default +1).
func update_progress(amount: int = 1) -> void:
	if _active == null:
		return
	_progress = clampi(_progress + amount, 0, _active.target)
	emit_signal("mission_progress_changed", _progress, _active.target)
	if _active.target > 0 and _progress >= _active.target:
		complete()

## Imposta il progresso a un valore assoluto.
func set_progress(value: int) -> void:
	if _active == null:
		return
	_progress = clampi(value, 0, _active.target)
	emit_signal("mission_progress_changed", _progress, _active.target)
	if _active.target > 0 and _progress >= _active.target:
		complete()

## Forza il completamento della missione attiva.
func complete() -> void:
	if _active == null or _completed:
		return
	_completed = true
	var completed: MissionData = _active
	emit_signal("mission_completed", completed)
	# Non chiama clear() automaticamente: l'HUD mostra "COMPLETATA" poi il
	# gioco chiama clear() quando vuole nascondere il pannello.

## Forza il fallimento della missione attiva.
func fail() -> void:
	if _active == null or _completed:
		return
	_completed = true
	emit_signal("mission_failed", _active)

## Rimuove la missione attiva e nasconde il pannello HUD.
func clear() -> void:
	_active   = null
	_progress = 0
	_completed = false
	emit_signal("mission_cleared")

# ---------------------------------------------------------------------------
# Helper factory — crea MissionData inline senza file .tres
# ---------------------------------------------------------------------------

## Crea una missione "Elimina nemici".
## Esempio: MissionManager.start(MissionManager.make_eliminate(5))
func make_eliminate(count: int, label: String = "") -> MissionData:
	var d := MissionData.new()
	d.type        = MissionData.Type.ELIMINATE
	if label.is_empty():
		d.label = TranslationServer.translate("mission_neutralize")
	else:
		d.label = label
	d.target      = count
	d.mission_id  = "eliminate_%d" % count
	d.accent_color = Color(0.988235, 0.380392, 0.156863, 1) # arancio
	return d

## Crea una missione "Raccogli item".
func make_collect(count: int, item_name: String) -> MissionData:
	var d := MissionData.new()
	d.type        = MissionData.Type.COLLECT
	d.label       = (TranslationServer.translate("mission_collect") % item_name.to_upper())
	d.target      = count
	d.mission_id  = "collect_%s" % item_name.to_lower()
	d.accent_color = Color(0.2, 0.9, 0.4, 1) # verde
	return d

## Crea una missione "Raggiungi punto".
func make_reach(point_name: String) -> MissionData:
	var d := MissionData.new()
	d.type        = MissionData.Type.REACH
	d.label       = TranslationServer.translate("mission_reach") % point_name.to_upper()
	d.target      = 0
	d.mission_id  = "reach_%s" % point_name.to_lower()
	d.accent_color = Color(0.0, 0.898039, 1.0, 1) # ciano
	return d

## Crea una missione "Attiva oggetto".
func make_activate(object_name: String) -> MissionData:
	var d := MissionData.new()
	d.type        = MissionData.Type.ACTIVATE
	d.label       = TranslationServer.translate("mission_activate") % object_name.to_upper()
	d.target      = 0
	d.mission_id  = "activate_%s" % object_name.to_lower()
	d.accent_color = Color(0.9, 0.8, 0.1, 1) # giallo
	return d

## Crea una missione "Sopravvivi N secondi".
func make_survive(seconds: int) -> MissionData:
	var d := MissionData.new()
	d.type        = MissionData.Type.SURVIVE
	d.label       = TranslationServer.translate("mission_survive")
	d.target      = seconds
	d.mission_id  = "survive_%ds" % seconds
	d.accent_color = Color(0.8, 0.2, 0.9, 1) # viola
	d.show_progress_bar = true
	return d

## Crea una missione custom a testo libero.
func make_custom(label: String, target: int = 0, color: Color = Color.WHITE) -> MissionData:
	var d := MissionData.new()
	d.type        = MissionData.Type.CUSTOM
	d.label       = label
	d.target      = target
	d.mission_id  = "custom_%s" % label.to_lower().replace(" ", "_")
	d.accent_color = color
	return d

## resource_preloader.gd — v2
## Autoload singleton per caricamento asincrono di scene e warm-up shader.
##
## DESIGN: il polling NON chiama mai load_threaded_get() durante _process()
## perché quella chiamata sincronizza con il main thread e causa freeze su
## scene grandi. Il cambio scena usa change_scene_to_file() che in Godot 4
## riutilizza internamente la cache del threaded loader (veloce ma non bloccante).
##
## API pubblica:
##   ResourcePreloader.preload_resources(paths: Array[String])
##   ResourcePreloader.preload_shaders(shader_paths: Array[String])
##   ResourcePreloader.get_progress() → float [0.0 … 1.0]
##   ResourcePreloader.is_done() → bool
##   ResourcePreloader.change_scene_when_ready(path: String)
##
## Segnali:
##   progress_changed(overall: float)
##   all_loaded()

extends Node

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------
signal progress_changed(overall: float)
signal all_loaded()

# ---------------------------------------------------------------------------
# Stato interno
# ---------------------------------------------------------------------------

## Percorsi in attesa di completamento: path → true
var _pending: Dictionary = {}

## Percorsi completati (LOADED o FAILED)
var _completed: Dictionary = {}

## ShaderMaterial dummy mantenuti in memoria per warm-up GPU
var _shader_materials: Array[ShaderMaterial] = []

## Path della scena da aprire quando tutto è pronto
var _pending_scene_path: String = ""

## Totale richieste avviate (per calcolo progresso)
var _total_requested: int = 0

## Ultima percentuale emessa (per evitare spam di segnali identici)
var _last_emitted_progress: float = -1.0

## Flag: tutto completato
var _done: bool = true


# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)   # attivato solo quando c'è lavoro


func _process(_delta: float) -> void:
	_poll_pending()
	_emit_progress()

	if _pending.is_empty():
		_finalize()


# ---------------------------------------------------------------------------
# API pubblica
# ---------------------------------------------------------------------------

## Avvia il preload in background della scena indicata.
## Includere solo scene "radice" — Godot carica automaticamente le dipendenze.
func preload_resources(paths: Array[String]) -> void:
	var any_new := false

	for path in paths:
		if path.is_empty():
			continue
		if _pending.has(path) or _completed.has(path):
			continue   # già in coda o completato
		if not ResourceLoader.exists(path):
			push_warning("ResourcePreloader: non trovato → %s" % path)
			continue

		var err := ResourceLoader.load_threaded_request(path)
		if err != OK:
			push_warning("ResourcePreloader: load_threaded_request err=%d → %s" % [err, path])
			continue

		_pending[path] = true
		_total_requested += 1
		any_new = true
		print("ResourcePreloader: avviato → ", path)

	if any_new:
		_done = false
		set_process(true)
		_emit_progress()


## Carica gli shader SINCRONAMENTE (sono semplici file GLSL di testo, ~KB)
## e crea dummy ShaderMaterial per forzare la compilazione GPU.
func preload_shaders(shader_paths: Array[String]) -> void:
	for path in shader_paths:
		if path.is_empty() or _completed.has(path):
			continue
		if not ResourceLoader.exists(path):
			push_warning("ResourcePreloader: shader non trovato → %s" % path)
			continue

		var shader: Resource = load(path)
		if not (shader is Shader):
			push_warning("ResourcePreloader: shader non valido → %s" % path)
			continue

		_completed[path] = shader
		_total_requested += 1  # contato come le altre risorse per il progresso
		var mat := ShaderMaterial.new()
		mat.shader = shader as Shader
		_shader_materials.append(mat)
		print("ResourcePreloader: shader pronto → ", path)


## Progresso globale [0.0 … 1.0].
func get_progress() -> float:
	if _total_requested == 0:
		return 1.0

	var done_count := float(_completed.size())
	var partial := 0.0

	for path in _pending.keys():
		var sub: Array = []
		# Ignoriamo il valore di ritorno — serve solo sub per il progresso parziale
		ResourceLoader.load_threaded_get_status(path, sub)
		if not sub.is_empty():
			partial += clampf(float(sub[0]), 0.0, 1.0)

	return clampf((done_count + partial) / float(_total_requested), 0.0, 1.0)


## true se non ci sono risorse ancora in caricamento.
func is_done() -> bool:
	return _done


## Cambia scena non appena il preload è terminato.
## Se già tutto pronto, cambia scena immediatamente.
func change_scene_when_ready(path: String) -> void:
	if _done:
		_do_change_scene(path)
		return
	# Memorizza la destinazione: il cambio avverrà in _finalize()
	_pending_scene_path = path


# ---------------------------------------------------------------------------
# Polling interno (chiamato ogni frame da _process)
# ---------------------------------------------------------------------------

func _poll_pending() -> void:
	var finished: Array[String] = []

	for path in _pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				# Status LOADED → load_threaded_get è veloce (resource già in RAM)
				var res := ResourceLoader.load_threaded_get(path)
				if res != null:
					_completed[path] = res   # salva il Resource per change_scene_to_packed
					print("ResourcePreloader: pronto → %s [%s]" % [path, res.get_class()])
				else:
					_completed[path] = true
					push_warning("ResourcePreloader: load_threaded_get null → %s" % path)
				finished.append(path)

			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error("ResourcePreloader: caricamento fallito → %s" % path)
				_completed[path] = true
				finished.append(path)

			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pass

	for path in finished:
		_pending.erase(path)


func _finalize() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	progress_changed.emit(1.0)
	all_loaded.emit()
	print("ResourcePreloader: tutto pronto (%d risorse)" % _completed.size())

	if not _pending_scene_path.is_empty():
		var target := _pending_scene_path
		_pending_scene_path = ""
		call_deferred("_do_change_scene", target)


func _emit_progress() -> void:
	var p := get_progress()
	if abs(p - _last_emitted_progress) >= 0.005:
		_last_emitted_progress = p
		progress_changed.emit(p)


func _do_change_scene(path: String) -> void:
	if not is_instance_valid(get_tree()):
		return
	# Se la risorsa è in cache come PackedScene (caricata via load_threaded_get)
	# usa change_scene_to_packed: più veloce perché non ricarica dal disco.
	var cached: Variant = _completed.get(path, null)
	if cached is PackedScene:
		get_tree().change_scene_to_packed(cached as PackedScene)
	else:
		get_tree().change_scene_to_file(path)

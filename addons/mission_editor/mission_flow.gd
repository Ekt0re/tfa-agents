## mission_flow.gd
## Resource che contiene un intero flusso di missioni (grafo).
## Salvabile come .tres per riutilizzo e caricamento runtime.
@tool
class_name MissionFlow
extends Resource

## ID univoco del flusso
@export var flow_id: String = ""

## Nome visualizzato nell'editor
@export var flow_name: String = "New Flow"

## Descrizione del flusso
@export var description: String = ""

## ID della missione di partenza (entry point)
@export var start_mission_id: String = ""

## Lista di tutte le missioni nel flusso
@export var missions: Array[Resource] = []

## Connessioni esplicite tra missioni (from_id -> { success: to_id, fail: to_id })
## Usate dal graph editor per disegnare le frecce
@export var connections: Array[Dictionary] = []


## Ritorna una missione per ID
func get_mission_by_id(mission_id: String) -> Resource:
	for m: Resource in missions:
		if m is MissionData and (m as MissionData).mission_id == mission_id:
			return m
	return null


## Ritorna tutte le missioni collegate a una data (successo o fallimento)
func get_connected_missions(mission_id: String) -> Array[String]:
	var result: Array[String] = []
	var mission: Resource = get_mission_by_id(mission_id)
	if mission == null or not (mission is MissionData):
		return result
	var data := mission as MissionData
	if not data.on_success_next.is_empty():
		result.append(data.on_success_next)
	if not data.on_fail_next.is_empty():
		result.append(data.on_fail_next)
	return result


## Ritorna la missione iniziale
func get_start_mission() -> Resource:
	if start_mission_id.is_empty() and not missions.is_empty():
		return missions[0]
	return get_mission_by_id(start_mission_id)


## Aggiunge una nuova missione al flusso con ID auto-generato
func add_mission(type: int = MissionData.Type.CUSTOM) -> MissionData:
	var data := MissionData.new()
	data.type = type as MissionData.Type
	data.mission_id = _generate_unique_id()
	data.label = "New Mission"
	# Posiziona il nodo a destra dell'ultimo
	if not missions.is_empty():
		var last := missions[-1] as MissionData
		if last:
			data.graph_position = last.graph_position + Vector2(300, 0)
	missions.append(data)
	return data


## Rimuove una missione per ID
func remove_mission(mission_id: String) -> void:
	for i in range(missions.size() - 1, -1, -1):
		if missions[i] is MissionData and (missions[i] as MissionData).mission_id == mission_id:
			missions.remove_at(i)
			break
	# Rimuovi connessioni che la referenziano
	_cleanup_connections(mission_id)


## Aggiunge una connessione esplicita (per il graph editor)
func add_connection(from_id: String, to_id: String, is_fail: bool = false) -> void:
	var conn := {
		"from": from_id,
		"to": to_id,
		"is_fail": is_fail
	}
	connections.append(conn)
	# Aggiorna anche il campo diretto sulla missione
	var mission := get_mission_by_id(from_id)
	if mission and mission is MissionData:
		var data := mission as MissionData
		if is_fail:
			data.on_fail_next = to_id
		else:
			data.on_success_next = to_id


## Rimuove una connessione
func remove_connection(from_id: String, to_id: String) -> void:
	for i in range(connections.size() - 1, -1, -1):
		var conn: Dictionary = connections[i]
		if conn.get("from", "") == from_id and conn.get("to", "") == to_id:
			connections.remove_at(i)


## Genera un ID univoco
func _generate_unique_id() -> String:
	var base := "mission_"
	var counter := missions.size() + 1
	while true:
		var candidate := "%s%03d" % [base, counter]
		if get_mission_by_id(candidate) == null:
			return candidate
		counter += 1
	return "%s%03d" % [base, counter]  # Fallback (unreachable)


## Pulisce connessioni che referenziano un ID rimosso
func _cleanup_connections(removed_id: String) -> void:
	for i in range(connections.size() - 1, -1, -1):
		var conn: Dictionary = connections[i]
		if conn.get("from", "") == removed_id or conn.get("to", "") == removed_id:
			connections.remove_at(i)
	# Pulisci riferimenti nelle missioni rimanenti
	for m: Resource in missions:
		if m is MissionData:
			var data := m as MissionData
			if data.on_success_next == removed_id:
				data.on_success_next = ""
			if data.on_fail_next == removed_id:
				data.on_fail_next = ""

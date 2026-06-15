## editor_main.gd
## Dock principale del Mission Flow Editor (Dialogic-style).
## Crea l'intera UI via codice: toolbar, graph editor, inspector, command editor.
@tool
extends VBoxContainer

# Reference al plugin
var _plugin: EditorPlugin = null
# Flow corrente
var _current_flow: Resource = null
var _current_path: String = ""
var _selected_mission_id: String = ""

# UI Nodes
var _toolbar: HBoxContainer = null
var _tab_container: TabContainer = null
var _graph_edit: GraphEdit = null
var _mission_list: ItemList = null
var _inspector_panel: VBoxContainer = null
var _command_panel: VBoxContainer = null
var _hsplit: HSplitContainer = null
var _status_label: Label = null

# Inspector fields
var _insp_id: LineEdit = null
var _insp_label: LineEdit = null
var _insp_desc: TextEdit = null
var _insp_type: OptionButton = null
var _insp_target: SpinBox = null
var _insp_color: ColorPickerButton = null
var _insp_progress_bar: CheckBox = null
var _insp_time_limit: SpinBox = null
var _insp_success_next: OptionButton = null
var _insp_fail_next: OptionButton = null
var _insp_tags: LineEdit = null
var _insp_fail_cond: LineEdit = null

# Command editor
var _cmd_list: ItemList = null
var _cmd_type: OptionButton = null
var _cmd_params: TextEdit = null
var _cmd_delay: SpinBox = null
var _cmd_enabled: CheckBox = null
var _cmd_desc: LineEdit = null
var _is_success_commands: bool = true

# Mission type names
const MISSION_TYPES := ["ELIMINATE", "COLLECT", "REACH", "ACTIVATE", "SURVIVE", "CUSTOM"]
const MISSION_COLORS := [
	Color(0.988, 0.38, 0.157), Color(0.2, 0.9, 0.4),
	Color(0.0, 0.898, 1.0), Color(0.9, 0.8, 0.1),
	Color(0.8, 0.2, 0.9), Color.WHITE
]

# Command type names
const CMD_TYPES := [
	"PLAY_SOUND", "CHANGE_SCENE", "SPAWN_ENEMIES", "PLAY_ANIMATION",
	"SET_VARIABLE", "CALL_METHOD", "SHOW_DIALOG",
	"ENABLE_CHECKPOINT", "DISABLE_CHECKPOINT", "DELAY"
]


func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _ready() -> void:
	custom_minimum_size = Vector2(350, 500)
	_build_ui()


# =========================================================================
# UI Construction
# =========================================================================

func _build_ui() -> void:
	# Toolbar
	_build_toolbar()
	# Status bar
	_status_label = Label.new()
	_status_label.text = "No flow loaded"
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	# Main split: graph/list | inspector
	_hsplit = HSplitContainer.new()
	_hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hsplit.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	add_child(_hsplit)

	# Left: tabs
	var left_panel := VBoxContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.5
	_hsplit.add_child(left_panel)

	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(_tab_container)

	# Flow Graph tab
	_graph_edit = GraphEdit.new()
	_graph_edit.name = "Flow Graph"
	_graph_edit.minimap_enabled = true
	_graph_edit.show_grid = true
	_graph_edit.grid_pattern = GraphEdit.GRID_PATTERN_LINES
	_graph_edit.connection_request.connect(_on_connection_request)
	_graph_edit.disconnection_request.connect(_on_disconnection_request)
	_graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph_edit.node_selected.connect(_on_graph_node_selected)
	_tab_container.add_child(_graph_edit)

	# Mission List tab
	_mission_list = ItemList.new()
	_mission_list.name = "Mission List"
	_mission_list.item_selected.connect(_on_list_item_selected)
	_tab_container.add_child(_mission_list)

	# Right: inspector + commands
	var right_panel := VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	_hsplit.add_child(right_panel)

	# Inspector
	_build_inspector(right_panel)
	# Command editor
	_build_command_editor(right_panel)

	add_child(_status_label)


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 4)

	var btn_new := Button.new()
	btn_new.text = "New"
	btn_new.tooltip_text = "Create new mission flow"
	btn_new.pressed.connect(_on_new_pressed)
	_toolbar.add_child(btn_new)

	var btn_open := Button.new()
	btn_open.text = "Open"
	btn_open.tooltip_text = "Open existing .tres flow"
	btn_open.pressed.connect(_on_open_pressed)
	_toolbar.add_child(btn_open)

	var btn_save := Button.new()
	btn_save.text = "Save"
	btn_save.tooltip_text = "Save current flow"
	btn_save.pressed.connect(_on_save_pressed)
	_toolbar.add_child(btn_save)

	var sep := VSeparator.new()
	_toolbar.add_child(sep)

	var btn_add := Button.new()
	btn_add.text = "+ Mission"
	btn_add.tooltip_text = "Add new mission node"
	btn_add.pressed.connect(_on_add_mission_pressed)
	_toolbar.add_child(btn_add)

	var btn_del := Button.new()
	btn_del.text = "- Del"
	btn_del.tooltip_text = "Delete selected mission"
	btn_del.pressed.connect(_on_delete_mission_pressed)
	_toolbar.add_child(btn_del)

	add_child(_toolbar)


func _build_inspector(parent: VBoxContainer) -> void:
	_inspector_panel = VBoxContainer.new()
	_inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = "Mission Inspector"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.0, 0.898, 1.0))
	_inspector_panel.add_child(lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_panel.add_child(scroll)

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 8)
	form.add_theme_constant_override("v_separation", 4)
	scroll.add_child(form)

	# ID
	_add_form_row(form, "ID:", _make_line_edit("_insp_id"))
	# Label
	_add_form_row(form, "Label:", _make_line_edit("_insp_label"))
	# Type
	_insp_type = OptionButton.new()
	for t in MISSION_TYPES:
		_insp_type.add_item(t)
	_insp_type.item_selected.connect(_on_inspector_changed)
	_add_form_row(form, "Type:", _insp_type)
	# Target
	_insp_target = SpinBox.new()
	_insp_target.min_value = 0
	_insp_target.max_value = 9999
	_insp_target.value_changed.connect(func(_v): _on_inspector_changed())
	_add_form_row(form, "Target:", _insp_target)
	# Color
	_insp_color = ColorPickerButton.new()
	_insp_color.color = Color.WHITE
	_insp_color.color_changed.connect(func(_c): _on_inspector_changed())
	_add_form_row(form, "Color:", _insp_color)
	# Progress Bar
	_insp_progress_bar = CheckBox.new()
	_insp_progress_bar.text = "Show"
	_insp_progress_bar.toggled.connect(func(_v): _on_inspector_changed())
	_add_form_row(form, "Progress Bar:", _insp_progress_bar)
	# Time Limit
	_insp_time_limit = SpinBox.new()
	_insp_time_limit.min_value = 0.0
	_insp_time_limit.max_value = 9999.0
	_insp_time_limit.suffix = "s"
	_insp_time_limit.value_changed.connect(func(_v): _on_inspector_changed())
	_add_form_row(form, "Time Limit:", _insp_time_limit)
	# Success Next
	_insp_success_next = OptionButton.new()
	_insp_success_next.add_item("(none)", 0)
	_insp_success_next.item_selected.connect(func(_i): _on_inspector_changed())
	_add_form_row(form, "On Success →", _insp_success_next)
	# Fail Next
	_insp_fail_next = OptionButton.new()
	_insp_fail_next.add_item("(none)", 0)
	_insp_fail_next.item_selected.connect(func(_i): _on_inspector_changed())
	_add_form_row(form, "On Fail →", _insp_fail_next)
	# Description
	_insp_desc = TextEdit.new()
	_insp_desc.custom_minimum_size = Vector2(0, 60)
	_insp_desc.text_changed.connect(_on_inspector_changed)
	_add_form_row(form, "Description:", _insp_desc)
	# Tags
	_add_form_row(form, "Tags:", _make_line_edit("_insp_tags"))
	# Fail Condition
	_add_form_row(form, "Fail Cond:", _make_line_edit("_insp_fail_cond"))

	parent.add_child(_inspector_panel)


func _build_command_editor(parent: VBoxContainer) -> void:
	_command_panel = VBoxContainer.new()
	_command_panel.custom_minimum_size = Vector2(0, 200)

	var lbl := Label.new()
	lbl.text = "Commands"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.1))
	_command_panel.add_child(lbl)

	# Toggle success/fail commands
	var toggle_hbox := HBoxContainer.new()
	var btn_success := Button.new()
	btn_success.text = "On Complete"
	btn_success.toggle_mode = true
	btn_success.button_pressed = true
	btn_success.pressed.connect(func(): _is_success_commands = true; _refresh_command_list())
	toggle_hbox.add_child(btn_success)
	var btn_fail := Button.new()
	btn_fail.text = "On Fail"
	btn_fail.toggle_mode = true
	btn_fail.pressed.connect(func(): _is_success_commands = false; _refresh_command_list())
	toggle_hbox.add_child(btn_fail)
	_command_panel.add_child(toggle_hbox)

	# Command list
	_cmd_list = ItemList.new()
	_cmd_list.custom_minimum_size = Vector2(0, 80)
	_cmd_list.item_selected.connect(_on_cmd_selected)
	_command_panel.add_child(_cmd_list)

	# Add/Remove buttons
	var cmd_btns := HBoxContainer.new()
	var btn_add_cmd := Button.new()
	btn_add_cmd.text = "+ Add Cmd"
	btn_add_cmd.pressed.connect(_on_add_command)
	cmd_btns.add_child(btn_add_cmd)
	var btn_del_cmd := Button.new()
	btn_del_cmd.text = "- Remove"
	btn_del_cmd.pressed.connect(_on_remove_command)
	cmd_btns.add_child(btn_del_cmd)
	_command_panel.add_child(cmd_btns)

	# Command properties
	var cmd_form := GridContainer.new()
	cmd_form.columns = 2
	_cmd_type = OptionButton.new()
	for ct in CMD_TYPES:
		_cmd_type.add_item(ct)
	_cmd_type.item_selected.connect(func(_i): _on_cmd_property_changed())
	_add_form_row(cmd_form, "Type:", _cmd_type)

	_cmd_params = TextEdit.new()
	_cmd_params.custom_minimum_size = Vector2(0, 50)
	_cmd_params.placeholder_text = '{ "key": "value" }'
	_cmd_params.text_changed.connect(_on_cmd_property_changed)
	_add_form_row(cmd_form, "Params:", _cmd_params)

	_cmd_delay = SpinBox.new()
	_cmd_delay.min_value = 0.0
	_cmd_delay.max_value = 60.0
	_cmd_delay.suffix = "s"
	_cmd_delay.value_changed.connect(func(_v): _on_cmd_property_changed())
	_add_form_row(cmd_form, "Delay:", _cmd_delay)

	_cmd_enabled = CheckBox.new()
	_cmd_enabled.text = "Enabled"
	_cmd_enabled.button_pressed = true
	_cmd_enabled.toggled.connect(func(_v): _on_cmd_property_changed())
	_add_form_row(cmd_form, "Active:", _cmd_enabled)

	_add_form_row(cmd_form, "Desc:", _make_line_edit("_cmd_desc"))

	_command_panel.add_child(cmd_form)
	parent.add_child(_command_panel)


# =========================================================================
# Helpers
# =========================================================================

func _add_form_row(form: GridContainer, label_text: String, control: Control) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	form.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(control)


func _make_line_edit(field_name: String) -> LineEdit:
	var le := LineEdit.new()
	le.text_changed.connect(func(_t): _on_inspector_changed())
	set(field_name, le)
	return le


# =========================================================================
# Data loading
# =========================================================================

func _load_flow(flow: Resource) -> void:
	_current_flow = flow
	_rebuild_graph()
	_rebuild_list()
	_refresh_branch_options()
	_status_label.text = "Flow: %s (%d missions)" % [
		flow.get("flow_name") if flow else "?",
		flow.get("missions").size() if flow else 0
	]


func _rebuild_graph() -> void:
	# Clear existing
	for child in _graph_edit.get_children():
		if child is GraphNode:
			child.queue_free()
	_graph_edit.clear_connections()
	if _current_flow == null:
		return

	var missions_arr: Array = _current_flow.get("missions")
	var start_id: String = _current_flow.get("start_mission_id")

	# Create nodes
	for m in missions_arr:
		if m == null:
			continue
		var gn := GraphNode.new()
		gn.name = m.get("mission_id")
		gn.title = m.get("label") if m.get("label") != "" else m.get("mission_id")
		gn.position_offset = m.get("graph_position")
		gn.tooltip_text = m.get("description") if m.get("description") else ""

		# Color by type
		var type_idx: int = int(m.get("type"))
		if type_idx < MISSION_COLORS.size():
			gn.set("theme_override_colors/close_color", MISSION_COLORS[type_idx])

		# Content label
		var content := VBoxContainer.new()
		var type_lbl := Label.new()
		type_lbl.text = MISSION_TYPES[type_idx] if type_idx < MISSION_TYPES.size() else "CUSTOM"
		type_lbl.add_theme_font_size_override("font_size", 10)
		type_lbl.add_theme_color_override("font_color", MISSION_COLORS[type_idx] if type_idx < MISSION_COLORS.size() else Color.WHITE)
		content.add_child(type_lbl)

		if int(m.get("target")) > 0:
			var target_lbl := Label.new()
			target_lbl.text = "Target: %d" % int(m.get("target"))
			target_lbl.add_theme_font_size_override("font_size", 10)
			content.add_child(target_lbl)

		if float(m.get("time_limit")) > 0.0:
			var time_lbl := Label.new()
			time_lbl.text = "⏱ %.0fs" % float(m.get("time_limit"))
			time_lbl.add_theme_font_size_override("font_size", 10)
			time_lbl.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
			content.add_child(time_lbl)

		# Start marker
		if m.get("mission_id") == start_id:
			var start_indicator := Label.new()
			start_indicator.text = "▶ START"
			start_indicator.add_theme_font_size_override("font_size", 10)
			start_indicator.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
			content.add_child(start_indicator)

		gn.add_child(content)

		# Slots: left = input, right = success out + fail out
		gn.set_slot_enabled_left(0, true)
		gn.set_slot_color_left(0, Color(0.7, 0.7, 0.7))
		gn.set_slot_type_left(0, 0)
		gn.set_slot_enabled_right(0, true)
		gn.set_slot_color_right(0, Color(0.3, 1.0, 0.3))
		gn.set_slot_type_right(0, 0)

		# Fail output slot (second row if has fail branch)
		if m.get("on_fail_next") != "" and m.get("on_fail_next") != null:
			var fail_row := Label.new()
			fail_row.text = "✗ fail"
			fail_row.add_theme_font_size_override("font_size", 9)
			fail_row.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
			gn.add_child(fail_row)
			gn.set_slot_enabled_right(1, true)
			gn.set_slot_color_right(1, Color(1.0, 0.3, 0.3))
			gn.set_slot_type_right(1, 1)

		_graph_edit.add_child(gn)

	# Draw connections
	for m in missions_arr:
		if m == null:
			continue
		var from_id: String = m.get("mission_id")
		var success_next: String = m.get("on_success_next") if m.get("on_success_next") else ""
		var fail_next: String = m.get("on_fail_next") if m.get("on_fail_next") else ""
		if not success_next.is_empty() and _graph_edit.has_node(success_next):
			_graph_edit.connect_node(from_id, 0, success_next, 0)
		if not fail_next.is_empty() and _graph_edit.has_node(fail_next):
			var from_port := 1 if _graph_edit.get_node(from_id).get_child_count() > 1 else 0
			_graph_edit.connect_node(from_id, from_port, fail_next, 0)


func _rebuild_list() -> void:
	_mission_list.clear()
	if _current_flow == null:
		return
	var missions_arr: Array = _current_flow.get("missions")
	for m in missions_arr:
		if m == null:
			continue
		var type_idx: int = int(m.get("type"))
		var type_name: String = MISSION_TYPES[type_idx] if type_idx < MISSION_TYPES.size() else "CUSTOM"
		var display := "[%s] %s - %s" % [type_name, m.get("mission_id"), m.get("label")]
		_mission_list.add_item(display)
		_mission_list.set_item_metadata(_mission_list.item_count - 1, m.get("mission_id"))


func _refresh_branch_options() -> void:
	_insp_success_next.clear()
	_insp_fail_next.clear()
	_insp_success_next.add_item("(none)")
	_insp_fail_next.add_item("(none)")
	if _current_flow == null:
		return
	var missions_arr: Array = _current_flow.get("missions")
	for m in missions_arr:
		if m == null:
			continue
		var mid: String = m.get("mission_id")
		if mid != _selected_mission_id:
			_insp_success_next.add_item(mid)
			_insp_fail_next.add_item(mid)


# =========================================================================
# Inspector
# =========================================================================

func _select_mission(mission_id: String) -> void:
	_selected_mission_id = mission_id
	_refresh_branch_options()
	if _current_flow == null:
		return
	var m: Resource = _current_flow.call("get_mission_by_id", mission_id)
	if m == null:
		return
	_insp_id.text = m.get("mission_id") if m.get("mission_id") else ""
	_insp_label.text = m.get("label") if m.get("label") else ""
	_insp_desc.text = m.get("description") if m.get("description") else ""
	_insp_type.selected = int(m.get("type"))
	_insp_target.value = int(m.get("target"))
	_insp_color.color = m.get("accent_color") if m.get("accent_color") else Color.WHITE
	_insp_progress_bar.button_pressed = bool(m.get("show_progress_bar"))
	_insp_time_limit.value = float(m.get("time_limit"))
	_insp_tags.text = ",".join(PackedStringArray(m.get("tags"))) if m.get("tags") else ""
	_insp_fail_cond.text = m.get("fail_condition") if m.get("fail_condition") else ""
	# Select branch options
	_select_option_by_text(_insp_success_next, m.get("on_success_next") if m.get("on_success_next") else "")
	_select_option_by_text(_insp_fail_next, m.get("on_fail_next") if m.get("on_fail_next") else "")
	_refresh_command_list()


func _select_option_by_text(option: OptionButton, text: String) -> void:
	for i in range(option.item_count):
		if option.get_item_text(i) == text:
			option.selected = i
			return
	option.selected = 0


func _on_inspector_changed(_arg = null) -> void:
	if _current_flow == null or _selected_mission_id.is_empty():
		return
	var m: Resource = _current_flow.call("get_mission_by_id", _selected_mission_id)
	if m == null:
		return
	var old_id: String = m.get("mission_id")
	m.set("label", _insp_label.text)
	m.set("description", _insp_desc.text)
	m.set("type", _insp_type.selected)
	m.set("target", int(_insp_target.value))
	m.set("accent_color", _insp_color.color)
	m.set("show_progress_bar", _insp_progress_bar.button_pressed)
	m.set("time_limit", _insp_time_limit.value)
	m.set("tags", PackedStringArray(_insp_tags.text.split(",")))
	m.set("fail_condition", _insp_fail_cond.text)
	# Branching
	var success_text := _insp_success_next.get_item_text(_insp_success_next.selected) if _insp_success_next.selected > 0 else ""
	var fail_text := _insp_fail_next.get_item_text(_insp_fail_next.selected) if _insp_fail_next.selected > 0 else ""
	m.set("on_success_next", success_text)
	m.set("on_fail_next", fail_text)
	# ID change
	var new_id := _insp_id.text.strip_edges()
	if not new_id.is_empty() and new_id != old_id:
		m.set("mission_id", new_id)
		_selected_mission_id = new_id
	# Refresh visuals
	_rebuild_graph()
	_rebuild_list()


# =========================================================================
# Command Editor
# =========================================================================

func _refresh_command_list() -> void:
	_cmd_list.clear()
	if _current_flow == null or _selected_mission_id.is_empty():
		return
	var m: Resource = _current_flow.call("get_mission_by_id", _selected_mission_id)
	if m == null:
		return
	var cmds: Array = m.get("on_complete_commands") if _is_success_commands else m.get("on_fail_commands")
	if cmds == null:
		return
	for cmd in cmds:
		if cmd == null:
			continue
		var display: String = cmd.get("description") if cmd.get("description") != "" else CMD_TYPES[int(cmd.get("command_type"))]
		_cmd_list.add_item(display)


func _on_cmd_selected(idx: int) -> void:
	if _current_flow == null or _selected_mission_id.is_empty():
		return
	var m: Resource = _current_flow.call("get_mission_by_id", _selected_mission_id)
	if m == null:
		return
	var cmds: Array = m.get("on_complete_commands") if _is_success_commands else m.get("on_fail_commands")
	if idx >= cmds.size():
		return
	var cmd: Resource = cmds[idx]
	_cmd_type.selected = int(cmd.get("command_type"))
	_cmd_params.text = JSON.stringify(cmd.get("parameters"), "  ")
	_cmd_delay.value = float(cmd.get("delay"))
	_cmd_enabled.button_pressed = bool(cmd.get("enabled"))
	_cmd_desc.text = cmd.get("description") if cmd.get("description") else ""


func _on_add_command() -> void:
	if _current_flow == null or _selected_mission_id.is_empty():
		return
	var m: Resource = _current_flow.call("get_mission_by_id", _selected_mission_id)
	if m == null:
		return
	var MissionCmdScript: GDScript = load("res://addons/mission_editor/mission_command.gd") as GDScript
	var cmd: Resource = MissionCmdScript.new()
	cmd.set("command_type", 0)
	cmd.set("parameters", {})
	cmd.set("enabled", true)
	var cmds: Array = m.get("on_complete_commands") if _is_success_commands else m.get("on_fail_commands")
	cmds.append(cmd)
	if _is_success_commands:
		m.set("on_complete_commands", cmds)
	else:
		m.set("on_fail_commands", cmds)
	_refresh_command_list()


func _on_remove_command() -> void:
	var idx := _cmd_list.get_selected_items()
	if idx.is_empty():
		return
	if _current_flow == null or _selected_mission_id.is_empty():
		return
	var m: Resource = _current_flow.call("get_mission_by_id", _selected_mission_id)
	if m == null:
		return
	var cmds: Array = m.get("on_complete_commands") if _is_success_commands else m.get("on_fail_commands")
	cmds.remove_at(idx[0])
	if _is_success_commands:
		m.set("on_complete_commands", cmds)
	else:
		m.set("on_fail_commands", cmds)
	_refresh_command_list()


func _on_cmd_property_changed() -> void:
	var idx_arr := _cmd_list.get_selected_items()
	if idx_arr.is_empty():
		return
	if _current_flow == null or _selected_mission_id.is_empty():
		return
	var m: Resource = _current_flow.call("get_mission_by_id", _selected_mission_id)
	if m == null:
		return
	var cmds: Array = m.get("on_complete_commands") if _is_success_commands else m.get("on_fail_commands")
	var idx: int = idx_arr[0]
	if idx >= cmds.size():
		return
	var cmd: Resource = cmds[idx]
	cmd.set("command_type", _cmd_type.selected)
	cmd.set("delay", _cmd_delay.value)
	cmd.set("enabled", _cmd_enabled.button_pressed)
	cmd.set("description", _cmd_desc.text)
	# Parse params JSON
	var json := JSON.new()
	if json.parse(_cmd_params.text) == OK:
		cmd.set("parameters", json.data if json.data is Dictionary else {})
	_refresh_command_list()


# =========================================================================
# Graph events
# =========================================================================

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _current_flow == null:
		return
	var is_fail: bool = from_port > 0
	_current_flow.call("add_connection", String(from_node), String(to_node), is_fail)
	_rebuild_graph()
	_rebuild_list()


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _current_flow == null:
		return
	_current_flow.call("remove_connection", String(from_node), String(to_node))
	_rebuild_graph()


func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	if _current_flow == null:
		return
	for node_name: StringName in nodes:
		_current_flow.call("remove_mission", String(node_name))
	_rebuild_graph()
	_rebuild_list()


func _on_graph_node_selected(node: Node) -> void:
	if node is GraphNode:
		_select_mission(node.name)


func _on_list_item_selected(idx: int) -> void:
	var mid: String = _mission_list.get_item_metadata(idx)
	if mid:
		_select_mission(mid)


# =========================================================================
# Toolbar actions
# =========================================================================

func _on_new_pressed() -> void:
	var FlowScript: GDScript = load("res://addons/mission_editor/mission_flow.gd") as GDScript
	var flow: Resource = FlowScript.new()
	flow.set("flow_name", "New Flow")
	flow.set("flow_id", "flow_new")
	# Add a starting mission
	var MissionDataScript: GDScript = load("res://Scripts/mission_data.gd") as GDScript
	var first: Resource = MissionDataScript.new()
	first.set("mission_id", "mission_001")
	first.set("label", "First Mission")
	first.set("type", 5)  # CUSTOM
	first.set("graph_position", Vector2(100, 100))
	flow.get("missions").append(first)
	flow.set("start_mission_id", "mission_001")
	_current_path = ""
	_load_flow(flow)


func _on_open_pressed() -> void:
	if _plugin:
		_plugin.show_open_dialog(_on_file_opened)


func _on_file_opened(path: String) -> void:
	var flow: Resource = load(path)
	if flow:
		_current_path = path
		_load_flow(flow)


func _on_save_pressed() -> void:
	if _current_flow == null:
		return
	if _current_path.is_empty() and _plugin:
		_plugin.show_save_dialog(_on_file_saved)
	else:
		_save_to_path(_current_path)


func _on_file_saved(path: String) -> void:
	_current_path = path
	_save_to_path(path)


func _save_to_path(path: String) -> void:
	if _current_flow == null:
		return
	ResourceSaver.save(_current_flow, path)
	if _plugin:
		_plugin.get_editor_interface().get_resource_filesystem().scan()
	_status_label.text = "Saved: %s" % path


func _on_add_mission_pressed() -> void:
	if _current_flow == null:
		_on_new_pressed()
	var MissionDataScript: GDScript = load("res://Scripts/mission_data.gd") as GDScript
	var new_mission: Resource = MissionDataScript.new()
	# Generate unique ID
	var count: int = _current_flow.get("missions").size()
	new_mission.set("mission_id", "mission_%03d" % (count + 1))
	new_mission.set("label", "New Mission")
	new_mission.set("type", 5)  # CUSTOM
	# Position offset
	var pos := Vector2(100 + count * 250, 100 + count * 80)
	new_mission.set("graph_position", pos)
	_current_flow.get("missions").append(new_mission)
	_rebuild_graph()
	_rebuild_list()
	_refresh_branch_options()


func _on_delete_mission_pressed() -> void:
	if _current_flow == null or _selected_mission_id.is_empty():
		return
	_current_flow.call("remove_mission", _selected_mission_id)
	_selected_mission_id = ""
	_rebuild_graph()
	_rebuild_list()
	_refresh_branch_options()

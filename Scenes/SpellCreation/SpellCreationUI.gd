extends Control

const MAX_CREDITS := SpellDefinition.MAX_CREDITS
const SIMPLE_THRESHOLD := SpellDefinition.SIMPLE_THRESHOLD
const TEST_SPELL_PATH := "user://test_spell.tres"
const MAIN_MENU_SCENE := "res://Scenes/MainMenu/MainMenu.tscn"
const SPELLS_DIR := "user://spells"
const LOADOUT_PATH := "user://loadout.cfg"
const LOADOUT_SLOT_COUNT := 3
const LOADOUT_CREDIT_LIMIT := 120
const LOADOUT_SLOT_NAMES: Array[String] = ["LMB", "RMB", "Shift"]
const BEAM_SPEED_COST_SCALE := SpellDefinition.BEAM_SPEED_COST_SCALE
const MANA_COST_SCALE := SpellDefinition.MANA_COST_SCALE
const MIN_MANA_COST := SpellDefinition.MIN_MANA_COST
const SPIRIT_MANA_SURCHARGE := SpellDefinition.SPIRIT_MANA_SURCHARGE
const BEAM_MANA_PER_SECOND_SCALE := SpellDefinition.BEAM_MANA_PER_SECOND_SCALE
const MAX_BASES := 3

const ELEMENTS: Array[String] = ["Fire", "Water", "Air", "Spirit", "Earth", "Light", "Void"]
const ELEMENT_COLORS: Dictionary = {
	"Fire": Color(1.0, 0.35, 0.05),
	"Water": Color(0.1, 0.55, 1.0),
	"Air": Color(0.75, 0.92, 1.0),
	"Spirit": Color(0.72, 0.3, 1.0),
	"Earth": Color(0.6, 0.4, 0.15),
	"Light": Color(1.0, 1.0, 0.35),
	"Void": Color(0.45, 0.1, 0.65),
}
const SHAPES: Array[String] = ["Beam", "Sphere", "Wall"]

# Spell state
var _spell_name: String = "New Spell"
var _selected_element: String = ""
var _selected_elements: Array[String] = []
var _selected_shape: String = ""
var _intensity: int = 1
var _size: int = 1
var _range_val: int = 1
var _speed: int = 1
var _charging: bool = false
var _burns: bool = false
var _cools: bool = false
var _pushes: bool = false
var _blows: bool = false
var _heals: bool = false
var _has_density: bool = false
var _density: int = 1
var _has_illusion: bool = false
var _has_pull: bool = false
var _pull: int = 1

# UI refs
var _credits_used_label: Label
var _credits_bar: ProgressBar
var _mana_cost_label: Label
var _damage_label: Label
var _spell_type_label: Label
var _element_buttons: Dictionary = {}
var _shape_buttons: Dictionary = {}
var _charging_row: HBoxContainer
var _charging_cb: CheckBox
var _intensity_slider: HSlider
var _intensity_val_lbl: Label
var _size_slider: HSlider
var _size_val_lbl: Label
var _range_slider: HSlider
var _range_val_lbl: Label
var _speed_lbl: Label
var _speed_slider: HSlider
var _speed_val_lbl: Label
var _attr_panels: Dictionary = {}
var _complex_panel: PanelContainer
var _complex_name_label: Label
var _complex_desc_label: Label
var _complex_stats_label: Label
var _complex_radar: Control
var _burns_cb: CheckBox
var _cools_cb: CheckBox
var _pushes_cb: CheckBox
var _blows_cb: CheckBox
var _heals_cb: CheckBox
var _density_cb: CheckBox
var _density_slider: HSlider
var _density_val_lbl: Label
var _illusion_cb: CheckBox
var _pull_cb: CheckBox
var _pull_slider: HSlider
var _pull_val_lbl: Label
var _preview_mesh: MeshInstance3D
var _preview_material: StandardMaterial3D
var _preview_pivot: Node3D
var _save_btn: Button
var _back_btn: Button
var _name_input: LineEdit
var _saved_spell_list: VBoxContainer
var _saved_spell_detail: Label
var _delete_saved_spell_btn: Button
var _loadout_cost_label: Label
var _loadout_slot_labels: Array[Label] = []
var _loadout_assign_buttons: Array[Button] = []
var _saved_spells: Array[Dictionary] = []
var _loadout_paths: Array[String] = []
var _selected_saved_spell_path: String = ""
var _selected_saved_spell: SpellDefinition
var _game_return_target: Node


func set_game_return_target(target: Node) -> void:
	_game_return_target = target


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_ui()
	_load_loadout()
	_reload_saved_spells()
	_load_test_spell()
	_refresh()


func _process(delta: float) -> void:
	if _preview_pivot:
		_preview_pivot.rotate_y(delta * 0.8)


# ---------------------------------------------------------------------------
# BUILD UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.11)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root_vbox.add_child(header)

	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.custom_minimum_size = Vector2(96, 34)
	_back_btn.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	_back_btn.pressed.connect(_go_to_main_menu)
	header.add_child(_back_btn)

	var title_lbl := Label.new()
	title_lbl.text = "Spell Creation"
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(0.92, 0.84, 1.0))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var new_spell_btn := Button.new()
	new_spell_btn.text = "New Spell"
	new_spell_btn.custom_minimum_size = Vector2(96, 34)
	new_spell_btn.pressed.connect(_on_cancel_pressed)
	header.add_child(new_spell_btn)

	root_vbox.add_child(HSeparator.new())

	var content := HBoxContainer.new()
	content.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	root_vbox.add_child(content)

	_build_properties_panel(content)
	_build_preview_panel(content)
	_build_loadout_panel(content)


func _build_properties_panel(parent: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.6
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	_build_name_row(vbox)
	_build_credits_display(vbox)
	_build_element_picker(vbox)
	_build_shape_picker(vbox)
	_build_properties_sliders(vbox)
	_build_attribute_panels(vbox)


func _build_name_row(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)

	var lbl := Label.new()
	lbl.text = "Spell Name:"
	lbl.add_theme_color_override("font_color", Color(0.75, 0.7, 0.88))
	lbl.custom_minimum_size.x = 90
	hbox.add_child(lbl)

	_name_input = LineEdit.new()
	_name_input.text = _spell_name
	_name_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_name_input.text_changed.connect(func(t: String) -> void: _spell_name = t)
	hbox.add_child(_name_input)


func _build_credits_display(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	parent.add_child(panel)

	var inner := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inner.add_theme_constant_override(s, 8)
	panel.add_child(inner)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	inner.add_child(vbox)

	var row := HBoxContainer.new()
	vbox.add_child(row)

	var lbl := Label.new()
	lbl.text = "Credits Used:"
	lbl.add_theme_color_override("font_color", Color(0.75, 0.7, 0.88))
	row.add_child(lbl)

	_credits_used_label = Label.new()
	_credits_used_label.text = "0 / %d" % MAX_CREDITS
	_credits_used_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_credits_used_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_credits_used_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	row.add_child(_credits_used_label)

	_credits_bar = ProgressBar.new()
	_credits_bar.max_value = MAX_CREDITS
	_credits_bar.value = 0
	_credits_bar.custom_minimum_size.y = 16
	vbox.add_child(_credits_bar)

	_mana_cost_label = Label.new()
	_mana_cost_label.text = "Mana Cost: -"
	_mana_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mana_cost_label.add_theme_font_size_override("font_size", 12)
	_mana_cost_label.add_theme_color_override("font_color", Color(0.65, 0.82, 1.0))
	vbox.add_child(_mana_cost_label)

	_damage_label = Label.new()
	_damage_label.text = "Damage: -"
	_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_damage_label.add_theme_font_size_override("font_size", 12)
	_damage_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.45))
	vbox.add_child(_damage_label)

	_spell_type_label = Label.new()
	_spell_type_label.text = "Select an element and shape to begin"
	_spell_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spell_type_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	_spell_type_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_spell_type_label)


func _build_element_picker(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("Base Elements (select up to 3)"))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)

	for el: String in ELEMENTS:
		var btn := Button.new()
		btn.text = el
		btn.toggle_mode = true
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_color", ELEMENT_COLORS[el])
		btn.toggled.connect(func(pressed: bool) -> void: _on_element_toggled(el, pressed))
		grid.add_child(btn)
		_element_buttons[el] = btn


func _build_shape_picker(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("Shape"))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)

	for sh: String in SHAPES:
		var btn := Button.new()
		btn.text = sh
		btn.toggle_mode = true
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.toggled.connect(func(pressed: bool) -> void: _on_shape_toggled(sh, pressed))
		hbox.add_child(btn)
		_shape_buttons[sh] = btn

	_charging_row = HBoxContainer.new()
	_charging_row.visible = false
	parent.add_child(_charging_row)

	var charge_lbl := Label.new()
	charge_lbl.text = "  Charging:"
	charge_lbl.add_theme_color_override("font_color", Color(0.75, 0.7, 0.88))
	_charging_row.add_child(charge_lbl)

	_charging_cb = CheckBox.new()
	_charging_cb.text = "Drains mana to grow sphere"
	_charging_cb.toggled.connect(func(v: bool) -> void: _charging = v; _refresh())
	_charging_row.add_child(_charging_cb)


func _build_properties_sliders(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("Properties"))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)

	_intensity_slider = _make_slider(1, 10, 1)
	_intensity_slider.value_changed.connect(_on_intensity_changed)
	_intensity_val_lbl = _add_slider_to_grid(grid, "Intensity", _intensity_slider)

	_size_slider = _make_slider(1, 10, 1)
	_size_slider.value_changed.connect(_on_size_changed)
	_size_val_lbl = _add_slider_to_grid(grid, "Size", _size_slider)

	_range_slider = _make_slider(1, 10, 1)
	_range_slider.value_changed.connect(_on_range_changed)
	_range_val_lbl = _add_slider_to_grid(grid, "Range", _range_slider)

	_speed_slider = _make_slider(1, 10, 1)
	_speed_slider.value_changed.connect(_on_speed_changed)
	_speed_val_lbl = _add_slider_to_grid(grid, "Speed", _speed_slider)


func _build_attribute_panels(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("Base Attributes"))
	_build_complex_panel(parent)

	# Fire
	var fire := _make_attr_panel(parent, "Fire Attributes")
	_attr_panels["Fire"] = fire[0]
	_burns_cb = _add_cb(fire[1], "Burns  —  Damage over time", func(v: bool) -> void: _burns = v; _refresh())

	# Water
	var water := _make_attr_panel(parent, "Water Attributes")
	_attr_panels["Water"] = water[0]
	_cools_cb = _add_cb(water[1], "Cools  —  Extinguishes burn effects", func(v: bool) -> void: _cools = v; _refresh())
	_pushes_cb = _add_cb(water[1], "Pushes  —  Knockback force", func(v: bool) -> void: _pushes = v; _refresh())

	# Air
	var air := _make_attr_panel(parent, "Air Attributes")
	_attr_panels["Air"] = air[0]
	_blows_cb = _add_cb(air[1], "Blows  —  Extinguishes fire, cancels some effects", func(v: bool) -> void: _blows = v; _refresh())

	# Spirit
	var spirit := _make_attr_panel(parent, "Spirit Attributes")
	_attr_panels["Spirit"] = spirit[0]
	_heals_cb = _add_cb(spirit[1], "Heals  —  Restores target health", func(v: bool) -> void: _heals = v; _refresh())

	# Earth
	var earth := _make_attr_panel(parent, "Earth Attributes")
	_attr_panels["Earth"] = earth[0]
	_density_cb = _add_cb(earth[1], "Density  —  More impact, less AOE on collision",
		func(v: bool) -> void: _has_density = v; _density_slider.visible = v; _refresh())
	var d_row := HBoxContainer.new()
	earth[1].add_child(d_row)
	var d_lbl := Label.new()
	d_lbl.text = "  Density:"
	d_lbl.custom_minimum_size.x = 90
	d_lbl.add_theme_color_override("font_color", Color(0.75, 0.7, 0.88))
	d_row.add_child(d_lbl)
	_density_slider = _make_slider(1, 10, 1)
	_density_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	_density_slider.value_changed.connect(_on_density_changed)
	_density_slider.visible = false
	d_row.add_child(_density_slider)
	_density_val_lbl = Label.new()
	_density_val_lbl.text = "1"
	_density_val_lbl.custom_minimum_size.x = 20
	d_row.add_child(_density_val_lbl)

	# Light
	var light := _make_attr_panel(parent, "Light Attributes")
	_attr_panels["Light"] = light[0]
	_illusion_cb = _add_cb(light[1], "Illusion  —  TBD", func(v: bool) -> void: _has_illusion = v; _refresh())

	# Void
	var void_p := _make_attr_panel(parent, "Void Attributes")
	_attr_panels["Void"] = void_p[0]
	_pull_cb = _add_cb(void_p[1], "Pull  —  Gravitational pull toward spell",
		func(v: bool) -> void: _has_pull = v; _pull_slider.visible = v; _refresh())
	var p_row := HBoxContainer.new()
	void_p[1].add_child(p_row)
	var p_lbl := Label.new()
	p_lbl.text = "  Pull Strength:"
	p_lbl.custom_minimum_size.x = 90
	p_lbl.add_theme_color_override("font_color", Color(0.75, 0.7, 0.88))
	p_row.add_child(p_lbl)
	_pull_slider = _make_slider(1, 10, 1)
	_pull_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	_pull_slider.value_changed.connect(_on_pull_changed)
	_pull_slider.visible = false
	p_row.add_child(_pull_slider)
	_pull_val_lbl = Label.new()
	_pull_val_lbl.text = "1"
	_pull_val_lbl.custom_minimum_size.x = 20
	p_row.add_child(_pull_val_lbl)

	for el: String in ELEMENTS:
		_attr_panels[el].visible = false


func _build_complex_panel(parent: VBoxContainer) -> void:
	_complex_panel = PanelContainer.new()
	_complex_panel.visible = false
	parent.add_child(_complex_panel)

	var margin := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 10)
	_complex_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_complex_name_label = Label.new()
	_complex_name_label.add_theme_font_size_override("font_size", 16)
	_complex_name_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45))
	vbox.add_child(_complex_name_label)

	_complex_desc_label = Label.new()
	_complex_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_complex_desc_label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.94))
	vbox.add_child(_complex_desc_label)

	_complex_radar = Control.new()
	_complex_radar.custom_minimum_size = Vector2(220, 150)
	_complex_radar.draw.connect(_draw_complex_radar)
	vbox.add_child(_complex_radar)

	_complex_stats_label = Label.new()
	_complex_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_complex_stats_label.add_theme_font_size_override("font_size", 12)
	_complex_stats_label.add_theme_color_override("font_color", Color(0.72, 0.7, 0.82))
	vbox.add_child(_complex_stats_label)


func _build_preview_panel(parent: Control) -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.size_flags_stretch_ratio = 0.75
	vbox.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	parent.add_child(vbox)

	vbox.add_child(_section_label("Preview"))

	var vpc := SubViewportContainer.new()
	vpc.size_flags_vertical = SIZE_EXPAND_FILL
	vpc.size_flags_horizontal = SIZE_EXPAND_FILL
	vpc.stretch = true
	vpc.custom_minimum_size = Vector2(180, 260)
	vbox.add_child(vpc)

	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	vpc.add_child(viewport)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.05, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.22, 0.32)
	env.ambient_light_energy = 1.0
	env_node.environment = env
	viewport.add_child(env_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 45, 0)
	light.light_energy = 1.2
	viewport.add_child(light)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.5, 3.5)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.0, 0.0), Vector3.UP)
	viewport.add_child(cam)

	_preview_pivot = Node3D.new()
	viewport.add_child(_preview_pivot)

	_preview_material = StandardMaterial3D.new()
	_preview_material.emission_enabled = true
	_preview_material.emission = Color(0.3, 0.3, 0.35)
	_preview_material.emission_energy_multiplier = 0.6
	_preview_material.albedo_color = Color(0.3, 0.3, 0.35)

	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.material_override = _preview_material
	_preview_pivot.add_child(_preview_mesh)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_save_btn = Button.new()
	_save_btn.text = "Save Spell"
	_save_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_save_btn.disabled = true
	_save_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_save_btn.pressed.connect(_on_save_pressed)
	btn_row.add_child(_save_btn)


func _build_loadout_panel(parent: Control) -> void:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 8)
	parent.add_child(panel)

	panel.add_child(_section_label("Saved Spells"))

	var saved_scroll := ScrollContainer.new()
	saved_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	saved_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	saved_scroll.custom_minimum_size = Vector2(260, 220)
	panel.add_child(saved_scroll)

	_saved_spell_list = VBoxContainer.new()
	_saved_spell_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_saved_spell_list.add_theme_constant_override("separation", 5)
	saved_scroll.add_child(_saved_spell_list)

	_saved_spell_detail = Label.new()
	_saved_spell_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_saved_spell_detail.add_theme_font_size_override("font_size", 12)
	_saved_spell_detail.add_theme_color_override("font_color", Color(0.78, 0.74, 0.88))
	_saved_spell_detail.text = "Save a spell, then select it here."
	panel.add_child(_saved_spell_detail)

	_delete_saved_spell_btn = Button.new()
	_delete_saved_spell_btn.text = "Delete Selected Spell"
	_delete_saved_spell_btn.disabled = true
	_delete_saved_spell_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.38))
	_delete_saved_spell_btn.pressed.connect(_delete_selected_saved_spell)
	panel.add_child(_delete_saved_spell_btn)

	panel.add_child(HSeparator.new())
	panel.add_child(_section_label("Loadout"))

	_loadout_cost_label = Label.new()
	_loadout_cost_label.add_theme_font_size_override("font_size", 13)
	_loadout_cost_label.add_theme_color_override("font_color", Color(0.65, 0.82, 1.0))
	panel.add_child(_loadout_cost_label)

	for i in range(LOADOUT_SLOT_COUNT):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		panel.add_child(row)

		var slot_label := Label.new()
		slot_label.custom_minimum_size.x = 96
		slot_label.add_theme_color_override("font_color", Color(0.9, 0.86, 1.0))
		row.add_child(slot_label)
		_loadout_slot_labels.append(slot_label)

		var assign_btn := Button.new()
		assign_btn.text = "Assign"
		assign_btn.size_flags_horizontal = SIZE_EXPAND_FILL
		assign_btn.pressed.connect(func(slot_index := i) -> void: _assign_selected_spell_to_slot(slot_index))
		row.add_child(assign_btn)
		_loadout_assign_buttons.append(assign_btn)

		var clear_btn := Button.new()
		clear_btn.text = "Clear"
		clear_btn.pressed.connect(func(slot_index := i) -> void: _clear_loadout_slot(slot_index))
		row.add_child(clear_btn)


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.86, 1.0))
	return lbl


func _make_attr_panel(parent: VBoxContainer, title: String) -> Array:
	var outer := PanelContainer.new()
	outer.visible = false
	parent.add_child(outer)

	var margin := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 8)
	outer.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	margin.add_child(inner)

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.85, 0.8, 0.95))
	inner.add_child(header)

	return [outer, inner]


func _make_slider(min_v: float, max_v: float, init: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.value = init
	s.step = 1
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	return s


func _add_slider_to_grid(grid: GridContainer, label_text: String, slider: HSlider) -> Label:
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.add_theme_color_override("font_color", Color(0.75, 0.7, 0.88))
	grid.add_child(lbl)
	if label_text == "Speed":
		_speed_lbl = lbl
	grid.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.text = "1"
	val_lbl.custom_minimum_size.x = 20
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(val_lbl)
	return val_lbl


func _add_cb(parent: VBoxContainer, text: String, callback: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.toggled.connect(callback)
	parent.add_child(cb)
	return cb


func _reload_saved_spells() -> void:
	_saved_spells.clear()
	var dir := DirAccess.open(SPELLS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres"):
				var path := "%s/%s" % [SPELLS_DIR, fname]
				var spell := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SpellDefinition
				if spell != null and spell.is_valid():
					_saved_spells.append({"path": path, "spell": spell})
			fname = dir.get_next()
		dir.list_dir_end()
	_saved_spells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var spell_a := a["spell"] as SpellDefinition
		var spell_b := b["spell"] as SpellDefinition
		return spell_a.spell_name.nocasecmp_to(spell_b.spell_name) < 0
	)
	_refresh_saved_spell_list()
	_refresh_loadout_panel()
	_update_saved_spell_detail()


func _refresh_saved_spell_list() -> void:
	if _saved_spell_list == null:
		return
	for child in _saved_spell_list.get_children():
		child.queue_free()
	if _saved_spells.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No saved spells yet."
		empty_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
		_saved_spell_list.add_child(empty_label)
		return
	for entry in _saved_spells:
		var spell := entry["spell"] as SpellDefinition
		var path := str(entry["path"])
		var btn := Button.new()
		btn.text = "%s  -  %s %s  -  %d cr" % [
			spell.spell_name, spell.get_base_display_name(), spell.shape, spell.calculate_credits()
		]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_color", _get_saved_spell_button_color(spell, path))
		btn.pressed.connect(func(spell_path := path, selected_spell := spell) -> void:
			_select_saved_spell(spell_path, selected_spell)
		)
		_saved_spell_list.add_child(btn)


func _get_saved_spell_button_color(spell: SpellDefinition, path: String) -> Color:
	if path == _selected_saved_spell_path:
		return Color(0.55, 1.0, 0.72)
	if _can_fit_spell_in_any_slot(spell):
		return Color(0.92, 0.88, 1.0)
	return Color(0.5, 0.5, 0.56)


func _select_saved_spell(path: String, spell: SpellDefinition) -> void:
	_selected_saved_spell_path = path
	_selected_saved_spell = spell
	_apply_spell_definition(spell)
	_update_saved_spell_detail()
	_refresh_saved_spell_list()
	_refresh_loadout_panel()
	_refresh()


func _update_saved_spell_detail() -> void:
	if _saved_spell_detail == null:
		return
	if _selected_saved_spell == null:
		_saved_spell_detail.text = "Select a saved spell to view or assign."
		if _delete_saved_spell_btn != null:
			_delete_saved_spell_btn.disabled = true
		return
	var spell := _selected_saved_spell
	var mana_text := "%.1f/sec" % spell.calculate_beam_mana_per_second() if spell.shape == "Beam" else "%d" % spell.calculate_mana_cost()
	var output_text := _get_spell_output_text(spell)
	_saved_spell_detail.text = "%s\n%s %s | %d cr | Mana %s | %s" % [
		spell.spell_name, spell.get_base_display_name(), spell.shape, spell.calculate_credits(), mana_text, output_text
	]
	if _delete_saved_spell_btn != null:
		_delete_saved_spell_btn.disabled = _selected_saved_spell_path.is_empty()


func _delete_selected_saved_spell() -> void:
	if _selected_saved_spell_path.is_empty():
		return
	var deleted_path := _selected_saved_spell_path
	var err := DirAccess.remove_absolute(deleted_path)
	if err != OK:
		push_error("Failed to delete spell: %s" % error_string(err))
		return
	for i in range(_loadout_paths.size()):
		if _loadout_paths[i] == deleted_path:
			_loadout_paths[i] = ""
	_save_loadout()
	_selected_saved_spell_path = ""
	_selected_saved_spell = null
	_reload_saved_spells()
	if _saved_spells.is_empty():
		_update_saved_spell_detail()
	_refresh_loadout_panel()


func _load_loadout() -> void:
	_loadout_paths.clear()
	for i in range(LOADOUT_SLOT_COUNT):
		_loadout_paths.append("")
	var cfg := ConfigFile.new()
	if cfg.load(LOADOUT_PATH) != OK:
		return
	for i in range(LOADOUT_SLOT_COUNT):
		_loadout_paths[i] = str(cfg.get_value("slots", str(i), ""))


func _save_loadout() -> void:
	var cfg := ConfigFile.new()
	for i in range(LOADOUT_SLOT_COUNT):
		cfg.set_value("slots", str(i), _loadout_paths[i])
	cfg.save(LOADOUT_PATH)


func _refresh_loadout_panel() -> void:
	if _loadout_cost_label == null:
		return
	var cost := _get_loadout_cost()
	_loadout_cost_label.text = "Loadout: %d / %d credits" % [cost, LOADOUT_CREDIT_LIMIT]
	_loadout_cost_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.35, 0.25) if cost > LOADOUT_CREDIT_LIMIT else Color(0.65, 0.82, 1.0)
	)
	for i in range(LOADOUT_SLOT_COUNT):
		var spell := _get_loadout_spell(i)
		var slot_text := "%s: Empty" % LOADOUT_SLOT_NAMES[i]
		if spell != null:
			slot_text = "%s: %s (%d)" % [LOADOUT_SLOT_NAMES[i], spell.spell_name, spell.calculate_credits()]
		_loadout_slot_labels[i].text = slot_text
		var can_assign := _selected_saved_spell != null and _can_assign_spell_to_slot(_selected_saved_spell, i)
		_loadout_assign_buttons[i].disabled = not can_assign
		_loadout_assign_buttons[i].text = "Assign %s" % LOADOUT_SLOT_NAMES[i]


func _assign_selected_spell_to_slot(slot_index: int) -> void:
	if _selected_saved_spell == null or _selected_saved_spell_path.is_empty():
		return
	if not _can_assign_spell_to_slot(_selected_saved_spell, slot_index):
		return
	_loadout_paths[slot_index] = _selected_saved_spell_path
	_save_loadout()
	_refresh_saved_spell_list()
	_refresh_loadout_panel()


func _clear_loadout_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= LOADOUT_SLOT_COUNT:
		return
	_loadout_paths[slot_index] = ""
	_save_loadout()
	_refresh_saved_spell_list()
	_refresh_loadout_panel()


func _get_loadout_spell(slot_index: int) -> SpellDefinition:
	if slot_index < 0 or slot_index >= _loadout_paths.size():
		return null
	var path := _loadout_paths[slot_index]
	if path.is_empty():
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SpellDefinition


func _get_loadout_cost(except_slot: int = -1) -> int:
	var total := 0
	for i in range(_loadout_paths.size()):
		if i == except_slot:
			continue
		var spell := _get_loadout_spell(i)
		if spell != null:
			total += spell.calculate_credits()
	return total


func _can_assign_spell_to_slot(spell: SpellDefinition, slot_index: int) -> bool:
	if spell == null:
		return false
	return _get_loadout_cost(slot_index) + spell.calculate_credits() <= LOADOUT_CREDIT_LIMIT


func _can_fit_spell_in_any_slot(spell: SpellDefinition) -> bool:
	for i in range(LOADOUT_SLOT_COUNT):
		if _can_assign_spell_to_slot(spell, i):
			return true
	return false


func _get_primary_element() -> String:
	if _selected_elements.is_empty():
		return ""
	return _selected_elements[0]


func _get_base_weights() -> Dictionary:
	var weights := {}
	if _selected_elements.is_empty():
		return weights
	var base_weight := int(100 / _selected_elements.size())
	var remainder := 100 - base_weight * _selected_elements.size()
	for i in _selected_elements.size():
		weights[_selected_elements[i]] = base_weight + (remainder if i == 0 else 0)
	return weights


func _get_blend_key() -> String:
	var elements := _selected_elements.duplicate()
	elements.sort()
	return "+".join(elements)


func _is_known_synergy() -> bool:
	return SpellDefinition.KNOWN_SYNERGIES.has(_get_blend_key()) or _selected_elements.has("Void") and _selected_elements.size() > 1


func _get_base_display_name() -> String:
	if _selected_elements.is_empty():
		return ""
	if _selected_elements.size() == 1:
		return _selected_elements[0]
	var key := _get_blend_key()
	if SpellDefinition.KNOWN_SYNERGIES.has(key):
		return SpellDefinition.KNOWN_SYNERGIES[key]
	if _selected_elements.has("Void"):
		var non_void: Array[String] = []
		for element in _selected_elements:
			if element != "Void":
				non_void.append(element)
		non_void.sort()
		return "Void-" + non_void[0] if not non_void.is_empty() else "Void"
	var elements := _selected_elements.duplicate()
	elements.sort()
	return " ".join(elements)


func _get_blended_color() -> Color:
	var weights := _get_base_weights()
	var total_weight := 0.0
	var color := Color.BLACK
	for element in weights.keys():
		var weight := float(weights[element])
		total_weight += weight
		color += ELEMENT_COLORS[str(element)] * weight
	if total_weight <= 0.0:
		return Color(0.6, 0.4, 1.0)
	return color / total_weight


func _get_complex_effect() -> Dictionary:
	if _selected_elements.size() <= 1:
		return {}
	var temp_spell := SpellDefinition.new()
	temp_spell.base_element = _get_primary_element()
	temp_spell.base_weights = _get_base_weights()
	return temp_spell.get_complex_effect()


func _update_complex_panel() -> void:
	var effect := _get_complex_effect()
	if effect.is_empty():
		return
	_complex_name_label.text = "%s %s" % [str(effect["name"]), _selected_shape]
	_complex_desc_label.text = str(effect["description"])
	var stats: Dictionary = effect["stats"]
	var pieces: Array[String] = []
	for label in _get_radar_labels():
		pieces.append("%s %d" % [label, int(stats.get(label, 0))])
	_complex_stats_label.text = " / ".join(pieces)
	_complex_radar.queue_redraw()


func _get_radar_labels() -> Array[String]:
	return ["Burn", "Force", "Area", "Control", "Support"]


func _draw_complex_radar() -> void:
	if _complex_radar == null or _selected_elements.size() <= 1:
		return
	var effect := _get_complex_effect()
	if effect.is_empty():
		return
	var stats: Dictionary = effect["stats"]
	var labels := _get_radar_labels()
	var center := _complex_radar.size * 0.5
	center.y += 4.0
	var radius: float = minf(_complex_radar.size.x, _complex_radar.size.y) * 0.34
	var axis_points := PackedVector2Array()
	var value_points := PackedVector2Array()
	for i in labels.size():
		var angle := -PI / 2.0 + TAU * float(i) / float(labels.size())
		var dir := Vector2(cos(angle), sin(angle))
		var axis_point := center + dir * radius
		axis_points.append(axis_point)
		var stat_value := clampf(float(stats.get(labels[i], 0)) / 10.0, 0.0, 1.0)
		value_points.append(center + dir * radius * stat_value)
		_complex_radar.draw_line(center, axis_point, Color(0.45, 0.42, 0.55, 0.75), 1.0)
		_complex_radar.draw_string(get_theme_default_font(), axis_point + dir * 10.0 - Vector2(18, 4), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 0.74, 0.88))
	_complex_radar.draw_polyline(axis_points + PackedVector2Array([axis_points[0]]), Color(0.45, 0.42, 0.55), 1.0)
	_complex_radar.draw_colored_polygon(value_points, _get_blended_color().lightened(0.15) * Color(1, 1, 1, 0.45))
	_complex_radar.draw_polyline(value_points + PackedVector2Array([value_points[0]]), _get_blended_color().lightened(0.35), 2.0)


# ---------------------------------------------------------------------------
# REFRESH
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var credits := _calculate_credits()
	var maxed := credits >= MAX_CREDITS
	var can_use_spell := not _selected_elements.is_empty() and _selected_shape != ""

	_credits_used_label.text = "%d / %d" % [credits, MAX_CREDITS]
	_credits_bar.value = credits
	_update_mana_cost_label(credits, can_use_spell)
	_update_damage_label(can_use_spell)

	if credits >= MAX_CREDITS:
		_credits_used_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	elif credits > int(MAX_CREDITS * 0.75):
		_credits_used_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		_credits_used_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))

	if _selected_elements.is_empty() or _selected_shape == "":
		_spell_type_label.text = "Select at least one element and a shape to begin"
		_spell_type_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	else:
		var spell_type := "Simple" if credits < SIMPLE_THRESHOLD else "Complex"
		_spell_type_label.text = "%s Spell  —  %s %s" % [spell_type, _get_base_display_name(), _selected_shape]
		var type_color := Color(0.4, 0.9, 1.0) if spell_type == "Simple" else Color(1.0, 0.7, 0.2)
		_spell_type_label.add_theme_color_override("font_color", type_color)

	_charging_row.visible = _selected_shape == "Sphere"
	var uses_speed := _selected_shape != "Wall"
	_speed_lbl.visible = uses_speed
	_speed_slider.visible = uses_speed
	_speed_val_lbl.visible = uses_speed

	var is_complex := _selected_elements.size() > 1
	_complex_panel.visible = is_complex
	for el: String in ELEMENTS:
		_attr_panels[el].visible = not is_complex and _selected_elements.has(el)
	if is_complex:
		_update_complex_panel()

	_intensity_val_lbl.text = str(_intensity)
	_size_val_lbl.text = str(_size)
	_range_val_lbl.text = str(_range_val)
	_speed_val_lbl.text = str(_speed)
	_density_val_lbl.text = str(_density)
	_pull_val_lbl.text = str(_pull)

	_apply_lock_state(maxed)
	_save_btn.disabled = not can_use_spell or credits > MAX_CREDITS
	if _save_btn != null:
		_save_btn.text = "Update Spell" if not _selected_saved_spell_path.is_empty() else "Save Spell"

	_update_preview()


func _apply_lock_state(locked: bool) -> void:
	for el: String in ELEMENTS:
		var btn: Button = _element_buttons[el]
		btn.disabled = (locked or _selected_elements.size() >= MAX_BASES) and not btn.button_pressed

	for sh: String in SHAPES:
		var btn: Button = _shape_buttons[sh]
		btn.disabled = locked and not btn.button_pressed

	_charging_cb.disabled = locked and not _charging_cb.button_pressed

	_apply_slider_lock(_intensity_slider, _intensity, locked)
	_apply_slider_lock(_size_slider, _size, locked)
	_apply_slider_lock(_range_slider, _range_val, locked)
	_apply_slider_lock(_speed_slider, _speed, locked)
	_apply_slider_lock(_density_slider, _density, locked)
	_apply_slider_lock(_pull_slider, _pull, locked)

	_burns_cb.disabled = locked and not _burns_cb.button_pressed
	_cools_cb.disabled = locked and not _cools_cb.button_pressed
	_pushes_cb.disabled = locked and not _pushes_cb.button_pressed
	_blows_cb.disabled = locked and not _blows_cb.button_pressed
	_heals_cb.disabled = locked and not _heals_cb.button_pressed
	_density_cb.disabled = locked and not _density_cb.button_pressed
	_illusion_cb.disabled = locked and not _illusion_cb.button_pressed
	_pull_cb.disabled = locked and not _pull_cb.button_pressed


func _update_mana_cost_label(credits: int, can_use_spell: bool) -> void:
	if _mana_cost_label == null:
		return
	if not can_use_spell:
		_mana_cost_label.text = "Mana Cost: -"
		return
	var mana_amount := float(credits) * MANA_COST_SCALE
	if _selected_elements.has("Spirit"):
		mana_amount *= SPIRIT_MANA_SURCHARGE
	var mana_cost: int = maxi(MIN_MANA_COST, int(ceil(mana_amount)))
	if _selected_shape == "Beam":
		var per_second: float = maxf(2.0, float(mana_cost) * BEAM_MANA_PER_SECOND_SCALE)
		_mana_cost_label.text = "Mana Drain: %.1f / sec" % per_second
	else:
		_mana_cost_label.text = "Mana Cost: %d" % mana_cost


func _update_damage_label(can_use_spell: bool) -> void:
	if _damage_label == null:
		return
	if not can_use_spell:
		_damage_label.text = "Damage: -"
		return
	var spell := _create_spell_definition()
	if spell.is_healing_spell():
		if _selected_shape == "Beam":
			_damage_label.text = "Healing: %d / tick" % spell.calculate_healing(true)
		else:
			_damage_label.text = "Healing: %d" % spell.calculate_healing()
	elif _selected_shape == "Beam":
		_damage_label.text = "Damage: %d / tick" % spell.calculate_damage(true)
	else:
		_damage_label.text = "Damage: %d" % spell.calculate_damage()


func _get_spell_output_text(spell: SpellDefinition) -> String:
	var push_suffix := " + %.1f push" % spell.calculate_push_force(false) if spell.calculate_push_force(false) > 0.0 else ""
	var gravity_suffix := " + %.1f gravity" % spell.calculate_gravity_force(0.0, 3.0, false) if spell.calculate_gravity_force(0.0, 3.0, false) > 0.0 else ""
	var blind_suffix := " + %.1fs blind" % spell.calculate_blind_duration(false) if spell.calculate_blind_duration(false) > 0.0 else ""
	if spell.is_healing_spell():
		return ("Healing %d/tick" % spell.calculate_healing(true) if spell.shape == "Beam" else "Healing %d" % spell.calculate_healing()) + push_suffix + gravity_suffix + blind_suffix
	return ("Damage %d/tick" % spell.calculate_damage(true) if spell.shape == "Beam" else "Damage %d" % spell.calculate_damage()) + push_suffix + gravity_suffix + blind_suffix


func _apply_slider_lock(slider: HSlider, _current_value: int, _locked: bool) -> void:
	slider.editable = true
	slider.max_value = 10


func _on_intensity_changed(value: float) -> void:
	var previous := _intensity
	_intensity = int(value)
	if not _accept_slider_change(previous, _intensity):
		_intensity = previous
		_intensity_slider.set_value_no_signal(previous)
	_refresh()


func _on_size_changed(value: float) -> void:
	var previous := _size
	_size = int(value)
	if not _accept_slider_change(previous, _size):
		_size = previous
		_size_slider.set_value_no_signal(previous)
	_refresh()


func _on_range_changed(value: float) -> void:
	var previous := _range_val
	_range_val = int(value)
	if not _accept_slider_change(previous, _range_val):
		_range_val = previous
		_range_slider.set_value_no_signal(previous)
	_refresh()


func _on_speed_changed(value: float) -> void:
	var previous := _speed
	_speed = int(value)
	if not _accept_slider_change(previous, _speed):
		_speed = previous
		_speed_slider.set_value_no_signal(previous)
	_refresh()


func _on_density_changed(value: float) -> void:
	var previous := _density
	_density = int(value)
	if not _accept_slider_change(previous, _density):
		_density = previous
		_density_slider.set_value_no_signal(previous)
	_refresh()


func _on_pull_changed(value: float) -> void:
	var previous := _pull
	_pull = int(value)
	if not _accept_slider_change(previous, _pull):
		_pull = previous
		_pull_slider.set_value_no_signal(previous)
	_refresh()


func _accept_slider_change(previous_value: int, new_value: int) -> bool:
	return new_value <= previous_value or _calculate_credits() <= MAX_CREDITS


func _calculate_credits() -> int:
	var cost := 0
	var base_count := _selected_elements.size()
	cost += base_count * 10
	match _selected_shape:
		"Beam": cost += 15
		"Sphere": cost += 10
		"Wall": cost += 12
	if _charging and _selected_shape == "Sphere":
		cost += 5
	cost += (_intensity - 1) * 3
	cost += (_size - 1) * 2
	if _selected_shape == "Beam":
		cost += int(pow(float(_speed - 1), 1.5) * BEAM_SPEED_COST_SCALE)
	elif _selected_shape == "Sphere":
		cost += (_speed - 1) * 2
	if _selected_shape == "Beam":
		cost += int(pow(float(_range_val - 1), 1.5) * 3)
	else:
		cost += (_range_val - 1) * 2
	if _burns: cost += 5
	if _cools: cost += 4
	if _pushes: cost += 4
	if _blows: cost += 4
	if _is_current_healing_spell(): cost += 8
	if _has_density: cost += 3 + (_density - 1) * 2
	if _has_illusion: cost += 10
	if _has_pull: cost += 4 + (_pull - 1) * 2
	if base_count == 2:
		cost = int(ceil(cost * 1.15))
	elif base_count == 3:
		cost = int(ceil(cost * 1.35))
	if _is_known_synergy():
		cost = int(ceil(cost * 0.9))
	return cost


func _is_current_healing_spell() -> bool:
	if _heals:
		return true
	if not _selected_elements.has("Spirit") or _selected_elements.has("Void"):
		return false
	if _selected_elements.size() == 1:
		return true
	var effect := _get_complex_effect()
	if effect.is_empty():
		return false
	var stats: Dictionary = effect["stats"]
	return int(stats.get("Support", 0)) >= 7


func _update_preview() -> void:
	if _preview_mesh == null:
		return

	match _selected_shape:
		"Sphere":
			var mesh := SphereMesh.new()
			mesh.radius = 0.35 + (_size - 1) * 0.06
			mesh.height = mesh.radius * 2.0
			_preview_mesh.mesh = mesh
		"Beam":
			var mesh := CapsuleMesh.new()
			mesh.radius = 0.08 + (_size - 1) * 0.015
			mesh.height = 0.5 + (_range_val - 1) * 0.18
			_preview_mesh.mesh = mesh
		"Wall":
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.8 + (_size - 1) * 0.1, 1.0 + (_size - 1) * 0.1, 0.05)
			_preview_mesh.mesh = mesh
		_:
			var mesh := SphereMesh.new()
			mesh.radius = 0.18
			mesh.height = 0.36
			_preview_mesh.mesh = mesh

	if not _selected_elements.is_empty():
		var col: Color = _get_blended_color()
		_preview_material.albedo_color = col
		_preview_material.emission = col
		_preview_material.emission_energy_multiplier = 1.2 + (_intensity - 1) * 0.25 + (_selected_elements.size() - 1) * 0.35
	else:
		_preview_material.albedo_color = Color(0.3, 0.28, 0.38)
		_preview_material.emission = Color(0.15, 0.13, 0.2)
		_preview_material.emission_energy_multiplier = 0.5

	var scale_f := 1.0 + (_intensity - 1) * 0.04
	if _selected_elements.size() > 1:
		scale_f += (_selected_elements.size() - 1) * 0.08
	_preview_mesh.scale = Vector3(scale_f, scale_f, scale_f)


# ---------------------------------------------------------------------------
# SIGNAL HANDLERS
# ---------------------------------------------------------------------------

func _on_element_toggled(element: String, is_pressed: bool) -> void:
	if is_pressed:
		if _selected_elements.size() >= MAX_BASES:
			_element_buttons[element].set_pressed_no_signal(false)
			return
		if not _selected_elements.has(element):
			_selected_elements.append(element)
	else:
		_selected_elements.erase(element)
	_selected_element = _get_primary_element()
	_reset_attributes()
	_refresh()


func _on_shape_toggled(shape: String, is_pressed: bool) -> void:
	if is_pressed:
		if _selected_shape != "" and _selected_shape != shape:
			_shape_buttons[_selected_shape].set_pressed_no_signal(false)
		_selected_shape = shape
		if shape != "Sphere":
			_charging = false
			_charging_cb.set_pressed_no_signal(false)
	else:
		_selected_shape = ""
	_refresh()


func _reset_attributes() -> void:
	_burns = false
	_cools = false
	_pushes = false
	_blows = false
	_heals = false
	_has_density = false
	_density = 1
	_has_illusion = false
	_has_pull = false
	_pull = 1
	_burns_cb.set_pressed_no_signal(false)
	_cools_cb.set_pressed_no_signal(false)
	_pushes_cb.set_pressed_no_signal(false)
	_blows_cb.set_pressed_no_signal(false)
	_heals_cb.set_pressed_no_signal(false)
	_density_cb.set_pressed_no_signal(false)
	_density_slider.set_value_no_signal(1)
	_density_slider.visible = false
	_illusion_cb.set_pressed_no_signal(false)
	_pull_cb.set_pressed_no_signal(false)
	_pull_slider.set_value_no_signal(1)
	_pull_slider.visible = false


func _on_save_pressed() -> void:
	var spell := _create_spell_definition()
	if not spell.is_valid():
		return

	DirAccess.make_dir_recursive_absolute("user://spells")
	var old_path := _selected_saved_spell_path
	var path := _get_spell_save_path()
	var err := ResourceSaver.save(spell, path)
	if err != OK:
		push_error("Failed to save spell: %s" % error_string(err))
		return
	if not old_path.is_empty() and old_path != path and ResourceLoader.exists(old_path):
		var remove_err := DirAccess.remove_absolute(old_path)
		if remove_err != OK:
			push_error("Failed to remove renamed spell file: %s" % error_string(remove_err))
	for i in range(_loadout_paths.size()):
		if _loadout_paths[i] == old_path:
			_loadout_paths[i] = path
	_save_loadout()
	print("Spell saved: ", path)
	_selected_saved_spell_path = path
	_selected_saved_spell = spell
	_reload_saved_spells()
	_show_save_feedback()


func _get_spell_save_path() -> String:
	var safe_name := _spell_name.to_lower().replace(" ", "_").strip_edges()
	if safe_name.is_empty():
		safe_name = "unnamed_spell"
	return "user://spells/%s.tres" % safe_name


func _create_spell_definition() -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = _spell_name
	spell.base_element = _get_primary_element()
	spell.base_weights = _get_base_weights()
	spell.shape = _selected_shape
	spell.intensity = _intensity
	spell.spell_size = _size
	spell.spell_range = _range_val
	spell.spell_speed = _speed
	spell.has_charging = _charging
	spell.burns = _burns
	spell.cools = _cools
	spell.pushes = _pushes
	spell.blows = _blows
	spell.heals = _heals
	spell.has_density = _has_density
	spell.density = _density
	spell.has_illusion = _has_illusion
	spell.has_pull = _has_pull
	spell.pull_strength = _pull
	return spell


func _save_test_spell() -> bool:
	var spell := _create_spell_definition()
	if not spell.is_valid():
		return false
	var err := ResourceSaver.save(spell, TEST_SPELL_PATH)
	if err != OK:
		push_error("Failed to save test spell: %s" % error_string(err))
		return false
	return true


func _load_test_spell() -> void:
	if not ResourceLoader.exists(TEST_SPELL_PATH):
		return
	var spell := ResourceLoader.load(TEST_SPELL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SpellDefinition
	if spell == null:
		return
	_apply_spell_definition(spell)


func _apply_spell_definition(spell: SpellDefinition) -> void:
	_spell_name = spell.spell_name
	_selected_elements.clear()
	for element in spell.get_base_elements():
		_selected_elements.append(element)
	_selected_element = _get_primary_element()
	_selected_shape = spell.shape
	_intensity = spell.intensity
	_size = spell.spell_size
	_range_val = spell.spell_range
	_speed = spell.spell_speed
	_charging = spell.has_charging
	_burns = spell.burns
	_cools = spell.cools
	_pushes = spell.pushes
	_blows = spell.blows
	_heals = spell.heals
	_has_density = spell.has_density
	_density = spell.density
	_has_illusion = spell.has_illusion
	_has_pull = spell.has_pull
	_pull = spell.pull_strength

	_name_input.text = _spell_name
	for el: String in ELEMENTS:
		_element_buttons[el].set_pressed_no_signal(_selected_elements.has(el))
	for sh: String in SHAPES:
		_shape_buttons[sh].set_pressed_no_signal(sh == _selected_shape)
	_charging_cb.set_pressed_no_signal(_charging)
	_intensity_slider.set_value_no_signal(_intensity)
	_size_slider.set_value_no_signal(_size)
	_range_slider.set_value_no_signal(_range_val)
	_speed_slider.set_value_no_signal(_speed)
	_burns_cb.set_pressed_no_signal(_burns)
	_cools_cb.set_pressed_no_signal(_cools)
	_pushes_cb.set_pressed_no_signal(_pushes)
	_blows_cb.set_pressed_no_signal(_blows)
	_heals_cb.set_pressed_no_signal(_heals)
	_density_cb.set_pressed_no_signal(_has_density)
	_density_slider.visible = _has_density
	_density_slider.set_value_no_signal(_density)
	_illusion_cb.set_pressed_no_signal(_has_illusion)
	_pull_cb.set_pressed_no_signal(_has_pull)
	_pull_slider.visible = _has_pull
	_pull_slider.set_value_no_signal(_pull)


func _show_save_feedback() -> void:
	var lbl := Label.new()
	lbl.text = "Spell Saved!"
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	lbl.set_anchors_and_offsets_preset(PRESET_CENTER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.8)
	tween.tween_callback(lbl.queue_free)


func _on_cancel_pressed() -> void:
	_spell_name = "New Spell"
	_selected_saved_spell_path = ""
	_selected_saved_spell = null
	_selected_element = ""
	_selected_elements.clear()
	_selected_shape = ""
	_intensity = 1
	_size = 1
	_range_val = 1
	_speed = 1
	_charging = false
	for btn: Button in _element_buttons.values():
		btn.set_pressed_no_signal(false)
		btn.disabled = false
	for btn: Button in _shape_buttons.values():
		btn.set_pressed_no_signal(false)
		btn.disabled = false
	_charging_cb.set_pressed_no_signal(false)
	_intensity_slider.set_value_no_signal(1)
	_size_slider.set_value_no_signal(1)
	_range_slider.set_value_no_signal(1)
	_speed_slider.set_value_no_signal(1)
	_name_input.text = _spell_name
	_reset_attributes()
	_update_saved_spell_detail()
	_refresh_saved_spell_list()
	_refresh_loadout_panel()
	_refresh()


func _go_to_main_menu() -> void:
	if _game_return_target != null and is_instance_valid(_game_return_target) and _game_return_target.has_method("close_spell_creator_for_local_player"):
		_game_return_target.close_spell_creator_for_local_player()
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().call_deferred("change_scene_to_file", MAIN_MENU_SCENE)

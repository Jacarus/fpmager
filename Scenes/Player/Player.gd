extends CharacterBody3D

const SPEED := 5.5
const JUMP_VELOCITY := 4.8
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.0025
const CAST_COOLDOWN := 0.35
const MAX_MANA := 100.0
const MAX_HEALTH := 100
const RESPAWN_DELAY := 2.5
const MANA_REGEN_PER_SECOND := 14.0
const FALL_DAMAGE_SAFE_HEIGHT := 5.0
const FALL_DAMAGE_PER_METER := 18.0
const HARD_LANDING_MOMENTUM_CANCEL_HEIGHT := 3.0
const FALL_LANDING_VELOCITY_EPSILON := 0.2
const BEAM_MANA_TICK_MINIMUM := 0.35
const SPHERE_MAX_CHARGE_TIME := 2.5
const SPHERE_MAX_CHARGE_SIZE_BONUS := 5
const LOADOUT_SLOT_COUNT := 3
const LOADOUT_CREDIT_LIMIT := 120
const LOADOUT_PATH := "user://loadout.cfg"
const MAIN_MENU_SCENE := "res://Scenes/MainMenu/MainMenu.tscn"
const LOADOUT_SLOT_NAMES: Array[String] = ["LMB", "RMB", "Shift"]
const TEST_SPELL_PATH := "user://test_spell.tres"
const CAMERA_OFFSET := Vector3(0.75, 0.25, 3.2)
const CAMERA_LOOK_AHEAD := Vector3(0.0, 0.0, -8.0)
const PUSH_RECOIL_SCALE := 0.55
const PLAYER_WATER_TEST_PUSH := 8.0
const DIRECT_GRAVITY_RADIUS := 3.0
const NETWORK_SEND_RATE := 0.016
const REMOTE_INTERPOLATION_DELAY := 0.07
const REMOTE_SNAPSHOT_LIMIT := 24
const REMOTE_EXTRAPOLATION_LIMIT := 0.2
const REMOTE_SNAP_DISTANCE := 4.0
const KILL_ZONE_Y := -12.0
const ELEMENT_COLORS: Dictionary = {
	"Fire": Color(1.0, 0.35, 0.05),
	"Water": Color(0.1, 0.55, 1.0),
	"Air": Color(0.75, 0.92, 1.0),
	"Spirit": Color(0.72, 0.3, 1.0),
	"Earth": Color(0.6, 0.4, 0.15),
	"Light": Color(1.0, 1.0, 0.35),
	"Void": Color(0.45, 0.1, 0.65),
}

const SpellProjectileScene = preload("res://Scenes/SpellProjectile/SpellProjectile.tscn")
const SpellImpactEffectScript = preload("res://Scripts/SpellImpactEffect.gd")
const SpellNetworkCodecScript = preload("res://Scripts/SpellNetworkCodec.gd")

var _head: Node3D
var _camera: Camera3D
var _cast_origin: Node3D
var _spell_label: Label
var _health_bar: ProgressBar
var _health_label: Label
var _death_label: Label
var _mana_bar: ProgressBar
var _mana_label: Label
var _hint_label: Label
var _blind_overlay: ColorRect
var _pause_overlay: CanvasLayer
var _fullscreen_btn: Button
var _spells: Array[SpellDefinition] = []
var _active_index: int = 0
var _loadout_slots: Array[SpellDefinition] = []
var _loadout_paths: Array[String] = []
var _loadout_message: String = ""
var _active_cast_slot: int = -1
var _cast_timer: float = 0.0
var _health: int = MAX_HEALTH
var _mana: float = MAX_MANA
var _external_velocity: Vector3 = Vector3.ZERO
var _blind_timer: float = 0.0
var _blind_duration: float = 0.0
var _is_dead: bool = false
var _respawn_timer: float = 0.0
var _kill_zone_respawn_timer: float = -1.0
var _respawn_position: Vector3
var _was_on_floor_last_frame: bool = true
var _fall_peak_y: float = 0.0
var _server_was_falling: bool = false
var _server_fall_peak_y: float = 0.0
var _server_previous_pos: Vector3
var _server_previous_velocity: Vector3 = Vector3.ZERO
var _server_has_previous_motion: bool = false
var _jump_was_pressed_last_frame: bool = false
var _active_beam: Node3D
var _active_beam_spell: SpellDefinition
var _beam_visible_length: float = 0.0
var _beam_impact_timer: float = 0.0
var _beam_core: MeshInstance3D
var _beam_tip: MeshInstance3D
var _beam_light: OmniLight3D
var _server_beam_origin: Vector3
var _server_beam_target: Vector3
var _server_beam_correction_time: float = -1.0
var _remote_beam: Node3D
var _remote_beam_spell: SpellDefinition
var _remote_beam_core: MeshInstance3D
var _remote_beam_tip: MeshInstance3D
var _remote_beam_light: OmniLight3D
var _remote_beam_origin: Vector3
var _remote_beam_target: Vector3
var _remote_beam_last_update_time: float = 0.0
var _player_color: Color = Color(0.18, 0.14, 0.24)
var _body_material: StandardMaterial3D
var _charging_sphere_spell: SpellDefinition
var _charging_sphere_time: float = 0.0
var _charging_sphere_paid_size: int = 0
var _charging_sphere_visual: MeshInstance3D
var _charging_sphere_light: OmniLight3D
var _charging_sphere_material: StandardMaterial3D
var _network_peer_id: int = 1
var _is_local_player: bool = true
var _net_send_timer: float = 0.0
var _server_state_lock_timer: float = 0.0
var _remote_snapshots: Array[Dictionary] = []
var _remote_clock_offset: float = 0.0
var _has_remote_clock_offset: bool = false
var _remote_clock_samples: int = 0
# Server-side position history for lag compensation (last 500 ms).
var _server_pos_history: Array[Dictionary] = []
const SERVER_POS_HISTORY_DURATION := 0.5


func setup_multiplayer(peer_id: int, is_local_player: bool) -> void:
	_network_peer_id = peer_id
	_is_local_player = is_local_player
	set_multiplayer_authority(peer_id)
	_remote_snapshots.clear()


func set_player_color(color: Color) -> void:
	_player_color = color
	if _body_material != null:
		_body_material.albedo_color = _player_color
		_body_material.emission = _player_color


func get_network_peer_id() -> int:
	return _network_peer_id


func _ready() -> void:
	_build_body()
	_camera.current = _is_local_player
	if _is_local_player:
		_build_hud()
		_build_pause_overlay()
		_load_spells()
	_respawn_position = global_position
	if _is_local_player:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_was_on_floor_last_frame = is_on_floor()
	_fall_peak_y = global_position.y
	_server_previous_pos = global_position
	_server_fall_peak_y = global_position.y


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_stop_remote_beam_visual()
		if _active_beam != null:
			_active_beam.queue_free()
		return
	if not _is_local_player:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_charged_sphere()
		_stop_beam()
		velocity.x = 0.0
		velocity.z = 0.0
		_external_velocity = Vector3.ZERO
		_force_client_transform_sync()


func _process(delta: float) -> void:
	_tick_remote_beam_visual()
	if not _is_local_player:
		_update_remote_visual_transform(delta)


func _tick_remote_beam_visual() -> void:
	if _remote_beam == null:
		return
	if _network_time() - _remote_beam_last_update_time > 0.6:
		_stop_remote_beam_visual()
		return
	_apply_remote_beam_transform()


func _build_body() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.75
	col.shape = capsule
	col.position.y = 0.875
	add_child(col)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = 1.6
	add_child(_head)

	_camera = Camera3D.new()
	_camera.position = CAMERA_OFFSET
	_head.add_child(_camera)
	_camera.look_at(_head.to_global(CAMERA_LOOK_AHEAD), Vector3.UP)

	_cast_origin = Node3D.new()
	_cast_origin.position = Vector3(0.45, -0.18, -0.45)
	_head.add_child(_cast_origin)

	_build_visible_mage()


func _build_visible_mage() -> void:
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = _player_color
	_body_material.emission_enabled = true
	_body_material.emission = _player_color
	_body_material.emission_energy_multiplier = 0.12
	_body_material.roughness = 0.8

	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.32
	body_mesh.height = 1.45
	body.mesh = body_mesh
	body.material_override = _body_material
	body.position.y = 0.8
	add_child(body)

	var hand_mat := StandardMaterial3D.new()
	hand_mat.albedo_color = Color(0.55, 0.46, 0.38)
	hand_mat.roughness = 0.65

	var hand := MeshInstance3D.new()
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.11
	hand_mesh.height = 0.22
	hand.mesh = hand_mesh
	hand.material_override = hand_mat
	hand.position = _cast_origin.position
	_head.add_child(hand)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Crosshair — PRESET_CENTER then set all four offsets so width/height are positive
	var crosshair := Label.new()
	crosshair.text = "+"
	canvas.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -10.0
	crosshair.offset_top = -10.0
	crosshair.offset_right = 10.0
	crosshair.offset_bottom = 10.0
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size", 22)
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))

	# Active spell name — PRESET_BOTTOM_WIDE gives anchor_right = 1 so width is valid
	_spell_label = Label.new()
	canvas.add_child(_spell_label)
	_spell_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_spell_label.offset_left = 16.0
	_spell_label.offset_top = -44.0
	_spell_label.offset_right = -16.0
	_spell_label.offset_bottom = -8.0
	_spell_label.add_theme_font_size_override("font_size", 16)
	_spell_label.add_theme_color_override("font_color", Color(0.95, 0.9, 1.0))

	var health_panel := VBoxContainer.new()
	canvas.add_child(health_panel)
	health_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	health_panel.offset_left = 16.0
	health_panel.offset_top = 42.0
	health_panel.offset_right = 236.0
	health_panel.offset_bottom = 84.0
	health_panel.add_theme_constant_override("separation", 4)

	_health_label = Label.new()
	_health_label.add_theme_font_size_override("font_size", 13)
	_health_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	health_panel.add_child(_health_label)

	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0.0
	_health_bar.max_value = MAX_HEALTH
	_health_bar.value = _health
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size = Vector2(220, 10)
	health_panel.add_child(_health_bar)
	_update_health_hud()

	var mana_panel := VBoxContainer.new()
	canvas.add_child(mana_panel)
	mana_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mana_panel.offset_left = 16.0
	mana_panel.offset_top = 88.0
	mana_panel.offset_right = 236.0
	mana_panel.offset_bottom = 130.0
	mana_panel.add_theme_constant_override("separation", 4)

	_mana_label = Label.new()
	_mana_label.add_theme_font_size_override("font_size", 13)
	_mana_label.add_theme_color_override("font_color", Color(0.65, 0.82, 1.0))
	mana_panel.add_child(_mana_label)

	_mana_bar = ProgressBar.new()
	_mana_bar.min_value = 0.0
	_mana_bar.max_value = MAX_MANA
	_mana_bar.value = _mana
	_mana_bar.show_percentage = false
	_mana_bar.custom_minimum_size = Vector2(220, 10)
	mana_panel.add_child(_mana_bar)
	_update_mana_hud()

	_death_label = Label.new()
	canvas.add_child(_death_label)
	_death_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_death_label.offset_left = -180.0
	_death_label.offset_top = -36.0
	_death_label.offset_right = 180.0
	_death_label.offset_bottom = 36.0
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 24)
	_death_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.25))
	_death_label.visible = false

	# Controls hint — PRESET_TOP_WIDE gives anchor_right = 1 so width is valid
	_hint_label = Label.new()
	canvas.add_child(_hint_label)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint_label.offset_left = 16.0
	_hint_label.offset_top = 12.0
	_hint_label.offset_right = -16.0
	_hint_label.offset_bottom = 32.0
	_hint_label.text = "WASD: Move   Space: Jump   LMB/RMB/Shift: Cast slots   Scroll: Browse spells   1/2/3: Assign browsed spell   ESC: Menu   F11: Fullscreen"
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.6))

	_blind_overlay = ColorRect.new()
	canvas.add_child(_blind_overlay)
	_blind_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blind_overlay.color = Color(1.0, 0.96, 0.72, 0.0)


func _build_pause_overlay() -> void:
	_pause_overlay = CanvasLayer.new()
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(220, 0)
	_pause_overlay.add_child(panel)

	var margin := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.pressed.connect(_on_resume)
	vbox.add_child(resume_btn)

	var spell_creator_btn := Button.new()
	spell_creator_btn.text = "Spell Creator"
	spell_creator_btn.pressed.connect(_go_to_spell_creator)
	vbox.add_child(spell_creator_btn)

	_fullscreen_btn = Button.new()
	_update_fullscreen_button()
	_fullscreen_btn.pressed.connect(GameSettings.toggle_fullscreen)
	vbox.add_child(_fullscreen_btn)
	if not GameSettings.fullscreen_changed.is_connected(_on_fullscreen_changed):
		GameSettings.fullscreen_changed.connect(_on_fullscreen_changed)

	var main_menu_btn := Button.new()
	main_menu_btn.text = "Main Menu"
	main_menu_btn.pressed.connect(_go_to_main_menu)
	vbox.add_child(main_menu_btn)


func _load_spells() -> void:
	_loadout_slots.clear()
	_loadout_paths.clear()
	for i in range(LOADOUT_SLOT_COUNT):
		_loadout_slots.append(null)
		_loadout_paths.append("")
	_load_test_spell()

	var dir := DirAccess.open("user://spells")
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres"):
				var spell := ResourceLoader.load("user://spells/" + fname, "", ResourceLoader.CACHE_MODE_IGNORE) as SpellDefinition
				if spell != null:
					_spells.append(spell)
			fname = dir.get_next()
		dir.list_dir_end()

	if _spells.is_empty():
		var fallback := SpellDefinition.new()
		fallback.spell_name = "Test Fireball"
		fallback.base_element = "Fire"
		fallback.shape = "Sphere"
		fallback.intensity = 3
		fallback.spell_size = 2
		fallback.spell_range = 5
		_spells.append(fallback)

	if not _load_saved_loadout():
		_build_default_loadout()
		_save_loadout()
	_update_spell_label()


func _load_test_spell() -> bool:
	if not ResourceLoader.exists(TEST_SPELL_PATH):
		return false
	var spell := ResourceLoader.load(TEST_SPELL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SpellDefinition
	if spell == null or not spell.is_valid():
		return false
	_spells.append(spell)
	_active_index = 0
	return true


func _update_spell_label() -> void:
	if _spells.is_empty():
		_spell_label.text = ""
		return
	var s := _spells[_active_index]
	var credits := s.calculate_credits()
	var mana_cost := s.calculate_mana_cost()
	var mana_text := "%.1f/s" % s.calculate_beam_mana_per_second() if s.shape == "Beam" else "%d mana" % mana_cost
	var damage_text := _get_spell_output_text(s)
	var message_suffix := "\n%s" % _loadout_message if not _loadout_message.is_empty() else ""
	_spell_label.text = "Browse [%d/%d] %s (%s %s) - %s %d cr - %s - %s\nLoadout %d/%d cr:  %s   %s   %s%s" % [
		_active_index + 1, _spells.size(),
		s.spell_name, s.get_base_display_name(), s.shape,
		s.get_spell_type(), credits, mana_text, damage_text,
		_get_loadout_cost(), LOADOUT_CREDIT_LIMIT,
		_get_slot_display_name(0), _get_slot_display_name(1), _get_slot_display_name(2),
		message_suffix
	]


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_player:
		return
	if event is InputEventMouseButton:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_cast_slot(0)
			else:
				_release_charged_sphere()
				_stop_beam()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_try_cast_slot(1)
			else:
				_release_charged_sphere()
				_stop_beam()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_spell(1)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_spell(-1)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		_head.rotation.x = clamp(_head.rotation.x, -deg_to_rad(85), deg_to_rad(85))

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_cancel_charged_sphere()
				_stop_beam()
				_toggle_pause()
			KEY_F11:
				GameSettings.toggle_fullscreen()
			KEY_SHIFT:
				_try_cast_slot(2)
			KEY_1, KEY_2, KEY_3:
				var idx: int = int(event.keycode) - int(KEY_1)
				_assign_active_spell_to_slot(idx)
	if event is InputEventKey and not event.pressed and not event.echo:
		if event.keycode == KEY_SHIFT:
			_release_charged_sphere()
			_stop_beam()


func _toggle_pause() -> void:
	var paused := not _pause_overlay.visible
	_pause_overlay.visible = paused
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	)


func _on_resume() -> void:
	_pause_overlay.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_fullscreen_changed(_enabled: bool) -> void:
	_update_fullscreen_button()


func _update_fullscreen_button() -> void:
	if _fullscreen_btn == null:
		return
	_fullscreen_btn.text = "Windowed" if GameSettings.is_fullscreen() else "Fullscreen"


func _go_to_spell_creator() -> void:
	_cancel_charged_sphere()
	_stop_beam()
	if _pause_overlay != null:
		_pause_overlay.visible = false
	var world := get_tree().current_scene
	if world != null and world.has_method("open_spell_creator_for_local_player"):
		world.open_spell_creator_for_local_player()


func _go_to_main_menu() -> void:
	_cancel_charged_sphere()
	_stop_beam()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	get_tree().call_deferred("change_scene_to_file", MAIN_MENU_SCENE)


func _cycle_spell(dir: int) -> void:
	if _spells.is_empty():
		return
	_cancel_charged_sphere()
	_stop_beam()
	_active_index = (_active_index + dir + _spells.size()) % _spells.size()
	_update_spell_label()


func _build_default_loadout() -> void:
	for spell in _spells:
		for slot_index in range(LOADOUT_SLOT_COUNT):
			if _loadout_slots[slot_index] == null and _can_assign_spell_to_slot(spell, slot_index):
				_loadout_slots[slot_index] = spell
				_loadout_paths[slot_index] = _find_spell_path(spell)
				break


func _load_saved_loadout() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(LOADOUT_PATH) != OK:
		return false
	var loaded_any := false
	for i in range(LOADOUT_SLOT_COUNT):
		var path := str(cfg.get_value("slots", str(i), ""))
		if path.is_empty():
			continue
		var spell := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SpellDefinition
		if spell == null or not spell.is_valid():
			continue
		if _get_loadout_cost() + spell.calculate_credits() > LOADOUT_CREDIT_LIMIT:
			continue
		_loadout_paths[i] = path
		_loadout_slots[i] = spell
		loaded_any = true
	return loaded_any


func _save_loadout() -> void:
	var cfg := ConfigFile.new()
	for i in range(LOADOUT_SLOT_COUNT):
		cfg.set_value("slots", str(i), _loadout_paths[i])
	cfg.save(LOADOUT_PATH)


func _find_spell_path(target_spell: SpellDefinition) -> String:
	if ResourceLoader.exists(TEST_SPELL_PATH):
		var test_spell := ResourceLoader.load(TEST_SPELL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SpellDefinition
		if test_spell == target_spell:
			return TEST_SPELL_PATH
	var dir := DirAccess.open("user://spells")
	if dir == null:
		return ""
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var path := "user://spells/%s" % fname
			var spell := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SpellDefinition
			if spell == target_spell:
				dir.list_dir_end()
				return path
		fname = dir.get_next()
	dir.list_dir_end()
	return ""


func _assign_active_spell_to_slot(slot_index: int) -> void:
	if _spells.is_empty() or slot_index < 0 or slot_index >= LOADOUT_SLOT_COUNT:
		return
	var spell := _spells[_active_index]
	if not _can_assign_spell_to_slot(spell, slot_index):
		_loadout_message = "Cannot assign %s to slot %d: loadout would exceed %d credits." % [
			spell.spell_name, slot_index + 1, LOADOUT_CREDIT_LIMIT
		]
		_update_spell_label()
		return
	_loadout_slots[slot_index] = spell
	_loadout_paths[slot_index] = _find_spell_path(spell)
	_save_loadout()
	_loadout_message = "Assigned %s to slot %d." % [spell.spell_name, slot_index + 1]
	_update_spell_label()


func _can_assign_spell_to_slot(spell: SpellDefinition, slot_index: int) -> bool:
	if spell == null:
		return false
	var projected_cost := spell.calculate_credits()
	for i in range(_loadout_slots.size()):
		if i == slot_index:
			continue
		var slotted := _loadout_slots[i] as SpellDefinition
		if slotted != null:
			projected_cost += slotted.calculate_credits()
	return projected_cost <= LOADOUT_CREDIT_LIMIT


func _get_loadout_cost() -> int:
	var total := 0
	for spell in _loadout_slots:
		var slotted := spell as SpellDefinition
		if slotted != null:
			total += slotted.calculate_credits()
	return total


func _get_slot_display_name(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= _loadout_slots.size():
		return "-"
	var spell := _loadout_slots[slot_index] as SpellDefinition
	if spell == null:
		return "-"
	return "%s %s(%d)" % [LOADOUT_SLOT_NAMES[slot_index], spell.spell_name, spell.calculate_credits()]


func _get_spell_output_text(spell: SpellDefinition) -> String:
	var push_suffix := " + %.1f push" % spell.calculate_push_force(false) if spell.calculate_push_force(false) > 0.0 else ""
	var gravity_suffix := " + %.1f gravity" % spell.calculate_gravity_force(0.0, 3.0, false) if spell.calculate_gravity_force(0.0, 3.0, false) > 0.0 else ""
	var blind_suffix := " + %.1fs blind" % spell.calculate_blind_duration(false) if spell.calculate_blind_duration(false) > 0.0 else ""
	if spell.is_healing_spell():
		return ("%d/tick heal" % spell.calculate_healing(true) if spell.shape == "Beam" else "%d heal" % spell.calculate_healing()) + push_suffix + gravity_suffix + blind_suffix
	return ("%d/tick" % spell.calculate_damage(true) if spell.shape == "Beam" else "%d dmg" % spell.calculate_damage()) + push_suffix + gravity_suffix + blind_suffix


func _try_cast_slot(slot_index: int) -> void:
	if _is_dead or _spells.is_empty() or _cast_timer > 0.0:
		return
	if slot_index < 0 or slot_index >= _loadout_slots.size():
		return
	var spell := _loadout_slots[slot_index]
	if spell == null:
		return
	_active_cast_slot = slot_index
	if spell.shape == "Beam":
		if _mana < BEAM_MANA_TICK_MINIMUM:
			return
		_start_beam(spell)
		return
	if spell.is_healing_spell() and not (spell.shape == "Sphere" and spell.has_charging):
		var mana_cost := spell.calculate_mana_cost()
		if not _spend_mana(mana_cost):
			return
		_cast_timer = CAST_COOLDOWN
		_cast_self_effect_spell(spell, mana_cost)
		return
	if spell.shape == "Sphere" and spell.has_charging:
		if not _spend_mana(spell.calculate_charged_mana_cost(spell.spell_size)):
			return
		_start_charged_sphere(spell)
		return

	if not _spend_mana(spell.calculate_mana_cost()):
		return
	_cast_timer = CAST_COOLDOWN
	_cast_projectile_spell(spell, _get_cast_origin(), _get_aim_direction())


func _start_beam(spell: SpellDefinition) -> void:
	if _active_beam != null:
		return

	_active_beam_spell = spell
	_beam_visible_length = 0.0
	_beam_impact_timer = 0.0
	_active_beam = Node3D.new()
	get_tree().current_scene.add_child(_active_beam)

	var col: Color = _get_spell_color(spell)
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = col
	core_mat.emission_enabled = true
	core_mat.emission = col
	core_mat.emission_energy_multiplier = 2.0 + spell.intensity * 0.25

	var core_mesh := CylinderMesh.new()
	_beam_core = MeshInstance3D.new()
	_beam_core.mesh = core_mesh
	_beam_core.material_override = core_mat
	_active_beam.add_child(_beam_core)

	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.18
	tip_mesh.height = 0.36
	_beam_tip = MeshInstance3D.new()
	_beam_tip.mesh = tip_mesh
	_beam_tip.material_override = core_mat
	_active_beam.add_child(_beam_tip)

	_beam_light = OmniLight3D.new()
	_beam_light.light_color = col
	_beam_light.light_energy = 1.0 + spell.intensity * 0.4
	_beam_light.omni_range = 3.0 + spell.spell_size * 0.4
	_active_beam.add_child(_beam_light)
	_broadcast_beam_start(spell)
	_update_beam()


func _stop_beam() -> void:
	if _active_beam == null:
		return
	_active_beam.queue_free()
	_active_beam = null
	_active_beam_spell = null
	_beam_visible_length = 0.0
	_beam_impact_timer = 0.0
	_beam_core = null
	_beam_tip = null
	_beam_light = null
	_server_beam_correction_time = -1.0
	var world := get_tree().current_scene
	if world != null and world.has_method("unregister_beam_segment"):
		world.unregister_beam_segment(_get_beam_source_key())
	_broadcast_beam_stop()


func _update_beam() -> void:
	if _active_beam == null or _active_beam_spell == null:
		return

	var origin: Vector3 = _get_cast_origin()
	var direction: Vector3 = _get_aim_direction()
	var max_distance: float = 7.0 + _active_beam_spell.spell_range * 3.0
	var target: Vector3 = origin + direction * max_distance
	var hit_normal: Vector3 = Vector3.UP
	var has_hit: bool = false

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [self]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		target = hit["position"]
		hit_normal = hit["normal"] as Vector3
		has_hit = true

	var target_length: float = maxf(0.1, origin.distance_to(target))
	var propagation_speed: float = _get_beam_propagation_speed(_active_beam_spell.spell_speed)
	_beam_visible_length = move_toward(_beam_visible_length, target_length, propagation_speed * get_physics_process_delta_time())
	var length: float = minf(target_length, maxf(0.1, _beam_visible_length))
	var visible_target: Vector3 = origin + direction * length
	var beam_blocked_by_spell := false
	var world := get_tree().current_scene
	if world != null and world.has_method("resolve_beam_segment") and not _is_network_client():
		var beam_result: Dictionary = world.resolve_beam_segment(_get_beam_source_key(), _active_beam_spell, origin, visible_target, self)
		visible_target = beam_result.get("target", visible_target) as Vector3
		beam_blocked_by_spell = bool(beam_result.get("blocked", false))
		length = maxf(0.1, origin.distance_to(visible_target))
	elif _is_network_client() and _network_time() - _server_beam_correction_time < 0.12 and origin.distance_to(_server_beam_origin) < 1.2:
		visible_target = _server_beam_target
		beam_blocked_by_spell = origin.distance_to(visible_target) + 0.05 < target_length
		length = maxf(0.1, origin.distance_to(visible_target))
	var midpoint: Vector3 = origin.lerp(visible_target, 0.5)
	var thickness: float = 0.08 + (_active_beam_spell.spell_size - 1) * 0.025

	var mesh := _beam_core.mesh as CylinderMesh
	mesh.top_radius = thickness
	mesh.bottom_radius = thickness
	mesh.height = length
	_beam_core.global_position = midpoint
	_beam_core.look_at(visible_target, Vector3.UP)
	_beam_core.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	var pulse_rate: float = 0.004 + _active_beam_spell.spell_speed * 0.012
	var pulse_strength: float = 0.12 + _active_beam_spell.spell_speed * 0.018
	var pulse := 1.0 + sin(Time.get_ticks_msec() * pulse_rate) * pulse_strength
	_beam_core.scale = Vector3(pulse, 1.0, pulse)
	_beam_tip.global_position = visible_target
	_beam_tip.scale = Vector3.ONE * (0.7 + thickness * 4.0 + pulse_strength * pulse)
	_beam_light.global_position = visible_target
	_broadcast_beam_update(origin, visible_target)

	if has_hit and not beam_blocked_by_spell and length >= target_length - 0.05 and _beam_impact_timer <= 0.0:
		if _is_network_client():
			_server_beam_tick.rpc_id(1, SpellNetworkCodecScript.to_dict(_active_beam_spell), origin, direction)
		else:
			_apply_spell_hit_to_collider(hit.get("collider"), _active_beam_spell, target, hit_normal, true)
			_apply_push_recoil(_active_beam_spell, target, hit_normal, true)
			_spawn_spell_impact(_active_beam_spell, target, hit_normal)
		_beam_impact_timer = 0.35


func _get_cast_origin() -> Vector3:
	if _cast_origin == null:
		return _camera.global_position
	return _cast_origin.global_position


func _get_aim_direction() -> Vector3:
	return _camera.global_basis.z.normalized() * -1.0


func _get_beam_propagation_speed(spell_speed: int) -> float:
	if spell_speed >= 10:
		return 420.0
	return 1.8 + pow(float(spell_speed), 1.55) * 2.1


func _get_beam_source_key() -> String:
	return "player:%d" % _network_peer_id


func _broadcast_beam_start(spell: SpellDefinition) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	var spell_data := SpellNetworkCodecScript.to_dict(spell)
	if multiplayer.is_server():
		_client_start_beam_visual.rpc(spell_data, _network_peer_id)
	else:
		_server_start_beam_visual.rpc_id(1, spell_data)


func _broadcast_beam_update(origin: Vector3, target: Vector3) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_client_update_beam_visual.rpc(origin, target, _network_peer_id, false)
	else:
		_server_update_beam_visual.rpc_id(1, origin, target)


func _broadcast_beam_stop() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_client_stop_beam_visual.rpc(_network_peer_id)
	else:
		_server_stop_beam_visual.rpc_id(1)


@rpc("any_peer", "reliable")
func _server_start_beam_visual(spell_data: Dictionary) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _network_peer_id:
		return
	_client_start_beam_visual.rpc(spell_data, _network_peer_id)
	_start_remote_beam_visual(SpellNetworkCodecScript.from_dict(spell_data))


@rpc("any_peer", "unreliable")
func _server_update_beam_visual(origin: Vector3, target: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _network_peer_id:
		return
	var broadcast_target := target
	var broadcast_blocked := false
	var world := get_tree().current_scene
	if world != null and world.has_method("resolve_beam_segment") and _remote_beam_spell != null:
		var beam_result: Dictionary = world.resolve_beam_segment(_get_beam_source_key(), _remote_beam_spell, origin, target, self)
		broadcast_target = beam_result.get("target", target) as Vector3
		broadcast_blocked = bool(beam_result.get("blocked", false))
	_client_update_beam_visual.rpc(origin, broadcast_target, _network_peer_id, broadcast_blocked)
	_update_remote_beam_visual(origin, broadcast_target)


@rpc("any_peer", "reliable")
func _server_stop_beam_visual() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _network_peer_id:
		return
	var world := get_tree().current_scene
	if world != null and world.has_method("unregister_beam_segment"):
		world.unregister_beam_segment(_get_beam_source_key())
	_client_stop_beam_visual.rpc(_network_peer_id)
	_stop_remote_beam_visual()


@rpc("any_peer", "reliable")
func _client_start_beam_visual(spell_data: Dictionary, source_peer_id: int) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	if source_peer_id == multiplayer.get_unique_id():
		return
	_start_remote_beam_visual(SpellNetworkCodecScript.from_dict(spell_data))


@rpc("any_peer", "unreliable")
func _client_update_beam_visual(origin: Vector3, target: Vector3, source_peer_id: int, source_blocked: bool = false) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	if source_peer_id == multiplayer.get_unique_id():
		if source_blocked:
			_server_beam_origin = origin
			_server_beam_target = target
			_server_beam_correction_time = _network_time()
		return
	_update_remote_beam_visual(origin, target)


@rpc("any_peer", "reliable")
func _client_stop_beam_visual(source_peer_id: int) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	if source_peer_id == multiplayer.get_unique_id():
		return
	_stop_remote_beam_visual()


func _start_remote_beam_visual(spell: SpellDefinition) -> void:
	_stop_remote_beam_visual()
	_remote_beam_spell = spell
	_remote_beam = Node3D.new()
	get_tree().current_scene.add_child(_remote_beam)

	var col: Color = _get_spell_color(spell)
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = col
	core_mat.emission_enabled = true
	core_mat.emission = col
	core_mat.emission_energy_multiplier = 2.0 + spell.intensity * 0.25

	_remote_beam_core = MeshInstance3D.new()
	_remote_beam_core.mesh = CylinderMesh.new()
	_remote_beam_core.material_override = core_mat
	_remote_beam.add_child(_remote_beam_core)

	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.18
	tip_mesh.height = 0.36
	_remote_beam_tip = MeshInstance3D.new()
	_remote_beam_tip.mesh = tip_mesh
	_remote_beam_tip.material_override = core_mat
	_remote_beam.add_child(_remote_beam_tip)

	_remote_beam_light = OmniLight3D.new()
	_remote_beam_light.light_color = col
	_remote_beam_light.light_energy = 1.0 + spell.intensity * 0.4
	_remote_beam_light.omni_range = 3.0 + spell.spell_size * 0.4
	_remote_beam.add_child(_remote_beam_light)
	_remote_beam_last_update_time = _network_time()


func _update_remote_beam_visual(origin: Vector3, target: Vector3) -> void:
	if _remote_beam == null or _remote_beam_spell == null:
		return
	_remote_beam_origin = origin
	_remote_beam_target = target
	_remote_beam_last_update_time = _network_time()
	_apply_remote_beam_transform()


func _apply_remote_beam_transform() -> void:
	if _remote_beam_core == null or _remote_beam_tip == null or _remote_beam_light == null or _remote_beam_spell == null:
		return
	var length: float = maxf(0.1, _remote_beam_origin.distance_to(_remote_beam_target))
	var midpoint: Vector3 = _remote_beam_origin.lerp(_remote_beam_target, 0.5)
	var thickness: float = 0.08 + (_remote_beam_spell.spell_size - 1) * 0.025
	var mesh := _remote_beam_core.mesh as CylinderMesh
	mesh.top_radius = thickness
	mesh.bottom_radius = thickness
	mesh.height = length
	_remote_beam_core.global_position = midpoint
	_remote_beam_core.look_at(_remote_beam_target, Vector3.UP)
	_remote_beam_core.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var pulse_rate: float = 0.004 + _remote_beam_spell.spell_speed * 0.012
	var pulse_strength: float = 0.12 + _remote_beam_spell.spell_speed * 0.018
	var pulse := 1.0 + sin(Time.get_ticks_msec() * pulse_rate) * pulse_strength
	_remote_beam_core.scale = Vector3(pulse, 1.0, pulse)
	_remote_beam_tip.global_position = _remote_beam_target
	_remote_beam_tip.scale = Vector3.ONE * (0.7 + thickness * 4.0 + pulse_strength * pulse)
	_remote_beam_light.global_position = _remote_beam_target


func _stop_remote_beam_visual() -> void:
	if _remote_beam != null:
		_remote_beam.queue_free()
	_remote_beam = null
	_remote_beam_spell = null
	_remote_beam_core = null
	_remote_beam_tip = null
	_remote_beam_light = null


func _get_spell_color(spell: SpellDefinition) -> Color:
	var weights := spell.get_base_weights()
	if weights.is_empty():
		return ELEMENT_COLORS.get(spell.base_element, Color(0.6, 0.4, 1.0))
	var total_weight := 0.0
	var color := Color.BLACK
	for element in weights.keys():
		var weight := float(weights[element])
		total_weight += weight
		color += ELEMENT_COLORS.get(str(element), Color(0.6, 0.4, 1.0)) * weight
	if total_weight <= 0.0:
		return Color(0.6, 0.4, 1.0)
	return color / total_weight


func _spawn_spell_impact(spell: SpellDefinition, position: Vector3, normal: Vector3, broadcast_to_clients: bool = true) -> void:
	var effect := SpellImpactEffectScript.new()
	get_tree().current_scene.add_child(effect)
	effect.initialize(spell, position, normal, self)
	var world := get_tree().current_scene
	if broadcast_to_clients and multiplayer.multiplayer_peer != null and multiplayer.is_server() and world != null and world.has_method("broadcast_spell_impact"):
		world.broadcast_spell_impact(spell, position, normal)


func _cast_projectile_spell(spell: SpellDefinition, from: Vector3, direction: Vector3) -> void:
	if _is_network_client():
		var world := get_tree().current_scene
		if world != null and world.has_method("remember_predicted_projectile"):
			world.remember_predicted_projectile(spell, from, direction)
		_spawn_projectile_local(spell, from, direction, self)
		_server_cast_projectile.rpc_id(1, SpellNetworkCodecScript.to_dict(spell), from, direction, _network_time())
		return
	_spawn_projectile_for_all(spell, from, direction)


func _cast_self_effect_spell(spell: SpellDefinition, mana_cost_paid: float = -1.0) -> void:
	var mana_cost := mana_cost_paid if mana_cost_paid >= 0.0 else float(spell.calculate_mana_cost())
	if _is_network_client():
		_server_cast_self_effect.rpc_id(1, SpellNetworkCodecScript.to_dict(spell), mana_cost)
		return
	_apply_self_effect_for_all(spell)


@rpc("any_peer", "reliable")
func _server_cast_projectile(spell_data: Dictionary, from: Vector3, direction: Vector3, client_cast_time: float = -1.0) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _network_peer_id:
		return
	_spawn_projectile_for_all(SpellNetworkCodecScript.from_dict(spell_data), from, direction, client_cast_time)


@rpc("any_peer", "reliable")
func _server_cast_self_effect(spell_data: Dictionary, mana_cost_paid: float = -1.0) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _network_peer_id:
		return
	var spell := SpellNetworkCodecScript.from_dict(spell_data)
	var mana_cost := mana_cost_paid if mana_cost_paid >= 0.0 else float(spell.calculate_mana_cost())
	if not _spend_mana(mana_cost):
		_broadcast_combat_state()
		return
	_apply_self_effect_for_all(spell)
	_broadcast_combat_state()


@rpc("any_peer", "reliable")
func _server_beam_tick(spell_data: Dictionary, origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _network_peer_id:
		return
	var spell := SpellNetworkCodecScript.from_dict(spell_data)
	var max_distance := 7.0 + spell.spell_range * 3.0
	var target := origin + direction.normalized() * max_distance
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var hit_position := hit["position"] as Vector3
	var hit_normal := hit["normal"] as Vector3
	var world := get_tree().current_scene
	if world != null and world.has_method("get_registered_beam_target"):
		var beam_target: Vector3 = world.get_registered_beam_target(_get_beam_source_key(), hit_position)
		if origin.distance_to(beam_target) + 0.05 < origin.distance_to(hit_position):
			return
	_apply_spell_hit_to_collider(hit.get("collider"), spell, hit_position, hit_normal, true)
	_apply_push_recoil(spell, hit_position, hit_normal, true)
	_spawn_spell_impact(spell, hit_position, hit_normal)


func _spawn_projectile_for_all(spell: SpellDefinition, from: Vector3, direction: Vector3, cast_server_time: float = -1.0) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		var world := get_tree().current_scene
		if world != null and world.has_method("spawn_network_projectile"):
			world.spawn_network_projectile(spell, from, direction, self, cast_server_time)
			return
		_client_spawn_projectile.rpc(SpellNetworkCodecScript.to_dict(spell), from, direction, _network_peer_id)
		return
	_spawn_projectile_local(spell, from, direction, self)


@rpc("any_peer", "call_local", "reliable")
func _client_spawn_projectile(spell_data: Dictionary, from: Vector3, direction: Vector3, source_peer_id: int) -> void:
	var source := _find_network_player(source_peer_id)
	_spawn_projectile_local(SpellNetworkCodecScript.from_dict(spell_data), from, direction, source)


func _spawn_projectile_local(spell: SpellDefinition, from: Vector3, direction: Vector3, source: Node) -> void:
	var proj := SpellProjectileScene.instantiate()
	get_tree().current_scene.add_child(proj)
	proj.initialize(spell, from, direction, source)


func _apply_self_effect_for_all(spell: SpellDefinition) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_client_apply_self_effect.rpc(SpellNetworkCodecScript.to_dict(spell), _network_peer_id)
		return
	_apply_self_effect_local(spell)


@rpc("any_peer", "call_local", "reliable")
func _client_apply_self_effect(spell_data: Dictionary, source_peer_id: int) -> void:
	var player := _find_network_player(source_peer_id)
	if player != self:
		return
	_apply_self_effect_local(SpellNetworkCodecScript.from_dict(spell_data))


func _apply_self_effect_local(spell: SpellDefinition) -> void:
	_heal(spell.calculate_healing(false))
	_spawn_spell_impact(spell, global_position + Vector3.UP * 0.7, Vector3.UP, false)


func _find_network_player(peer_id: int) -> Node:
	var root := get_parent()
	if root == null:
		return self
	var player := root.get_node_or_null("Player_%d" % peer_id)
	return player if player != null else self


func _is_network_client() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.is_server()



func _apply_spell_hit_to_collider(collider: Object, spell: SpellDefinition, hit_position: Vector3, hit_normal: Vector3, is_beam_tick: bool) -> bool:
	var damageable := _find_damageable_node(collider)
	if damageable == null:
		return false
	damageable.apply_spell_hit(spell, hit_position, hit_normal, is_beam_tick)
	return true


func _find_damageable_node(value: Object) -> Node:
	var node := value as Node
	while node != null:
		if node.has_method("apply_spell_hit"):
			return node
		node = node.get_parent()
	return null


func _start_charged_sphere(spell: SpellDefinition) -> void:
	if _charging_sphere_spell != null:
		return

	_charging_sphere_spell = spell
	_charging_sphere_time = 0.0
	_charging_sphere_paid_size = spell.spell_size

	var col: Color = _get_spell_color(spell)
	_charging_sphere_material = StandardMaterial3D.new()
	_charging_sphere_material.albedo_color = col
	_charging_sphere_material.emission_enabled = true
	_charging_sphere_material.emission = col
	_charging_sphere_material.emission_energy_multiplier = 1.5 + spell.intensity * 0.25

	_charging_sphere_visual = MeshInstance3D.new()
	_charging_sphere_visual.material_override = _charging_sphere_material
	get_tree().current_scene.add_child(_charging_sphere_visual)

	_charging_sphere_light = OmniLight3D.new()
	_charging_sphere_light.light_color = col
	get_tree().current_scene.add_child(_charging_sphere_light)
	_update_charged_sphere(0.0)


func _release_charged_sphere() -> void:
	if _charging_sphere_spell == null:
		return

	var charged_spell := _create_charged_sphere_spell()
	var charged_mana_cost := _charging_sphere_spell.calculate_charged_mana_cost(_charging_sphere_paid_size)
	_cancel_charged_sphere()
	_cast_timer = CAST_COOLDOWN
	if charged_spell.is_healing_spell():
		_cast_self_effect_spell(charged_spell, charged_mana_cost)
		return

	_cast_projectile_spell(charged_spell, _get_cast_origin(), _get_aim_direction())


func _cancel_charged_sphere() -> void:
	if _charging_sphere_visual != null:
		_charging_sphere_visual.queue_free()
	if _charging_sphere_light != null:
		_charging_sphere_light.queue_free()
	_charging_sphere_spell = null
	_charging_sphere_time = 0.0
	_charging_sphere_paid_size = 0
	_charging_sphere_visual = null
	_charging_sphere_light = null
	_charging_sphere_material = null


func _update_charged_sphere(delta: float) -> void:
	if _charging_sphere_spell == null or _charging_sphere_visual == null:
		return

	_charging_sphere_time = minf(SPHERE_MAX_CHARGE_TIME, _charging_sphere_time + delta)
	_try_buy_charged_sphere_growth()
	var charged_size := _get_charged_sphere_size()
	var radius: float = 0.12 + (charged_size - 1) * 0.04
	var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.014) * 0.06

	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	_charging_sphere_visual.mesh = mesh
	_charging_sphere_visual.global_position = _get_cast_origin()
	_charging_sphere_visual.scale = Vector3.ONE * pulse

	_charging_sphere_light.global_position = _get_cast_origin()
	_charging_sphere_light.light_energy = 0.8 + _charging_sphere_spell.intensity * 0.35 + _get_charge_progress() * 1.4
	_charging_sphere_light.omni_range = 2.0 + charged_size * 0.35

	if _charging_sphere_material != null:
		_charging_sphere_material.emission_energy_multiplier = 1.5 + _charging_sphere_spell.intensity * 0.25 + _get_charge_progress() * 1.2


func _create_charged_sphere_spell() -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = _charging_sphere_spell.spell_name
	spell.base_element = _charging_sphere_spell.base_element
	spell.base_weights = _charging_sphere_spell.get_base_weights().duplicate()
	spell.shape = _charging_sphere_spell.shape
	spell.intensity = _charging_sphere_spell.intensity
	spell.spell_size = _get_charged_sphere_size()
	spell.spell_range = _charging_sphere_spell.spell_range
	spell.spell_speed = _charging_sphere_spell.spell_speed
	spell.has_charging = _charging_sphere_spell.has_charging
	spell.burns = _charging_sphere_spell.burns
	spell.cools = _charging_sphere_spell.cools
	spell.pushes = _charging_sphere_spell.pushes
	spell.blows = _charging_sphere_spell.blows
	spell.heals = _charging_sphere_spell.heals
	spell.has_density = _charging_sphere_spell.has_density
	spell.density = _charging_sphere_spell.density
	spell.has_illusion = _charging_sphere_spell.has_illusion
	spell.has_pull = _charging_sphere_spell.has_pull
	spell.pull_strength = _charging_sphere_spell.pull_strength
	return spell


func _get_charged_sphere_size() -> int:
	if _charging_sphere_paid_size > 0:
		return _charging_sphere_paid_size
	return _get_desired_charged_sphere_size()


func _get_desired_charged_sphere_size() -> int:
	return _charging_sphere_spell.spell_size + int(round(_get_charge_progress() * SPHERE_MAX_CHARGE_SIZE_BONUS))


func _get_charge_progress() -> float:
	if _charging_sphere_spell == null:
		return 0.0
	return clampf(_charging_sphere_time / SPHERE_MAX_CHARGE_TIME, 0.0, 1.0)


func _try_buy_charged_sphere_growth() -> void:
	if _charging_sphere_spell == null:
		return
	var desired_size := _get_desired_charged_sphere_size()
	while _charging_sphere_paid_size < desired_size:
		var next_size := _charging_sphere_paid_size + 1
		var current_cost := _charging_sphere_spell.calculate_charged_mana_cost(_charging_sphere_paid_size)
		var next_cost := _charging_sphere_spell.calculate_charged_mana_cost(next_size)
		if not _spend_mana(next_cost - current_cost):
			return
		_charging_sphere_paid_size = next_size


func _spend_mana(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if _mana + 0.001 < amount:
		return false
	_mana = maxf(0.0, _mana - amount)
	_update_mana_hud()
	return true


func _restore_mana(amount: float) -> void:
	if amount <= 0.0:
		return
	_mana = minf(MAX_MANA, _mana + amount)
	_update_mana_hud()


func _update_mana_hud() -> void:
	if _mana_bar != null:
		_mana_bar.value = _mana
	if _mana_label != null:
		_mana_label.text = "Mana  %d / %d" % [int(round(_mana)), int(MAX_MANA)]


func apply_spell_hit(spell: SpellDefinition, _hit_position: Vector3, _hit_normal: Vector3, is_beam_tick: bool = false) -> void:
	if spell == null or _is_dead:
		return
	if spell.is_blind_spell():
		apply_blind(spell.calculate_blind_duration(is_beam_tick))
	_apply_pushback(spell, _hit_position, _hit_normal, is_beam_tick)
	_apply_gravity_pull(_hit_position, spell, DIRECT_GRAVITY_RADIUS, is_beam_tick)
	var healing := spell.calculate_healing(is_beam_tick)
	if healing > 0:
		_heal(healing)
	else:
		_take_damage(spell.calculate_damage(is_beam_tick))
	_broadcast_combat_state()


func apply_spell_recoil(spell: SpellDefinition, hit_position: Vector3, hit_normal: Vector3, is_beam_tick: bool = false) -> void:
	if spell == null or _is_dead:
		return
	_apply_push_recoil(spell, hit_position, hit_normal, is_beam_tick)
	_broadcast_combat_state()


func apply_blind(duration: float) -> void:
	if duration <= 0.0 or _is_dead:
		return
	_blind_timer = maxf(_blind_timer, duration)
	_blind_duration = maxf(_blind_duration, duration)
	_update_blind_overlay()
	_broadcast_combat_state()


func _take_damage(amount: int) -> void:
	if amount <= 0:
		return
	_health = maxi(0, _health - amount)
	_update_health_hud()
	if _health <= 0:
		_die()


func _heal(amount: int) -> void:
	if amount <= 0:
		return
	_health = mini(MAX_HEALTH, _health + amount)
	_update_health_hud()


func _apply_fall_damage(fall_distance: float) -> bool:
	if _is_dead or fall_distance <= FALL_DAMAGE_SAFE_HEIGHT:
		return false
	var damage := int(round((fall_distance - FALL_DAMAGE_SAFE_HEIGHT) * FALL_DAMAGE_PER_METER))
	if damage <= 0:
		return false
	_take_damage(damage)
	return true


func _apply_pushback(spell: SpellDefinition, hit_position: Vector3, hit_normal: Vector3, is_beam_tick: bool) -> void:
	if not spell.get_base_elements().has("Water"):
		return
	var minimum_push := PLAYER_WATER_TEST_PUSH * (0.45 if is_beam_tick else 1.0)
	var force := maxf(minimum_push, spell.calculate_push_force(is_beam_tick))
	if force <= 0.0:
		return
	var push_dir := global_position - hit_position
	push_dir.y = 0.0
	if push_dir.length_squared() < 0.01:
		push_dir = -hit_normal
	push_dir.y = 0.25
	_external_velocity += push_dir.normalized() * force


func _apply_push_recoil(spell: SpellDefinition, hit_position: Vector3, hit_normal: Vector3, is_beam_tick: bool) -> void:
	var force := spell.calculate_push_force(is_beam_tick) * PUSH_RECOIL_SCALE
	if force <= 0.0:
		return
	var recoil_dir := global_position - hit_position
	recoil_dir.y = 0.0
	if recoil_dir.length_squared() < 0.01:
		recoil_dir = hit_normal
	recoil_dir.y = 0.1
	_external_velocity += recoil_dir.normalized() * force


func apply_gravity_pull(center: Vector3, spell: SpellDefinition, radius: float, is_beam_tick: bool = false) -> void:
	if spell == null or _is_dead:
		return
	_apply_gravity_pull(center, spell, radius, is_beam_tick)
	_broadcast_combat_state()


func _apply_gravity_pull(center: Vector3, spell: SpellDefinition, radius: float, is_beam_tick: bool) -> void:
	var pull_dir := center - global_position
	pull_dir.y = 0.0
	var distance := pull_dir.length()
	if distance < 0.05:
		return
	var force := spell.calculate_gravity_force(distance, radius, is_beam_tick)
	if force <= 0.0:
		return
	_external_velocity += pull_dir.normalized() * force


func _update_health_hud() -> void:
	if _health_bar != null:
		_health_bar.value = _health
	if _health_label != null:
		_health_label.text = "Health  %d / %d" % [_health, MAX_HEALTH]


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_respawn_timer = RESPAWN_DELAY
	_cancel_charged_sphere()
	_stop_beam()
	velocity = Vector3.ZERO
	_external_velocity = Vector3.ZERO
	_blind_timer = 0.0
	_blind_duration = 0.0
	_update_blind_overlay()
	if _death_label != null:
		_death_label.visible = true
		_death_label.text = "Defeated - respawning..."


func _respawn() -> void:
	_is_dead = false
	_kill_zone_respawn_timer = -1.0
	_health = MAX_HEALTH
	_mana = MAX_MANA
	global_position = _respawn_position
	velocity = Vector3.ZERO
	_external_velocity = Vector3.ZERO
	_was_on_floor_last_frame = true
	_fall_peak_y = global_position.y
	_server_was_falling = false
	_server_fall_peak_y = global_position.y
	_server_previous_pos = global_position
	_server_previous_velocity = Vector3.ZERO
	_server_has_previous_motion = false
	_jump_was_pressed_last_frame = false
	_server_state_lock_timer = 0.35
	_blind_timer = 0.0
	_blind_duration = 0.0
	_update_blind_overlay()
	_update_health_hud()
	_update_mana_hud()
	if _death_label != null:
		_death_label.visible = false
	_broadcast_combat_state()
	_force_network_transform_sync()


func _physics_process(delta: float) -> void:
	var was_on_floor_at_start := is_on_floor()
	if _server_state_lock_timer > 0.0:
		_server_state_lock_timer = maxf(0.0, _server_state_lock_timer - delta)
	if not _is_local_player:
		if multiplayer.multiplayer_peer != null and multiplayer.is_server():
			if _is_dead:
				_tick_server_respawn(delta)
			else:
				_restore_mana(MANA_REGEN_PER_SECOND * delta)
		return
	if _cast_timer > 0.0:
		_cast_timer -= delta
	if _beam_impact_timer > 0.0:
		_beam_impact_timer -= delta
	if not _is_dead and global_position.y < KILL_ZONE_Y:
		_kill_zone_respawn_timer = RESPAWN_DELAY
		_die()
		if multiplayer.multiplayer_peer != null and multiplayer.is_server():
			_broadcast_combat_state()
	if _kill_zone_respawn_timer > 0.0:
		_kill_zone_respawn_timer -= delta
		if _death_label != null:
			_death_label.text = "Defeated - respawning in %.1f" % maxf(_kill_zone_respawn_timer, 0.0)
		if _kill_zone_respawn_timer <= 0.0:
			_kill_zone_respawn_timer = -1.0
			_respawn()
		return
	if _is_dead:
		_tick_server_respawn(delta)
		return
	if _active_beam == null and _charging_sphere_spell == null:
		_restore_mana(MANA_REGEN_PER_SECOND * delta)
	_external_velocity = _external_velocity.move_toward(Vector3.ZERO, 12.0 * delta)
	if _blind_timer > 0.0:
		_blind_timer = maxf(0.0, _blind_timer - delta)
		_update_blind_overlay()

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_cancel_charged_sphere()
		_stop_beam()
		_jump_was_pressed_last_frame = Input.is_key_pressed(KEY_SPACE)
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		var pre_slide_vy := velocity.y
		var pre_slide_y := global_position.y
		move_and_slide()
		if pre_slide_vy < 0.0:
			if velocity.y > 0.0 or (pre_slide_y - global_position.y) < absf(pre_slide_vy * delta) * 0.5:
				velocity.y = 0.0
		_update_local_fall_damage_after_move(was_on_floor_at_start)
		_sync_network_state(delta)
		return

	if _active_beam != null:
		if not _spend_mana(_active_beam_spell.calculate_beam_mana_per_second() * delta):
			_stop_beam()
		else:
			_update_beam()
	if _charging_sphere_spell != null:
		_restore_mana(MANA_REGEN_PER_SECOND * delta * 0.25)
		_update_charged_sphere(delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var jump_pressed := Input.is_key_pressed(KEY_SPACE)
	if jump_pressed and not _jump_was_pressed_last_frame and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_jump_was_pressed_last_frame = jump_pressed

	var move_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): move_dir.y -= 1
	if Input.is_key_pressed(KEY_S): move_dir.y += 1
	if Input.is_key_pressed(KEY_A): move_dir.x -= 1
	if Input.is_key_pressed(KEY_D): move_dir.x += 1

	var direction := (transform.basis * Vector3(move_dir.x, 0, move_dir.y)).normalized()
	if direction.length_squared() > 0.001:
		velocity.x = direction.x * SPEED + _external_velocity.x
		velocity.z = direction.z * SPEED + _external_velocity.z
	else:
		velocity.x = _external_velocity.x
		velocity.z = _external_velocity.z
	if _external_velocity.y > 0.0:
		velocity.y = maxf(velocity.y, _external_velocity.y)

	var pre_slide_vy := velocity.y
	var pre_slide_y := global_position.y
	move_and_slide()
	if pre_slide_vy < 0.0:
		if velocity.y > 0.0 or (pre_slide_y - global_position.y) < absf(pre_slide_vy * delta) * 0.5:
			velocity.y = 0.0
	_update_local_fall_damage_after_move(was_on_floor_at_start)
	_record_server_position()
	_sync_network_state(delta)


func _update_local_fall_damage_after_move(was_on_floor_at_start: bool) -> void:
	var now_on_floor := is_on_floor()
	if now_on_floor:
		velocity.y = 0.0
		if not was_on_floor_at_start:
			_external_velocity.y = 0.0
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		if now_on_floor and not _was_on_floor_last_frame:
			_absorb_landing_momentum(maxf(0.0, _fall_peak_y - global_position.y))
		_was_on_floor_last_frame = now_on_floor
		_fall_peak_y = global_position.y if now_on_floor else maxf(_fall_peak_y, global_position.y)
		return
	if was_on_floor_at_start and not now_on_floor:
		_fall_peak_y = global_position.y
	elif not now_on_floor:
		_fall_peak_y = maxf(_fall_peak_y, global_position.y)
	elif not _was_on_floor_last_frame:
		var fall_distance := maxf(0.0, _fall_peak_y - global_position.y)
		_absorb_landing_momentum(fall_distance)
		if _apply_fall_damage(fall_distance) and multiplayer.multiplayer_peer != null and multiplayer.is_server():
			_broadcast_combat_state()
		_fall_peak_y = global_position.y
	elif now_on_floor:
		_fall_peak_y = global_position.y
	_was_on_floor_last_frame = now_on_floor


func _absorb_landing_momentum(fall_distance: float) -> void:
	if fall_distance < HARD_LANDING_MOMENTUM_CANCEL_HEIGHT:
		return
	velocity = Vector3.ZERO
	_external_velocity = Vector3.ZERO


func _tick_server_respawn(delta: float) -> void:
	_respawn_timer -= delta
	if _death_label != null:
		_death_label.text = "Defeated - respawning in %.1f" % maxf(_respawn_timer, 0.0)
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		_respawn_timer = maxf(_respawn_timer, 0.0)
		return
	if _respawn_timer <= 0.0:
		_respawn()


func _record_server_position() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var now := _network_time()
	_server_pos_history.append({"t": now, "pos": global_position})
	var cutoff := now - SERVER_POS_HISTORY_DURATION
	while _server_pos_history.size() > 1 and float(_server_pos_history[0]["t"]) < cutoff:
		_server_pos_history.pop_front()


# Returns the best-estimate position of this player at the given server time.
# Used by lag compensation in SpellProjectile hit detection.
func get_position_at_time(query_time: float) -> Vector3:
	if _server_pos_history.is_empty():
		return global_position
	if query_time <= float(_server_pos_history[0]["t"]):
		return _server_pos_history[0]["pos"]
	if query_time >= float(_server_pos_history[_server_pos_history.size() - 1]["t"]):
		return global_position
	for i in range(1, _server_pos_history.size()):
		var a: Dictionary = _server_pos_history[i - 1]
		var b: Dictionary = _server_pos_history[i]
		if float(a["t"]) <= query_time and float(b["t"]) >= query_time:
			var span := maxf(float(b["t"]) - float(a["t"]), 0.001)
			var t := (query_time - float(a["t"])) / span
			return (a["pos"] as Vector3).lerp(b["pos"] as Vector3, t)
	return global_position


func _sync_network_state(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_net_send_timer += delta
	if _net_send_timer < NETWORK_SEND_RATE:
		return
	_net_send_timer = 0.0
	var head_pitch := _head.rotation.x if _head != null else 0.0
	var timestamp := _network_time()
	if multiplayer.is_server():
		_client_receive_player_state.rpc(_network_peer_id, global_position, velocity, rotation.y, head_pitch, timestamp)
	else:
		_server_receive_player_state.rpc_id(1, global_position, velocity, rotation.y, head_pitch, timestamp)


func _force_client_transform_sync() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	var head_pitch := _head.rotation.x if _head != null else 0.0
	_server_receive_player_state.rpc_id(1, global_position, velocity, rotation.y, head_pitch, _network_time())


func _force_network_transform_sync() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var head_pitch := _head.rotation.x if _head != null else 0.0
	_client_receive_player_state.rpc(_network_peer_id, global_position, velocity, rotation.y, head_pitch, _network_time())


func _broadcast_combat_state() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var world := get_tree().current_scene
	if world != null and world.has_method("broadcast_player_combat_state"):
		world.broadcast_player_combat_state(
			_network_peer_id,
			_health,
			_mana,
			_is_dead,
			_respawn_timer,
			_blind_timer,
			_blind_duration,
			global_position,
			_external_velocity
		)
		return
	_client_receive_combat_state.rpc(
		_network_peer_id,
		_health,
		_mana,
		_is_dead,
	_respawn_timer,
	_blind_timer,
	_blind_duration,
	global_position,
	_external_velocity
	)


@rpc("any_peer", "reliable")
func _client_receive_combat_state(
	peer_id: int,
	health: int,
	mana: float,
	is_dead: bool,
	respawn_timer: float,
	blind_timer: float,
	blind_duration: float,
	pos: Vector3,
	external_velocity: Vector3
) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.get_remote_sender_id() != 1:
		return
	var player := _find_network_player(peer_id)
	if player == null:
		return
	player._apply_combat_state(health, mana, is_dead, respawn_timer, blind_timer, blind_duration, pos, external_velocity)


func _apply_combat_state(
	health: int,
	mana: float,
	is_dead: bool,
	respawn_timer: float,
	blind_timer: float,
	blind_duration: float,
	pos: Vector3,
	external_velocity: Vector3
) -> void:
	_health = health
	_mana = mana
	_is_dead = is_dead
	_respawn_timer = respawn_timer
	_kill_zone_respawn_timer = -1.0
	_blind_timer = blind_timer
	_blind_duration = blind_duration
	var should_snap_position := not _is_local_player or _is_dead or global_position.distance_to(pos) > 1.5
	if should_snap_position:
		global_position = pos
		_remote_snapshots.clear()
	_external_velocity = external_velocity
	if should_snap_position and not _is_dead and health == MAX_HEALTH:
		velocity = Vector3.ZERO
		if external_velocity.length_squared() <= 0.001:
			_external_velocity = Vector3.ZERO
	if _is_local_player:
		_update_health_hud()
		_update_mana_hud()
		_update_blind_overlay()
		if _death_label != null:
			_death_label.visible = _is_dead
			if _is_dead:
				_death_label.text = "Defeated - respawning in %.1f" % maxf(_respawn_timer, 0.0)


func apply_network_combat_state(
	health: int,
	mana: float,
	is_dead: bool,
	respawn_timer: float,
	blind_timer: float,
	blind_duration: float,
	pos: Vector3,
	external_velocity: Vector3
) -> void:
	_apply_combat_state(health, mana, is_dead, respawn_timer, blind_timer, blind_duration, pos, external_velocity)


@rpc("any_peer", "unreliable")
func _server_receive_player_state(pos: Vector3, net_velocity: Vector3, yaw: float, head_pitch: float, _timestamp: float) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _network_peer_id:
		return
	if _server_state_lock_timer > 0.0:
		_client_receive_player_state.rpc(_network_peer_id, global_position, velocity, rotation.y, _head.rotation.x if _head != null else 0.0, _network_time())
		return
	_update_server_fall_damage_from_motion(pos, net_velocity)
	velocity = net_velocity
	add_remote_snapshot(pos, net_velocity, yaw, head_pitch, _network_time())
	_client_receive_player_state.rpc(_network_peer_id, pos, net_velocity, yaw, head_pitch, _network_time())


func _update_server_fall_damage_from_motion(pos: Vector3, net_velocity: Vector3) -> void:
	if _is_dead:
		_server_has_previous_motion = true
		_server_previous_pos = pos
		_server_previous_velocity = net_velocity
		return
	if not _server_has_previous_motion:
		_server_has_previous_motion = true
		_server_previous_pos = pos
		_server_previous_velocity = net_velocity
		_server_fall_peak_y = pos.y
		return

	var previous_velocity := _server_previous_velocity
	if net_velocity.y > FALL_LANDING_VELOCITY_EPSILON:
		_server_fall_peak_y = maxf(_server_fall_peak_y, pos.y)
		_server_was_falling = false
	elif net_velocity.y < -FALL_LANDING_VELOCITY_EPSILON:
		if not _server_was_falling:
			_server_fall_peak_y = maxf(_server_previous_pos.y, pos.y)
		else:
			_server_fall_peak_y = maxf(_server_fall_peak_y, pos.y)
		_server_was_falling = true
	elif _server_was_falling and previous_velocity.y < -FALL_LANDING_VELOCITY_EPSILON:
		var fall_distance := maxf(0.0, _server_fall_peak_y - pos.y)
		if _apply_fall_damage(fall_distance):
			_broadcast_combat_state()
		_server_was_falling = false
		_server_fall_peak_y = pos.y
	else:
		_server_fall_peak_y = maxf(_server_fall_peak_y, pos.y)

	_server_previous_pos = pos
	_server_previous_velocity = net_velocity


@rpc("any_peer", "unreliable")
func _client_receive_player_state(peer_id: int, pos: Vector3, net_velocity: Vector3, yaw: float, head_pitch: float, timestamp: float) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var player := _find_network_player(peer_id)
	if player == null:
		return
	if player.has_method("add_remote_snapshot"):
		player.add_remote_snapshot(pos, net_velocity, yaw, head_pitch, timestamp)


func add_remote_snapshot(pos: Vector3, net_velocity: Vector3, yaw: float, head_pitch: float, timestamp: float) -> void:
	var local_time := _network_time()
	var measured_offset := local_time - timestamp
	if not _has_remote_clock_offset:
		_remote_clock_offset = measured_offset
		_has_remote_clock_offset = true
	else:
		_remote_clock_samples += 1
		# Fast convergence for first 30 samples, then settle to slow drift correction.
		var rate := lerpf(0.15, 0.02, clampf(_remote_clock_samples / 30.0, 0.0, 1.0))
		_remote_clock_offset = lerpf(_remote_clock_offset, measured_offset, rate)
	var snapshot := {
		"time": timestamp + _remote_clock_offset,
		"sender_time": timestamp,
		"pos": pos,
		"velocity": net_velocity,
		"yaw": yaw,
		"head_pitch": head_pitch,
	}
	_remote_snapshots.append(snapshot)
	while _remote_snapshots.size() > REMOTE_SNAPSHOT_LIMIT:
		_remote_snapshots.pop_front()
	if not _is_local_player and global_position.distance_to(pos) > REMOTE_SNAP_DISTANCE:
		_apply_remote_snapshot(snapshot)


func _hermite_pos(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, t: float, span: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return (2*t3 - 3*t2 + 1) * p0 + (t3 - 2*t2 + t) * span * v0 \
		 + (-2*t3 + 3*t2) * p1 + (t3 - t2) * span * v1


func _update_remote_visual_transform(delta: float) -> void:
	if _remote_snapshots.is_empty():
		return
	var render_time := _network_time() - REMOTE_INTERPOLATION_DELAY
	if _remote_snapshots.size() == 1:
		_apply_remote_snapshot(_remote_snapshots[0])
		return
	for i in range(1, _remote_snapshots.size()):
		var older: Dictionary = _remote_snapshots[i - 1]
		var newer: Dictionary = _remote_snapshots[i]
		if float(older["time"]) <= render_time and float(newer["time"]) >= render_time:
			var span: float = maxf(float(newer["time"]) - float(older["time"]), 0.001)
			var t: float = clampf((render_time - float(older["time"])) / span, 0.0, 1.0)
			global_position = _hermite_pos(
				older["pos"], older["velocity"], newer["pos"], newer["velocity"], t, span)
			rotation.y = lerp_angle(float(older["yaw"]), float(newer["yaw"]), t)
			if _head != null:
				_head.rotation.x = lerp_angle(float(older["head_pitch"]), float(newer["head_pitch"]), t)
			return
	var latest: Dictionary = _remote_snapshots[_remote_snapshots.size() - 1]
	var elapsed: float = clampf(render_time - float(latest["time"]), 0.0, REMOTE_EXTRAPOLATION_LIMIT)
	global_position = latest["pos"] as Vector3 + (latest["velocity"] as Vector3) * elapsed
	rotation.y = float(latest["yaw"])
	if _head != null:
		_head.rotation.x = float(latest["head_pitch"])


func _apply_remote_snapshot(snapshot: Dictionary) -> void:
	global_position = snapshot["pos"] as Vector3
	rotation.y = float(snapshot["yaw"])
	if _head != null:
		_head.rotation.x = float(snapshot["head_pitch"])


func _network_time() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _update_blind_overlay() -> void:
	if _blind_overlay == null:
		return
	if _blind_timer <= 0.0:
		_blind_overlay.color = Color(1.0, 0.96, 0.72, 0.0)
		return
	var strength := clampf(_blind_timer / maxf(_blind_duration, 0.1), 0.0, 1.0)
	_blind_overlay.color = Color(1.0, 0.97, 0.78, lerpf(0.18, 0.92, strength))

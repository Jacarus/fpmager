extends Control

const SPELL_CREATOR_SCENE := "res://Scenes/SpellCreation/SpellCreationUI.tscn"
const WORLD_SCENE := "res://Scenes/World/World.tscn"
const DEFAULT_PORT := 24567
const MAX_PLAYERS := 12

var _menu_stack: Array[Control] = []
var _root_box: VBoxContainer
var _status_label: Label
var _address_input: LineEdit
var _port_input: SpinBox
var _bots_check: CheckBox
var _bot_count_spin: SpinBox
var _difficulty_options: OptionButton
var _fullscreen_btn: Button


func _ready() -> void:
	if DedicatedServer.is_active():
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_ui()
	if not GameSettings.fullscreen_changed.is_connected(_on_fullscreen_changed):
		GameSettings.fullscreen_changed.connect(_on_fullscreen_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		GameSettings.toggle_fullscreen()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.1)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)

	_root_box = VBoxContainer.new()
	_root_box.add_theme_constant_override("separation", 12)
	margin.add_child(_root_box)

	var title := Label.new()
	title.text = "FP Mager"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.92, 0.84, 1.0))
	_root_box.add_child(title)

	_root_box.add_child(HSeparator.new())

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.86))
	_root_box.add_child(_status_label)

	_show_main_options()


func _clear_menu_stack() -> void:
	for child in _menu_stack:
		child.queue_free()
	_menu_stack.clear()


func _add_menu_item(node: Control) -> void:
	_menu_stack.append(node)
	_root_box.add_child(node)


func _show_main_options() -> void:
	_clear_menu_stack()
	_status_label.text = ""

	var creator_btn := _make_menu_button("Spell Creator")
	creator_btn.pressed.connect(_go_to_spell_creator)
	_add_menu_item(creator_btn)

	var play_btn := _make_menu_button("Play")
	play_btn.pressed.connect(_show_play_options)
	_add_menu_item(play_btn)

	_fullscreen_btn = _make_menu_button("")
	_update_fullscreen_button()
	_fullscreen_btn.pressed.connect(GameSettings.toggle_fullscreen)
	_add_menu_item(_fullscreen_btn)

	var exit_btn := _make_menu_button("Exit")
	exit_btn.pressed.connect(_exit_app)
	_add_menu_item(exit_btn)


func _show_play_options() -> void:
	_clear_menu_stack()
	_status_label.text = ""

	var create_btn := _make_menu_button("Create")
	create_btn.pressed.connect(_show_host_options)
	_add_menu_item(create_btn)

	var join_btn := _make_menu_button("Join")
	join_btn.pressed.connect(_show_join_options)
	_add_menu_item(join_btn)

	var back_btn := _make_menu_button("Back")
	back_btn.pressed.connect(_show_main_options)
	_add_menu_item(back_btn)


func _show_join_options() -> void:
	_clear_menu_stack()
	_status_label.text = ""

	_address_input = LineEdit.new()
	_address_input.placeholder_text = "Server address"
	_address_input.text = "127.0.0.1"
	_add_menu_item(_address_input)

	_port_input = SpinBox.new()
	_port_input.min_value = 1
	_port_input.max_value = 65535
	_port_input.value = DEFAULT_PORT
	_port_input.step = 1
	_port_input.prefix = "Port "
	_add_menu_item(_port_input)

	var join_btn := _make_menu_button("Join Server")
	join_btn.pressed.connect(_join_game)
	_add_menu_item(join_btn)

	var back_btn := _make_menu_button("Back")
	back_btn.pressed.connect(_show_play_options)
	_add_menu_item(back_btn)


func _show_host_options() -> void:
	_clear_menu_stack()
	_status_label.text = ""

	_bots_check = CheckBox.new()
	_bots_check.text = "Bots"
	_bots_check.button_pressed = GameSettings.bots_enabled
	_bots_check.toggled.connect(_on_bots_toggled)
	_add_menu_item(_bots_check)

	_bot_count_spin = SpinBox.new()
	_bot_count_spin.min_value = 1
	_bot_count_spin.max_value = 12
	_bot_count_spin.step = 1
	_bot_count_spin.value = GameSettings.bot_count
	_bot_count_spin.prefix = "Number of bots "
	_bot_count_spin.editable = _bots_check.button_pressed
	_add_menu_item(_bot_count_spin)

	_difficulty_options = OptionButton.new()
	_difficulty_options.add_item("Easy")
	_difficulty_options.add_item("Medium")
	_difficulty_options.add_item("Hard")
	var selected_index := ["Easy", "Medium", "Hard"].find(GameSettings.bot_difficulty)
	_difficulty_options.select(maxi(selected_index, 1))
	_difficulty_options.disabled = not _bots_check.button_pressed
	_add_menu_item(_difficulty_options)

	var start_btn := _make_menu_button("Start Host")
	start_btn.pressed.connect(_host_game)
	_add_menu_item(start_btn)

	var back_btn := _make_menu_button("Back")
	back_btn.pressed.connect(_show_play_options)
	_add_menu_item(back_btn)


func _on_bots_toggled(enabled: bool) -> void:
	if _bot_count_spin != null:
		_bot_count_spin.editable = enabled
		_bot_count_spin.modulate = Color.WHITE if enabled else Color(0.55, 0.55, 0.6)
	if _difficulty_options != null:
		_difficulty_options.disabled = not enabled
		_difficulty_options.modulate = Color.WHITE if enabled else Color(0.55, 0.55, 0.6)


func _make_menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size.y = 42
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	return btn


func _on_fullscreen_changed(_enabled: bool) -> void:
	_update_fullscreen_button()


func _update_fullscreen_button() -> void:
	if _fullscreen_btn == null:
		return
	_fullscreen_btn.text = "Windowed" if GameSettings.is_fullscreen() else "Fullscreen"


func _go_to_spell_creator() -> void:
	_close_network_peer()
	get_tree().call_deferred("change_scene_to_file", SPELL_CREATOR_SCENE)


func _host_game() -> void:
	_close_network_peer()
	GameSettings.bots_enabled = _bots_check == null or _bots_check.button_pressed
	GameSettings.bot_count = int(_bot_count_spin.value) if _bot_count_spin != null else 1
	GameSettings.bot_difficulty = _difficulty_options.get_item_text(_difficulty_options.selected) if _difficulty_options != null else "Medium"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	if err != OK:
		_status_label.text = "Could not host on port %d." % DEFAULT_PORT
		return
	multiplayer.multiplayer_peer = peer
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


func _join_game() -> void:
	_close_network_peer()
	var address := _address_input.text.strip_edges()
	if address.is_empty():
		_status_label.text = "Enter a server address."
		return
	var port := int(_port_input.value)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_status_label.text = "Could not connect to %s:%d." % [address, port]
		return
	multiplayer.multiplayer_peer = peer
	_status_label.text = "Connecting to %s:%d..." % [address, port]
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)


func _on_connected_to_server() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


func _on_connection_failed() -> void:
	_close_network_peer()
	_status_label.text = "Connection failed."


func _close_network_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


func _exit_app() -> void:
	_close_network_peer()
	get_tree().quit()

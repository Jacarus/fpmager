extends Node3D

const PlayerScene = preload("res://Scenes/Player/Player.tscn")
const BasicCasterScene = preload("res://Scenes/NPC/BasicCaster.tscn")
const SpellProjectileScene = preload("res://Scenes/SpellProjectile/SpellProjectile.tscn")
const SpellImpactEffectScript = preload("res://Scripts/SpellImpactEffect.gd")
const SpellCreationScene = preload("res://Scenes/SpellCreation/SpellCreationUI.tscn")
const PushTestTargetScript = preload("res://Scenes/World/PushTestTarget.gd")
const SpellNetworkCodecScript = preload("res://Scripts/SpellNetworkCodec.gd")
const PLAYER_LOADOUT_CREDIT_LIMIT := 120

var _player: Node3D
var _players_root: Node3D
var _players: Dictionary = {}
var _basic_caster: Node3D
var _basic_casters: Dictionary = {}
var _creator_layer: CanvasLayer
var _peers_in_creator: Dictionary = {}


func _ready() -> void:
	if not GameSettings.bot_settings_changed.is_connected(_on_bot_settings_changed):
		GameSettings.bot_settings_changed.connect(_on_bot_settings_changed)
	_build_environment()
	_build_level()
	_players_root = Node3D.new()
	_players_root.name = "Players"
	add_child(_players_root)
	if multiplayer.multiplayer_peer != null:
		_setup_multiplayer_world()
	else:
		_spawn_single_player()
		_spawn_configured_bots()
	_spawn_push_test_target()


func _setup_multiplayer_world() -> void:
	if multiplayer.is_server():
		if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if not _is_dedicated_server():
			_spawn_player_for_peer(1, Vector3(0, 1.0, 8))
		_spawn_configured_bots()
	else:
		_request_world_state.rpc_id(1)


func _is_dedicated_server() -> bool:
	return DedicatedServer.is_active()


func _build_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.08, 0.06, 0.14)
	sky_mat.sky_horizon_color = Color(0.28, 0.18, 0.38)
	sky_mat.ground_bottom_color = Color(0.06, 0.05, 0.08)
	sky_mat.ground_horizon_color = Color(0.18, 0.14, 0.22)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)


func _build_level() -> void:
	# Floor
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40), Color(0.18, 0.2, 0.17))

	# Outer walls
	_add_box(Vector3(19.5, 2.0, 0), Vector3(1, 5, 40), Color(0.22, 0.2, 0.26))
	_add_box(Vector3(-19.5, 2.0, 0), Vector3(1, 5, 40), Color(0.22, 0.2, 0.26))
	_add_box(Vector3(0, 2.0, -19.5), Vector3(40, 5, 1), Color(0.22, 0.2, 0.26))
	_add_box(Vector3(0, 2.0, 19.5), Vector3(40, 5, 1), Color(0.22, 0.2, 0.26))

	# Obstacles — scattered boxes and pillars
	_add_box(Vector3(5, 0.75, -6), Vector3(1.5, 1.5, 1.5), Color(0.32, 0.28, 0.36))
	_add_box(Vector3(-4, 1.5, -9), Vector3(1.2, 3.0, 1.2), Color(0.32, 0.28, 0.36))
	_add_box(Vector3(9, 0.5, 4), Vector3(3.5, 1.0, 1.2), Color(0.32, 0.28, 0.36))
	_add_box(Vector3(-8, 2.0, 6), Vector3(1.2, 4.0, 1.2), Color(0.32, 0.28, 0.36))
	_add_box(Vector3(0, 0.75, -11), Vector3(5, 1.5, 1.2), Color(0.32, 0.28, 0.36))
	_add_box(Vector3(-12, 0.5, -3), Vector3(1.2, 1.0, 4), Color(0.32, 0.28, 0.36))
	_add_box(Vector3(13, 1.0, -7), Vector3(1.2, 2.0, 1.2), Color(0.32, 0.28, 0.36))
	_add_box(Vector3(-6, 0.6, 12), Vector3(4, 1.2, 1.2), Color(0.32, 0.28, 0.36))
	_add_box(Vector3(3, 1.5, 10), Vector3(1.2, 3.0, 1.2), Color(0.32, 0.28, 0.36))


func _add_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.mesh = mesh
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)


func _spawn_single_player() -> void:
	var player := PlayerScene.instantiate()
	player.position = Vector3(0, 1.0, 8)
	_players_root.add_child(player)
	_player = player


@rpc("any_peer", "reliable")
func _request_world_state() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	for existing_peer_id in _players.keys():
		var player := _players[existing_peer_id] as Node3D
		if player != null:
			_spawn_player_for_peer.rpc_id(peer_id, int(existing_peer_id), player.global_position)
	for bot_id in _basic_casters.keys():
		var caster := _basic_casters[bot_id] as Node3D
		if caster != null:
			_spawn_basic_caster_for_all.rpc_id(
				peer_id,
				int(bot_id),
				caster.global_position,
				caster.get_spell_loadout_data() if caster.has_method("get_spell_loadout_data") else [],
				caster.get_difficulty_data() if caster.has_method("get_difficulty_data") else _get_bot_difficulty_data()
			)
	if not _players.has(peer_id):
		var spawn_position := _get_spawn_position(_players.size())
		_spawn_player_for_peer.rpc(peer_id, spawn_position)


@rpc("authority", "call_local", "reliable")
func _spawn_player_for_peer(peer_id: int, spawn_position: Vector3) -> void:
	if _players.has(peer_id):
		return
	var player := PlayerScene.instantiate()
	player.name = "Player_%d" % peer_id
	if player.has_method("setup_multiplayer"):
		player.setup_multiplayer(peer_id, peer_id == multiplayer.get_unique_id())
	player.position = spawn_position
	_players_root.add_child(player)
	_players[peer_id] = player
	if _player == null or peer_id == multiplayer.get_unique_id():
		_player = player
	_refresh_basic_caster_target()


func _on_peer_disconnected(peer_id: int) -> void:
	_despawn_player_for_peer.rpc(peer_id)


@rpc("authority", "call_local", "reliable")
func _despawn_player_for_peer(peer_id: int) -> void:
	var player := _players.get(peer_id) as Node
	if player != null:
		player.queue_free()
	_players.erase(peer_id)
	if _player == player:
		_player = null
	_refresh_basic_caster_target()


func _get_spawn_position(index: int) -> Vector3:
	var positions: Array[Vector3] = [
		Vector3(0, 1.0, 8),
		Vector3(2.5, 1.0, 8),
		Vector3(-2.5, 1.0, 8),
		Vector3(0, 1.0, 11),
	]
	return positions[index % positions.size()]


func _spawn_configured_bots() -> void:
	_reconcile_configured_bots()


func _on_bot_settings_changed() -> void:
	_reconcile_configured_bots()


func _can_manage_bots() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func _reconcile_configured_bots() -> void:
	if not _can_manage_bots():
		return
	var desired_count := GameSettings.bot_count if GameSettings.bots_enabled else 0
	for bot_id in _basic_casters.keys():
		if int(bot_id) >= desired_count:
			_despawn_basic_caster(bot_id)
	for i in range(desired_count):
		if _basic_casters.has(i):
			continue
		var pos := _get_bot_spawn_position(i)
		var loadout := _create_random_bot_loadout()
		var difficulty_data := _get_bot_difficulty_data()
		if multiplayer.multiplayer_peer != null and multiplayer.is_server():
			_spawn_basic_caster_for_all.rpc(i, pos, loadout, difficulty_data)
		else:
			_spawn_basic_caster_local(i, pos, loadout, difficulty_data)
	_update_existing_bot_difficulty()


func _despawn_basic_caster(bot_id: int) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_despawn_basic_caster_for_all.rpc(bot_id)
	else:
		_despawn_basic_caster_local(bot_id)


func _spawn_basic_caster() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	if _player == null:
		return
	_spawn_basic_caster_local(0, Vector3(0, 0.0, -12), _create_random_bot_loadout(), _get_bot_difficulty_data())


@rpc("any_peer", "call_local", "reliable")
func _spawn_basic_caster_for_all(bot_id: int, spawn_position: Vector3, loadout_data: Array, difficulty_data: Dictionary) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	_spawn_basic_caster_local(bot_id, spawn_position, loadout_data, difficulty_data)


func _spawn_basic_caster_local(bot_id: int, spawn_position: Vector3, loadout_data: Array, difficulty_data: Dictionary) -> void:
	if _basic_casters.has(bot_id):
		return
	var caster := BasicCasterScene.instantiate()
	caster.name = "BasicCaster_%d" % bot_id
	caster.position = spawn_position
	if caster.has_method("set_spell_loadout_data"):
		caster.set_spell_loadout_data(loadout_data)
	if caster.has_method("set_difficulty_data"):
		caster.set_difficulty_data(difficulty_data)
	caster.target = _player
	add_child(caster)
	_basic_casters[bot_id] = caster
	if _basic_caster == null:
		_basic_caster = caster
	_refresh_basic_caster_target()


@rpc("any_peer", "call_local", "reliable")
func _despawn_basic_caster_for_all(bot_id: int) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	_despawn_basic_caster_local(bot_id)


func _despawn_basic_caster_local(bot_id: int) -> void:
	var caster := _basic_casters.get(bot_id) as Node
	if caster == null:
		return
	if _basic_caster == caster:
		_basic_caster = null
	_basic_casters.erase(bot_id)
	caster.queue_free()
	if _basic_caster == null:
		for existing in _basic_casters.values():
			if existing is Node3D:
				_basic_caster = existing
				break
	_refresh_basic_caster_target()


func _update_existing_bot_difficulty() -> void:
	var difficulty_data := _get_bot_difficulty_data()
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_update_basic_caster_difficulty_for_all.rpc(difficulty_data)
	else:
		_update_basic_caster_difficulty_local(difficulty_data)


@rpc("any_peer", "call_local", "reliable")
func _update_basic_caster_difficulty_for_all(difficulty_data: Dictionary) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	_update_basic_caster_difficulty_local(difficulty_data)


func _update_basic_caster_difficulty_local(difficulty_data: Dictionary) -> void:
	for caster in _basic_casters.values():
		if caster != null and caster.has_method("set_difficulty_data"):
			caster.set_difficulty_data(difficulty_data)


func open_spell_creator_for_local_player() -> void:
	if _creator_layer != null:
		return
	var peer_id := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server():
			_set_peer_in_creator(peer_id, true)
		else:
			_server_set_peer_in_creator.rpc_id(1, true)
			_show_spell_creator_overlay()
	else:
		_despawn_player_for_peer(peer_id)
		_show_spell_creator_overlay()


func close_spell_creator_for_local_player() -> void:
	_close_spell_creator_overlay()
	var peer_id := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server():
			_set_peer_in_creator(peer_id, false)
		else:
			_server_set_peer_in_creator.rpc_id(1, false)
	else:
		_spawn_player_for_peer(peer_id, _get_spawn_position(_players.size()))


@rpc("any_peer", "reliable")
func _server_set_peer_in_creator(in_creator: bool) -> void:
	if not multiplayer.is_server():
		return
	_set_peer_in_creator(multiplayer.get_remote_sender_id(), in_creator)


func _set_peer_in_creator(peer_id: int, in_creator: bool) -> void:
	if in_creator:
		if _peers_in_creator.has(peer_id):
			return
		_peers_in_creator[peer_id] = true
		_despawn_player_for_peer.rpc(peer_id)
		if peer_id == multiplayer.get_unique_id():
			_show_spell_creator_overlay()
	else:
		if not _peers_in_creator.has(peer_id):
			return
		_peers_in_creator.erase(peer_id)
		_spawn_player_for_peer.rpc(peer_id, _get_spawn_position(_players.size()))


func _show_spell_creator_overlay() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_creator_layer = CanvasLayer.new()
	add_child(_creator_layer)
	var creator := SpellCreationScene.instantiate()
	if creator.has_method("set_game_return_target"):
		creator.set_game_return_target(self)
	_creator_layer.add_child(creator)


func _close_spell_creator_overlay() -> void:
	if _creator_layer != null:
		_creator_layer.queue_free()
		_creator_layer = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _refresh_basic_caster_target() -> void:
	if _basic_caster == null:
		return
	var best_player: Node3D = null
	for player in _players.values():
		if player is Node3D:
			best_player = player
			break
	for caster in _basic_casters.values():
		if caster != null:
			caster.target = best_player
	if _player == null:
		_player = best_player


func _get_bot_spawn_position(index: int) -> Vector3:
	var positions: Array[Vector3] = [
		Vector3(0, 0.0, -12),
		Vector3(4, 0.0, -12),
		Vector3(-4, 0.0, -12),
		Vector3(8, 0.0, -8),
		Vector3(-8, 0.0, -8),
		Vector3(0, 0.0, -16),
	]
	return positions[index % positions.size()]


func _create_random_bot_loadout() -> Array:
	var pool := [
		_make_bot_spell_data("Bot Fire", {"Fire": 100}, "Sphere", 2, 2, 7, 4, {"burns": true}),
		_make_bot_spell_data("Bot Water Push", {"Water": 100}, "Sphere", 2, 2, 7, 4, {"pushes": true}),
		_make_bot_spell_data("Bot Light Flash", {"Light": 100}, "Sphere", 2, 3, 7, 5, {"has_illusion": true}),
		_make_bot_spell_data("Bot Singularity", {"Void": 50, "Earth": 50}, "Sphere", 2, 3, 7, 3, {"has_pull": true, "pull_strength": 3}),
		_make_bot_spell_data("Bot Frost", {"Water": 50, "Air": 50}, "Sphere", 2, 2, 7, 4, {"cools": true}),
		_make_bot_spell_data("Bot Wildfire", {"Fire": 50, "Air": 50}, "Sphere", 2, 2, 7, 5, {"burns": true}),
		_make_bot_spell_data("Bot Mud", {"Water": 50, "Earth": 50}, "Sphere", 2, 3, 6, 3, {"pushes": true}),
		_make_bot_spell_data("Bot Crystal", {"Earth": 50, "Light": 50}, "Sphere", 2, 2, 8, 4, {"has_density": true, "density": 3}),
	]
	pool.shuffle()
	var budget := _get_bot_spell_budget()
	var chosen: Array = []
	var total_cost := 0
	for data in pool:
		var cost := _get_spell_data_cost(data)
		if total_cost + cost > budget:
			continue
		chosen.append(data)
		total_cost += cost
		if chosen.size() >= 3:
			return chosen
	if chosen.is_empty() and not pool.is_empty():
		chosen.append(pool[0])
	return chosen


func _get_bot_spell_budget() -> int:
	match GameSettings.bot_difficulty:
		"Easy":
			return int(floor(PLAYER_LOADOUT_CREDIT_LIMIT * 0.5))
		"Hard":
			return int(ceil(PLAYER_LOADOUT_CREDIT_LIMIT * 1.5))
		_:
			return PLAYER_LOADOUT_CREDIT_LIMIT


func _get_bot_difficulty_data() -> Dictionary:
	match GameSettings.bot_difficulty:
		"Easy":
			return {"difficulty": "Easy", "cast_cooldown": 5.0, "spell_budget": _get_bot_spell_budget(), "cast_when_ready": false}
		"Hard":
			return {"difficulty": "Hard", "cast_cooldown": 0.0, "spell_budget": _get_bot_spell_budget(), "cast_when_ready": true}
		_:
			return {"difficulty": "Medium", "cast_cooldown": 3.0, "spell_budget": _get_bot_spell_budget(), "cast_when_ready": false}


func _get_spell_data_cost(data: Dictionary) -> int:
	return SpellNetworkCodecScript.from_dict(data).calculate_credits()


func _make_bot_spell_data(spell_name: String, weights: Dictionary, shape: String, intensity: int, size: int, spell_range: int, speed: int, flags: Dictionary = {}) -> Dictionary:
	var data := {
		"spell_name": spell_name,
		"base_element": str(weights.keys()[0]),
		"base_weights": weights,
		"shape": shape,
		"intensity": intensity,
		"spell_size": size,
		"spell_range": spell_range,
		"spell_speed": speed,
		"has_charging": false,
		"burns": false,
		"cools": false,
		"pushes": false,
		"blows": false,
		"heals": false,
		"has_density": false,
		"density": 1,
		"has_illusion": false,
		"has_pull": false,
		"pull_strength": 1,
	}
	for key in flags.keys():
		data[key] = flags[key]
	return data


func broadcast_player_combat_state(
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
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_client_receive_player_combat_state.rpc(
		peer_id,
		health,
		mana,
		is_dead,
		respawn_timer,
		blind_timer,
		blind_duration,
		pos,
		external_velocity
	)


@rpc("any_peer", "call_local", "reliable")
func _client_receive_player_combat_state(
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
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	var player := _players.get(peer_id) as Node
	if player != null and player.has_method("apply_network_combat_state"):
		player.apply_network_combat_state(health, mana, is_dead, respawn_timer, blind_timer, blind_duration, pos, external_velocity)


func spawn_network_projectile(spell: SpellDefinition, from: Vector3, direction: Vector3, source: Node, cast_server_time: float = -1.0) -> void:
	if multiplayer.multiplayer_peer == null:
		_spawn_projectile_local(spell, from, direction, source)
		return
	if not multiplayer.is_server():
		return
	var t := cast_server_time if cast_server_time >= 0.0 else Time.get_ticks_msec() / 1000.0
	_spawn_projectile_local(spell, from, direction, source, t)
	var source_peer_id := 0
	if source != null and source.has_method("get_network_peer_id"):
		source_peer_id = int(source.get_network_peer_id())
	_client_spawn_network_projectile.rpc(SpellNetworkCodecScript.to_dict(spell), from, direction, source_peer_id)


@rpc("any_peer", "reliable")
func _client_spawn_network_projectile(spell_data: Dictionary, from: Vector3, direction: Vector3, source_peer_id: int) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	if multiplayer.is_server():
		return
	if source_peer_id == multiplayer.get_unique_id():
		return
	var source := _players.get(source_peer_id) as Node
	_spawn_projectile_local(SpellNetworkCodecScript.from_dict(spell_data), from, direction, source)


func _spawn_projectile_local(spell: SpellDefinition, from: Vector3, direction: Vector3, source: Node, cast_server_time: float = -1.0) -> void:
	var projectile := SpellProjectileScene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.initialize(spell, from, direction, source, cast_server_time)


func broadcast_spell_impact(spell: SpellDefinition, position: Vector3, normal: Vector3) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_client_spawn_spell_impact.rpc(SpellNetworkCodecScript.to_dict(spell), position, normal)


@rpc("any_peer", "reliable")
func _client_spawn_spell_impact(spell_data: Dictionary, position: Vector3, normal: Vector3) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	if multiplayer.is_server():
		return
	var effect := SpellImpactEffectScript.new()
	get_tree().current_scene.add_child(effect)
	effect.initialize(SpellNetworkCodecScript.from_dict(spell_data), position, normal, null)
	effect.set_visual_only(true)



func _spawn_push_test_target() -> void:
	var target := RigidBody3D.new()
	target.set_script(PushTestTargetScript)
	target.position = Vector3(3.0, 0.8, -9.5)
	add_child(target)

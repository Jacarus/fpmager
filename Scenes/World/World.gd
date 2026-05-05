extends Node3D

const PlayerScene = preload("res://Scenes/Player/Player.tscn")
const BasicCasterScene = preload("res://Scenes/NPC/BasicCaster.tscn")
const BossCasterScene = preload("res://Scenes/NPC/BossCaster.tscn")
const SpellProjectileScene = preload("res://Scenes/SpellProjectile/SpellProjectile.tscn")
const SpellImpactEffectScript = preload("res://Scripts/SpellImpactEffect.gd")
const SpellCreationScene = preload("res://Scenes/SpellCreation/SpellCreationUI.tscn")
const PushTestTargetScript = preload("res://Scenes/World/PushTestTarget.gd")
const SpellNetworkCodecScript = preload("res://Scripts/SpellNetworkCodec.gd")
const PLAYER_LOADOUT_CREDIT_LIMIT := 120
const BEAM_COLLISION_RADIUS_BASE := 0.08
const BEAM_COLLISION_RADIUS_SIZE_SCALE := 0.045
const BEAM_COLLISION_IMPACT_INTERVAL := 0.35
const BEAM_CLASH_MAX_PUSH_FRACTION := 0.72
const BEAM_CLASH_SMOOTHING := 0.28
const BASE_PROPERTIES := {
	"Fire": {"temperature": 10, "density": 2, "opposing": ["Water", "Void"]},
	"Water": {"temperature": 2, "density": 6, "opposing": ["Fire", "Void"]},
	"Air": {"temperature": 4, "density": 1, "opposing": ["Earth"]},
	"Spirit": {"temperature": 5, "density": 0, "opposing": ["Void"]},
	"Earth": {"temperature": 3, "density": 10, "opposing": ["Air"]},
	"Light": {"temperature": 6, "density": 0, "opposing": ["Void"]},
	"Void": {"temperature": 0, "density": -10, "opposing": ["Light", "Spirit", "Fire", "Water"]},
}
const PLAYER_COLORS: Array[Color] = [
	Color(0.2, 0.48, 1.0),
	Color(1.0, 0.28, 0.22),
	Color(0.18, 0.85, 0.42),
	Color(1.0, 0.78, 0.18),
]

var _player: Node3D
var _players_root: Node3D
var _players: Dictionary = {}
var _player_color_indices: Dictionary = {}
var _basic_caster: Node3D
var _basic_casters: Dictionary = {}
var _bosses: Dictionary = {}
var _boss_hud_layer: CanvasLayer
var _boss_hud_panel: VBoxContainer
var _boss_hud_label: Label
var _boss_hud_bar: ProgressBar
var _boss_hud_parts_label: Label
var _creator_layer: CanvasLayer
var _peers_in_creator: Dictionary = {}
var _active_spell_impacts: Array[Dictionary] = []
var _next_spell_impact_id: int = 1
var _predicted_projectile_echoes: Array[Dictionary] = []
var _active_beam_segments: Dictionary = {}
var _beam_collision_impacts: Dictionary = {}
var _beam_clash_points: Dictionary = {}
var _world_state_retry_timer: float = 0.0
var _world_state_request_cooldown: float = 0.0


func _ready() -> void:
	if not GameSettings.bot_settings_changed.is_connected(_on_bot_settings_changed):
		GameSettings.bot_settings_changed.connect(_on_bot_settings_changed)
	if not GameSettings.boss_settings_changed.is_connected(_on_boss_settings_changed):
		GameSettings.boss_settings_changed.connect(_on_boss_settings_changed)
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
		_spawn_configured_boss()
	_spawn_push_test_target()
	if _is_dedicated_server():
		DedicatedServer.notify_world_ready()


func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_prune_expired_spell_impacts()
	else:
		_prune_predicted_projectile_echoes()
		if _world_state_request_cooldown > 0.0:
			_world_state_request_cooldown -= _delta
		_retry_world_state_request(_delta)
	_prune_invalid_bosses()
	_prune_stale_beam_segments()


func _setup_multiplayer_world() -> void:
	if multiplayer.is_server():
		if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if not _is_dedicated_server():
			_spawn_player_for_peer(1, Vector3(0, 1.0, 8), _assign_player_color(1))
		_spawn_configured_bots()
		_spawn_configured_boss()
	else:
		_request_world_state_from_server()


func _is_dedicated_server() -> bool:
	return DedicatedServer.is_active()


func _request_world_state_from_server() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	if _world_state_request_cooldown > 0.0:
		return
	_world_state_request_cooldown = 1.0
	_world_state_retry_timer = 1.0
	_request_world_state.rpc_id(1, multiplayer.get_unique_id())


func _retry_world_state_request(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	if _player != null:
		return
	if _creator_layer != null:
		return
	_world_state_retry_timer -= delta
	if _world_state_retry_timer > 0.0:
		return
	_request_world_state_from_server()


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
	if player.has_method("set_player_color"):
		player.set_player_color(PLAYER_COLORS[0])
	_players_root.add_child(player)
	_player = player


@rpc("any_peer", "reliable")
func _request_world_state(requested_peer_id: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0 and requested_peer_id > 1:
		peer_id = requested_peer_id
	if peer_id <= 1:
		print("[World] Ignoring world-state request with invalid peer id: ", peer_id)
		return
	print("[World] World-state request from peer ", peer_id)
	if not _players.has(peer_id) and not _peers_in_creator.has(peer_id):
		var spawn_position := _get_spawn_position(_players.size())
		var player_color := _assign_player_color(peer_id)
		_spawn_player_for_peer(peer_id, spawn_position, player_color)
		_spawn_player_for_peer.rpc_id(peer_id, peer_id, spawn_position, player_color)
		for connected_peer_id in multiplayer.get_peers():
			if int(connected_peer_id) != peer_id:
				_spawn_player_for_peer.rpc_id(int(connected_peer_id), peer_id, spawn_position, player_color)
	for existing_peer_id in _players.keys():
		var player := _players[existing_peer_id] as Node3D
		if player != null:
			_spawn_player_for_peer.rpc_id(peer_id, int(existing_peer_id), player.global_position, _get_player_color(int(existing_peer_id)))
	print("[World] Sending %d bots to peer %d" % [_basic_casters.size(), peer_id])
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
	for boss_id in _bosses.keys():
		var boss := _bosses[boss_id] as Node3D
		if boss != null:
			var settings: Dictionary = boss.get_settings_data() if boss.has_method("get_settings_data") else {}
			_spawn_boss_for_all.rpc_id(peer_id, int(boss_id), boss.global_position, settings)
			if boss.has_method("send_full_state_to_peer"):
				boss.send_full_state_to_peer(peer_id)
	_send_active_spell_impacts(peer_id)


@rpc("authority", "reliable")
func _spawn_player_for_peer(peer_id: int, spawn_position: Vector3, player_color: Color = Color(0.18, 0.14, 0.24)) -> void:
	if _players.has(peer_id):
		return
	print("[World] Spawning player ", peer_id, " local_unique=", multiplayer.get_unique_id())
	var player := PlayerScene.instantiate()
	player.name = "Player_%d" % peer_id
	if player.has_method("setup_multiplayer"):
		player.setup_multiplayer(peer_id, peer_id == multiplayer.get_unique_id())
	if player.has_method("set_player_color"):
		player.set_player_color(player_color)
	player.position = spawn_position
	_players_root.add_child(player)
	_players[peer_id] = player
	if _player == null or peer_id == multiplayer.get_unique_id():
		_player = player
	_refresh_basic_caster_target()
	_refresh_boss_targets()


func _on_peer_disconnected(peer_id: int) -> void:
	_player_color_indices.erase(peer_id)
	_peers_in_creator.erase(peer_id)
	_despawn_player_for_peer.rpc(peer_id)


@rpc("authority", "call_local", "reliable")
func _despawn_player_for_peer(peer_id: int) -> void:
	var player := _players.get(peer_id) as Node
	if player != null:
		player.queue_free()
		unregister_beam_segment("player:%d" % peer_id)
		_players.erase(peer_id)
		if _player == player:
			_player = null
		_refresh_basic_caster_target()
		_refresh_boss_targets()


func _assign_player_color(peer_id: int) -> Color:
	if _player_color_indices.has(peer_id):
		return PLAYER_COLORS[int(_player_color_indices[peer_id])]
	var used := {}
	for value in _player_color_indices.values():
		used[int(value)] = true
	for i in range(PLAYER_COLORS.size()):
		if not used.has(i):
			_player_color_indices[peer_id] = i
			return PLAYER_COLORS[i]
	var fallback_index: int = abs(peer_id) % PLAYER_COLORS.size()
	_player_color_indices[peer_id] = fallback_index
	return PLAYER_COLORS[fallback_index]


func _get_player_color(peer_id: int) -> Color:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		return _assign_player_color(peer_id)
	var index := int(_player_color_indices.get(peer_id, 0))
	return PLAYER_COLORS[clampi(index, 0, PLAYER_COLORS.size() - 1)]


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


func force_reconcile_bots() -> void:
	_reconcile_configured_bots()


func _spawn_configured_boss() -> void:
	_reconcile_configured_boss()


func _on_boss_settings_changed() -> void:
	_reconcile_configured_boss()


func _can_manage_bots() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func _can_manage_bosses() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func _reconcile_configured_bots() -> void:
	if not _can_manage_bots():
		return
	var desired_count := GameSettings.bot_count if GameSettings.bots_enabled else 0
	print("[World] _reconcile_configured_bots: desired=%d current=%d bots_enabled=%s" % [desired_count, _basic_casters.size(), str(GameSettings.bots_enabled)])
	for bot_id in _basic_casters.keys():
		if int(bot_id) >= desired_count:
			_despawn_basic_caster(bot_id)
	for i in range(desired_count):
		if _basic_casters.has(i):
			continue
		var pos := _get_bot_spawn_position(i)
		var loadout := _create_random_bot_loadout()
		var difficulty_data := _get_bot_difficulty_data()
		print("[World] Spawning bot %d at %s" % [i, str(pos)])
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


@rpc("authority", "reliable")
func _spawn_basic_caster_for_all(bot_id: int, spawn_position: Vector3, loadout_data: Array, difficulty_data: Dictionary) -> void:
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
	print("[World] Bot %d spawned locally, total bots: %d" % [bot_id, _basic_casters.size()])
	if _basic_caster == null:
		_basic_caster = caster
	_refresh_basic_caster_target()


@rpc("authority", "call_local", "reliable")
func _despawn_basic_caster_for_all(bot_id: int) -> void:
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


@rpc("authority", "call_local", "reliable")
func _update_basic_caster_difficulty_for_all(difficulty_data: Dictionary) -> void:
	_update_basic_caster_difficulty_local(difficulty_data)


func _update_basic_caster_difficulty_local(difficulty_data: Dictionary) -> void:
	for caster in _basic_casters.values():
		if caster != null and caster.has_method("set_difficulty_data"):
			caster.set_difficulty_data(difficulty_data)


func broadcast_basic_caster_state(
	bot_id: int,
	pos: Vector3,
	yaw: float,
	health: int,
	is_dead: bool,
	blind_timer: float,
	timestamp: float
) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_client_receive_basic_caster_state.rpc(bot_id, pos, yaw, health, is_dead, blind_timer, timestamp)


@rpc("authority", "unreliable")
func _client_receive_basic_caster_state(
	bot_id: int,
	pos: Vector3,
	yaw: float,
	health: int,
	is_dead: bool,
	blind_timer: float,
	timestamp: float
) -> void:
	if multiplayer.is_server():
		return
	var caster := _basic_casters.get(bot_id) as Node
	if caster == null:
		if _player == null:
			_request_world_state_from_server()
		return
	if caster.has_method("_client_receive_state"):
		caster._client_receive_state(pos, yaw, health, is_dead, blind_timer, timestamp)


func _reconcile_configured_boss() -> void:
	if not _can_manage_bosses():
		return
	if GameSettings.boss_enabled:
		if _bosses.has(0):
			return
		spawn_boss(GameSettings.get_boss_spawn_settings())
	elif _bosses.has(0):
		despawn_boss(0)


func spawn_boss(settings: Dictionary = {}) -> bool:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return false
	var boss_id := int(settings.get("boss_id", _get_next_boss_id()))
	var replace_existing := bool(settings.get("replace_existing", false))
	if _bosses.has(boss_id):
		var existing := _bosses.get(boss_id) as Node
		var existing_dead := false
		if existing != null and existing.has_method("get_state_data"):
			var state := existing.get_state_data() as Dictionary
			existing_dead = bool(state.get("is_dead", false))
		if not existing_dead and not replace_existing:
			return false
		despawn_boss(boss_id)
	var spawn_position := settings.get("spawn_position", Vector3(0, 0.0, -14)) as Vector3
	var boss_settings := settings.duplicate(true)
	boss_settings.erase("replace_existing")
	boss_settings["boss_id"] = boss_id
	boss_settings["spawn_position"] = spawn_position
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_spawn_boss_for_all.rpc(boss_id, spawn_position, boss_settings)
	else:
		_spawn_boss_local(boss_id, spawn_position, boss_settings)
	return true


func despawn_boss(boss_id: int = 0) -> bool:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return false
	if not _bosses.has(boss_id):
		return false
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_despawn_boss_for_all.rpc(boss_id)
	else:
		_despawn_boss_local(boss_id)
	return true


func get_boss_count() -> int:
	return _bosses.size()


@rpc("authority", "reliable")
func _spawn_boss_for_all(boss_id: int, spawn_position: Vector3, settings: Dictionary) -> void:
	_spawn_boss_local(boss_id, spawn_position, settings)


func _spawn_boss_local(boss_id: int, spawn_position: Vector3, settings: Dictionary) -> void:
	if _bosses.has(boss_id):
		return
	var boss := BossCasterScene.instantiate()
	boss.name = "BossCaster_%d" % boss_id
	var boss_settings := settings.duplicate(true)
	boss_settings["boss_id"] = boss_id
	boss_settings["spawn_position"] = spawn_position
	if boss.has_method("configure"):
		boss.configure(boss_settings)
	boss.position = spawn_position
	if boss.has_method("get_boss_id"):
		boss_id = int(boss.get_boss_id())
	add_child(boss)
	_bosses[boss_id] = boss
	_refresh_boss_targets()
	if boss.has_method("get_state_data"):
		update_boss_health_hud(boss.get_state_data())


@rpc("authority", "call_local", "reliable")
func _despawn_boss_for_all(boss_id: int) -> void:
	_despawn_boss_local(boss_id)


func _despawn_boss_local(boss_id: int) -> void:
	var boss := _bosses.get(boss_id) as Node
	if boss != null:
		boss.queue_free()
	_bosses.erase(boss_id)
	_remove_boss_health_hud_if_empty()


func _get_next_boss_id() -> int:
	var next_id := 0
	while _bosses.has(next_id):
		next_id += 1
	return next_id


func _refresh_boss_targets() -> void:
	var players := get_active_player_nodes()
	var target_player: Node3D = null
	if not players.is_empty():
		target_player = players[0] as Node3D
	for boss in _bosses.values():
		if boss != null:
			boss.target = target_player


func get_active_player_nodes() -> Array:
	var results: Array = []
	for player in _players.values():
		if player is Node3D and is_instance_valid(player):
			results.append(player)
	if results.is_empty() and _player != null and is_instance_valid(_player):
		results.append(_player)
	return results


func spawn_authoritative_spell_impact(spell: SpellDefinition, position: Vector3, normal: Vector3, source: Node = null) -> void:
	if spell == null:
		return
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	var effect := SpellImpactEffectScript.new()
	get_tree().current_scene.add_child(effect)
	effect.initialize(spell, position, normal, source)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		broadcast_spell_impact(spell, position, normal)


func update_boss_health_hud(state: Dictionary) -> void:
	if _is_dedicated_server():
		return
	_ensure_boss_health_hud()
	var max_health: int = max(1, int(state.get("max_health", 1)))
	var health: int = clampi(int(state.get("health", 0)), 0, max_health)
	_boss_hud_label.text = "%s  %d / %d" % [str(state.get("display_name", "Boss")), health, max_health]
	_boss_hud_bar.max_value = max_health
	_boss_hud_bar.value = health
	_boss_hud_panel.visible = not bool(state.get("is_dead", false)) or health > 0
	var part_texts: Array[String] = []
	for part in state.get("parts", []):
		var data := part as Dictionary
		var name := str(data.get("name", data.get("id", "Part")))
		if bool(data.get("destroyed", false)):
			part_texts.append("%s: destroyed" % name)
		else:
			part_texts.append("%s: %d/%d" % [name, int(data.get("health", 0)), int(data.get("max_health", 1))])
	_boss_hud_parts_label.text = "   ".join(part_texts)


func _ensure_boss_health_hud() -> void:
	if _boss_hud_layer != null:
		return
	_boss_hud_layer = CanvasLayer.new()
	_boss_hud_layer.name = "BossHud"
	add_child(_boss_hud_layer)

	_boss_hud_panel = VBoxContainer.new()
	_boss_hud_layer.add_child(_boss_hud_panel)
	_boss_hud_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_boss_hud_panel.offset_left = 320.0
	_boss_hud_panel.offset_top = 18.0
	_boss_hud_panel.offset_right = -320.0
	_boss_hud_panel.offset_bottom = 84.0
	_boss_hud_panel.add_theme_constant_override("separation", 4)

	_boss_hud_label = Label.new()
	_boss_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_hud_label.add_theme_font_size_override("font_size", 18)
	_boss_hud_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42))
	_boss_hud_panel.add_child(_boss_hud_label)

	_boss_hud_bar = ProgressBar.new()
	_boss_hud_bar.min_value = 0.0
	_boss_hud_bar.max_value = 1.0
	_boss_hud_bar.show_percentage = false
	_boss_hud_bar.custom_minimum_size = Vector2(520, 14)
	_boss_hud_panel.add_child(_boss_hud_bar)

	_boss_hud_parts_label = Label.new()
	_boss_hud_parts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_hud_parts_label.add_theme_font_size_override("font_size", 12)
	_boss_hud_parts_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.68, 0.88))
	_boss_hud_panel.add_child(_boss_hud_parts_label)


func _remove_boss_health_hud_if_empty() -> void:
	if not _bosses.is_empty():
		return
	if _boss_hud_layer != null:
		_boss_hud_layer.queue_free()
	_boss_hud_layer = null
	_boss_hud_panel = null
	_boss_hud_label = null
	_boss_hud_bar = null
	_boss_hud_parts_label = null


func _prune_invalid_bosses() -> void:
	var removed := false
	for boss_id in _bosses.keys():
		var boss := _bosses[boss_id] as Node
		if boss == null or not is_instance_valid(boss) or boss.is_queued_for_deletion():
			_bosses.erase(boss_id)
			removed = true
	if removed:
		_remove_boss_health_hud_if_empty()


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
		_show_spell_creator_overlay()


func close_spell_creator_for_local_player() -> void:
	_close_spell_creator_overlay()
	var peer_id := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server():
			_set_peer_in_creator(peer_id, false)
		else:
			_server_set_peer_in_creator.rpc_id(1, false)


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
		# Don't despawn the player - keep the node alive for RPC calls
		# Just mark them as in creator so they don't participate in gameplay
		if peer_id == multiplayer.get_unique_id():
			_show_spell_creator_overlay()
	else:
		if not _peers_in_creator.has(peer_id):
			return
		_peers_in_creator.erase(peer_id)
		# Player already exists, no need to respawn
		# Just close the overlay if we're the local player
		if peer_id == multiplayer.get_unique_id():
			_close_spell_creator_overlay()


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
		"wall_time": 4,
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


@rpc("authority", "call_local", "reliable")
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
	var player := _players.get(peer_id) as Node
	if player != null and player.has_method("apply_network_combat_state"):
		player.apply_network_combat_state(health, mana, is_dead, respawn_timer, blind_timer, blind_duration, pos, external_velocity)


func broadcast_player_transform_state(peer_id: int, pos: Vector3, net_velocity: Vector3, yaw: float, head_pitch: float, timestamp: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_client_receive_player_transform_state.rpc(peer_id, pos, net_velocity, yaw, head_pitch, timestamp)


@rpc("authority", "unreliable")
func _client_receive_player_transform_state(peer_id: int, pos: Vector3, net_velocity: Vector3, yaw: float, head_pitch: float, timestamp: float) -> void:
	if multiplayer.is_server():
		return
	var player := _players.get(peer_id) as Node
	if player == null:
		if _player == null:
			_request_world_state_from_server()
		return
	if player.has_method("apply_network_transform_state"):
		player.apply_network_transform_state(peer_id, pos, net_velocity, yaw, head_pitch, timestamp)


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


func remember_predicted_projectile(spell: SpellDefinition, from: Vector3, direction: Vector3) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	_predicted_projectile_echoes.append({
		"spell_key": _get_projectile_prediction_spell_key(spell),
		"from": from,
		"direction": direction.normalized(),
		"created_at": Time.get_ticks_msec() / 1000.0,
	})
	_prune_predicted_projectile_echoes()


@rpc("authority", "reliable")
func _client_spawn_network_projectile(spell_data: Dictionary, from: Vector3, direction: Vector3, source_peer_id: int) -> void:
	if multiplayer.is_server():
		return
	var spell := SpellNetworkCodecScript.from_dict(spell_data)
	if source_peer_id == multiplayer.get_unique_id() or _consume_predicted_projectile_echo(spell, from, direction):
		return
	var source := _players.get(source_peer_id) as Node
	_spawn_projectile_local(spell, from, direction, source)


func _spawn_projectile_local(spell: SpellDefinition, from: Vector3, direction: Vector3, source: Node, cast_server_time: float = -1.0) -> void:
	var projectile := SpellProjectileScene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.initialize(spell, from, direction, source, cast_server_time)


func _consume_predicted_projectile_echo(spell: SpellDefinition, from: Vector3, direction: Vector3) -> bool:
	_prune_predicted_projectile_echoes()
	var spell_key := _get_projectile_prediction_spell_key(spell)
	var normalized_direction := direction.normalized()
	for i in range(_predicted_projectile_echoes.size() - 1, -1, -1):
		var prediction := _predicted_projectile_echoes[i]
		var predicted_direction := prediction["direction"] as Vector3
		if str(prediction["spell_key"]) != spell_key:
			continue
		if (prediction["from"] as Vector3).distance_to(from) > 1.2:
			continue
		if predicted_direction.dot(normalized_direction) < 0.985:
			continue
		_predicted_projectile_echoes.remove_at(i)
		return true
	return false


func _prune_predicted_projectile_echoes() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_predicted_projectile_echoes.size() - 1, -1, -1):
		if now - float(_predicted_projectile_echoes[i]["created_at"]) > 1.5:
			_predicted_projectile_echoes.remove_at(i)


func _get_projectile_prediction_spell_key(spell: SpellDefinition) -> String:
	if spell == null:
		return ""
	return "%s|%s|%s|%d|%d|%d|%d" % [
		spell.spell_name,
		spell.get_blend_key(),
		spell.shape,
		spell.intensity,
		spell.spell_size,
		spell.spell_range,
		spell.spell_speed,
	]


func resolve_beam_segment(source_key: String, spell: SpellDefinition, origin: Vector3, raw_target: Vector3, source: Node = null) -> Dictionary:
	if spell == null:
		return {"target": raw_target, "blocked": false}
	var now := Time.get_ticks_msec() / 1000.0
	var segment := {
		"source_key": source_key,
		"spell": spell,
		"origin": origin,
		"raw_target": raw_target,
		"target": raw_target,
		"source": source,
		"updated_at": now,
	}
	_active_beam_segments[source_key] = segment

	var best_t := 2.0
	var clipped_target := raw_target
	var blocked := false
	var direction := (raw_target - origin).normalized()
	var beam_radius := _get_beam_collision_radius(spell)
	var beam_length := maxf(origin.distance_to(raw_target), 0.001)
	for node in get_tree().get_nodes_in_group("spell_projectile"):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("is_spell_wall") or not bool(node.is_spell_wall()):
			continue
		if node.has_method("is_spell_consumed") and bool(node.is_spell_consumed()):
			continue
		var wall_hit: Dictionary = node.get_wall_segment_hit(origin, raw_target, beam_radius)
		if wall_hit.is_empty():
			continue
		var hit_position := wall_hit["position"] as Vector3
		var t_wall := origin.distance_to(hit_position) / beam_length
		if t_wall >= best_t:
			continue
		best_t = t_wall
		clipped_target = hit_position
		blocked = true
		var outcome: Dictionary = node.apply_wall_block(spell, true, source_key, BEAM_COLLISION_IMPACT_INTERVAL)
		var reaction_spell := outcome.get("reaction_spell") as SpellDefinition
		if reaction_spell == null:
			reaction_spell = spell
		_maybe_spawn_beam_wall_impact(source_key, node, reaction_spell, hit_position, -direction)
	for other_key in _active_beam_segments.keys():
		var other_source_key := str(other_key)
		if other_source_key == source_key:
			continue
		var other := _active_beam_segments[other_key] as Dictionary
		if other.is_empty() or now - float(other.get("updated_at", 0.0)) > 0.25:
			continue
		var other_spell := other.get("spell") as SpellDefinition
		if other_spell == null:
			continue
		var other_origin := other["origin"] as Vector3
		var other_raw_target := other["raw_target"] as Vector3
		var closest := _get_closest_segment_points(origin, raw_target, other_origin, other_raw_target)
		var collision_radius := _get_beam_collision_radius(spell) + _get_beam_collision_radius(other_spell)
		if float(closest["distance"]) > collision_radius:
			continue

		var t_self := float(closest["t_a"])
		var t_other := float(closest["t_b"])
		var collision_point: Vector3 = (closest["point_a"] as Vector3).lerp(closest["point_b"] as Vector3, 0.5)
		var other_direction := (other_raw_target - other_origin).normalized()
		var outcome := _resolve_beam_collision(spell, other_spell, direction, other_direction)
		var pair_key := _get_beam_pair_key(source_key, other_source_key)
		var clash_point := _get_pushed_beam_clash_point(
			pair_key,
			collision_point,
			origin,
			raw_target,
			t_self,
			other_origin,
			other_raw_target,
			t_other,
			float(outcome.get("clash_bias", 0.0))
		)
		var impact_spell := outcome.get("reaction_spell") as SpellDefinition
		if impact_spell == null:
			impact_spell = spell
		_maybe_spawn_beam_collision_impact(source_key, other_source_key, impact_spell, clash_point, -direction)

		if bool(outcome.get("block_b", false)):
			var other_target := clash_point
			if other_origin.distance_to(other_target) < other_origin.distance_to(other.get("target", other_raw_target)):
				other["target"] = other_target
				other["blocked"] = true
				_active_beam_segments[other_key] = other
		if bool(outcome.get("block_a", false)) and t_self < best_t:
			best_t = t_self
			clipped_target = clash_point
			blocked = true

	segment["target"] = clipped_target
	segment["blocked"] = blocked
	_active_beam_segments[source_key] = segment
	return {"target": clipped_target, "blocked": blocked}


func get_registered_beam_target(source_key: String, fallback: Vector3) -> Vector3:
	var segment := _active_beam_segments.get(source_key, {}) as Dictionary
	if segment.is_empty():
		return fallback
	if not bool(segment.get("blocked", false)):
		return fallback
	return segment.get("target", fallback) as Vector3


func unregister_beam_segment(source_key: String) -> void:
	_active_beam_segments.erase(source_key)


func _resolve_beam_collision(a: SpellDefinition, b: SpellDefinition, direction_a: Vector3, direction_b: Vector3) -> Dictionary:
	var opposing_pair := _find_opposing_pair(a, b)
	if not opposing_pair.is_empty():
		var power_a := _get_opposition_power(a, opposing_pair[0])
		var power_b := _get_opposition_power(b, opposing_pair[1])
		var high_power: float = maxf(power_a, power_b)
		if _is_steam_reaction(opposing_pair):
			return {
				"block_a": true,
				"block_b": true,
				"clash_bias": _get_power_bias(power_a, power_b),
				"reaction_spell": _create_reaction_spell(a, b, opposing_pair, 1.75),
			}
		var interference := _get_wave_interference(a, b, direction_a, direction_b)
		var cancel_strength := _get_cancel_strength(interference)
		var effective_a := power_a * (0.65 + cancel_strength * 0.7)
		var effective_b := power_b * (0.65 + cancel_strength * 0.7)
		var reaction_spell := _create_reaction_spell(a, b, opposing_pair)
		if high_power <= 0.0:
			return {"block_a": true, "block_b": true, "reaction_spell": reaction_spell}
		return {
			"block_a": true,
			"block_b": true,
			"clash_bias": _get_power_bias(effective_a, effective_b),
			"reaction_spell": reaction_spell,
		}

	if a.get_dominant_base() == b.get_dominant_base():
		var total_a := _get_total_power(a)
		var total_b := _get_total_power(b)
		var interference := _get_wave_interference(a, b, direction_a, direction_b)
		var high_power: float = maxf(total_a, total_b)
		if interference >= 0.35:
			return {"block_a": false, "block_b": false}
		if high_power <= 0.0 or interference <= -0.35 and absf(total_a - total_b) / high_power <= 0.25:
			return {"block_a": true, "block_b": true}
		if interference <= -0.35:
			return {"block_a": true, "block_b": true, "clash_bias": _get_power_bias(total_a, total_b)}
		return {"block_a": true, "block_b": true, "clash_bias": _get_power_bias(total_a, total_b) * 0.45}

	var density_a := _get_spell_density(a)
	var density_b := _get_spell_density(b)
	var density_delta := absf(density_a - density_b)
	if density_delta > 6.0:
		return {"block_a": true, "block_b": true, "clash_bias": _get_power_bias(density_a, density_b)}
	var temp_delta := absf(_get_spell_temperature(a) - _get_spell_temperature(b))
	var interference := _get_wave_interference(a, b, direction_a, direction_b)
	if temp_delta > 6.0:
		return {"block_a": true, "block_b": true, "clash_bias": _get_power_bias(_get_total_power(a), _get_total_power(b)) * 0.65}
	if interference > 0.55:
		return {"block_a": false, "block_b": false}
	return {"block_a": true, "block_b": true, "clash_bias": _get_power_bias(_get_total_power(a), _get_total_power(b)) * 0.35}


func _get_beam_pair_key(source_a: String, source_b: String) -> String:
	var keys := [source_a, source_b]
	keys.sort()
	return "%s|%s" % [keys[0], keys[1]]


func _get_pushed_beam_clash_point(
	pair_key: String,
	collision_point: Vector3,
	origin_a: Vector3,
	target_a: Vector3,
	t_a: float,
	origin_b: Vector3,
	target_b: Vector3,
	t_b: float,
	clash_bias: float
) -> Vector3:
	var desired := collision_point
	var bias := clampf(clash_bias, -1.0, 1.0)
	var push := absf(bias) * BEAM_CLASH_MAX_PUSH_FRACTION
	if push > 0.01:
		if bias > 0.0:
			var pushed_t := lerpf(t_b, 0.03, push)
			desired = origin_b.lerp(target_b, clampf(pushed_t, 0.0, 1.0))
		else:
			var pushed_t := lerpf(t_a, 0.03, push)
			desired = origin_a.lerp(target_a, clampf(pushed_t, 0.0, 1.0))
	var previous := _beam_clash_points.get(pair_key, desired) as Vector3
	var smoothed := previous.lerp(desired, BEAM_CLASH_SMOOTHING)
	_beam_clash_points[pair_key] = smoothed
	return smoothed


func _get_power_bias(power_a: float, power_b: float) -> float:
	var high_power: float = maxf(absf(power_a), absf(power_b))
	if high_power <= 0.001:
		return 0.0
	return clampf((power_a - power_b) / high_power, -1.0, 1.0)


func _is_steam_reaction(opposing_pair: Array[String]) -> bool:
	return opposing_pair.has("Fire") and opposing_pair.has("Water")


func _maybe_spawn_beam_collision_impact(source_a: String, source_b: String, spell: SpellDefinition, position: Vector3, normal: Vector3) -> void:
	var pair_key := _get_beam_pair_key(source_a, source_b)
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_beam_collision_impacts.get(pair_key, -99.0)) < BEAM_COLLISION_IMPACT_INTERVAL:
		return
	_beam_collision_impacts[pair_key] = now
	var effect := SpellImpactEffectScript.new()
	get_tree().current_scene.add_child(effect)
	effect.initialize(spell, position, normal, null)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		broadcast_spell_impact(spell, position, normal)


func _maybe_spawn_beam_wall_impact(source_key: String, wall: Node3D, spell: SpellDefinition, position: Vector3, front_normal: Vector3) -> void:
	var wall_key := "wall:%d" % wall.get_instance_id()
	var pair_key := _get_beam_pair_key(source_key, wall_key)
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_beam_collision_impacts.get(pair_key, -99.0)) < BEAM_COLLISION_IMPACT_INTERVAL:
		return
	_beam_collision_impacts[pair_key] = now
	var effect := SpellImpactEffectScript.new()
	get_tree().current_scene.add_child(effect)
	effect.initialize(spell, position, front_normal, null)
	effect.set_blocking_plane(wall.global_position, front_normal)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		broadcast_spell_impact(spell, position, front_normal)


func _prune_stale_beam_segments() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for key in _active_beam_segments.keys():
		var segment := _active_beam_segments[key] as Dictionary
		if now - float(segment.get("updated_at", 0.0)) > 0.5:
			_active_beam_segments.erase(key)
	for key in _beam_collision_impacts.keys():
		if now - float(_beam_collision_impacts[key]) > 2.0:
			_beam_collision_impacts.erase(key)
	for key in _beam_clash_points.keys():
		var key_text := str(key)
		var parts := key_text.split("|", false)
		if parts.size() != 2 or not _active_beam_segments.has(parts[0]) or not _active_beam_segments.has(parts[1]):
			_beam_clash_points.erase(key)


func _get_beam_collision_radius(spell: SpellDefinition) -> float:
	return BEAM_COLLISION_RADIUS_BASE + float(spell.spell_size) * BEAM_COLLISION_RADIUS_SIZE_SCALE


func _get_closest_segment_points(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> Dictionary:
	var u := a1 - a0
	var v := b1 - b0
	var w := a0 - b0
	var a := u.dot(u)
	var b := u.dot(v)
	var c := v.dot(v)
	var d := u.dot(w)
	var e := v.dot(w)
	var denominator := a * c - b * b
	var sc := 0.0
	var tc := 0.0
	if denominator > 0.0001:
		sc = clampf((b * e - c * d) / denominator, 0.0, 1.0)
	if c > 0.0001:
		tc = clampf((b * sc + e) / c, 0.0, 1.0)
	if a > 0.0001:
		sc = clampf((b * tc - d) / a, 0.0, 1.0)
	var point_a := a0 + u * sc
	var point_b := b0 + v * tc
	return {
		"point_a": point_a,
		"point_b": point_b,
		"t_a": sc,
		"t_b": tc,
		"distance": point_a.distance_to(point_b),
	}


func _find_opposing_pair(a: SpellDefinition, b: SpellDefinition) -> Array[String]:
	for base_a in a.get_base_elements():
		for base_b in b.get_base_elements():
			var props: Dictionary = BASE_PROPERTIES.get(base_a, {})
			var opposing: Array = props.get("opposing", [])
			if opposing.has(base_b):
				return [base_a, base_b]
	return []


func _get_opposition_power(spell: SpellDefinition, base: String) -> float:
	var weights := spell.get_base_weights()
	var weight := float(weights.get(base, 0)) / 100.0
	return weight * float(spell.intensity) * float(spell.spell_size)


func _get_total_power(spell: SpellDefinition) -> float:
	return float(spell.intensity) * float(spell.spell_size)


func _get_spell_temperature(spell: SpellDefinition) -> float:
	return _get_weighted_base_property(spell, "temperature", 5.0)


func _get_spell_density(spell: SpellDefinition) -> float:
	return _get_weighted_base_property(spell, "density", 1.0)


func _get_weighted_base_property(spell: SpellDefinition, property: String, fallback: float) -> float:
	var weights := spell.get_base_weights()
	var total := 0.0
	var value := 0.0
	for base in weights.keys():
		var weight := float(weights[base])
		total += weight
		var props: Dictionary = BASE_PROPERTIES.get(str(base), {})
		value += float(props.get(property, fallback)) * weight
	if total <= 0.0:
		return fallback
	return value / total


func _get_wave_interference(a: SpellDefinition, b: SpellDefinition, direction_a: Vector3, direction_b: Vector3) -> float:
	var phase_delta: float = _get_wave_phase(a) - _get_wave_phase(b)
	var phase_alignment := cos(phase_delta)
	var direction_alignment := direction_a.normalized().dot(direction_b.normalized())
	var aim_factor: float = clampf((1.0 - direction_alignment) * 0.5, 0.0, 1.0)
	return clampf(phase_alignment * 0.75 - aim_factor * 0.35, -1.0, 1.0)


func _get_cancel_strength(interference: float) -> float:
	return clampf(-interference, 0.0, 1.0)


func _get_wave_phase(spell: SpellDefinition) -> float:
	var lifetime := Time.get_ticks_msec() / 1000.0
	return _get_base_phase_offset(spell.get_dominant_base()) + lifetime * _get_wave_frequency(spell) * TAU


func _get_wave_frequency(spell: SpellDefinition) -> float:
	return 0.65 + spell.spell_speed * 0.08 + spell.intensity * 0.035 + spell.get_base_elements().size() * 0.06


func _get_base_phase_offset(base: String) -> float:
	match base:
		"Fire": return 0.0
		"Water": return PI
		"Air": return PI * 0.33
		"Earth": return PI * 1.33
		"Spirit": return PI * 0.72
		"Light": return PI * 0.18
		"Void": return PI * 1.18
		_: return 0.0


func _create_reaction_spell(a: SpellDefinition, b: SpellDefinition, opposing_pair: Array[String], strength_scale: float = 1.0) -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = "Steam Clash" if _is_steam_reaction(opposing_pair) else "Beam Clash"
	spell.base_element = opposing_pair[0]
	spell.base_weights = {opposing_pair[0]: 50, opposing_pair[1]: 50}
	spell.shape = "Sphere"
	spell.intensity = max(1, int(round((a.intensity + b.intensity) * 0.5 * strength_scale)))
	spell.spell_size = max(1, int(round((a.spell_size + b.spell_size) * 0.5 * strength_scale)))
	spell.spell_range = 1
	spell.spell_speed = 1
	if _is_steam_reaction(opposing_pair):
		spell.burns = true
		spell.cools = true
	return spell


func broadcast_spell_impact(spell: SpellDefinition, position: Vector3, normal: Vector3) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var spell_data := SpellNetworkCodecScript.to_dict(spell)
	var impact_id := _remember_spell_impact(spell_data, position, normal)
	_client_spawn_spell_impact.rpc(impact_id, spell_data, position, normal, 0.0)


@rpc("authority", "reliable")
func _client_spawn_spell_impact(impact_id: int, spell_data: Dictionary, position: Vector3, normal: Vector3, age: float = 0.0) -> void:
	if multiplayer.is_server():
		return
	var effect := SpellImpactEffectScript.new()
	effect.name = "SpellImpact_%d" % impact_id
	get_tree().current_scene.add_child(effect)
	effect.initialize(SpellNetworkCodecScript.from_dict(spell_data), position, normal, null, age)
	effect.set_visual_only(true)


func _remember_spell_impact(spell_data: Dictionary, position: Vector3, normal: Vector3) -> int:
	_prune_expired_spell_impacts()
	var spell := SpellNetworkCodecScript.from_dict(spell_data)
	var lifetime: float = SpellImpactEffectScript.estimate_lifetime(spell)
	var impact_id := _next_spell_impact_id
	_next_spell_impact_id += 1
	_active_spell_impacts.append({
		"id": impact_id,
		"spell_data": spell_data,
		"position": position,
		"normal": normal,
		"created_at": Time.get_ticks_msec() / 1000.0,
		"lifetime": lifetime,
	})
	return impact_id


func _send_active_spell_impacts(peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_prune_expired_spell_impacts()
	var now := Time.get_ticks_msec() / 1000.0
	for impact in _active_spell_impacts:
		var age := now - float(impact["created_at"])
		_client_spawn_spell_impact.rpc_id(
			peer_id,
			int(impact["id"]),
			impact["spell_data"] as Dictionary,
			impact["position"] as Vector3,
			impact["normal"] as Vector3,
			age
		)


func _prune_expired_spell_impacts() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_active_spell_impacts.size() - 1, -1, -1):
		var impact := _active_spell_impacts[i]
		if now - float(impact["created_at"]) >= float(impact["lifetime"]):
			_active_spell_impacts.remove_at(i)


func broadcast_push_test_target_state(pos: Vector3, rot: Vector3, lin_vel: Vector3, ang_vel: Vector3) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_client_receive_push_test_target_state.rpc(pos, rot, lin_vel, ang_vel)


@rpc("authority", "unreliable")
func _client_receive_push_test_target_state(pos: Vector3, rot: Vector3, lin_vel: Vector3, ang_vel: Vector3) -> void:
	if multiplayer.is_server():
		return
	var target := get_node_or_null("PushTestTarget")
	if target == null:
		return
	if target.has_method("_client_receive_state"):
		target._client_receive_state(pos, rot, lin_vel, ang_vel)


func _spawn_push_test_target() -> void:
	var target := RigidBody3D.new()
	target.name = "PushTestTarget"
	target.set_script(PushTestTargetScript)
	target.position = Vector3(3.0, 0.8, -9.5)
	add_child(target)

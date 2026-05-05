extends Node

const DEFAULT_PORT := 24567
const MAX_PLAYERS := 12
const COMMAND_POLL_INTERVAL := 1.0

var _active := false
var _heartbeat_timer := 0.0
var _command_poll_timer := 0.0
var _command_file_path := ""
var _command_file_offset := 0
var _command_file_buffer := ""
var _command_file_read_error_logged := false
var _world_ready := false


func _ready() -> void:
	if not _should_run_as_server():
		return
	_active = true
	_apply_env_settings()
	_init_command_file()
	var port := _read_env_int("PORT", DEFAULT_PORT)
	print("[Server] Starting dedicated server on port %d" % port)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("[Server] Failed to bind port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[Server] Ready. Loading world...")
	get_tree().call_deferred("change_scene_to_file", "res://Scenes/World/World.tscn")


func _process(delta: float) -> void:
	if not _active:
		return
	_heartbeat_timer += delta
	if _heartbeat_timer >= 10.0:
		_heartbeat_timer = 0.0
		print("[Server] Heartbeat — peers connected: %d" % multiplayer.get_peers().size())

	_command_poll_timer += delta
	if _command_poll_timer >= COMMAND_POLL_INTERVAL:
		_command_poll_timer = 0.0
		_poll_server_commands()


func is_active() -> bool:
	return _active


func _should_run_as_server() -> bool:
	return OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_args()


func _apply_env_settings() -> void:
	var bots_val := OS.get_environment("BOTS")
	if bots_val != "":
		GameSettings.bots_enabled = bots_val.to_lower() in ["1", "true", "yes"]
	var count_val := OS.get_environment("BOT_COUNT")
	if count_val != "" and count_val.is_valid_int():
		GameSettings.bot_count = clampi(int(count_val), 0, 12)
	var diff_val := OS.get_environment("BOT_DIFFICULTY")
	if diff_val in ["Easy", "Medium", "Hard"]:
		GameSettings.bot_difficulty = diff_val
	GameSettings.set_bot_settings(GameSettings.bots_enabled, GameSettings.bot_count, GameSettings.bot_difficulty)


func _read_env_int(key: String, fallback: int) -> int:
	var val := OS.get_environment(key)
	return int(val) if val != "" and val.is_valid_int() else fallback


func _init_command_file() -> void:
	_command_file_path = OS.get_environment("SERVER_COMMAND_FILE")
	if _command_file_path == "":
		_command_file_path = "user://server_commands.txt"
	if not FileAccess.file_exists(_command_file_path):
		var create_file := FileAccess.open(_command_file_path, FileAccess.WRITE)
		if create_file == null:
			push_warning("[Server] Command file cannot be created: %s (%s)" % [_command_file_path, error_string(FileAccess.get_open_error())])
			return
		create_file.close()
		print("[Server] Created command file: %s" % _command_file_path)
	var file := FileAccess.open(_command_file_path, FileAccess.READ)
	if file != null:
		_command_file_offset = file.get_length()
		file.close()
	else:
		push_warning("[Server] Command file cannot be read: %s (%s)" % [_command_file_path, error_string(FileAccess.get_open_error())])
	print("[Server] Command file: %s" % _command_file_path)


func _poll_server_commands() -> void:
	if not _world_ready:
		return
	if _command_file_path == "":
		return
	var file := FileAccess.open(_command_file_path, FileAccess.READ)
	if file == null:
		if not _command_file_read_error_logged:
			_command_file_read_error_logged = true
			push_warning("[Server] Command file poll failed: %s (%s)" % [_command_file_path, error_string(FileAccess.get_open_error())])
		return
	_command_file_read_error_logged = false
	var length := file.get_length()
	if length < _command_file_offset:
		_command_file_offset = 0
		_command_file_buffer = ""
	if length <= _command_file_offset:
		file.close()
		return
	file.seek(_command_file_offset)
	var bytes := file.get_buffer(length - _command_file_offset)
	_command_file_offset = length
	file.close()

	_command_file_buffer += bytes.get_string_from_utf8()
	var has_complete_line := _command_file_buffer.ends_with("\n") or _command_file_buffer.ends_with("\r")
	var lines := _command_file_buffer.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	_command_file_buffer = ""
	if not has_complete_line and not lines.is_empty():
		_command_file_buffer = lines[lines.size() - 1]
		lines.remove_at(lines.size() - 1)
	for raw_line in lines:
		_run_server_command(raw_line)


func _run_server_command(raw_command: String) -> void:
	var command := raw_command.strip_edges()
	if command.is_empty() or command.begins_with("#"):
		return
	print("[ServerCommand] > %s" % command)
	var result := _try_run_world_command(command)
	if not bool(result.get("handled", false)):
		result = GameSettings.apply_server_command(command)
		if bool(result.get("ok", false)) and _is_bot_settings_command(command):
			_force_world_bot_reconcile()
	var message := str(result.get("message", ""))
	if bool(result.get("ok", false)):
		if message != "":
			print("[ServerCommand] %s" % message)
	else:
		print("[ServerCommand] ERROR: %s" % message)


func _is_bot_settings_command(command: String) -> bool:
	var parts := command.split(" ", false)
	if parts.is_empty():
		return false
	return parts[0].to_lower() in ["bots", "bot_count", "botcount", "bot_difficulty", "botdifficulty", "difficulty"]


func _force_world_bot_reconcile() -> void:
	var world := get_tree().current_scene
	if world == null:
		push_warning("[Server] Cannot reconcile bots: world not loaded.")
		return
	if not world.has_method("force_reconcile_bots"):
		push_warning("[Server] Current scene does not support force_reconcile_bots().")
		return
	world.force_reconcile_bots()


func _try_run_world_command(command: String) -> Dictionary:
	var parts := command.split(" ", false)
	if parts.is_empty():
		return {"handled": false}
	var first := parts[0].to_lower()
	if first == "bot" and parts.size() >= 2:
		var bot_action := parts[1].to_lower()
		var bot_world := get_tree().current_scene
		if bot_world == null:
			return {"handled": true, "ok": false, "message": "World not loaded."}
		match bot_action:
			"status":
				var bot_count: int = bot_world.get("_basic_casters").size() if bot_world.get("_basic_casters") != null else -1
				return {"handled": true, "ok": true, "message": "world bot count: %d  settings: %s" % [bot_count, GameSettings.get_bot_settings_summary()]}
			"reconcile":
				_force_world_bot_reconcile()
				return {"handled": true, "ok": true, "message": "bot reconcile requested. settings: %s" % GameSettings.get_bot_settings_summary()}
			_:
				return {"handled": true, "ok": false, "message": "Unknown bot action '%s'. Try: bot status, bot reconcile" % bot_action}
	if first != "boss":
		return {"handled": false}
	var world := get_tree().current_scene
	if world == null:
		return {"handled": true, "ok": false, "message": "World is not loaded yet."}
	if parts.size() < 2:
		return {"handled": true, "ok": true, "message": _boss_command_help()}
	var action := parts[1].to_lower()
	match action:
		"spawn":
			if not world.has_method("spawn_boss"):
				return {"handled": true, "ok": false, "message": "Current scene cannot spawn bosses."}
			var settings := _parse_boss_settings(parts)
			var ok := bool(world.spawn_boss(settings))
			var spawn_message := "boss spawned %s" % str(settings) if ok else "Boss spawn rejected."
			return {"handled": true, "ok": ok, "message": spawn_message}
		"replace", "respawn", "restart":
			if not world.has_method("spawn_boss"):
				return {"handled": true, "ok": false, "message": "Current scene cannot spawn bosses."}
			var settings := _parse_boss_settings(parts)
			settings["replace_existing"] = true
			if not settings.has("boss_id"):
				settings["boss_id"] = 0
			var ok := bool(world.spawn_boss(settings))
			var replace_message := "boss replaced %s" % str(settings) if ok else "Boss replace rejected."
			return {"handled": true, "ok": ok, "message": replace_message}
		"despawn", "remove":
			if not world.has_method("despawn_boss"):
				return {"handled": true, "ok": false, "message": "Current scene cannot despawn bosses."}
			var boss_id := int(parts[2]) if parts.size() >= 3 and parts[2].is_valid_int() else 0
			var ok := bool(world.despawn_boss(boss_id))
			var despawn_message := "boss %d despawned" % boss_id if ok else "No boss %d exists." % boss_id
			return {"handled": true, "ok": ok, "message": despawn_message}
		"status":
			return {"handled": true, "ok": true, "message": _get_boss_status_message(world)}
		"help":
			return {"handled": true, "ok": true, "message": _boss_command_help()}
		_:
			return {"handled": true, "ok": false, "message": _boss_command_help()}


func _parse_boss_settings(parts: PackedStringArray) -> Dictionary:
	var settings := {}
	for i in range(2, parts.size()):
		var token := parts[i]
		var key := ""
		var value := ""
		if token.find("=") >= 0:
			var pair := token.split("=", false, 1)
			key = pair[0].to_lower()
			value = pair[1]
		elif token.is_valid_int() and not settings.has("max_health"):
			key = "health"
			value = token
		else:
			continue
		match key:
			"id", "boss_id":
				if value.is_valid_int():
					settings["boss_id"] = int(value)
			"health", "max_health":
				if value.is_valid_int():
					settings["max_health"] = maxi(1, int(value))
			"scale", "avatar_scale":
				if value.is_valid_float():
					settings["avatar_scale"] = maxf(0.35, float(value))
			"cooldown", "cooldown_scale", "ability_cooldown_scale":
				if value.is_valid_float():
					settings["ability_cooldown_scale"] = maxf(0.25, float(value))
			"speed", "move_speed", "movement_speed", "movement_speed_scale":
				if value.is_valid_float():
					settings["movement_speed_scale"] = maxf(0.25, float(value))
			"respawn", "respawns", "respawn_enabled":
				settings["respawn_enabled"] = _parse_bool(value)
			"replace", "replace_existing", "force":
				settings["replace_existing"] = _parse_bool(value)
			"respawn_delay":
				if value.is_valid_float():
					settings["respawn_delay"] = maxf(0.1, float(value))
			"despawn_delay":
				if value.is_valid_float():
					settings["despawn_delay"] = maxf(0.1, float(value))
			"name", "display_name":
				settings["display_name"] = value.replace("_", " ")
			"blind":
				settings["blind_volley_enabled"] = value.to_lower() not in ["0", "false", "off", "no"]
			"aoe":
				settings["large_aoe_enabled"] = value.to_lower() not in ["0", "false", "off", "no"]
			"gravity", "singularity":
				settings["singularity_enabled"] = value.to_lower() not in ["0", "false", "off", "no"]
	return settings


func _parse_bool(value: String) -> bool:
	return value.to_lower() not in ["0", "false", "off", "no", "disabled"]


func _get_boss_status_message(world: Node) -> String:
	if world.has_method("get_boss_count"):
		return "boss_count=%d" % int(world.get_boss_count())
	return "boss status unavailable"


func _boss_command_help() -> String:
	return "Commands: boss spawn [health] [name=Aether_Colossus] [scale=1.0] [cooldown=1.0] [speed=1.0] [respawn=off] [replace=off] [blind=on] [aoe=on] [gravity=on], boss replace [settings], boss despawn [id], boss status"


func _on_peer_connected(id: int) -> void:
	print("[Server] Peer %d connected  (total peers: %d)" % [id, multiplayer.get_peers().size()])


func _on_peer_disconnected(id: int) -> void:
	print("[Server] Peer %d disconnected" % id)


func notify_world_ready() -> void:
	_world_ready = true
	print("[Server] World ready, processing any pending commands...")
	_poll_server_commands()

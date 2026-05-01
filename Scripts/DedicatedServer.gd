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
	var file := FileAccess.open(_command_file_path, FileAccess.READ)
	if file != null:
		_command_file_offset = file.get_length()
		file.close()
	print("[Server] Command file: %s" % _command_file_path)


func _poll_server_commands() -> void:
	if _command_file_path == "":
		return
	var file := FileAccess.open(_command_file_path, FileAccess.READ)
	if file == null:
		return
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
	var result := GameSettings.apply_server_command(command)
	var message := str(result.get("message", ""))
	if bool(result.get("ok", false)):
		if message != "":
			print("[ServerCommand] %s" % message)
	else:
		print("[ServerCommand] ERROR: %s" % message)


func _on_peer_connected(id: int) -> void:
	print("[Server] Peer %d connected  (total peers: %d)" % [id, multiplayer.get_peers().size()])


func _on_peer_disconnected(id: int) -> void:
	print("[Server] Peer %d disconnected" % id)

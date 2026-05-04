extends Node

signal bot_settings_changed
signal boss_settings_changed
signal fullscreen_changed(enabled: bool)

const MIN_BOT_COUNT := 0
const MAX_BOT_COUNT := 12
const DIFFICULTIES := ["Easy", "Medium", "Hard"]

var bots_enabled: bool = true
var bot_count: int = 1
var bot_difficulty: String = "Medium"
var boss_enabled: bool = false
var boss_max_health: int = 1800
var boss_avatar_scale: float = 1.0
var boss_ability_cooldown_scale: float = 1.0
var boss_movement_speed_scale: float = 1.0
var boss_respawn_enabled: bool = false


func has_window_display() -> bool:
	return DisplayServer.get_name().to_lower() != "headless"


func is_fullscreen() -> bool:
	if not has_window_display():
		return false
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func set_fullscreen(enabled: bool) -> void:
	if not has_window_display():
		return
	var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() == target_mode:
		return
	DisplayServer.window_set_mode(target_mode)
	fullscreen_changed.emit(enabled)


func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())


func set_bot_settings(enabled: bool, count: int = bot_count, difficulty: String = bot_difficulty) -> bool:
	var normalized_count := clampi(count, MIN_BOT_COUNT, MAX_BOT_COUNT)
	var normalized_difficulty := _normalize_difficulty(difficulty)
	if not DIFFICULTIES.has(normalized_difficulty):
		normalized_difficulty = bot_difficulty if DIFFICULTIES.has(bot_difficulty) else "Medium"
	var changed := bots_enabled != enabled or bot_count != normalized_count or bot_difficulty != normalized_difficulty
	bots_enabled = enabled
	bot_count = normalized_count
	bot_difficulty = normalized_difficulty
	if changed:
		bot_settings_changed.emit()
	return changed


func set_boss_settings(
	enabled: bool,
	max_health: int = boss_max_health,
	avatar_scale: float = boss_avatar_scale,
	ability_cooldown_scale: float = boss_ability_cooldown_scale,
	movement_speed_scale: float = boss_movement_speed_scale,
	respawn_enabled: bool = boss_respawn_enabled
) -> bool:
	var normalized_health := maxi(100, max_health)
	var normalized_scale := clampf(avatar_scale, 0.5, 2.5)
	var normalized_cooldown := clampf(ability_cooldown_scale, 0.25, 3.0)
	var normalized_move_speed := clampf(movement_speed_scale, 0.25, 3.0)
	var changed := (
		boss_enabled != enabled
		or boss_max_health != normalized_health
		or not is_equal_approx(boss_avatar_scale, normalized_scale)
		or not is_equal_approx(boss_ability_cooldown_scale, normalized_cooldown)
		or not is_equal_approx(boss_movement_speed_scale, normalized_move_speed)
		or boss_respawn_enabled != respawn_enabled
	)
	boss_enabled = enabled
	boss_max_health = normalized_health
	boss_avatar_scale = normalized_scale
	boss_ability_cooldown_scale = normalized_cooldown
	boss_movement_speed_scale = normalized_move_speed
	boss_respawn_enabled = respawn_enabled
	if changed:
		boss_settings_changed.emit()
	return changed


func get_boss_spawn_settings() -> Dictionary:
	return {
		"boss_id": 0,
		"display_name": "Aether Colossus",
		"max_health": boss_max_health,
		"avatar_scale": boss_avatar_scale,
		"ability_cooldown_scale": boss_ability_cooldown_scale,
		"movement_speed_scale": boss_movement_speed_scale,
		"respawn_enabled": boss_respawn_enabled,
		"respawn_delay": 10.0,
		"despawn_delay": 5.0,
		"blind_volley_enabled": true,
		"large_aoe_enabled": true,
		"singularity_enabled": true,
	}


func apply_server_command(command: String) -> Dictionary:
	var cleaned := command.strip_edges()
	if cleaned.is_empty() or cleaned.begins_with("#"):
		return {"ok": true, "message": ""}
	var parts := cleaned.split(" ", false)
	if parts.is_empty():
		return {"ok": true, "message": ""}

	var name := parts[0].to_lower()
	match name:
		"help":
			return {"ok": true, "message": _server_command_help()}
		"status", "bot_status":
			return {"ok": true, "message": get_bot_settings_summary()}
		"bots":
			return _apply_bots_command(parts)
		"bot_count", "botcount":
			if parts.size() < 2:
				return {"ok": false, "message": "Usage: bot_count <0-12>"}
			return _apply_bot_count(parts[1])
		"bot_difficulty", "botdifficulty", "difficulty":
			if parts.size() < 2:
				return {"ok": false, "message": "Usage: bot_difficulty <Easy|Medium|Hard>"}
			return _apply_bot_difficulty(parts[1])
		_:
			return {"ok": false, "message": "Unknown server command '%s'. Try: help" % parts[0]}


func get_bot_settings_summary() -> String:
	return "bots=%s bot_count=%d bot_difficulty=%s" % [str(bots_enabled).to_lower(), bot_count, bot_difficulty]


func _apply_bots_command(parts: PackedStringArray) -> Dictionary:
	if parts.size() < 2:
		return {"ok": true, "message": get_bot_settings_summary()}
	var value := parts[1].to_lower()
	if value in ["on", "true", "yes", "1", "enable", "enabled"]:
		set_bot_settings(true, maxi(bot_count, 1), bot_difficulty)
		return {"ok": true, "message": get_bot_settings_summary()}
	if value in ["off", "false", "no", "0", "disable", "disabled"]:
		set_bot_settings(false, bot_count, bot_difficulty)
		return {"ok": true, "message": get_bot_settings_summary()}
	if value in ["count", "number"]:
		if parts.size() < 3:
			return {"ok": false, "message": "Usage: bots count <0-12>"}
		return _apply_bot_count(parts[2])
	if value in ["difficulty", "diff"]:
		if parts.size() < 3:
			return {"ok": false, "message": "Usage: bots difficulty <Easy|Medium|Hard>"}
		return _apply_bot_difficulty(parts[2])
	if parts[1].is_valid_int():
		var count := clampi(int(parts[1]), MIN_BOT_COUNT, MAX_BOT_COUNT)
		set_bot_settings(count > 0, count, bot_difficulty)
		return {"ok": true, "message": get_bot_settings_summary()}
	return {"ok": false, "message": "Usage: bots <on|off|count|difficulty|0-12>"}


func _apply_bot_count(value: String) -> Dictionary:
	if not value.is_valid_int():
		return {"ok": false, "message": "Bot count must be a number from 0 to 12."}
	var count := clampi(int(value), MIN_BOT_COUNT, MAX_BOT_COUNT)
	set_bot_settings(count > 0, count, bot_difficulty)
	return {"ok": true, "message": get_bot_settings_summary()}


func _apply_bot_difficulty(value: String) -> Dictionary:
	var difficulty := _normalize_difficulty(value)
	if not DIFFICULTIES.has(difficulty):
		return {"ok": false, "message": "Bot difficulty must be Easy, Medium, or Hard."}
	set_bot_settings(bots_enabled, bot_count, difficulty)
	return {"ok": true, "message": get_bot_settings_summary()}


func _normalize_difficulty(value: String) -> String:
	var lower := value.strip_edges().to_lower()
	for difficulty in DIFFICULTIES:
		if difficulty.to_lower() == lower:
			return difficulty
	return value


func _server_command_help() -> String:
	return "Commands: status, bots on, bots off, bots <0-12>, bot_count <0-12>, bot_difficulty <Easy|Medium|Hard>"

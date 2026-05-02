extends CharacterBody3D

const SpellProjectileScene = preload("res://Scenes/SpellProjectile/SpellProjectile.tscn")
const MAX_HEALTH := 80
const RESPAWN_DELAY := 4.0
const MOVE_SPEED := 2.2
const STRAFE_SPEED := 1.35
const RETREAT_DISTANCE := 6.5
const CHASE_DISTANCE := 12.0
const STRAFE_FLIP_INTERVAL := 2.6
const KNOCKBACK_DECAY := 10.0
const ARENA_LIMIT := 18.0
const ENABLE_COMBAT_MOVEMENT := true
const NPC_PUSH_MULTIPLIER := 1.8
const NPC_WATER_TEST_PUSH := 10.0
const DIRECT_GRAVITY_RADIUS := 3.0
const MAX_MANA := 100.0
const MANA_REGEN_PER_SECOND := 14.0
const KILL_ZONE_Y := -12.0
const REMOTE_INTERPOLATION_DELAY := 0.14
const REMOTE_SNAPSHOT_LIMIT := 12
const REMOTE_EXTRAPOLATION_LIMIT := 0.2
const NPC_BODY_COLOR := Color(0.18, 0.07, 0.22)
const NPC_EMISSION_COLOR := Color(1.0, 0.18, 0.82)
const NPC_LABEL_COLOR := Color(1.0, 0.48, 0.92)

var target: Node3D
var _cooldown: float = 1.6
var _timer: float = 0.7
var _health: int = MAX_HEALTH
var _is_dead: bool = false
var _respawn_timer: float = 0.0
var _spawn_position: Vector3
var _knockback_velocity: Vector3 = Vector3.ZERO
var _strafe_dir: float = 1.0
var _strafe_timer: float = 0.0
var _blind_timer: float = 0.0
var _attack_index: int = 0
var _body: Node3D
var _collision_shape: CollisionShape3D
var _health_label: Label3D
var _cast_origin: Node3D
var _net_sync_timer: float = 0.0
var _spell_loadout_data: Array = []
var _difficulty_data: Dictionary = {"difficulty": "Medium", "cast_cooldown": 3.0, "spell_budget": 120, "cast_when_ready": false}
var _mana: float = MAX_MANA
var _remote_snapshots: Array[Dictionary] = []
var _remote_clock_offset: float = 0.0
var _has_remote_clock_offset: bool = false
var _remote_clock_samples: int = 0


func _ready() -> void:
	_spawn_position = global_position
	_strafe_dir = 1.0 if randi() % 2 == 0 else -1.0
	_strafe_timer = randf_range(0.6, STRAFE_FLIP_INTERVAL)
	_build_body()


func _build_body() -> void:
	_body = Node3D.new()
	add_child(_body)

	_collision_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.5
	_collision_shape.shape = capsule
	_collision_shape.position.y = 0.75
	add_child(_collision_shape)

	var mesh_inst := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.5
	mesh_inst.mesh = mesh
	mesh_inst.position.y = 0.75
	var mat := StandardMaterial3D.new()
	mat.albedo_color = NPC_BODY_COLOR
	mat.emission_enabled = true
	mat.emission = NPC_EMISSION_COLOR
	mat.emission_energy_multiplier = 0.25
	mesh_inst.material_override = mat
	_body.add_child(mesh_inst)

	_health_label = Label3D.new()
	_health_label.position = Vector3(0.0, 1.9, 0.0)
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_label.font_size = 36
	_health_label.modulate = NPC_LABEL_COLOR
	add_child(_health_label)
	_update_health_label()

	_cast_origin = Node3D.new()
	_cast_origin.position = Vector3(0.0, 1.25, -0.45)
	add_child(_cast_origin)

	var marker := MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.11
	marker_mesh.height = 0.22
	marker.mesh = marker_mesh
	marker.material_override = mat
	_cast_origin.add_child(marker)


func _process(delta: float) -> void:
	if _is_network_client():
		_update_remote_visual_transform(delta)
		return
	if _blind_timer > 0.0:
		_blind_timer = maxf(0.0, _blind_timer - delta)
		_update_health_label()
	if _is_dead:
		_respawn_timer -= delta
		if _health_label != null:
			_health_label.text = "Respawn %.1f" % maxf(_respawn_timer, 0.0)
		if _respawn_timer <= 0.0:
			_respawn()
		return
	if target == null or not is_instance_valid(target):
		return
	_mana = minf(MAX_MANA, _mana + MANA_REGEN_PER_SECOND * delta)
	var flat_target := Vector3(target.global_position.x, global_position.y, target.global_position.z)
	if _blind_timer <= 0.0 and global_position.distance_squared_to(flat_target) > 0.01:
		look_at(flat_target, Vector3.UP)

	if _blind_timer > 0.0:
		return

	if bool(_difficulty_data.get("cast_when_ready", false)):
		_try_fire_at_target()
	else:
		_timer -= delta
		if _timer <= 0.0:
			_timer = float(_difficulty_data.get("cast_cooldown", _cooldown))
			_try_fire_at_target()


func _physics_process(delta: float) -> void:
	if _is_network_client():
		return
	if not _is_dead and global_position.y < KILL_ZONE_Y:
		_die()
	if _is_dead:
		_sync_network_state(delta)
		return
	var flat_target := global_position
	if target != null and is_instance_valid(target):
		flat_target = Vector3(target.global_position.x, global_position.y, target.global_position.z)
	_update_movement(delta, flat_target)
	_sync_network_state(delta)


func _update_movement(delta: float, flat_target: Vector3) -> void:
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_dir *= -1.0
		_strafe_timer = randf_range(STRAFE_FLIP_INTERVAL * 0.65, STRAFE_FLIP_INTERVAL * 1.35)

	var desired_velocity := Vector3.ZERO
	if ENABLE_COMBAT_MOVEMENT:
		var to_target := flat_target - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance > 0.01:
			var target_dir := to_target / distance
			if distance > CHASE_DISTANCE:
				desired_velocity += target_dir * MOVE_SPEED
			elif distance < RETREAT_DISTANCE:
				desired_velocity -= target_dir * MOVE_SPEED

			var strafe_dir := Vector3(-target_dir.z, 0.0, target_dir.x) * _strafe_dir
			desired_velocity += strafe_dir * STRAFE_SPEED

	var control_scale := clampf(1.0 - (_knockback_velocity.length() / 12.0), 0.2, 1.0)
	var final_velocity := desired_velocity * control_scale + _knockback_velocity
	velocity.x = final_velocity.x
	velocity.y = 0.0
	velocity.z = final_velocity.z
	move_and_slide()

	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	global_position.x = clampf(global_position.x, -ARENA_LIMIT, ARENA_LIMIT)
	global_position.z = clampf(global_position.z, -ARENA_LIMIT, ARENA_LIMIT)
	global_position.y = _spawn_position.y


func _try_fire_at_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	var spell := _peek_next_attack_spell()
	if spell == null:
		return
	var mana_cost := spell.calculate_mana_cost()
	if _mana + 0.001 < mana_cost:
		return
	_mana = maxf(0.0, _mana - mana_cost)
	var aim_point := target.global_position + Vector3.UP * 1.1
	var dir := aim_point - _cast_origin.global_position
	if dir.length_squared() < 0.01:
		return
	_attack_index += 1

	var world := get_tree().current_scene
	if world != null and world.has_method("spawn_network_projectile"):
		world.spawn_network_projectile(spell, _cast_origin.global_position, dir.normalized(), self)
		return
	var projectile := SpellProjectileScene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.initialize(spell, _cast_origin.global_position, dir.normalized(), self)


func _peek_next_attack_spell() -> SpellDefinition:
	if _spell_loadout_data.is_empty():
		return _create_default_attack_spell(_attack_index)
	var data := _spell_loadout_data[_attack_index % _spell_loadout_data.size()] as Dictionary
	return _spell_from_dict(data)


func _create_next_attack_spell() -> SpellDefinition:
	if not _spell_loadout_data.is_empty():
		var data := _spell_loadout_data[_attack_index % _spell_loadout_data.size()] as Dictionary
		_attack_index += 1
		return _spell_from_dict(data)
	var spell := _create_default_attack_spell(_attack_index)
	_attack_index += 1
	return spell


func _create_default_attack_spell(index: int) -> SpellDefinition:
	var spell := SpellDefinition.new()
	match index % 4:
		0:
			spell.spell_name = "NPC Fire"
			spell.base_element = "Fire"
			spell.base_weights = {"Fire": 100}
			spell.shape = "Sphere"
			spell.intensity = 2
			spell.spell_size = 2
			spell.spell_range = 7
			spell.spell_speed = 4
			spell.burns = true
		1:
			spell.spell_name = "NPC Water Push"
			spell.base_element = "Water"
			spell.base_weights = {"Water": 100}
			spell.shape = "Sphere"
			spell.intensity = 2
			spell.spell_size = 2
			spell.spell_range = 7
			spell.spell_speed = 4
			spell.pushes = true
		2:
			spell.spell_name = "NPC Light Flash"
			spell.base_element = "Light"
			spell.base_weights = {"Light": 100}
			spell.shape = "Sphere"
			spell.intensity = 2
			spell.spell_size = 3
			spell.spell_range = 7
			spell.spell_speed = 5
			spell.has_illusion = true
		_:
			spell.spell_name = "NPC Singularity"
			spell.base_element = "Void"
			spell.base_weights = {"Void": 50, "Earth": 50}
			spell.shape = "Sphere"
			spell.intensity = 2
			spell.spell_size = 3
			spell.spell_range = 7
			spell.spell_speed = 3
			spell.has_pull = true
			spell.pull_strength = 3
	return spell


func set_spell_loadout_data(loadout_data: Array) -> void:
	_spell_loadout_data = loadout_data.duplicate(true)


func get_spell_loadout_data() -> Array:
	return _spell_loadout_data.duplicate(true)


func set_difficulty_data(difficulty_data: Dictionary) -> void:
	_difficulty_data = difficulty_data.duplicate(true)
	_cooldown = float(_difficulty_data.get("cast_cooldown", _cooldown))
	_timer = randf_range(0.4, maxf(_cooldown, 0.8))


func get_difficulty_data() -> Dictionary:
	return _difficulty_data.duplicate(true)


func _spell_from_dict(data: Dictionary) -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = str(data.get("spell_name", "Bot Spell"))
	spell.base_element = str(data.get("base_element", ""))
	spell.base_weights = (data.get("base_weights", {}) as Dictionary).duplicate()
	spell.shape = str(data.get("shape", "Sphere"))
	spell.intensity = int(data.get("intensity", 1))
	spell.spell_size = int(data.get("spell_size", 1))
	spell.spell_range = int(data.get("spell_range", 1))
	spell.spell_speed = int(data.get("spell_speed", 1))
	spell.has_charging = bool(data.get("has_charging", false))
	spell.burns = bool(data.get("burns", false))
	spell.cools = bool(data.get("cools", false))
	spell.pushes = bool(data.get("pushes", false))
	spell.blows = bool(data.get("blows", false))
	spell.heals = bool(data.get("heals", false))
	spell.has_density = bool(data.get("has_density", false))
	spell.density = int(data.get("density", 1))
	spell.has_illusion = bool(data.get("has_illusion", false))
	spell.has_pull = bool(data.get("has_pull", false))
	spell.pull_strength = int(data.get("pull_strength", 1))
	return spell


func apply_spell_hit(spell: SpellDefinition, _hit_position: Vector3, _hit_normal: Vector3, is_beam_tick: bool = false) -> void:
	if spell == null or _is_dead:
		return
	if spell.is_blind_spell():
		apply_blind(spell.calculate_blind_duration(is_beam_tick))
	_apply_pushback(spell, _hit_position, _hit_normal, is_beam_tick)
	_apply_gravity_pull(_hit_position, spell, DIRECT_GRAVITY_RADIUS, is_beam_tick)
	var healing := spell.calculate_healing(is_beam_tick)
	if healing > 0:
		_health = mini(MAX_HEALTH, _health + healing)
	else:
		_health = maxi(0, _health - spell.calculate_damage(is_beam_tick))
	_update_health_label()
	if _health <= 0:
		_die()


func apply_blind(duration: float) -> void:
	if duration <= 0.0 or _is_dead:
		return
	_blind_timer = maxf(_blind_timer, duration)
	_update_health_label()


func _update_health_label() -> void:
	if _health_label != null:
		if _blind_timer > 0.0:
			_health_label.text = "BLINDED %.1f" % _blind_timer
		else:
			_health_label.text = "%d / %d" % [_health, MAX_HEALTH]


func _die() -> void:
	_is_dead = true
	_respawn_timer = RESPAWN_DELAY
	_knockback_velocity = Vector3.ZERO
	_blind_timer = 0.0
	_timer = _cooldown
	if _body != null:
		_body.visible = false
	if _collision_shape != null:
		_collision_shape.disabled = true
	collision_layer = 0
	collision_mask = 0
	if _health_label != null:
		_health_label.visible = true
		_health_label.text = "Respawn %.1f" % RESPAWN_DELAY


func _respawn() -> void:
	_is_dead = false
	_health = MAX_HEALTH
	_knockback_velocity = Vector3.ZERO
	_blind_timer = 0.0
	global_position = _spawn_position
	velocity = Vector3.ZERO
	if _body != null:
		_body.visible = true
	if _collision_shape != null:
		_collision_shape.disabled = false
	collision_layer = 1
	collision_mask = 1
	_update_health_label()


func _apply_pushback(spell: SpellDefinition, hit_position: Vector3, hit_normal: Vector3, is_beam_tick: bool) -> void:
	if not spell.get_base_elements().has("Water"):
		return
	var minimum_push := NPC_WATER_TEST_PUSH * (0.45 if is_beam_tick else 1.0)
	var force := maxf(minimum_push, spell.calculate_push_force(is_beam_tick) * NPC_PUSH_MULTIPLIER)
	var push_dir := global_position - hit_position
	push_dir.y = 0.0
	if push_dir.length_squared() < 0.01:
		push_dir = -hit_normal
	push_dir.y = 0.0
	if push_dir.length_squared() < 0.01:
		push_dir = -global_basis.z
	_knockback_velocity += push_dir.normalized() * force


func apply_gravity_pull(center: Vector3, spell: SpellDefinition, radius: float, is_beam_tick: bool = false) -> void:
	if spell == null or _is_dead:
		return
	_apply_gravity_pull(center, spell, radius, is_beam_tick)


func _apply_gravity_pull(center: Vector3, spell: SpellDefinition, radius: float, is_beam_tick: bool) -> void:
	var pull_dir := center - global_position
	pull_dir.y = 0.0
	var distance := pull_dir.length()
	if distance < 0.05:
		return
	var force := spell.calculate_gravity_force(distance, radius, is_beam_tick)
	if force <= 0.0:
		return
	_knockback_velocity += pull_dir.normalized() * force


func _is_network_client() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.is_server()


func _sync_network_state(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_net_sync_timer -= delta
	if _net_sync_timer > 0.0:
		return
	_net_sync_timer = 0.1
	_client_receive_state.rpc(global_position, rotation.y, _health, _is_dead, _blind_timer, _network_time())


@rpc("authority", "unreliable")
func _client_receive_state(pos: Vector3, yaw: float, health: int, is_dead: bool, blind_timer: float, timestamp: float = -1.0) -> void:
	if multiplayer.is_server():
		return
	_health = health
	_is_dead = is_dead
	_blind_timer = blind_timer
	_add_remote_snapshot(pos, yaw, timestamp if timestamp >= 0.0 else _network_time())
	if _body != null:
		_body.visible = not _is_dead
	if _collision_shape != null:
		_collision_shape.disabled = _is_dead
	_update_health_label()


func _add_remote_snapshot(pos: Vector3, yaw: float, timestamp: float) -> void:
	var local_time := _network_time()
	var measured_offset := local_time - timestamp
	if not _has_remote_clock_offset:
		_remote_clock_offset = measured_offset
		_has_remote_clock_offset = true
	else:
		_remote_clock_samples += 1
		var alpha := 0.15 if _remote_clock_samples < 30 else 0.03
		_remote_clock_offset = lerpf(_remote_clock_offset, measured_offset, alpha)
	_remote_snapshots.append({
		"t": timestamp + _remote_clock_offset,
		"pos": pos,
		"yaw": yaw,
	})
	while _remote_snapshots.size() > REMOTE_SNAPSHOT_LIMIT:
		_remote_snapshots.pop_front()
	if _remote_snapshots.size() == 1:
		global_position = pos
		rotation.y = yaw


func _update_remote_visual_transform(_delta: float) -> void:
	if _remote_snapshots.is_empty():
		return
	var render_time := _network_time() - REMOTE_INTERPOLATION_DELAY
	if _remote_snapshots.size() == 1:
		_apply_remote_snapshot(_remote_snapshots[0])
		return
	for i in range(1, _remote_snapshots.size()):
		var older: Dictionary = _remote_snapshots[i - 1]
		var newer: Dictionary = _remote_snapshots[i]
		if float(older["t"]) <= render_time and float(newer["t"]) >= render_time:
			var span := maxf(float(newer["t"]) - float(older["t"]), 0.001)
			var t := clampf((render_time - float(older["t"])) / span, 0.0, 1.0)
			global_position = (older["pos"] as Vector3).lerp(newer["pos"] as Vector3, t)
			rotation.y = lerp_angle(float(older["yaw"]), float(newer["yaw"]), t)
			return
	var latest: Dictionary = _remote_snapshots[_remote_snapshots.size() - 1]
	var previous: Dictionary = _remote_snapshots[_remote_snapshots.size() - 2]
	var elapsed := clampf(render_time - float(latest["t"]), 0.0, REMOTE_EXTRAPOLATION_LIMIT)
	var span := maxf(float(latest["t"]) - float(previous["t"]), 0.001)
	var estimated_velocity := ((latest["pos"] as Vector3) - (previous["pos"] as Vector3)) / span
	global_position = latest["pos"] as Vector3 + estimated_velocity * elapsed
	rotation.y = float(latest["yaw"])


func _apply_remote_snapshot(snapshot: Dictionary) -> void:
	global_position = snapshot["pos"] as Vector3
	rotation.y = float(snapshot["yaw"])


func _network_time() -> float:
	return Time.get_ticks_msec() / 1000.0

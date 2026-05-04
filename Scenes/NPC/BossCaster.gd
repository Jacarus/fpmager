extends Node3D

const SpellImpactEffectScript = preload("res://Scripts/SpellImpactEffect.gd")

const DEFAULT_SETTINGS := {
	"boss_id": 0,
	"display_name": "Aether Colossus",
	"max_health": 1800,
	"avatar_scale": 1.0,
	"ability_cooldown_scale": 1.0,
	"spawn_position": Vector3(0, 0.0, -14),
	"blind_volley_enabled": true,
	"large_aoe_enabled": true,
	"singularity_enabled": true,
	"respawn_enabled": false,
	"respawn_delay": 10.0,
	"despawn_delay": 5.0,
	"movement_speed_scale": 1.0,
}
const PART_SPECS := {
	"core": {
		"display_name": "Core",
		"ability": "large_aoe",
		"health": 650,
		"position": Vector3(0.0, 2.55, 0.0),
		"size": Vector3(1.75, 2.35, 0.9),
		"color": Color(0.32, 0.11, 0.42),
	},
	"head": {
		"display_name": "Crown",
		"ability": "command",
		"health": 360,
		"position": Vector3(0.0, 4.25, 0.0),
		"size": Vector3(1.1, 0.75, 0.85),
		"color": Color(0.48, 0.18, 0.58),
	},
	"left_arm": {
		"display_name": "Prism Arm",
		"ability": "blind_volley",
		"health": 420,
		"position": Vector3(-1.55, 2.95, 0.0),
		"size": Vector3(0.65, 2.15, 0.65),
		"color": Color(0.92, 0.82, 0.25),
	},
	"right_arm": {
		"display_name": "Gravity Arm",
		"ability": "singularity",
		"health": 420,
		"position": Vector3(1.55, 2.95, 0.0),
		"size": Vector3(0.65, 2.15, 0.65),
		"color": Color(0.28, 0.09, 0.62),
	},
	"feet": {
		"display_name": "Anchor Feet",
		"ability": "movement",
		"health": 300,
		"position": Vector3(0.0, 0.55, 0.0),
		"size": Vector3(1.85, 0.65, 0.95),
		"color": Color(0.18, 0.08, 0.24),
	},
}
const DEFAULT_PART_HEALTH_TOTAL := 2150
const SYNC_INTERVAL := 0.12
const ARENA_LIMIT := 17.0
const PRISM_VOLLEY_WINDUP := 0.75
const CATACLYSM_WINDUP := 2.2
const GRAVITY_WELL_WINDUP := 1.45
const DEFAULT_RESPAWN_DELAY := 10.0
const DEFAULT_DESPAWN_DELAY := 5.0
const CATACLYSM_RADIUS := 6.4
const GRAVITY_WELL_RADIUS := 7.7
const SELF_DAMAGE_MARGIN := 1.5
const AI_THINK_INTERVAL := 0.35
const BOSS_MOVE_SPEED := 1.55
const BOSS_STRAFE_SPEED := 0.95
const BOSS_ACCELERATION := 3.0
const PREFERRED_DISTANCE_MIN := 7.0
const PREFERRED_DISTANCE_MAX := 13.5
const TARGET_STICKY_SCORE := 18.0
const CLUSTER_RADIUS := 7.0
const DEATH_ANIMATION_DURATION := 1.25

var target: Node3D
var _settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var _boss_id: int = 0
var _display_name: String = "Aether Colossus"
var _max_health: int = 1800
var _health: int = 1800
var _is_dead: bool = false
var _death_timer: float = 0.0
var _sync_timer: float = 0.0
var _ability_timers: Dictionary = {}
var _parts: Dictionary = {}
var _part_health: Dictionary = {}
var _part_max_health: Dictionary = {}
var _part_destroyed: Dictionary = {}
var _part_labels: Dictionary = {}
var _health_label: Label3D
var _name_label: Label3D
var _body_root: Node3D
var _death_burst: MeshInstance3D
var _death_burst_material: StandardMaterial3D
var _death_anim_time: float = 0.0
var _death_anim_active: bool = false
var _left_cast_origin: Node3D
var _right_cast_origin: Node3D
var _core_cast_origin: Node3D
var _pending_attacks: Array[Dictionary] = []
var _next_telegraph_id: int = 1
var _spawn_position: Vector3 = Vector3.ZERO
var _movement_velocity: Vector3 = Vector3.ZERO
var _ai_think_timer: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_timer: float = 0.0
var _last_attack_type: String = ""
var _despawn_requested: bool = false


class BossPart:
	extends StaticBody3D

	var boss: Node
	var part_id: String = ""

	func setup(owner_boss: Node, id: String) -> void:
		boss = owner_boss
		part_id = id

	func apply_spell_hit(spell: SpellDefinition, hit_position: Vector3, hit_normal: Vector3, is_beam_tick: bool = false) -> void:
		if is_instance_valid(boss) and boss.has_method("apply_part_spell_hit"):
			boss.apply_part_spell_hit(part_id, spell, hit_position, hit_normal, is_beam_tick)

	func is_damageable() -> bool:
		if not is_instance_valid(boss) or not boss.has_method("is_part_damageable"):
			return false
		return bool(boss.is_part_damageable(part_id))

	func apply_blind(_duration: float) -> void:
		pass

	func apply_gravity_pull(_center: Vector3, _spell: SpellDefinition, _radius: float, _is_beam_tick: bool = false) -> void:
		pass


class BossAttackTelegraph:
	extends Node3D

	var _label_text: String = ""
	var _radius: float = 1.0
	var _duration: float = 1.0
	var _age: float = 0.0
	var _mesh_instance: MeshInstance3D
	var _material: StandardMaterial3D
	var _label: Label3D
	var _light: OmniLight3D

	func setup(label_text: String, pos: Vector3, radius: float, duration: float, color: Color) -> void:
		_label_text = label_text
		_radius = maxf(0.2, radius)
		_duration = maxf(0.1, duration)
		global_position = pos

		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(color.r, color.g, color.b, 0.28)
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.emission_enabled = true
		_material.emission = color
		_material.emission_energy_multiplier = 0.9
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		_mesh_instance = MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 1.0
		mesh.bottom_radius = 1.0
		mesh.height = 0.06
		_mesh_instance.mesh = mesh
		_mesh_instance.material_override = _material
		add_child(_mesh_instance)

		_light = OmniLight3D.new()
		_light.light_color = color
		_light.light_energy = 1.2
		_light.omni_range = _radius * 1.8
		add_child(_light)

		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.position.y = 0.55
		_label.font_size = 26
		_label.modulate = Color(1.0, 0.92, 0.72)
		add_child(_label)
		_update_visuals()

	func _process(delta: float) -> void:
		_age += delta
		_update_visuals()
		if _age >= _duration:
			queue_free()

	func _update_visuals() -> void:
		var t := clampf(_age / _duration, 0.0, 1.0)
		var pulse := 1.0 + sin(_age * 18.0) * 0.04
		var settle := lerpf(0.72, 1.0, ease(t, -1.4))
		if _mesh_instance != null:
			_mesh_instance.scale = Vector3(_radius * settle * pulse, 1.0, _radius * settle * pulse)
		if _material != null:
			_material.albedo_color.a = lerpf(0.18, 0.48, t)
			_material.emission_energy_multiplier = lerpf(0.75, 1.8, t)
		if _light != null:
			_light.light_energy = lerpf(0.5, 2.0, t)
		if _label != null:
			_label.text = "%s %.1f" % [_label_text, maxf(0.0, _duration - _age)]
			_label.modulate.a = lerpf(0.75, 1.0, t)


func configure(settings: Dictionary) -> void:
	_settings = DEFAULT_SETTINGS.duplicate(true)
	for key in settings.keys():
		_settings[key] = settings[key]
	_boss_id = int(_settings.get("boss_id", 0))
	_display_name = str(_settings.get("display_name", "Aether Colossus"))
	_max_health = max(1, int(_settings.get("max_health", 1800)))
	_health = _max_health
	position = _settings.get("spawn_position", position) as Vector3
	_spawn_position = position


func get_boss_id() -> int:
	return _boss_id


func get_settings_data() -> Dictionary:
	return _settings.duplicate(true)


func _ready() -> void:
	configure(_settings)
	_build_avatar()
	_reset_abilities()
	_update_labels()
	_update_world_hud()


func _process(delta: float) -> void:
	_update_death_animation(delta)
	if _is_network_client():
		return
	if _is_dead:
		_death_timer -= delta
		if _death_timer <= 0.0:
			if bool(_settings.get("respawn_enabled", false)):
				_respawn()
				return
			_request_world_despawn()
			return
		_update_labels()
		_sync_network_state(delta)
		return
	_tick_ai(delta)
	_tick_pending_attacks(delta)
	_sync_network_state(delta)


func _build_avatar() -> void:
	var avatar_scale := maxf(0.35, float(_settings.get("avatar_scale", 1.0)))
	scale = Vector3.ONE * avatar_scale
	_body_root = Node3D.new()
	_body_root.name = "Body"
	add_child(_body_root)

	_name_label = Label3D.new()
	_name_label.position = Vector3(0.0, 5.35, 0.0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.font_size = 42
	_name_label.modulate = Color(1.0, 0.86, 0.45)
	add_child(_name_label)

	_health_label = Label3D.new()
	_health_label.position = Vector3(0.0, 4.85, 0.0)
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_label.font_size = 34
	_health_label.modulate = Color(1.0, 0.45, 0.38)
	add_child(_health_label)

	_add_part("core")
	_add_part("head")
	_add_part("left_arm")
	_add_part("right_arm")
	_add_part("feet")
	_add_leg(Vector3(-0.55, 0.95, 0.0))
	_add_leg(Vector3(0.55, 0.95, 0.0))

	_left_cast_origin = _add_cast_origin(Vector3(-2.05, 3.2, -0.25), Color(1.0, 0.95, 0.35))
	_right_cast_origin = _add_cast_origin(Vector3(2.05, 3.2, -0.25), Color(0.45, 0.16, 1.0))
	_core_cast_origin = _add_cast_origin(Vector3(0.0, 3.0, -0.65), Color(1.0, 0.2, 0.1))
	_build_death_burst()


func _build_death_burst() -> void:
	_death_burst_material = StandardMaterial3D.new()
	_death_burst_material.albedo_color = Color(1.0, 0.25, 0.1, 0.0)
	_death_burst_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_death_burst_material.emission_enabled = true
	_death_burst_material.emission = Color(1.0, 0.22, 0.08)
	_death_burst_material.emission_energy_multiplier = 0.0
	_death_burst_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_death_burst = MeshInstance3D.new()
	_death_burst.name = "DeathBurst"
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	_death_burst.mesh = mesh
	_death_burst.material_override = _death_burst_material
	_death_burst.position.y = 2.45
	_death_burst.visible = false
	add_child(_death_burst)


func _add_part(part_id: String) -> void:
	var spec: Dictionary = PART_SPECS[part_id]
	var part := BossPart.new()
	part.name = "BossPart_%s" % part_id
	part.setup(self, part_id)
	part.position = spec["position"] as Vector3
	part.collision_layer = 1
	part.collision_mask = 1
	_body_root.add_child(part)
	_parts[part_id] = part
	var max_part_health := _get_scaled_part_max_health(part_id)
	_part_max_health[part_id] = max_part_health
	_part_health[part_id] = max_part_health
	_part_destroyed[part_id] = false

	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = spec["size"] as Vector3
	shape_node.shape = shape
	part.add_child(shape_node)

	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = spec["size"] as Vector3
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _make_material(spec["color"] as Color)
	part.add_child(mesh_inst)

	var label := Label3D.new()
	label.position.y = (spec["size"] as Vector3).y * 0.5 + 0.25
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 20
	label.modulate = Color(1.0, 0.92, 0.68)
	part.add_child(label)
	_part_labels[part_id] = label


func _get_scaled_part_max_health(part_id: String) -> int:
	if not PART_SPECS.has(part_id):
		return 1
	var spec: Dictionary = PART_SPECS[part_id]
	var base_health := maxf(1.0, float(spec.get("health", 1)))
	var scaled := roundf(float(_max_health) * base_health / float(DEFAULT_PART_HEALTH_TOTAL))
	return maxi(1, int(scaled))


func _add_leg(pos: Vector3) -> void:
	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.52, 1.9, 0.62)
	mesh_inst.position = pos
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _make_material(Color(0.2, 0.09, 0.28))
	_body_root.add_child(mesh_inst)


func _add_cast_origin(pos: Vector3, color: Color) -> Node3D:
	var origin := Node3D.new()
	origin.position = pos
	add_child(origin)
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	marker.mesh = mesh
	marker.material_override = _make_material(color, 1.6)
	origin.add_child(marker)
	return origin


func _make_material(color: Color, emission_scale: float = 0.55) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission_scale
	mat.roughness = 0.5
	return mat


func _reset_abilities() -> void:
	var scale_value := _cooldown_scale()
	_ability_timers = {
		"blind_volley": 3.0 * scale_value,
		"large_aoe": 6.0 * scale_value,
		"singularity": 8.0 * scale_value,
	}
	_ai_think_timer = randf_range(0.1, AI_THINK_INTERVAL)
	_strafe_dir = 1.0 if randi() % 2 == 0 else -1.0
	_strafe_timer = randf_range(1.2, 2.8)


func _tick_ai(delta: float) -> void:
	_tick_ability_cooldowns(delta)
	target = _choose_target()
	_update_movement(delta)
	_update_facing(delta)
	_ai_think_timer -= delta
	if _ai_think_timer <= 0.0:
		_ai_think_timer = AI_THINK_INTERVAL
		_choose_and_cast_attack()


func _tick_ability_cooldowns(delta: float) -> void:
	for key in _ability_timers.keys():
		_ability_timers[key] = float(_ability_timers[key]) - delta


func _choose_and_cast_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if _pending_attacks.size() >= 3:
		return
	var candidates: Array[Dictionary] = []
	var target_distance := _flat_distance_to(target)
	var cluster_count := _count_players_near(target.global_position, CLUSTER_RADIUS)
	var cataclysm_pos := _find_safe_ground_attack_position(target.global_position, CATACLYSM_RADIUS)
	var has_cataclysm_pos := _is_safe_ground_attack_position(cataclysm_pos, CATACLYSM_RADIUS)
	var gravity_points := _get_map_pressure_points(3, GRAVITY_WELL_RADIUS)
	if _ability_ready("blind_volley", "left_arm", "blind_volley_enabled"):
		candidates.append({
			"type": "blind_volley",
			"score": 28.0 + (8.0 if target_distance > 6.0 and target_distance < 18.0 else 0.0) + float(cluster_count) * 5.0,
		})
	if _ability_ready("large_aoe", "core", "large_aoe_enabled") and has_cataclysm_pos:
		candidates.append({
			"type": "large_aoe",
			"score": 22.0 + float(cluster_count) * 22.0 + (10.0 if target_distance < 11.0 else 0.0),
		})
	if _ability_ready("singularity", "right_arm", "singularity_enabled") and not gravity_points.is_empty():
		candidates.append({
			"type": "singularity",
			"score": 30.0 + (18.0 if target_distance > 10.0 else 0.0) + float(cluster_count) * 8.0,
		})
	if candidates.is_empty():
		return
	var chosen := _pick_weighted_attack(candidates)
	match str(chosen.get("type", "")):
		"blind_volley":
			_cast_blind_volley()
			_ability_timers["blind_volley"] = 7.0 * _cooldown_scale()
		"large_aoe":
			_cast_large_aoe()
			_ability_timers["large_aoe"] = 12.0 * _cooldown_scale()
		"singularity":
			_cast_singularity_barrage()
			_ability_timers["singularity"] = 10.0 * _cooldown_scale()
	_last_attack_type = str(chosen.get("type", ""))


func _pick_weighted_attack(candidates: Array[Dictionary]) -> Dictionary:
	var total := 0.0
	for candidate in candidates:
		var score := maxf(1.0, float(candidate.get("score", 1.0)))
		if str(candidate.get("type", "")) == _last_attack_type:
			score *= 0.55
		candidate["score"] = score
		total += score
	var roll := randf() * maxf(total, 0.001)
	var cursor := 0.0
	for candidate in candidates:
		cursor += float(candidate.get("score", 1.0))
		if roll <= cursor:
			return candidate
	return candidates[candidates.size() - 1]


func _ability_ready(ability: String, part_id: String, setting_key: String) -> bool:
	if not bool(_settings.get(setting_key, true)):
		return false
	if _is_part_destroyed(part_id):
		return false
	return float(_ability_timers.get(ability, 0.0)) <= 0.0


func _cooldown_scale() -> float:
	var scale_value := float(_settings.get("ability_cooldown_scale", 1.0))
	return clampf(scale_value, 0.25, 5.0)


func _movement_speed_scale() -> float:
	return clampf(float(_settings.get("movement_speed_scale", 1.0)), 0.2, 3.0)


func _cast_blind_volley() -> void:
	var spell := _make_spell("Boss Prism Split", {"Light": 100}, 4, 4, 12, 4, {"has_illusion": true})
	var positions := _get_map_pressure_points(5)
	var targets: Array[Vector3] = []
	for pos in positions:
		targets.append(pos + Vector3.UP * 1.0)
	_schedule_pending_attack({
		"type": "projectile_volley",
		"required_part": "left_arm",
		"spell": spell,
		"origin_part": "left_arm",
		"targets": targets,
		"remaining": PRISM_VOLLEY_WINDUP,
	})
	_spawn_attack_telegraph("Prism Split", _left_cast_origin.global_position, 1.2, PRISM_VOLLEY_WINDUP, Color(1.0, 0.94, 0.35))


func _cast_large_aoe() -> void:
	var spell := _make_spell("Boss Cataclysm", {"Fire": 50, "Earth": 50}, 6, 26, 8, 1, {"burns": true, "has_density": true, "density": 6})
	var pos := global_position
	if target != null and is_instance_valid(target):
		pos = target.global_position
	pos = _find_safe_ground_attack_position(pos, CATACLYSM_RADIUS)
	if not _is_safe_ground_attack_position(pos, CATACLYSM_RADIUS):
		return
	_schedule_pending_attack({
		"type": "impact",
		"required_part": "core",
		"spell": spell,
		"position": pos,
		"normal": Vector3.UP,
		"self_safe_radius": CATACLYSM_RADIUS,
		"remaining": CATACLYSM_WINDUP,
	})
	_spawn_attack_telegraph("Cataclysm", pos, CATACLYSM_RADIUS, CATACLYSM_WINDUP, Color(1.0, 0.28, 0.08))


func _cast_singularity_barrage() -> void:
	var spell := _make_spell("Boss Gravity Wells", {"Void": 50, "Earth": 50}, 5, 11, 8, 1, {"has_pull": true, "pull_strength": 6})
	for pos in _get_map_pressure_points(3, GRAVITY_WELL_RADIUS):
		_schedule_pending_attack({
			"type": "impact",
			"required_part": "right_arm",
			"spell": spell,
			"position": pos,
			"normal": Vector3.UP,
			"self_safe_radius": GRAVITY_WELL_RADIUS,
			"remaining": GRAVITY_WELL_WINDUP,
		})
		_spawn_attack_telegraph("Gravity Well", pos, GRAVITY_WELL_RADIUS, GRAVITY_WELL_WINDUP, Color(0.48, 0.12, 1.0))


func _get_map_pressure_points(count: int, safe_radius: float = 0.0) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var players := _get_player_targets()
	for player in players:
		if points.size() >= count:
			break
		var p := (player as Node3D).global_position
		var point := _clamp_ground_position(p)
		if safe_radius <= 0.0 or _is_safe_ground_attack_position(point, safe_radius):
			points.append(point)
	var index := 0
	while points.size() < count and index < count * 12:
		var angle := (float(index) / maxf(1.0, float(count))) * TAU + randf_range(-0.25, 0.25)
		var radius := randf_range(5.0, 15.0)
		var point := _clamp_ground_position(Vector3(cos(angle) * radius, 0.05, sin(angle) * radius))
		if safe_radius <= 0.0 or _is_safe_ground_attack_position(point, safe_radius):
			points.append(point)
		index += 1
	return points


func _spawn_authoritative_impact(spell: SpellDefinition, pos: Vector3, normal: Vector3) -> void:
	var world := get_tree().current_scene
	if world != null and world.has_method("spawn_authoritative_spell_impact"):
		world.spawn_authoritative_spell_impact(spell, pos, normal, self)
		return
	var effect := SpellImpactEffectScript.new()
	get_tree().current_scene.add_child(effect)
	effect.initialize(spell, pos, normal, self)


func _schedule_pending_attack(data: Dictionary) -> void:
	_pending_attacks.append(data)


func _tick_pending_attacks(delta: float) -> void:
	for i in range(_pending_attacks.size() - 1, -1, -1):
		var attack := _pending_attacks[i] as Dictionary
		attack["remaining"] = float(attack.get("remaining", 0.0)) - delta
		if float(attack["remaining"]) > 0.0:
			_pending_attacks[i] = attack
			continue
		_pending_attacks.remove_at(i)
		_execute_pending_attack(attack)


func _execute_pending_attack(attack: Dictionary) -> void:
	var required_part := str(attack.get("required_part", ""))
	if required_part != "" and _is_part_destroyed(required_part):
		return
	var spell := attack.get("spell") as SpellDefinition
	if spell == null:
		return
	match str(attack.get("type", "")):
		"projectile_volley":
			var origin_part := str(attack.get("origin_part", ""))
			var source := _parts.get(origin_part) as Node
			var origin := _get_origin_for_part(origin_part)
			for target_pos in attack.get("targets", []):
				_fire_boss_projectile(spell, origin, target_pos as Vector3, source)
		"impact":
			var pos := attack.get("position", global_position) as Vector3
			var self_safe_radius := float(attack.get("self_safe_radius", 0.0))
			if self_safe_radius > 0.0 and not _is_safe_ground_attack_position(pos, self_safe_radius):
				return
			_spawn_authoritative_impact(spell, pos, attack.get("normal", Vector3.UP) as Vector3)


func _fire_boss_projectile(spell: SpellDefinition, origin: Vector3, target_pos: Vector3, source: Node) -> void:
	var direction := target_pos - origin
	if direction.length_squared() < 0.01:
		return
	if _projectile_would_self_damage(spell, origin, target_pos, source):
		return
	var world := get_tree().current_scene
	if world != null and world.has_method("spawn_network_projectile"):
		world.spawn_network_projectile(spell, origin, direction.normalized(), source if source != null else self)


func _projectile_would_self_damage(spell: SpellDefinition, origin: Vector3, target_pos: Vector3, source: Node) -> bool:
	if spell == null:
		return false
	var impact_radius := SpellImpactEffectScript.estimate_radius(spell) + SELF_DAMAGE_MARGIN
	if _flat_distance_to_position(target_pos) <= impact_radius:
		return true
	var wall_hit := _get_first_spell_wall_hit(origin, target_pos, 0.25 + spell.spell_size * 0.06)
	if not wall_hit.is_empty() and _flat_distance_to_position(wall_hit["position"] as Vector3) <= impact_radius:
		return true
	var query := PhysicsRayQueryParameters3D.create(origin, target_pos)
	query.exclude = _get_boss_collision_excludes(source)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and _flat_distance_to_position(hit["position"] as Vector3) <= impact_radius


func _get_first_spell_wall_hit(origin: Vector3, target_pos: Vector3, incoming_radius: float) -> Dictionary:
	var best_hit: Dictionary = {}
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("spell_projectile"):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("is_spell_wall") or not bool(node.is_spell_wall()):
			continue
		if node.has_method("is_spell_consumed") and bool(node.is_spell_consumed()):
			continue
		var hit: Dictionary = node.get_wall_segment_hit(origin, target_pos, incoming_radius)
		if hit.is_empty():
			continue
		var distance := origin.distance_to(hit["position"] as Vector3)
		if distance < best_distance:
			best_distance = distance
			best_hit = hit
	return best_hit


func _get_boss_collision_excludes(source: Node) -> Array:
	var excludes: Array = []
	if source is CollisionObject3D:
		excludes.append(source)
	for part in _parts.values():
		if part is CollisionObject3D and not excludes.has(part):
			excludes.append(part)
	return excludes


func _get_origin_for_part(part_id: String) -> Vector3:
	match part_id:
		"left_arm":
			return _left_cast_origin.global_position if _left_cast_origin != null else global_position + Vector3.UP * 3.0
		"right_arm":
			return _right_cast_origin.global_position if _right_cast_origin != null else global_position + Vector3.UP * 3.0
		_:
			return _core_cast_origin.global_position if _core_cast_origin != null else global_position + Vector3.UP * 2.5


func _spawn_attack_telegraph(label: String, pos: Vector3, radius: float, duration: float, color: Color) -> void:
	var telegraph_id := _next_telegraph_id
	_next_telegraph_id += 1
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_client_spawn_attack_telegraph.rpc(telegraph_id, label, pos, radius, duration, color)
	else:
		_client_spawn_attack_telegraph(telegraph_id, label, pos, radius, duration, color)


@rpc("authority", "call_local", "reliable")
func _client_spawn_attack_telegraph(telegraph_id: int, label: String, pos: Vector3, radius: float, duration: float, color: Color) -> void:
	var telegraph := BossAttackTelegraph.new()
	telegraph.name = "BossTelegraph_%d" % telegraph_id
	get_tree().current_scene.add_child(telegraph)
	telegraph.setup(label, pos, radius, duration, color)


func _make_spell(spell_name: String, weights: Dictionary, intensity: int, size: int, spell_range: int, speed: int, flags: Dictionary = {}) -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = spell_name
	spell.base_element = str(weights.keys()[0])
	spell.base_weights = weights.duplicate()
	spell.shape = "Sphere"
	spell.intensity = intensity
	spell.spell_size = size
	spell.spell_range = spell_range
	spell.spell_speed = speed
	spell.burns = bool(flags.get("burns", false))
	spell.cools = bool(flags.get("cools", false))
	spell.pushes = bool(flags.get("pushes", false))
	spell.blows = bool(flags.get("blows", false))
	spell.heals = bool(flags.get("heals", false))
	spell.has_density = bool(flags.get("has_density", false))
	spell.density = int(flags.get("density", 1))
	spell.has_illusion = bool(flags.get("has_illusion", false))
	spell.has_pull = bool(flags.get("has_pull", false))
	spell.pull_strength = int(flags.get("pull_strength", 1))
	return spell


func _choose_target() -> Node3D:
	var players := _get_player_targets()
	var best: Node3D = null
	var best_score := -INF
	for player in players:
		var node := player as Node3D
		if node == null or not _is_valid_target(node):
			continue
		var distance := _flat_distance_to(node)
		var center_distance := Vector2(node.global_position.x, node.global_position.z).length()
		var score := 100.0 - distance * 3.0 - center_distance * 0.4
		score += float(_count_players_near(node.global_position, CLUSTER_RADIUS)) * 10.0
		if node == target:
			score += TARGET_STICKY_SCORE
		if score > best_score:
			best = node
			best_score = score
	return best


func _update_movement(delta: float) -> void:
	if _is_part_destroyed("feet"):
		_movement_velocity = _movement_velocity.move_toward(Vector3.ZERO, BOSS_ACCELERATION * delta)
		return
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_dir *= -1.0
		_strafe_timer = randf_range(1.5, 3.8)
	var desired := Vector3.ZERO
	if target != null and is_instance_valid(target):
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance > 0.05:
			var target_dir := to_target / distance
			if distance > PREFERRED_DISTANCE_MAX:
				desired += target_dir * BOSS_MOVE_SPEED
			elif distance < PREFERRED_DISTANCE_MIN:
				desired -= target_dir * BOSS_MOVE_SPEED
			var strafe_weight := 0.45 if _pending_attacks.size() > 0 else 1.0
			desired += Vector3(-target_dir.z, 0.0, target_dir.x) * _strafe_dir * BOSS_STRAFE_SPEED * strafe_weight
	var center_pull := Vector3(-global_position.x, 0.0, -global_position.z)
	if center_pull.length() > 13.0:
		desired += center_pull.normalized() * BOSS_MOVE_SPEED * 0.8
	desired += _get_pending_ground_attack_avoidance() * BOSS_MOVE_SPEED * 1.6
	desired *= _movement_speed_scale()
	_movement_velocity = _movement_velocity.move_toward(desired, BOSS_ACCELERATION * delta)
	global_position += _movement_velocity * delta
	global_position.x = clampf(global_position.x, -ARENA_LIMIT, ARENA_LIMIT)
	global_position.z = clampf(global_position.z, -ARENA_LIMIT, ARENA_LIMIT)
	global_position.y = _spawn_position.y


func _get_pending_ground_attack_avoidance() -> Vector3:
	var avoid := Vector3.ZERO
	for pending in _pending_attacks:
		var attack := pending as Dictionary
		if str(attack.get("type", "")) != "impact":
			continue
		var radius := float(attack.get("self_safe_radius", 0.0))
		if radius <= 0.0:
			continue
		var pos := attack.get("position", global_position) as Vector3
		var away := global_position - pos
		away.y = 0.0
		var distance := away.length()
		var safe_distance := radius + SELF_DAMAGE_MARGIN
		if distance >= safe_distance:
			continue
		if distance <= 0.01:
			away = Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
			distance = 0.01
		avoid += away.normalized() * ((safe_distance - distance) / safe_distance)
	return avoid.limit_length(1.0)


func _update_facing(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var flat_target := Vector3(target.global_position.x, global_position.y, target.global_position.z)
	var to_target := flat_target - global_position
	if to_target.length_squared() <= 0.01:
		return
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(delta * 4.0, 0.0, 1.0))


func _is_valid_target(node: Node3D) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	if node.has_method("is_combat_targetable") and not bool(node.is_combat_targetable()):
		return false
	return true


func _flat_distance_to(node: Node3D) -> float:
	var offset := node.global_position - global_position
	offset.y = 0.0
	return offset.length()


func _flat_distance_to_position(pos: Vector3) -> float:
	var offset := pos - global_position
	offset.y = 0.0
	return offset.length()


func _clamp_ground_position(pos: Vector3) -> Vector3:
	return Vector3(clampf(pos.x, -ARENA_LIMIT, ARENA_LIMIT), 0.05, clampf(pos.z, -ARENA_LIMIT, ARENA_LIMIT))


func _is_safe_ground_attack_position(pos: Vector3, attack_radius: float) -> bool:
	return _flat_distance_to_position(pos) > attack_radius + SELF_DAMAGE_MARGIN


func _find_safe_ground_attack_position(preferred: Vector3, attack_radius: float) -> Vector3:
	var preferred_ground := _clamp_ground_position(preferred)
	if _is_safe_ground_attack_position(preferred_ground, attack_radius):
		return preferred_ground
	var safe_points := _get_map_pressure_points(1, attack_radius)
	if not safe_points.is_empty():
		return safe_points[0]
	var away := preferred_ground - global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	var fallback := global_position + away.normalized() * (attack_radius + SELF_DAMAGE_MARGIN + 0.5)
	return _clamp_ground_position(fallback)


func _count_players_near(pos: Vector3, radius: float) -> int:
	var count := 0
	for player in _get_player_targets():
		var node := player as Node3D
		if node == null or not _is_valid_target(node):
			continue
		var flat_a := Vector2(node.global_position.x, node.global_position.z)
		var flat_b := Vector2(pos.x, pos.z)
		if flat_a.distance_to(flat_b) <= radius:
			count += 1
	return count


func _get_player_targets() -> Array:
	var world := get_tree().current_scene
	if world != null and world.has_method("get_active_player_nodes"):
		return world.get_active_player_nodes()
	return []


func apply_part_spell_hit(part_id: String, spell: SpellDefinition, _hit_position: Vector3, _hit_normal: Vector3, is_beam_tick: bool = false) -> void:
	if spell == null or _is_dead or not _part_health.has(part_id) or _is_part_destroyed(part_id):
		return
	var damage := spell.calculate_damage(is_beam_tick)
	if damage <= 0:
		return
	var actual_damage: int = mini(damage, int(_part_health[part_id]))
	_part_health[part_id] = maxi(0, int(_part_health[part_id]) - actual_damage)
	_health = maxi(0, _health - actual_damage)
	if int(_part_health[part_id]) <= 0:
		_destroy_part(part_id)
	if _health <= 0 or _all_parts_destroyed():
		_die()
	_update_labels()
	_update_world_hud()
	_sync_network_state(999.0)


func is_part_damageable(part_id: String) -> bool:
	return not _is_dead and _part_health.has(part_id) and not _is_part_destroyed(part_id)


func _destroy_part(part_id: String) -> void:
	if not _part_health.has(part_id):
		return
	_part_destroyed[part_id] = true
	var part := _parts.get(part_id) as StaticBody3D
	if part == null:
		return
	part.set_deferred("collision_layer", 0)
	part.set_deferred("collision_mask", 0)
	for child in part.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", true)
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			mesh.material_override = _make_material(Color(0.05, 0.04, 0.06), 0.05)


func _start_death_animation() -> void:
	_death_anim_time = 0.0
	_death_anim_active = true
	if _body_root != null:
		_body_root.visible = true
	if _death_burst != null:
		_death_burst.visible = true
		_death_burst.scale = Vector3.ONE * 0.1


func _reset_death_animation() -> void:
	_death_anim_time = 0.0
	_death_anim_active = false
	if _body_root != null:
		_body_root.visible = true
		_body_root.position = Vector3.ZERO
		_body_root.rotation = Vector3.ZERO
		_body_root.scale = Vector3.ONE
	if _death_burst != null:
		_death_burst.visible = false
		_death_burst.scale = Vector3.ONE * 0.1
	if _death_burst_material != null:
		_death_burst_material.albedo_color = Color(1.0, 0.25, 0.1, 0.0)
		_death_burst_material.emission_energy_multiplier = 0.0


func _update_death_animation(delta: float) -> void:
	if not _death_anim_active:
		return
	_death_anim_time = minf(_death_anim_time + delta, DEATH_ANIMATION_DURATION)
	var t := clampf(_death_anim_time / DEATH_ANIMATION_DURATION, 0.0, 1.0)
	var collapse := ease(t, -1.75)
	if _body_root != null:
		_body_root.rotation.z = lerpf(0.0, deg_to_rad(68.0), collapse)
		_body_root.rotation.x = lerpf(0.0, deg_to_rad(-10.0), collapse)
		_body_root.position = Vector3(0.0, lerpf(0.0, -0.75, collapse), 0.0)
		_body_root.scale = Vector3.ONE * lerpf(1.0, 0.52, t)
	if _death_burst != null:
		_death_burst.scale = Vector3.ONE * lerpf(0.1, 3.2, ease(t, -2.0))
	if _death_burst_material != null:
		var alpha := sin(t * PI) * 0.46
		_death_burst_material.albedo_color = Color(1.0, 0.25, 0.1, alpha)
		_death_burst_material.emission_energy_multiplier = sin(t * PI) * 2.0
	if _death_anim_time >= DEATH_ANIMATION_DURATION:
		_death_anim_active = false
		if _body_root != null:
			_body_root.visible = false
		if _death_burst != null:
			_death_burst.visible = false


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_health = 0
	_despawn_requested = false
	if bool(_settings.get("respawn_enabled", false)):
		_death_timer = float(_settings.get("respawn_delay", DEFAULT_RESPAWN_DELAY))
	else:
		_death_timer = float(_settings.get("despawn_delay", DEFAULT_DESPAWN_DELAY))
	_pending_attacks.clear()
	_start_death_animation()
	for part_id in _parts.keys():
		_destroy_part(str(part_id))
	_update_labels()
	_update_world_hud()
	_sync_network_state(999.0)


func _respawn() -> void:
	_is_dead = false
	_health = _max_health
	_death_timer = 0.0
	_despawn_requested = false
	_pending_attacks.clear()
	_reset_death_animation()
	_reset_abilities()
	for part_id in PART_SPECS.keys():
		var max_part_health := _get_scaled_part_max_health(part_id)
		_part_max_health[part_id] = max_part_health
		_part_health[part_id] = max_part_health
		_part_destroyed[part_id] = false
		_restore_part(part_id)
	_update_labels()
	_update_world_hud()
	_sync_network_state(999.0)


func _restore_part(part_id: String) -> void:
	var part := _parts.get(part_id) as StaticBody3D
	if part == null:
		return
	var spec: Dictionary = PART_SPECS[part_id]
	part.set_deferred("collision_layer", 1)
	part.set_deferred("collision_mask", 1)
	for child in part.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", false)
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			mesh.material_override = _make_material(spec["color"] as Color)


func _all_parts_destroyed() -> bool:
	for part_id in _part_destroyed.keys():
		if not bool(_part_destroyed[part_id]):
			return false
	return true


func _is_part_destroyed(part_id: String) -> bool:
	return bool(_part_destroyed.get(part_id, false))


func _update_labels() -> void:
	if _name_label != null:
		_name_label.text = _display_name
	if _health_label != null:
		if _is_dead:
			if bool(_settings.get("respawn_enabled", false)):
				_health_label.text = "RESPAWN %.1f" % maxf(_death_timer, 0.0)
			else:
				_health_label.text = "DESPAWN %.1f" % maxf(_death_timer, 0.0)
		else:
			_health_label.text = "%d / %d" % [_health, _max_health]
	for part_id in _part_labels.keys():
		var label := _part_labels[part_id] as Label3D
		if label == null:
			continue
		var spec: Dictionary = PART_SPECS[part_id]
		if _is_part_destroyed(str(part_id)):
			label.text = "%s destroyed" % str(spec.get("display_name", part_id))
		else:
			label.text = "%s %d/%d" % [
				str(spec.get("display_name", part_id)),
				int(_part_health.get(part_id, 0)),
				int(_part_max_health.get(part_id, _get_scaled_part_max_health(str(part_id)))),
			]


func _sync_network_state(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_sync_timer -= delta
	if _sync_timer > 0.0:
		return
	_sync_timer = SYNC_INTERVAL
	_client_receive_state.rpc(get_state_data())


func send_full_state_to_peer(peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_client_receive_state.rpc_id(peer_id, get_state_data())


@rpc("authority", "unreliable")
func _client_receive_state(state: Dictionary) -> void:
	if multiplayer.is_server():
		return
	apply_state_data(state)


func get_state_data() -> Dictionary:
	var part_states: Array = []
	for part_id in PART_SPECS.keys():
		var spec: Dictionary = PART_SPECS[part_id]
		part_states.append({
			"id": part_id,
			"name": str(spec.get("display_name", part_id)),
			"ability": str(spec.get("ability", "")),
			"health": int(_part_health.get(part_id, 0)),
			"max_health": int(_part_max_health.get(part_id, _get_scaled_part_max_health(part_id))),
			"destroyed": bool(_part_destroyed.get(part_id, false)),
		})
	return {
		"boss_id": _boss_id,
		"display_name": _display_name,
		"position": global_position,
		"yaw": rotation.y,
		"health": _health,
		"max_health": _max_health,
		"is_dead": _is_dead,
		"parts": part_states,
	}


func apply_state_data(state: Dictionary) -> void:
	var was_dead := _is_dead
	_boss_id = int(state.get("boss_id", _boss_id))
	_display_name = str(state.get("display_name", _display_name))
	global_position = state.get("position", global_position) as Vector3
	rotation.y = float(state.get("yaw", rotation.y))
	_health = int(state.get("health", _health))
	_max_health = int(state.get("max_health", _max_health))
	_is_dead = bool(state.get("is_dead", _is_dead))
	if _is_dead and not was_dead:
		_start_death_animation()
	elif not _is_dead and was_dead:
		_reset_death_animation()
	for part_state in state.get("parts", []):
		var data := part_state as Dictionary
		var part_id := str(data.get("id", ""))
		if part_id == "":
			continue
		_part_max_health[part_id] = int(data.get("max_health", _part_max_health.get(part_id, _get_scaled_part_max_health(part_id))))
		_part_health[part_id] = int(data.get("health", _part_health.get(part_id, 0)))
		var was_destroyed := _is_part_destroyed(part_id)
		_part_destroyed[part_id] = bool(data.get("destroyed", false))
		if _is_part_destroyed(part_id) and not was_destroyed:
			_destroy_part(part_id)
		elif not _is_part_destroyed(part_id) and was_destroyed:
			_restore_part(part_id)
	_update_labels()
	_update_world_hud()


func _update_world_hud() -> void:
	var world := get_tree().current_scene
	if world != null and world.has_method("update_boss_health_hud"):
		world.update_boss_health_hud(get_state_data())


func _request_world_despawn() -> void:
	if _despawn_requested:
		return
	_despawn_requested = true
	var world := get_tree().current_scene
	if world != null and world.has_method("despawn_boss"):
		world.call_deferred("despawn_boss", _boss_id)


func _is_network_client() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.is_server()

extends Node3D

const SpellImpactEffectScript = preload("res://Scripts/SpellImpactEffect.gd")

const BASE_PROPERTIES := {
	"Fire": {"temperature": 10, "density": 2, "opposing": ["Water", "Void"]},
	"Water": {"temperature": 2, "density": 6, "opposing": ["Fire", "Void"]},
	"Air": {"temperature": 4, "density": 1, "opposing": ["Earth"]},
	"Spirit": {"temperature": 5, "density": 0, "opposing": ["Void"]},
	"Earth": {"temperature": 3, "density": 10, "opposing": ["Air"]},
	"Light": {"temperature": 6, "density": 0, "opposing": ["Void"]},
	"Void": {"temperature": 0, "density": -10, "opposing": ["Light", "Spirit", "Fire", "Water"]},
}
const ELEMENT_COLORS: Dictionary = {
	"Fire": Color(1.0, 0.35, 0.05),
	"Water": Color(0.1, 0.55, 1.0),
	"Air": Color(0.75, 0.92, 1.0),
	"Spirit": Color(0.72, 0.3, 1.0),
	"Earth": Color(0.6, 0.4, 0.15),
	"Light": Color(1.0, 1.0, 0.35),
	"Void": Color(0.45, 0.1, 0.65),
}
const WALL_BASE_HEALTH := 24.0
const WALL_INTENSITY_HEALTH := 12.0
const WALL_SIZE_HEALTH := 8.0
const WALL_SAME_TYPE_DAMAGE_SCALE := 0.25
const WALL_OPPOSED_DAMAGE_SCALE := 1.65
const WALL_MIN_DAMAGE := 1.0
const WALL_CRACK_COUNT := 9
const WALL_START_ALPHA := 0.86
const WALL_END_ALPHA := 0.18

var _velocity: Vector3 = Vector3.ZERO
var _lifetime: float = 0.0
var _max_lifetime: float = 5.0
var _is_static: bool = false
var _spell: SpellDefinition
var _last_position: Vector3
var _target_position: Vector3
var _has_target_position: bool = false
var _source: Node
var _consumed: bool = false
var _collision_grace: float = 0.08
var _wave_phase_offset: float = 0.0
var _is_authoritative: bool = true
var _cast_server_time: float = 0.0
var _wall_size: Vector3 = Vector3.ZERO
var _wall_health: float = 0.0
var _wall_max_health: float = 0.0
var _wall_block_times: Dictionary = {}
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _wall_cracks: Array[MeshInstance3D] = []
var _wall_base_color: Color = Color.WHITE
var _wall_physical_body: StaticBody3D
var _wall_collision_shape: CollisionShape3D


func initialize(spell: SpellDefinition, from: Vector3, direction: Vector3, source: Node = null, cast_server_time: float = -1.0) -> void:
	_spell = spell
	_source = source
	_is_authoritative = multiplayer.multiplayer_peer == null or multiplayer.is_server()
	_cast_server_time = cast_server_time if cast_server_time >= 0.0 else Time.get_ticks_msec() / 1000.0
	_wave_phase_offset = _get_base_phase_offset(spell.get_dominant_base())
	add_to_group("spell_projectile")
	var col: Color = _get_spell_color(spell)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.2 + (spell.intensity - 1) * 0.28
	_material = mat
	_wall_base_color = col

	var mesh_inst := MeshInstance3D.new()
	_mesh_instance = mesh_inst
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.8 + spell.intensity * 0.35
	light.omni_range = 2.5 + spell.spell_size * 0.3
	add_child(light)

	match spell.shape:
		"Sphere":
			var mesh := SphereMesh.new()
			mesh.radius = (0.12 + (spell.spell_size - 1) * 0.04) * _get_blend_visual_scale(spell)
			mesh.height = mesh.radius * 2.0
			mesh_inst.mesh = mesh
			var speed := 4.0 + spell.spell_speed * 4.5
			_velocity = direction.normalized() * speed
			_max_lifetime = 1.5 + (spell.spell_range - 1) * 0.4
			global_position = from
			_last_position = global_position

		"Beam":
			var mesh := CapsuleMesh.new()
			mesh.radius = 0.04 + (spell.spell_size - 1) * 0.01
			mesh.height = (0.5 + (spell.spell_range - 1) * 0.12) * _get_blend_visual_scale(spell)
			mesh_inst.mesh = mesh
			mesh_inst.rotation.x = PI / 2.0
			var speed := 10.0 + spell.spell_speed * 2.5
			_velocity = direction.normalized() * speed
			_max_lifetime = 0.8 + (spell.spell_range - 1) * 0.15
			global_position = from
			_last_position = global_position

		"Wall":
			var mesh := BoxMesh.new()
			mesh.size = Vector3(
				0.8 + (spell.spell_size - 1) * 0.18,
				1.2 + (spell.spell_size - 1) * 0.15,
				0.1
			) * _get_blend_visual_scale(spell)
			_wall_size = mesh.size
			_wall_max_health = _calculate_wall_health(spell)
			_wall_health = _wall_max_health
			mesh_inst.mesh = mesh
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = WALL_START_ALPHA
			mat.emission_energy_multiplier *= 0.75
			_is_static = true
			_max_lifetime = maxf(0.5, float(spell.wall_time))
			global_position = _get_wall_position(from, direction)
			_last_position = global_position
			# Face back toward caster
			if direction.length_squared() > 0.001:
				look_at(from, Vector3.UP)
			_build_wall_cracks()
			_build_earth_wall_physics()
			_update_wall_visuals()

		_:
			# Fallback sphere
			var mesh := SphereMesh.new()
			mesh.radius = 0.15
			mesh.height = 0.3
			mesh_inst.mesh = mesh
			_velocity = direction.normalized() * 10.0
			global_position = from
			_last_position = global_position


func _process(delta: float) -> void:
	if _consumed:
		return
	_lifetime += delta
	if _collision_grace > 0.0:
		_collision_grace -= delta
	if _lifetime >= _max_lifetime:
		queue_free()
		return
	if is_spell_wall():
		_update_wall_visuals()
	if not _is_static:
		var next_position := global_position + _velocity * delta
		if not _is_authoritative:
			var visual_hit := _get_world_hit(global_position, next_position)
			if not visual_hit.is_empty():
				var visual_hit_position := visual_hit["position"] as Vector3
				var visual_hit_normal := visual_hit["normal"] as Vector3
				_spawn_visual_impact(visual_hit_position, visual_hit_normal)
				_consume()
				return
			global_position = next_position
			_last_position = global_position
			return
		var hit := _get_world_hit(global_position, next_position)
		if not hit.is_empty():
			var hit_position := hit["position"] as Vector3
			var hit_normal := hit["normal"] as Vector3
			var wall := _find_spell_wall_node(hit.get("collider"))
			if wall != null and wall != self:
				_resolve_wall_block(wall, hit_position, hit_normal)
				return
			_apply_spell_hit_to_collider(hit.get("collider"), hit_position, hit_normal)
			_apply_recoil_to_source(hit_position, hit_normal)
			_spawn_impact(hit_position, hit_normal)
			_consume()
			return
		if _collision_grace <= 0.0 and _check_spell_collision(next_position):
			return
		global_position = next_position
		_last_position = global_position
		if _has_target_position and global_position.distance_to(_target_position) < 0.12:
			global_position = _target_position
			_velocity = Vector3.ZERO
			_is_static = true


func get_spell_definition() -> SpellDefinition:
	return _spell


func is_spell_consumed() -> bool:
	return _consumed


func is_spell_wall() -> bool:
	return _is_static and _spell != null and _spell.shape == "Wall"


func is_physical_earth_wall() -> bool:
	return is_spell_wall() and _spell.get_base_elements().has("Earth")


func get_wall_health() -> float:
	return _wall_health


func get_wall_max_health() -> float:
	return _wall_max_health


func get_wall_segment_hit(from: Vector3, to: Vector3, incoming_radius: float) -> Dictionary:
	if not is_spell_wall():
		return {}
	var local_from := to_local(from)
	var local_to := to_local(to)
	var local_delta := local_to - local_from
	var half_extents := _wall_size * 0.5 + Vector3.ONE * maxf(0.02, incoming_radius)
	var t_enter := 0.0
	var t_exit := 1.0
	var enter_axis := -1
	var enter_sign := 0.0
	for axis in range(3):
		var start := _get_axis(local_from, axis)
		var delta := _get_axis(local_delta, axis)
		var min_value := -_get_axis(half_extents, axis)
		var max_value := _get_axis(half_extents, axis)
		if absf(delta) <= 0.0001:
			if start < min_value or start > max_value:
				return {}
			continue
		var inv_delta := 1.0 / delta
		var t1 := (min_value - start) * inv_delta
		var t2 := (max_value - start) * inv_delta
		var axis_sign := -1.0
		if t1 > t2:
			var temp := t1
			t1 = t2
			t2 = temp
			axis_sign = 1.0
		if t1 > t_enter:
			t_enter = t1
			enter_axis = axis
			enter_sign = axis_sign
		t_exit = minf(t_exit, t2)
		if t_enter > t_exit:
			return {}
	if t_exit < 0.0 or t_enter > 1.0:
		return {}
	var hit_t := clampf(t_enter, 0.0, 1.0)
	var local_hit := local_from + local_delta * hit_t
	var local_normal := _axis_vector(enter_axis, enter_sign)
	if enter_axis < 0:
		local_normal = Vector3.BACK if local_from.z < local_to.z else Vector3.FORWARD
	return {
		"position": to_global(local_hit),
		"normal": global_transform.basis * local_normal,
	}


func apply_wall_block(incoming_spell: SpellDefinition, is_beam_tick: bool = false, block_key: String = "", block_interval: float = 0.0) -> Dictionary:
	if not is_spell_wall() or incoming_spell == null:
		return {}
	if block_interval > 0.0 and block_key != "":
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(_wall_block_times.get(block_key, -99.0)) < block_interval:
			return {"damage": 0.0, "destroyed": false, "reaction_spell": _get_wall_reaction_spell(incoming_spell)}
		_wall_block_times[block_key] = now
	var incoming_damage := maxf(WALL_MIN_DAMAGE, float(incoming_spell.calculate_damage(is_beam_tick)))
	var scale := _get_wall_damage_scale(incoming_spell)
	var damage := maxf(WALL_MIN_DAMAGE, incoming_damage * scale)
	_wall_health = maxf(0.0, _wall_health - damage)
	_update_wall_visuals()
	var destroyed := _wall_health <= 0.0
	if destroyed:
		_consume()
	return {
		"damage": damage,
		"destroyed": destroyed,
		"reaction_spell": _get_wall_reaction_spell(incoming_spell),
	}


func _check_spell_collision(next_position: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("spell_projectile"):
		if node == self or not is_instance_valid(node):
			continue
		if not node.has_method("get_spell_definition") or not node.has_method("is_spell_consumed"):
			continue
		if node.is_spell_consumed():
			continue
		if node.has_method("is_spell_wall") and bool(node.is_spell_wall()):
			var wall_hit: Dictionary = node.get_wall_segment_hit(global_position, next_position, _get_collision_radius())
			if not wall_hit.is_empty():
				_resolve_wall_block(node, wall_hit["position"] as Vector3, wall_hit["normal"] as Vector3)
				return true
			continue
		var other_pos: Vector3 = node.global_position
		var radius: float = _get_collision_radius() + node._get_collision_radius()
		if _distance_to_segment(other_pos, global_position, next_position) <= radius:
			_resolve_spell_collision(node, global_position.lerp(next_position, 0.5))
			return true
	return false


func _resolve_wall_block(wall: Node3D, collision_point: Vector3, wall_normal: Vector3) -> void:
	if _spell == null or wall == null or not wall.has_method("apply_wall_block"):
		return
	var outcome: Dictionary = wall.apply_wall_block(_spell)
	var reaction_spell := outcome.get("reaction_spell") as SpellDefinition
	if reaction_spell == null:
		reaction_spell = _spell
	var front_normal := -_velocity.normalized()
	if front_normal.length_squared() <= 0.001:
		front_normal = wall_normal.normalized()
	_spawn_wall_block_impact(reaction_spell, collision_point, front_normal, wall.global_position)
	_consume()


func _resolve_spell_collision(other: Node3D, collision_point: Vector3) -> void:
	var other_spell: SpellDefinition = other.get_spell_definition()
	if _spell == null or other_spell == null:
		return

	var opposing_pair: Array[String] = _find_opposing_pair(_spell, other_spell)
	if not opposing_pair.is_empty():
		_resolve_opposition(other, other_spell, collision_point, opposing_pair)
		return

	if _spell.get_dominant_base() == other_spell.get_dominant_base():
		_resolve_same_base(other, other_spell, collision_point)
		return

	_resolve_general_collision(other, other_spell, collision_point)


func _resolve_opposition(other: Node3D, other_spell: SpellDefinition, collision_point: Vector3, opposing_pair: Array[String]) -> void:
	var my_power := _get_opposition_power(_spell, opposing_pair[0])
	var other_power := _get_opposition_power(other_spell, opposing_pair[1])
	var interference := _get_wave_interference(other)
	var cancel_strength := _get_cancel_strength(interference)
	var high_power: float = maxf(my_power, other_power)
	if high_power <= 0.0:
		_consume()
		other._consume()
		return

	var reaction_spell := _create_reaction_spell(_spell, other_spell, opposing_pair)
	_spawn_impact_with_spell(reaction_spell, collision_point, Vector3.UP)

	var effective_my_power := my_power * (0.65 + cancel_strength * 0.7)
	var effective_other_power := other_power * (0.65 + cancel_strength * 0.7)
	var effective_high_power: float = maxf(effective_my_power, effective_other_power)

	if absf(effective_my_power - effective_other_power) / effective_high_power <= 0.28:
		_consume()
		other._consume()
	elif effective_my_power > effective_other_power:
		_weaken_by_ratio(clampf(effective_other_power / effective_my_power, 0.05, 0.95))
		other._consume()
	else:
		other._weaken_by_ratio(clampf(effective_my_power / effective_other_power, 0.05, 0.95))
		_consume()


func _resolve_same_base(other: Node3D, other_spell: SpellDefinition, collision_point: Vector3) -> void:
	var my_power := _get_total_power(_spell)
	var other_power := _get_total_power(other_spell)
	var interference := _get_wave_interference(other)
	_spawn_impact(collision_point, Vector3.UP)
	if interference >= 0.35:
		if my_power >= other_power:
			_merge_from(other_spell, other_power / maxf(my_power, 0.1), interference)
			other._consume()
		else:
			other._merge_from(_spell, my_power / maxf(other_power, 0.1), interference)
			_consume()
	elif interference <= -0.35:
		var high_power: float = maxf(my_power, other_power)
		if absf(my_power - other_power) / high_power <= 0.25:
			_consume()
			other._consume()
		elif my_power > other_power:
			_weaken_by_ratio(clampf(other_power / my_power, 0.1, 0.9))
			other._consume()
		else:
			other._weaken_by_ratio(clampf(my_power / other_power, 0.1, 0.9))
			_consume()
	else:
		_weaken_by_ratio(0.18)
		other._weaken_by_ratio(0.18)


func _resolve_general_collision(other: Node3D, other_spell: SpellDefinition, collision_point: Vector3) -> void:
	var temp_delta := absf(_get_spell_temperature(_spell) - _get_spell_temperature(other_spell))
	var density_delta := absf(_get_spell_density(_spell) - _get_spell_density(other_spell))
	var interference := _get_wave_interference(other)
	_spawn_impact(collision_point, Vector3.UP)
	if density_delta > 6.0:
		if _get_spell_density(_spell) < _get_spell_density(other_spell):
			_velocity = _velocity.rotated(Vector3.UP, deg_to_rad(18.0 + density_delta * 2.0))
		else:
			other._deflect_from(collision_point, density_delta)
	elif temp_delta > 6.0:
		var loss := 0.12 + _get_cancel_strength(interference) * 0.22
		_weaken_by_ratio(loss)
		other._weaken_by_ratio(loss)
	else:
		if interference > 0.55:
			_weaken_by_ratio(-0.08)
			other._weaken_by_ratio(-0.08)
		else:
			var loss := 0.05 + _get_cancel_strength(interference) * 0.18
			_weaken_by_ratio(loss)
			other._weaken_by_ratio(loss)


func _consume() -> void:
	_consumed = true
	queue_free()


func _weaken_by_ratio(ratio: float) -> void:
	var remaining := clampf(1.0 - ratio, 0.15, 1.0)
	if ratio < 0.0:
		remaining = clampf(1.0 - ratio, 1.0, 1.25)
	_spell = _duplicate_spell(_spell)
	_spell.intensity = max(1, int(round(_spell.intensity * remaining)))
	_spell.spell_size = max(1, int(round(_spell.spell_size * remaining)))


func _merge_from(other_spell: SpellDefinition, speed_penalty_ratio: float, interference: float = 1.0) -> void:
	var boost := clampf(interference, 0.35, 1.0)
	_spell = _duplicate_spell(_spell)
	_spell.intensity = max(1, int(round(_spell.intensity + other_spell.intensity * lerpf(0.25, 0.75, boost))))
	_spell.spell_size = max(1, int(round(max(_spell.spell_size, other_spell.spell_size) + min(_spell.spell_size, other_spell.spell_size) * lerpf(0.15, 0.45, boost))))
	_velocity *= clampf(1.0 - speed_penalty_ratio * 0.5, 0.35, 1.0)


func _deflect_from(collision_point: Vector3, density_delta: float) -> void:
	var away := (global_position - collision_point).normalized()
	if away.length_squared() < 0.001:
		away = Vector3.RIGHT
	_velocity = (_velocity.normalized() + away * clampf(density_delta / 10.0, 0.0, 1.0)).normalized() * _velocity.length()


func _get_wave_interference(other: Node3D) -> float:
	var phase_delta: float = _get_wave_phase() - other._get_wave_phase()
	var phase_alignment: float = cos(phase_delta)
	var direction_alignment: float = 0.0
	if _velocity.length_squared() > 0.001 and other._velocity.length_squared() > 0.001:
		direction_alignment = _velocity.normalized().dot(other._velocity.normalized())
	var aim_factor: float = clampf((1.0 - direction_alignment) * 0.5, 0.0, 1.0)
	return clampf(phase_alignment * 0.75 - aim_factor * 0.35, -1.0, 1.0)


func _get_cancel_strength(interference: float) -> float:
	return clampf(-interference, 0.0, 1.0)


func _get_wave_phase() -> float:
	return _wave_phase_offset + _lifetime * _get_wave_frequency() * TAU


func _get_wave_frequency() -> float:
	if _spell == null:
		return 1.0
	return 0.65 + _spell.spell_speed * 0.08 + _spell.intensity * 0.035 + _spell.get_base_elements().size() * 0.06


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


func _get_world_hit(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _get_source_excludes()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _get_source_excludes() -> Array:
	if is_instance_valid(_source) and _source is CollisionObject3D:
		return [_source]
	return []


func _apply_spell_hit_to_collider(collider: Object, hit_position: Vector3, hit_normal: Vector3) -> bool:
	var damageable := _find_damageable_node(collider)
	if damageable == null:
		return false
	if is_instance_valid(_source) and damageable == _source:
		return false
	# Lag compensation: re-check the hit against the target's rewound position.
	# If the target has moved far enough since cast time that the projectile
	# wouldn't actually overlap now, skip the damage to avoid phantom hits.
	if _is_authoritative and damageable.has_method("get_position_at_time"):
		var rewind_pos: Vector3 = damageable.get_position_at_time(_cast_server_time)
		var hit_radius := 0.6 + _spell.spell_size * 0.08
		if rewind_pos.distance_to(hit_position) > hit_radius + 1.2:
			return false
	damageable.apply_spell_hit(_spell, hit_position, hit_normal, false)
	return true


func _apply_recoil_to_source(hit_position: Vector3, hit_normal: Vector3) -> void:
	if is_instance_valid(_source) and _source.has_method("apply_spell_recoil"):
		_source.apply_spell_recoil(_spell, hit_position, hit_normal, false)


func _find_damageable_node(value: Object) -> Node:
	var node := value as Node
	while node != null:
		if node.has_method("apply_spell_hit"):
			if node.has_method("is_damageable") and not bool(node.is_damageable()):
				return null
			return node
		node = node.get_parent()
	return null


func _spawn_impact(position: Vector3, normal: Vector3) -> void:
	if _spell == null:
		return
	_spawn_impact_with_spell(_spell, position, normal)


func _spawn_impact_with_spell(spell: SpellDefinition, position: Vector3, normal: Vector3) -> void:
	var effect := SpellImpactEffectScript.new()
	get_tree().current_scene.add_child(effect)
	effect.initialize(spell, position, normal, _source)
	var world := get_tree().current_scene
	if _is_authoritative and multiplayer.multiplayer_peer != null and multiplayer.is_server() and world != null and world.has_method("broadcast_spell_impact"):
		world.broadcast_spell_impact(spell, position, normal)


func _spawn_wall_block_impact(spell: SpellDefinition, position: Vector3, front_normal: Vector3, wall_position: Vector3) -> void:
	if spell == null:
		return
	var effect := SpellImpactEffectScript.new()
	get_tree().current_scene.add_child(effect)
	effect.initialize(spell, position, front_normal, _source)
	effect.set_blocking_plane(wall_position, front_normal)
	var world := get_tree().current_scene
	if _is_authoritative and multiplayer.multiplayer_peer != null and multiplayer.is_server() and world != null and world.has_method("broadcast_spell_impact"):
		world.broadcast_spell_impact(spell, position, front_normal)


func _spawn_visual_impact(position: Vector3, normal: Vector3) -> void:
	if _spell == null:
		return
	var effect := SpellImpactEffectScript.new()
	get_tree().current_scene.add_child(effect)
	effect.initialize(_spell, position, normal, _source)
	effect.set_visual_only(true)


func _get_wall_position(from: Vector3, direction: Vector3) -> Vector3:
	var dir := direction.normalized()
	var desired_position := from + dir * 2.2
	var hit := _get_world_hit(from, desired_position)
	if hit.is_empty():
		return desired_position
	return (hit["position"] as Vector3) - dir * 0.08


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


func _get_blend_visual_scale(spell: SpellDefinition) -> float:
	return 1.0 + max(0, spell.get_base_elements().size() - 1) * 0.12


func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _get_collision_radius() -> float:
	if _spell == null:
		return 0.25
	if is_spell_wall():
		return maxf(_wall_size.x, _wall_size.y) * 0.5
	return 0.25 + _spell.spell_size * 0.06


func _find_spell_wall_node(value: Variant) -> Node3D:
	var node := value as Node
	while node != null:
		if node.has_method("is_spell_wall") and bool(node.is_spell_wall()):
			return node as Node3D
		node = node.get_parent()
	return null


func _build_wall_cracks() -> void:
	if not is_spell_wall():
		return
	var crack_material := StandardMaterial3D.new()
	crack_material.albedo_color = Color(0.03, 0.02, 0.018, 0.92)
	crack_material.emission_enabled = true
	crack_material.emission = Color(0.08, 0.035, 0.02)
	crack_material.emission_energy_multiplier = 0.18
	crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var crack_specs: Array[Dictionary] = [
		{"pos": Vector3(-0.28, 0.12, -0.56), "size": Vector3(0.035, 0.48, 0.012), "rot": -0.55},
		{"pos": Vector3(-0.16, -0.12, -0.56), "size": Vector3(0.03, 0.36, 0.012), "rot": 0.72},
		{"pos": Vector3(0.1, 0.22, -0.56), "size": Vector3(0.028, 0.52, 0.012), "rot": 0.18},
		{"pos": Vector3(0.31, -0.04, -0.56), "size": Vector3(0.035, 0.44, 0.012), "rot": -0.78},
		{"pos": Vector3(-0.38, -0.34, -0.56), "size": Vector3(0.025, 0.34, 0.012), "rot": -0.08},
		{"pos": Vector3(0.38, 0.35, -0.56), "size": Vector3(0.025, 0.32, 0.012), "rot": 0.88},
		{"pos": Vector3(0.0, -0.38, -0.56), "size": Vector3(0.03, 0.5, 0.012), "rot": 1.24},
		{"pos": Vector3(-0.02, 0.02, -0.56), "size": Vector3(0.04, 0.72, 0.014), "rot": -1.05},
		{"pos": Vector3(0.22, -0.28, -0.56), "size": Vector3(0.028, 0.42, 0.012), "rot": 0.42},
	]
	for spec in crack_specs:
		var crack := _create_wall_crack(spec, crack_material, -1.0)
		add_child(crack)
		_wall_cracks.append(crack)
		var back_crack := _create_wall_crack(spec, crack_material, 1.0)
		add_child(back_crack)
		_wall_cracks.append(back_crack)


func _create_wall_crack(spec: Dictionary, material: StandardMaterial3D, z_sign: float) -> MeshInstance3D:
	var crack := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var size := spec.get("size", Vector3(0.03, 0.4, 0.012)) as Vector3
	mesh.size = Vector3(size.x * _wall_size.x, size.y * _wall_size.y, size.z)
	crack.mesh = mesh
	crack.material_override = material
	var pos := spec.get("pos", Vector3.ZERO) as Vector3
	crack.position = Vector3(pos.x * _wall_size.x, pos.y * _wall_size.y, z_sign * _wall_size.z * 0.62)
	crack.rotation.z = float(spec.get("rot", 0.0)) * z_sign
	crack.visible = false
	return crack


func _build_earth_wall_physics() -> void:
	if not is_physical_earth_wall():
		return
	_wall_physical_body = StaticBody3D.new()
	_wall_physical_body.name = "EarthWallBody"
	_wall_physical_body.collision_layer = 1
	_wall_physical_body.collision_mask = 1
	add_child(_wall_physical_body)

	_wall_collision_shape = CollisionShape3D.new()
	_wall_collision_shape.name = "EarthWallCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(_wall_size.x, _wall_size.y, maxf(_wall_size.z, 0.35))
	_wall_collision_shape.shape = shape
	_wall_physical_body.add_child(_wall_collision_shape)


func _update_wall_visuals() -> void:
	if not is_spell_wall():
		return
	var health_ratio := clampf(_wall_health / maxf(_wall_max_health, 0.001), 0.0, 1.0)
	var age_ratio := clampf(_lifetime / maxf(_max_lifetime, 0.001), 0.0, 1.0)
	if _material != null:
		var col := _wall_base_color
		col.a = lerpf(WALL_START_ALPHA, WALL_END_ALPHA, age_ratio)
		_material.albedo_color = col
		_material.emission_energy_multiplier = (0.55 + health_ratio * 0.55) * (1.0 - age_ratio * 0.45)
	var cracks_per_side := int(ceil((1.0 - health_ratio) * float(WALL_CRACK_COUNT)))
	for i in range(_wall_cracks.size()):
		var crack_index := int(floor(float(i) / 2.0))
		_wall_cracks[i].visible = crack_index < cracks_per_side


func _calculate_wall_health(spell: SpellDefinition) -> float:
	if spell == null:
		return WALL_BASE_HEALTH
	var health := WALL_BASE_HEALTH
	health += float(spell.intensity) * WALL_INTENSITY_HEALTH
	health += float(spell.spell_size) * WALL_SIZE_HEALTH
	var bases := spell.get_base_elements()
	if bases.has("Earth"):
		health *= 1.35
	if bases.has("Void"):
		health *= 1.2
	if bases.has("Spirit") or bases.has("Light"):
		health *= 0.9
	if bases.size() > 1:
		health *= 1.1
	return maxf(WALL_BASE_HEALTH, health)


func _get_wall_damage_scale(incoming_spell: SpellDefinition) -> float:
	if incoming_spell == null or _spell == null:
		return 1.0
	if _shares_any_base(_spell, incoming_spell):
		return WALL_SAME_TYPE_DAMAGE_SCALE
	if not _find_opposing_pair(_spell, incoming_spell).is_empty():
		return WALL_OPPOSED_DAMAGE_SCALE
	var temp_delta := absf(_get_spell_temperature(_spell) - _get_spell_temperature(incoming_spell))
	var density_delta := absf(_get_spell_density(_spell) - _get_spell_density(incoming_spell))
	return clampf(0.85 + temp_delta * 0.035 + density_delta * 0.025, 0.85, 1.35)


func _get_wall_reaction_spell(incoming_spell: SpellDefinition) -> SpellDefinition:
	if incoming_spell == null or _spell == null:
		return null
	var opposing_pair := _find_opposing_pair(_spell, incoming_spell)
	if opposing_pair.is_empty():
		return null
	return _create_reaction_spell(_spell, incoming_spell, opposing_pair)


func _shares_any_base(a: SpellDefinition, b: SpellDefinition) -> bool:
	for base in a.get_base_elements():
		if b.get_base_elements().has(base):
			return true
	return false


func _find_opposing_pair(a: SpellDefinition, b: SpellDefinition) -> Array[String]:
	for base_a in a.get_base_elements():
		for base_b in b.get_base_elements():
			var props: Dictionary = BASE_PROPERTIES.get(base_a, {})
			var opposing: Array = props.get("opposing", [])
			if opposing.has(base_b):
				return [base_a, base_b]
	return []


func _get_axis(value: Vector3, axis: int) -> float:
	match axis:
		0:
			return value.x
		1:
			return value.y
		2:
			return value.z
		_:
			return 0.0


func _axis_vector(axis: int, sign: float) -> Vector3:
	match axis:
		0:
			return Vector3(sign, 0.0, 0.0)
		1:
			return Vector3(0.0, sign, 0.0)
		2:
			return Vector3(0.0, 0.0, sign)
		_:
			return Vector3.ZERO


func _get_opposition_power(spell: SpellDefinition, base: String) -> float:
	var weights := spell.get_base_weights()
	var weight := float(weights.get(base, 0)) / 100.0
	return weight * float(spell.intensity) * float(spell.spell_size)


func _get_total_power(spell: SpellDefinition) -> float:
	return float(spell.intensity) * float(spell.spell_size)


func _get_spell_temperature(spell: SpellDefinition) -> float:
	var weights := spell.get_base_weights()
	var total := 0.0
	var value := 0.0
	for base in weights.keys():
		var weight := float(weights[base])
		total += weight
		var props: Dictionary = BASE_PROPERTIES.get(str(base), {})
		value += float(props.get("temperature", 5)) * weight
	if total <= 0.0:
		return 5.0
	return value / total


func _get_spell_density(spell: SpellDefinition) -> float:
	var weights := spell.get_base_weights()
	var total := 0.0
	var value := 0.0
	for base in weights.keys():
		var weight := float(weights[base])
		total += weight
		var props: Dictionary = BASE_PROPERTIES.get(str(base), {})
		value += float(props.get("density", 1)) * weight
	if total <= 0.0:
		return 1.0
	return value / total


func _create_reaction_spell(a: SpellDefinition, b: SpellDefinition, opposing_pair: Array[String]) -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = "Reaction"
	spell.base_element = opposing_pair[0]
	spell.base_weights = {opposing_pair[0]: 50, opposing_pair[1]: 50}
	spell.shape = "Sphere"
	spell.intensity = max(1, int(round((a.intensity + b.intensity) * 0.5)))
	spell.spell_size = max(1, int(round((a.spell_size + b.spell_size) * 0.5)))
	spell.spell_range = 1
	spell.spell_speed = 1
	return spell


func _duplicate_spell(source: SpellDefinition) -> SpellDefinition:
	var spell := SpellDefinition.new()
	spell.spell_name = source.spell_name
	spell.base_element = source.base_element
	spell.base_weights = source.get_base_weights().duplicate()
	spell.shape = source.shape
	spell.intensity = source.intensity
	spell.spell_size = source.spell_size
	spell.spell_range = source.spell_range
	spell.spell_speed = source.spell_speed
	spell.wall_time = source.wall_time
	spell.has_charging = source.has_charging
	spell.burns = source.burns
	spell.cools = source.cools
	spell.pushes = source.pushes
	spell.blows = source.blows
	spell.heals = source.heals
	spell.has_density = source.has_density
	spell.density = source.density
	spell.has_illusion = source.has_illusion
	spell.has_pull = source.has_pull
	spell.pull_strength = source.pull_strength
	return spell
